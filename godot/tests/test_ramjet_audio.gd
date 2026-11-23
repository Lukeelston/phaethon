## The ramjet's own voice (audio/engine_audio.gd), stepped through the sim on the range: nothing of it off
## the ramjet (its loops paused, the burner's rumble what it was), the catch as it lights (a shot an engine, the
## loops straight in and over their mark), the speed followed (the scream more than the roar, both played
## faster), the boost taken, one engine's flameout taking that side's voice alone, the shut-down (a shot, the
## note falling, silence inside a second), a blink that earns no second shot, and the solo switch the audio
## gate uses. What it sounds like is tools/engine_audio_check.py's business (it measures recordings); this is
## the switchwork, and runs in a few seconds:
##   --headless --audio-driver Dummy -s res://tests/test_ramjet_audio.gd
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const EngineSound := preload("res://audio/engine_audio.gd")
const DT := 1.0 / 480.0
const FRAME := 1.0 / 90.0

var failures := 0
var checks := 0
var sim
var audio
var armed := false
var _frames := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _mph() -> float:
	return sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.23694


## Fly for a while: both levers through the gate (the burner; the ramjet when armed), the boost held or not.
func _fly(seconds: float, boost := false) -> void:
	var inp := {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
	if boost:
		inp["boost"] = true
	var acc := 0.0
	for f in roundi(seconds / FRAME):
		sim.armed = armed
		acc += FRAME
		while acc >= DT:
			sim.step(inp, DT)
			sim.events.clear()
			acc -= DT
		audio.update(inp, FRAME)
		_frames += 1
		if _frames % 90 == 0:      # (let the audio server take the updates as they come)
			await process_frame


func _loops(k: int) -> Array:
	return audio.voices[k].players.ramjet + audio.voices[k].players.ramscream


func _paused(k: int) -> bool:
	for p: AudioStreamPlayer in _loops(k):
		if not p.stream_paused:
			return false
	return true


func _heard(k: int) -> bool:
	for p: AudioStreamPlayer in _loops(k):
		if p.stream_paused or p.volume_db < -40.0:
			return false
	return true


func _run() -> void:
	var T: Dictionary = EngineSound.TUNE
	sim = Sim.new({"track": "range"})
	audio = EngineSound.new()
	root.add_child(audio)
	audio.setup(sim)
	var vl: Dictionary = audio.voices[0]
	var vr: Dictionary = audio.voices[1]

	# the bank
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EngineSound.RAM_DIR + "manifest.json"))
	var loops_ok := true
	for layer in EngineSound.RAM_LAYERS:
		var streams: Array = audio._streams[layer]
		loops_ok = loops_ok and streams.size() == 1
		for s: AudioStreamWAV in streams:
			loops_ok = loops_ok and s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.format == AudioStreamWAV.FORMAT_16_BITS and not s.stereo \
				and absf(float(s.loop_end) / s.mix_rate - float(manifest.layers[layer].seconds)) < 0.01 and float(manifest.layers[layer].seam) < 1.0
	_check("the bank: a roar and a scream, each one forward-looping 16-bit loop of the length the bake wrote, its seam measured under 1", loops_ok)
	_check("... and a light-up and a shut-down take for each engine, none of them looping",
		audio._ram_light.size() == 2 and audio._ram_out.size() == 2 and audio._ram_light[0].loop_mode == AudioStreamWAV.LOOP_DISABLED
		and audio._ram_out[1].loop_mode == AudioStreamWAV.LOOP_DISABLED and audio._ram_light[0] != audio._ram_light[1])

	# off the ramjet: the burner from rest to 3,000 mph
	await _fly(5.5)
	var burner_db: float = (vl.players.burner[0] as AudioStreamPlayer).volume_db
	_check("on the burner at %.0f mph (mode %s): nothing of the ramjet's (never lit, in 0, its loops paused, no shot)" % [_mph(), sim.mode],
		sim.mode == "burner" and vl.ram_n == 0 and vr.ram_n == 0 and vl.ram == 0.0 and _paused(0) and _paused(1) and not (vl.ram_shots as AudioStreamPlayer).playing)
	var burner_was := linear_to_db(float(T.burner_gain) * db_to_linear(float(T.level_db[1])))
	_check("... and the burner's rumble is what it was (%.2f dB, as burner_gain at full level gives: %.2f)" % [burner_db, burner_was],
		vl.burn > 0.99 and absf(burner_db - burner_was) < 0.05)

	# it lights
	armed = true
	await _fly(FRAME)
	var shot_l: AudioStreamPlayer = vl.ram_shots
	var shot_r: AudioStreamPlayer = vr.ram_shots
	_check("armed: the sim is on the ramjet and each engine's voice lights at once (one light-up each, its kick at the top)",
		sim.mode == "ramjet" and vl.ram_lit and vr.ram_lit and vl.ram_n == 1 and vr.ram_n == 1 and vl.ram_kick > 0.9)
	_check("... with a shot: the left engine's take on the left, the right's on the right, each on its engine's own side bus",
		shot_l.playing and shot_r.playing and shot_l.stream == audio._ram_light[0] and shot_r.stream == audio._ram_light[1]
		and shot_l.bus == &"EngineL_pops" and shot_r.bus == &"EngineR_pops")
	var lit_mph := _mph()
	var kicked: Array = (vl.ram_db as Array).duplicate()
	var settled_there: float = float(kicked[0]) - float(T.ram_kick_db[0]) * float(vl.ram_kick)      # the roar's level at this speed, its kick taken off
	_check("... the shot %.0f dB over the roar's settled level at that speed, and no higher than %+.0f dB (%.1f dB against %.1f): bolder than the steady roar" % [T.ram_light_db, T.ram_shot_max_db, shot_l.volume_db, settled_there],
		float(T.ram_light_db) > 0.0 and shot_l.volume_db > settled_there + 2.0
		and absf(shot_l.volume_db - minf(settled_there + float(T.ram_light_db), float(T.ram_shot_max_db))) < 0.05)
	await _fly(0.1)
	_check("a tenth of a second on its loops are in (%.2f of the way) and heard, both engines'" % vl.ram, vl.ram > 0.9 and _heard(0) and _heard(1))
	_check("the burner's rumble has stepped back under it (%.1f dB against %.1f on the burner alone)" % [(vl.players.burner[0] as AudioStreamPlayer).volume_db, burner_db],
		(vl.players.burner[0] as AudioStreamPlayer).volume_db < burner_db - 5.0)
	await _fly(2.0)
	var slow: Array = (vl.ram_db as Array).duplicate()
	var slow_at: Array = [float(vl.at.ramjet), float(vl.at.ramscream)]
	var slow_mph := _mph()
	_check("two seconds on the kick has gone (%.2f) and the roar has settled %.1f dB under where it lit (speed %.0f -> %.0f mph)" % [vl.ram_kick, float(kicked[0]) - float(slow[0]), lit_mph, slow_mph],
		vl.ram_kick < 0.05 and float(kicked[0]) - float(slow[0]) > 1.5)

	# it follows the speed, as flown ...
	await _fly(9.0)
	var fast: Array = (vl.ram_db as Array).duplicate()
	var fast_mph := _mph()
	_check("it follows the speed as flown: %.0f -> %.0f mph, the roar %+.1f dB, the scream %+.1f dB (more than the roar: it brightens)" % [slow_mph, fast_mph, float(fast[0]) - float(slow[0]), float(fast[1]) - float(slow[1])],
		fast_mph > slow_mph + 1000.0 and float(fast[0]) - float(slow[0]) > 0.3 and float(fast[1]) - float(slow[1]) > float(fast[0]) - float(slow[0]) + 0.3)
	_check("... and both are played faster, the scream's note climbing more (roar x%.2f -> x%.2f, scream x%.2f -> x%.2f)" % [slow_at[0], vl.at.ramjet, slow_at[1], vl.at.ramscream],
		float(vl.at.ramjet) > slow_at[0] * 1.03 and float(vl.at.ramscream) / slow_at[1] > float(vl.at.ramjet) / slow_at[0])
	# ... and across the speeds the headset's fourth gear takes it through (the craft set at each: the levers alone top out near 6,000)
	var at_speed := {}
	for mph: float in [3000.0, 5000.0, 7000.0]:
		for body in sim.bodies:
			body.vx = mph * 0.44704
			body.vy = 0.0
		await _fly(2.0 * FRAME)
		at_speed[mph] = [float(vl.ram_db[0]), float(vl.ram_db[1]), float(vl.at.ramjet), float(vl.at.ramscream)]
	_check("at 3,000 / 5,000 / 7,000 mph the roar is at %.1f / %.1f / %.1f dB and the scream at %.1f / %.1f / %.1f dB: each louder than the last, the scream gaining on the roar" % [
		at_speed[3000.0][0], at_speed[5000.0][0], at_speed[7000.0][0], at_speed[3000.0][1], at_speed[5000.0][1], at_speed[7000.0][1]],
		at_speed[5000.0][0] > at_speed[3000.0][0] + 0.5 and at_speed[7000.0][0] > at_speed[5000.0][0] + 0.5
		and at_speed[7000.0][1] - at_speed[3000.0][1] > at_speed[7000.0][0] - at_speed[3000.0][0] + 1.0)
	_check("... and its note climbs with it (the scream played x%.2f / x%.2f / x%.2f)" % [at_speed[3000.0][3], at_speed[5000.0][3], at_speed[7000.0][3]],
		at_speed[5000.0][3] > at_speed[3000.0][3] * 1.05 and at_speed[7000.0][3] > at_speed[5000.0][3] * 1.05 and at_speed[7000.0][2] > at_speed[3000.0][2] * 1.05)
	await _fly(1.0)
	_check("its thrust is the ramjet's full (%.2f) and it has not lit a second time" % vl.ram_thr, vl.ram_thr > 0.95 and vl.ram_n == 1 and vl.ram_outs == 0)

	# the boost
	var before: Array = (vl.ram_db as Array).duplicate()
	var before_at := float(vl.at.ramscream)
	await _fly(1.0, true)
	_check("the held boost (the sim's stage %d) pushes it a stage harder: the roar %+.1f dB, the scream %+.1f dB, its note x%.2f" % [sim.boost, float(vl.ram_db[0]) - float(before[0]), float(vl.ram_db[1]) - float(before[1]), float(vl.at.ramscream) / before_at],
		sim.boost == 1 and vl.ram_boost > 0.95 and float(vl.ram_db[0]) - float(before[0]) > float(T.ram_boost_db[0]) - 0.3
		and float(vl.ram_db[1]) - float(before[1]) > float(T.ram_boost_db[1]) - 0.3 and float(vl.at.ramscream) > before_at * 1.05)
	await _fly(1.0)
	_check("let go, it comes back to where it was (within 0.5 dB of the roar before the boost)", vl.ram_boost < 0.05 and absf(float(vl.ram_db[0]) - float(before[0])) < 0.5)

	# one engine out
	sim.eL.heat = 1.3
	sim.eL.flameout = true
	await _fly(1.0)
	_check("the left engine flamed out: its voice goes with it (in %.3f, %s, %d shut-down shot) and the right's plays on (in %.2f, mode %s, %d shut-downs)" % [vl.ram,
		"loops paused" if _paused(0) else "LOOPS STILL PLAYING", vl.ram_outs, vr.ram, sim.mode, vr.ram_outs],
		not vl.ram_lit and vl.ram < 0.01 and _paused(0) and vl.ram_outs == 1 and shot_l.stream == audio._ram_out[0] and vr.ram_lit and vr.ram > 0.99 and _heard(1) and vr.ram_outs == 0)
	sim.eL.heat = 0.0
	sim.eL.flameout = false
	await _fly(1.0)
	_check("relit, the left engine's ramjet catches again (its second light-up, with its shot)", vl.ram_lit and vl.ram_n == 2 and vl.ram > 0.99 and shot_l.stream == audio._ram_light[0])

	# the shut-down
	var note := float(vl.at.ramscream)
	armed = false
	await _fly(FRAME)
	_check("disarmed: the sim is back on the burner and both voices shut down, each with its own take of the cut-off",
		sim.mode == "burner" and not vl.ram_lit and not vr.ram_lit and shot_l.playing and shot_l.stream == audio._ram_out[0] and shot_r.stream == audio._ram_out[1] and vr.ram_outs == 1)
	await _fly(0.2)
	_check("a fifth of a second on it is %.0f%% of the way out and its note has fallen to x%.2f" % [100.0 * (1.0 - vl.ram), float(vl.at.ramscream) / note],
		vl.ram < 0.2 and float(vl.at.ramscream) < note * 0.7)
	await _fly(0.8)
	_check("a second on there is nothing of it: its loops are paused again, and the burner's rumble is back (%.2f dB)" % (vl.players.burner[0] as AudioStreamPlayer).volume_db,
		vl.ram < 1e-3 and _paused(0) and _paused(1) and absf((vl.players.burner[0] as AudioStreamPlayer).volume_db - burner_was) < 0.3)

	# a blink earns no second shot
	armed = true
	await _fly(0.2)
	armed = false
	await _fly(0.1)
	armed = true
	await _fly(FRAME)
	_check("armed, disarmed and armed again inside %.1f s: it lights again (its loops come back) without a second light-up shot" % T.ram_relight_s,
		vl.ram_lit and vl.ram_n == 4 and shot_l.stream == audio._ram_out[0])
	await _fly(1.0)

	# the audio gate's switch
	audio.solo = "v8"
	await _fly(0.1)
	var quiet := (vl.players.ramjet[0] as AudioStreamPlayer).volume_db <= -80.0 and _paused(0)
	audio.solo = "ramjet"
	await _fly(0.1)
	_check("solo: another layer alone silences it; solo \"ramjet\" plays its roar and its scream and nothing else",
		quiet and _heard(0) and (vl.players.v8[0] as AudioStreamPlayer).volume_db <= -80.0 and (vl.players.turbine[0] as AudioStreamPlayer).volume_db <= -80.0)
	audio.solo = ""

	# a crash takes it with the rest
	shot_l.stop()
	sim.crash_t = 1.0
	for f in 45:
		audio.update({"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}, FRAME)
	_check("a crash: the ramjet's voice goes with the engines', at once and with no shut-down shot (in %.3f)" % vl.ram,
		not vl.ram_lit and vl.ram < 0.02 and not shot_l.playing and (vl.players.ramjet[0] as AudioStreamPlayer).volume_db <= -80.0)
	sim.crash_t = 0.0

	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
	audio.queue_free()
	await process_frame
	audio = null
	sim = null
	await process_frame
	print("RAMJET AUDIO %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
