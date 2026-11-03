## Speedcraft fourth keeps rising; Starfighter first stays bounded through the real audio path.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Controls := preload("res://input/quest_controls.gd")
const View := preload("res://view/craft_view.gd")
const EngineSound := preload("res://audio/engine_audio.gd")
const DT := 1.0 / 60.0
const SPEEDS := [1.2, 2.0, 4.0, 8.0]
var sim
var view
var audio
var controls
var reference := 0.0
var sf := 0.0
var checks := 0
var fails := 0
var capture_dir := ""
var capture_only := false
var repairing := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			capture_dir = arg.get_slice("=", 1)
		elif arg == "--capture-only":
			capture_only = true
	_run.call_deferred()

func _run() -> void:
	sim = Sim.new({"track": "range"})
	view = View.new()
	view.sim = sim
	audio = EngineSound.new()
	root.add_child(audio)
	audio.setup(sim)
	for layer in ["v8", "v12", "second", "turbine"]:
		var reference_frames: int = audio._streams[layer][0].loop_end
		var aligned := true
		for stream: AudioStreamWAV in audio._streams[layer]:
			aligned = aligned and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo \
				and stream.data.size() == reference_frames * 2 and stream.loop_end == reference_frames \
				and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		_check(layer + " imported pitch levels remain PCM16 with equal sample lengths", aligned and reference_frames > 44100)
	if capture_only:
		_check("capture-only run has an output directory", capture_dir != "")
		if capture_dir != "":
			await _capture()
		await _finish()
		return
	for handling in ["speed"]:
		sf = 1.0 if handling == "starfighter" else 0.0
		reference = Controls.V_TOP_SF if sf > 0.0 else Controls.V_TOP_SPEED
		controls = Controls.new()
		controls.scheme = "triggers"
		controls.set_gear(4)
		var targets := []
		var played := []
		for x in SPEEDS:
			await _advance(x, 35.0)
			targets.append([float(audio.voices[0].at.v8), float(audio.voices[0].at.v12)])
			played.append(_played_rpm())
		_check(handling + " full triggers stay at .87 while fourth reaches the audio path",
			absf(view.inp.thrL - 0.87) < 0.001 and absf(view.inp.thrR - 0.87) < 0.001 and view.inp.gearOverdrive and view.inp.gearIndex == 4)
		for k in range(1, SPEEDS.size()):
			_check("%s fourth target and played V8/V12 pitch rise at %.1fx reference speed" % [handling, SPEEDS[k]],
				targets[k][0] > targets[k - 1][0] * 1.01 and targets[k][1] > targets[k - 1][1] * 1.01 and
				played[k][0] > played[k - 1][0] * 1.01 and played[k][1] > played[k - 1][1] * 1.01)
		var equal_steps := []
		for x in [2.0, 3.0, 4.0]:
			await _advance(x, 12.0)
			equal_steps.append(_played_rpm())
		_check(handling + " equal speed increments produce progressively smaller audible pitch increments",
			equal_steps[1][0] - equal_steps[0][0] > equal_steps[2][0] - equal_steps[1][0] and
			equal_steps[1][1] - equal_steps[0][1] > equal_steps[2][1] - equal_steps[1][1] and
			equal_steps[2][0] > equal_steps[1][0] + 10.0)
		var high: Array = _played_rpm()
		await _advance(4.0, 2.0, 0.0)
		_check(handling + " throttle lift drops both engine notes at held high speed", _played_rpm()[0] < high[0] * 0.8 and _played_rpm()[1] < high[1] * 0.8)
		await _advance(4.0, 20.0)
		high = _played_rpm()
		controls.set_gear(3)
		await _advance(4.0, 2.0)
		_check(handling + " downshift restores the lower gear's bounded note", _played_rpm()[0] < high[0] * 0.8 and _played_rpm()[1] < high[1] * 0.8 and not view.inp.gearOverdrive)
		for gear in range(1, 4):
			controls.set_gear(gear)
			await _advance(2.0, 4.0)
			var lower := _played_rpm()
			await _advance(8.0, 4.0)
			_check("%s gear %d keeps its original ceiling" % [handling, gear], absf(_played_rpm()[0] - lower[0]) < 2.0 and absf(_played_rpm()[1] - lower[1]) < 2.0)
		controls.set_gear(4)
		await _advance(4.0, 20.0)
		var normal_spool: float = audio.voices[1].spool
		sim.mode = "burner"
		await _advance(4.0, 3.0)
		_check(handling + " afterburner still adds above the uncapped fourth-gear note", audio.voices[1].spool > normal_spool + 0.1)
		sim.mode = "ramjet"
		await _advance(4.0, 3.0)
		_check(handling + " ramjet still adds above afterburner", audio.voices[1].spool > normal_spool + 0.25)
		sim.mode = "normal"
		repairing = true
		await _advance(4.0, 2.0)
		_check(handling + " repair limits even an uncapped fourth-gear target", audio.voices[0].spool < 0.65 and audio.voices[1].spool < 0.65)
		repairing = false
		sim.eL.flameout = true
		await _advance(4.0, 8.0)
		_check(handling + " flameout still winds the failed side below idle", audio.voices[0].spool < -0.3 and audio.voices[0].fire < 0.001 and audio.voices[1].spool > 1.0)
		sim.eL.flameout = false
		await _advance(4.0, 1.0)
		_check(handling + " relight still brings the failed side back", audio.voices[0].spool > 0.0 and audio.voices[0].fire > 0.1)
		print("OVERDRIVE AUDIO METRICS ", handling, ": targets_rpm=", targets, " played_rpm=", played, " equal_speed_steps=", equal_steps)
	sf = 1.0
	reference = Controls.V_TOP_SF
	controls.sync_handling(sf)
	await _advance(1.2, 20.0)
	var sf_note := _played_rpm()
	await _advance(8.0, 20.0)
	_check("Starfighter first keeps a bounded note and never forwards overdrive", view.inp.gearIndex == 0 and not view.inp.gearOverdrive and absf(_played_rpm()[0] - sf_note[0]) < 2.0 and absf(_played_rpm()[1] - sf_note[1]) < 2.0)
	await _advance(8.0, 2.0, 0.0)
	_check("Starfighter throttle lift drops both engine notes", _played_rpm()[0] < sf_note[0] * 0.8 and _played_rpm()[1] < sf_note[1] * 0.8)
	if capture_dir != "":
		await _capture()
	await _finish()

func _finish() -> void:
	view.free()
	view = null
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
	audio.queue_free()
	await process_frame
	audio = null
	sim = null
	controls = null
	await process_frame
	print("OVERDRIVE AUDIO %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)

## Capture each actual solo layer at settled speed. The Python checker measures the PCM
## against the requested RPM, so a remaining AudioStreamPlayer pitch cap cannot hide here.
func _capture() -> void:
	var err := DirAccess.make_dir_recursive_absolute(capture_dir)
	_check("capture directory is available", err == OK)
	if err != OK:
		return
	controls = Controls.new()
	controls.scheme = "triggers"
	controls.set_gear(4)
	reference = Controls.V_TOP_SPEED
	sf = 0.0
	var records := []
	for layer in ["v8", "v12"]:
		audio.solo = layer
		for x in [1.2, 2.0, 3.0, 4.0, 8.0]:
			await _advance(x, 35.0)
			var rec := AudioEffectRecord.new()
			AudioServer.add_bus_effect(0, rec)
			rec.set_recording_active(true)
			var began := Time.get_ticks_usec()
			var previous := began
			while Time.get_ticks_usec() - began < 1500000:
				var now := Time.get_ticks_usec()
				_tick(x, (now - previous) / 1000000.0)
				previous = now
				await process_frame
			rec.set_recording_active(false)
			var wav := rec.get_recording()
			AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
			var path := capture_dir.path_join("%s_x%.1f.wav" % [layer, x])
			_check("saved %s capture at %.1fx reference speed" % [layer, x], wav.save_to_wav(path) == OK)
			records.append({"layer": layer, "speed_ratio": x, "wav": path,
				"target_rpm": float(audio.voices[0].at[layer]), "player_pitch": float(audio.voices[0].players[layer][-1].pitch_scale)})
	var index := FileAccess.open(capture_dir.path_join("captures.json"), FileAccess.WRITE)
	_check("capture index opened", index != null)
	if index:
		index.store_string(JSON.stringify(records, "\t") + "\n")
		index.close()

func _tick(x: float, dt: float, trigger := 1.0) -> void:
	var speed := x * reference
	sim.pod.vx = speed
	sim.pod.vy = 0.0
	var out: Dictionary = controls.update({"lt": trigger, "rt": trigger, "lg": 0.0, "rg": 0.0,
		"ls": Vector2.ZERO, "rs": Vector2.ZERO, "speed": speed, "vtop": reference, "sf": sf, "yaw": 0.0}, dt)
	# Same forwarding contract as VRCockpit; these remain ordinary physics lever values.
	view.inp = {"thrL": out.thrL, "thrR": out.thrR, "brkL": out.brkL, "brkR": out.brkR,
		"repair": repairing, "gearRpm": out.rpm, "gearIndex": controls.gear, "gearOverdrive": out.overdrive}
	audio.update(view._engine_inp(), dt)

func _advance(x: float, seconds: float, trigger := 1.0) -> void:
	for frame in int(seconds / DT):
		_tick(x, DT, trigger)
		if frame % 120 == 119:
			await process_frame

func _played_rpm() -> Array:
	return [audio.voices[0].players.v8[-1].pitch_scale * float(audio._rate_at.v8),
		audio.voices[0].players.v12[-1].pitch_scale * float(audio._rate_at.v12)]

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		fails += 1
	print(("PASS " if passed else "FAIL ") + label)
