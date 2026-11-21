## The start-up from the pilot's seat (vr/startup_sequence.gd, vr/overhead_panel.gd): stills of the
## panel under the header and of the cockpit at each step, in daylight just outside the Eridanus
## terminal. Run windowed, as render_cockpit_spike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_startup.gd -- --mute --out=DIR [--views=a,b] [--pose=N]
extends "res://tests/render_terminal_art.gd"

const Sequence := preload("res://vr/startup_sequence.gd")
# Name, head offset from the seated eye (m), where the head is turned (degrees: up, left), and
# how far through the start-up the craft is.
const VIEWS := [
	["s1-cold", Vector3(0.0, 0.0, 0.0), Vector3(20, 0, 0), "cold"],
	["s2-cold-dash", Vector3(0.0, -0.02, -0.12), Vector3(-24, 0, 0), "cold"],
	["s3-self-test", Vector3(0.0, -0.02, -0.12), Vector3(-24, 0, 0), "selftest"],
	["s4-battery-on", Vector3(0.0, 0.0, 0.0), Vector3(20, 0, 0), "power"],
	["s5-guard-up", Vector3(-0.1, 0.13, -0.1), Vector3(40, 30, 0), "guard"],
	["s6-armed", Vector3(0.1, 0.13, -0.1), Vector3(40, -30, 0), "armed"],
	["s7-armed-ahead", Vector3(0.0, 0.0, 0.0), Vector3(4, 0, 0), "armed"],
	["s8-cranking", Vector3(0.0, 0.0, 0.0), Vector3(14, 0, 0), "cranking"],
	["s9-run-up", Vector3(0.0, 0.0, 0.0), Vector3(6, 0, 0), "runup"],
	["s10-run-up-dash", Vector3(0.0, -0.02, -0.12), Vector3(-24, 0, 0), "runup"],
	["s11-ready", Vector3(0.0, 0.0, 0.0), Vector3(20, 0, 0), "ready"],
	["s12-flying", Vector3(0.0, 0.0, 0.0), Vector3(20, 0, 0), "flying"],
	["s13-left-pod", Vector3(-0.14, 0.17, -0.14), Vector3(44, 26, 0), "power"],
	["s14-right-pod", Vector3(0.14, 0.17, -0.14), Vector3(44, -26, 0), "ready"],
]
var levers := [0.0, 0.0]


## A stretch of time in the cockpit, the sequence stepped as _read_input would step it.
func _advance(seconds: float, shown := false) -> void:
	var s = seat.startup
	for frame in roundi(seconds / STEP):
		seat.inp = {"thrL": levers[0], "thrR": levers[1], "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
		s.gears = true
		s.step(STEP, levers, 1)
		seat._apply_startup(STEP)
		seat._process(STEP)
		if shown or frame % 6 == 0:
			await process_frame


## Bring the craft from cold to a named point in its start-up.
func _reach(point: String) -> void:
	var s = seat.startup
	levers = [0.0, 0.0]
	s.cold()
	seat._turbine_lamp = false
	if point == "cold":
		await _advance(0.3)
		return
	s.flick("batt", 1)
	if point == "selftest":
		await _advance(Sequence.SELFTEST_S * 0.42)
		return
	await _advance(Sequence.SELFTEST_S + 0.6)
	if point == "power":
		return
	s.flick("engine", 1)
	if point == "guard":
		await _advance(0.6)
		return
	s.flick("engine", 1)
	await _advance(Sequence.GUARD_AFTER_S + 0.6)
	if point == "armed":
		return
	s.press_start(0.0)
	if point == "cranking":
		await _advance(Sequence.STAGGER_S + 0.5)
		return
	await _advance(Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 0.4)
	levers = [1.0, 1.0]
	await _advance(Sequence.TURBINE_UP_S + (0.4 if point == "runup" else 0.1))
	if point == "runup":
		return
	for key in s.checks:
		s.checks[key] = true
	levers = [0.0, 0.0]
	await _advance(Sequence.TURBINE_DOWN_S + 0.4)
	if point == "ready":
		return
	s.flick("park", -1)
	await _advance(Sequence.CLEARED_S + 0.6)


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var only := PackedStringArray()
	var pose := 98
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--pose="):
			pose = int(arg.trim_prefix("--pose="))
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat._nose_loaded = true        # (the pilot's saved choices stay out of the pictures)
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr or seat.overhead == null:
		push_error("This needs the Eridanus Network road, a monoscopic viewport and the roofed cockpit.")
		quit(1)
		return
	_set_pose(pose)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		_set_pose(pose)
		seat.cam.position = view[1]
		seat.cam.rotation_degrees = view[2]
		await _reach(view[3])
		await _advance(0.25, true)
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("STARTUP_SHOT %s: %s" % [view[0], seat.startup.message().replace("\n", " / ")])
	seat.free()
	quit()
