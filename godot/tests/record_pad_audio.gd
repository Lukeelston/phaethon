## Record the real cockpit Master output on a cold Glacier start, with the pilot seated.
## --headless --xr-mode off --audio-driver Dummy --max-fps 60 --path godot
## -s res://tests/record_pad_audio.gd -- --out=C:/temp/pad.wav [--stems]
## Optional simultaneous StartPad and Engines recordings retain the in-game pan and gain.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
var seat
var out := ""
var records := {}
var levers := [0.0, 0.0]
var gear := 1
var clock := AudioEffectCapture.new()
var first_frame := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	_run.call_deferred()


func _advance(seconds: float) -> void:
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1e6)
	var tick := Time.get_ticks_usec()
	while Time.get_ticks_usec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := minf((now - tick) * .000001, .10)
		tick = now
		seat.inp = {"thrL": levers[0], "thrR": levers[1], "brkL": 0., "brkR": 0., "repair": false, "reignite": false}
		seat.startup.step(delta, levers, gear)
		seat._apply_startup(delta)
		seat._process(delta)


func _mark(label: String) -> void:
	var sample := clock.get_pushed_frames() + clock.get_discarded_frames() - first_frame
	print("PAD MIX %.3f %s" % [float(sample) / AudioServer.get_mix_rate(), label])


func _run() -> void:
	if out.is_empty():
		push_error("Pass --out= and a writable WAV path.")
		quit(1)
		return
	Seat._nose_loaded = true
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = "city:GLACIER"
	Seat.pad_start = true
	Seat.cold_start = true
	Seat.cold_on_entry = true
	Seat.best_dir = OS.get_user_data_dir().path_join("record_pad_audio_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0  # script the controls; the cockpit still steps and mixes every frame
	if not seat.pad or not seat.pad.audio or seat.startup.batt or seat.pad.station_id != "glacier":
		push_error("Capture needs the cold Glacier cockpit with audio enabled.")
		quit(1)
		return
	await _advance(2)
	var buses := ["Master"]
	if "--stems" in OS.get_cmdline_user_args():
		buses.append_array(["StartPad", "Engines"])
	for bus: String in buses:
		var rec := AudioEffectRecord.new()
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), rec)
		records[bus] = rec
	AudioServer.add_bus_effect(0, clock)
	for rec: AudioEffectRecord in records.values():
		rec.set_recording_active(true)
	first_frame = clock.get_pushed_frames() + clock.get_discarded_frames()
	_mark("cart under load")
	await _advance(1.5)
	seat.startup_work("batt", 1)
	await _advance(3.3)
	seat.startup_work("engine", 1)
	await _advance(.4)
	seat.startup_work("engine", 1)
	await _advance(1.5)
	_mark("starter engaged")
	if seat.startup_work("start", 1) != "start":
		push_error("The starter was refused.")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 9000
	while not seat.startup.all_running() and Time.get_ticks_msec() < deadline:
		await _advance(.04)
	if not seat.startup.all_running():
		push_error("The engines failed to reach idle.")
		quit(1)
		return
	_mark("both engines running, lead drops")
	await _advance(1.6)
	levers = [1.0, 1.0]
	gear = 2
	await _advance(3.1)
	levers = [0.0, 0.0]
	await _advance(3.6)
	if not seat.startup.checks_done() or seat.startup_work("park", -1) != "park_release":
		push_error("The pilot failed the run-up or could not release the brake.")
		quit(1)
		return
	_mark("brake released, gate lifts")
	deadline = Time.get_ticks_msec() + 4000
	while seat.pad.gate_open < 1 and Time.get_ticks_msec() < deadline:
		await _advance(.03)
	if seat.pad.gate_open < 1:
		push_error("The gate failed to clear.")
		quit(1)
		return
	_mark("gate clear, station answers")
	await _advance(2.3)
	_mark("end")
	for rec: AudioEffectRecord in records.values():
		rec.set_recording_active(false)
	var ok := true
	for bus: String in buses:
		var wave: AudioStreamWAV = records[bus].get_recording()
		var path := out if bus == "Master" else out.get_basename() + "_" + bus + ".wav"
		if not wave or wave.get_length() < 10.0 or wave.save_to_wav(path) != OK:
			ok = false
		else:
			print("PAD MIX wrote ", path, " (", wave.get_length(), " s)")
	seat.free()
	quit(0 if ok else 1)
