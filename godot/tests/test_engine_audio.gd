## EngineAudio capture: flies a scripted lever profile on the range, records the master bus
## and logs each layer's RPM, so tools/engine_audio_check.py can confirm the pitch follows
## the levers. Real time (the audio thread runs at wall-clock pace), about 31 s.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --audio-output-latency 10 --max-fps 90 --path godot -s res://tests/test_engine_audio.gd
##        -- --out=C:/path/capture.wav [--solo=v8|v12|turbine|burner] [--flat]
## --flat holds every gain at 1 and the low-pass open, so only the band crossfades move the level.
## Writes capture.wav and capture.csv. Exit code 0 = streams loaded, audio captured, no clipping.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const EngineAudioScript := preload("res://audio/engine_audio.gd")
const DT := 1.0 / 480.0
const END := 30.5

var sim
var audio
var rec: AudioEffectRecord
var out_path := "user://engine_capture.wav"
var solo := ""
var flat := false
var t := 0.0
var acc := 0.0
var log_t := 0.0
var rows := PackedStringArray(["t,thrL,thrR,mode,outL,outR,sL,sR,v8L,v8R,v12L,v12R,turbL,turbR"])
var started := false
var clock: AudioStreamPlayer


## The lever profile: idle, a full rev, the afterburner, a lever split, a left flameout with
## its wind-down, a reignite, then lever blips: fast sweeps through several RPM bands at once.
static func profile(time: float) -> Dictionary:
	var l := 0.0
	var r := 0.0
	if time < 2.0:
		pass
	elif time < 8.0:
		l = 0.87 * (time - 2.0) / 6.0
		r = l
	elif time < 10.0:
		l = 0.87
		r = 0.87
	elif time < 12.5:
		l = 1.0   # into the gate: afterburner
		r = 1.0
	elif time < 15.0:
		l = 0.5
		r = 0.5
	elif time < 19.0:
		l = 0.87   # split: the left engine screams, the right one idles along
		r = 0.15
	elif time < 21.0:
		pass
	elif time < 27.0:
		l = 0.6
		r = 0.6
	else:
		l = 0.87 if int((time - 27.0) / 0.6) % 2 == 0 else 0.25   # blips every 0.6 s
		r = l
	return {"thrL": l, "thrR": r, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": time >= 24.0}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.get_slice("=", 1)
		elif a.begins_with("--solo="):
			solo = a.get_slice("=", 1)
		elif a == "--flat":
			flat = true
	sim = CraftSimScript.new({"track": "range"})
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)


func _process(_delta: float) -> bool:
	if not started:   # the root is only ready for players from the first frame
		audio = EngineAudioScript.new()
		audio.solo = solo
		audio.flat = flat
		root.add_child(audio)
		audio.setup(sim)
		# Time comes from the audio clock: a silent player's position. Headless Godot mixes
		# through the Dummy driver, which runs ~1% slow of the wall clock, and frame deltas would
		# also count the setup frame the recording never heard. (A sound card clocks itself.)
		var silence := AudioStreamWAV.new()
		silence.mix_rate = 8000
		var zeros := PackedByteArray()
		zeros.resize(8000 * int(END + 10.0))
		silence.data = zeros
		clock = AudioStreamPlayer.new()
		clock.stream = silence
		clock.volume_db = -80.0
		root.add_child(clock)
		clock.play()
		rec.set_recording_active(true)
		started = true
		return false
	var now := clock.get_playback_position() + AudioServer.get_time_since_last_mix()
	var delta := maxf(0.0, now - t)
	t = now
	var inp := profile(t)
	if t >= 21.0 and t - delta < 21.0:
		sim.eL.heat = 1.1   # force a left flameout
	acc += minf(delta, 0.05)
	while acc >= DT:
		sim.step(inp, DT)
		sim.events.clear()
		acc -= DT
	audio.update(inp, delta)
	if t - log_t >= 0.05:
		log_t = t
		var vl: Dictionary = audio.voices[0]
		var vr: Dictionary = audio.voices[1]
		rows.append("%.3f,%.3f,%.3f,%s,%d,%d,%.4f,%.4f,%.1f,%.1f,%.1f,%.1f,%.4f,%.4f" % [t, inp.thrL, inp.thrR,
			sim.mode, int(sim.eL.flameout), int(sim.eR.flameout), vl.spool, vr.spool,
			vl.at.v8, vr.at.v8, vl.at.v12, vr.at.v12, vl.at.turbine, vr.at.turbine])
	if t < END:
		return false
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	var fails := 0
	var loaded := 0
	for layer in EngineAudioScript.LAYERS:
		for s: AudioStreamWAV in audio._streams[layer]:
			if s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.loop_end > 44100 and s.format == AudioStreamWAV.FORMAT_16_BITS:
				loaded += 1
	var total := 0
	for layer in EngineAudioScript.LAYERS:
		total += audio._streams[layer].size()
	fails += _check("%d/%d loops loaded as forward-looping 16-bit PCM" % [loaded, total], loaded == total and total > 0)
	var data := wav.data   # the getter copies the whole buffer: read it once
	var frames := data.size() >> 2
	var peak := 0
	var sq := 0.0
	for i in range(0, frames * 2, 7):   # stride: plenty for peak/RMS on 2.4 M samples
		var v := absi(data.decode_s16(i * 2))
		peak = maxi(peak, v)
		sq += v * v
	var rms_db := 20.0 * log(sqrt(sq / (frames * 2 / 7.0)) / 32768.0) / log(10.0)
	print("capture: %.1f s, peak %.1f dBFS, rms %.1f dBFS" % [float(frames) / wav.mix_rate,
		20.0 * log(maxf(peak, 1) / 32768.0) / log(10.0), rms_db])
	fails += _check("captured %.1f s of the %.0f s profile" % [float(frames) / wav.mix_rate, END], frames > wav.mix_rate * (END - 2.0))
	fails += _check("audible (rms above -45 dBFS)", rms_db > -45.0)
	fails += _check("no clipping (peak below full scale)", peak < 32767)
	wav.save_to_wav(out_path)
	var f := FileAccess.open(out_path.get_basename() + ".csv", FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("wrote ", ProjectSettings.globalize_path(out_path))
	print("ENGINE AUDIO ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)
	return true


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
