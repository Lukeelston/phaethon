## The start-up, heard: a whole cold start worked in the cockpit in real time, so the engine's movie
## writer records what the game itself plays (the start-up's sounds and the engines' voices, mixed
## as a pilot gets them). The picture is the seat's, small; the sound is the point. Run windowed:
## --xr-mode off --resolution 640x360 --fixed-fps 120 --write-movie FILE.avi
## -s res://tests/record_startup.gd -- --out=DIR
## and take the sound out of the film (ffmpeg -i FILE.avi -vn FILE.wav). No --mute. Each thing done
## is printed with its time (RECORD lines), to mark the recording with.
extends "res://tests/render_startup.gd"

var clock := 0.0


func _did(what: String, seconds: float) -> void:
	print("RECORD %.2f s: %s" % [clock, what])
	clock += seconds
	await _advance(seconds, true)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Seat._nose_loaded = true        # (the pilot's saved choices stay out of it)
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.approach_display.process_mode = Node.PROCESS_MODE_DISABLED      # (stepped in _advance)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr or seat.overhead == null or seat.startup_audio == null:
		push_error("This needs the Eridanus Network road, a monoscopic viewport, the roofed cockpit and sound.")
		quit(1)
		return
	_set_pose(98)
	for i in 600:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
	seat.cam.rotation_degrees = Vector3(14, 0, 0)
	var s = seat.startup
	levers = [0.0, 0.0]
	s.cold()
	seat._turbine_lamp = false
	await _did("cold and dark", 1.0)
	s.flick("batt", 1)
	await _did("1 BATT up: the bus, the self-test", Sequence.SELFTEST_S + 1.4)
	s.press_start(0.0)
	await _did("START pressed too soon: refused", 1.2)
	s.flick("engine", 1)
	await _did("2 ENGINE: the guard lifted", 0.8)
	s.flick("engine", 1)
	await _did("2 ENGINE: the switch thrown (pumps, binder), the guard falls shut", Sequence.GUARD_AFTER_S + 1.8)
	s.press_start(0.0)
	await _did("3 START: left engine, then the right", Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 2.6)
	levers = [1.0, 1.0]
	await _did("4 the run-up: both levers held against the brake", Sequence.TURBINE_UP_S + 0.8)
	for key in s.checks:
		s.checks[key] = true
	levers = [0.0, 0.0]
	await _did("levers back", Sequence.TURBINE_DOWN_S + 1.0)
	s.flick("park", -1)
	await _did("5 PARK released: cleared", 2.5)
	s.flick("park", 1)
	await _did("PARK set again", 1.5)
	s.flick("engine", 1)
	await _did("ENGINE guard lifted", 0.8)
	s.flick("engine", -1)
	await _did("ENGINE off: both engines cut", 2.5)
	s.flick("batt", -1)
	await _did("BATT off: dark", 2.0)
	print("RECORD %.2f s: end" % clock)
	seat.free()
	quit()
