## The start-up from the pilot's seat (vr/startup_sequence.gd, vr/overhead_panel.gd): stills of the
## panel under the header and of the cockpit at each step, in daylight just outside the Eridanus
## terminal. Run windowed, as render_cockpit_spike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_startup.gd -- --mute --out=DIR [--views=a,b] [--pose=N]
## The a views are the checklist on the glass in motion (view/startup_glass.gdshader), each caught
## part way through what it does, at about a headset's own pixels; beside each is saved the
## projector's own picture of it (NAME-picture.png). The glass's clockwork is stepped with the
## sequence here, not by the frames drawn, so a view is the same view every time.
extends "res://tests/render_terminal_art.gd"

const Sequence := preload("res://vr/startup_sequence.gd")
# Name, head offset from the seated eye (m), where the head is turned (degrees: up, left), how far
# through the start-up the craft is, and (optional) the field of view.
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
	["a1-bus-comes-up", Vector3.ZERO, Vector3(19, 0, 0), "bus", 38.0],
	["a2-self-test", Vector3.ZERO, Vector3(19, 0, 0), "selftest", 38.0],
	["a3-refused", Vector3.ZERO, Vector3(19, 0, 0), "refused", 38.0],
	["a4-step-ticked-off", Vector3.ZERO, Vector3(19, 0, 0), "ticking", 38.0],
	["a5-next-page-arriving", Vector3.ZERO, Vector3(19, 0, 0), "typing", 38.0],
	["a6-press-start", Vector3.ZERO, Vector3(19, 0, 0), "armed", 38.0],
	["a7-left-engine-cranking", Vector3.ZERO, Vector3(19, 0, 0), "crank", 38.0],
	["a8-left-engine-catching", Vector3.ZERO, Vector3(19, 0, 0), "catch", 38.0],
	["a9-turbines-spooling", Vector3.ZERO, Vector3(19, 0, 0), "spooling", 38.0],
	["a10-release-the-brake", Vector3.ZERO, Vector3(19, 0, 0), "ready", 38.0],
	["a11-cleared-lands", Vector3.ZERO, Vector3(19, 0, 0), "cleared-0.0", 38.0],
	["a12-cleared-brakes-stowing", Vector3.ZERO, Vector3(19, 0, 0), "cleared-0.4", 38.0],
	["a13-cleared-held", Vector3.ZERO, Vector3(19, 0, 0), "cleared-1.5", 38.0],
	["a14-cranking-headset-field", Vector3.ZERO, Vector3(8, 0, 0), "crank", 96.0],
	["a15-cleared-headset-field", Vector3.ZERO, Vector3(8, 0, 0), "cleared-0.4", 96.0],
	# the status strip under the gauges through the start-up (push 26: its rail of five steps under the words)
	["t1-strip-battery-on", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "power", 16.0],
	["t2-strip-refused", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "refused", 16.0],
	["t3-strip-cranking", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "crank", 16.0],
	["t4-strip-turbines", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "spooling", 16.0],
	["t5-strip-ready", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "ready", 16.0],
	["t6-strip-cleared", Vector3(0.0, -0.02, -0.12), Vector3(-30, 16, 0), "cleared-0.4", 16.0],
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
		seat.approach_display._process(STEP)      # (the glass's clockwork, in the sequence's own time)
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
	if point == "bus":                     # (each of these is caught a quarter of a second later: the view's own settling)
		await _advance(0.23)
		return
	if point == "selftest":
		await _advance(Sequence.SELFTEST_S * 0.42)
		return
	await _advance(Sequence.SELFTEST_S + 0.6)
	if point == "power":
		return
	if point == "refused":
		s.press_start(0.0)
		await _advance(0.3)
		return
	s.flick("engine", 1)
	if point == "guard":
		await _advance(0.6)
		return
	s.flick("engine", 1)
	if point == "ticking" or point == "typing":
		await _advance(0.05 if point == "ticking" else 0.38)
		return
	await _advance(Sequence.GUARD_AFTER_S + 0.6)
	if point == "armed":
		return
	s.press_start(0.0)
	if point == "crank" or point == "catch":
		await _advance(0.65 if point == "crank" else Sequence.CRANK_S + 0.15)
		return
	if point == "cranking":
		await _advance(Sequence.STAGGER_S + 0.5)
		return
	await _advance(Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 0.4)
	levers = [1.0, 1.0]
	if point == "spooling":
		await _advance(0.95)
		return
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
	if point.begins_with("cleared-"):
		await _advance(float(point.trim_prefix("cleared-")))
		return
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
	var outlook := preload("res://view/outlook.gd")      # (--time=night --weather=clear: the panel after dark)
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
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
	seat.approach_display.process_mode = Node.PROCESS_MODE_DISABLED      # (stepped in _advance)
	seat.cruise = 0.0
	var wide: float = seat.cam.fov
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
		seat.cam.fov = float(view[4]) if view.size() > 4 else wide
		await _reach(view[3])
		await _advance(0.25, true)
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		if str(view[0]).begins_with("a") and seat.approach_display.port:
			seat.approach_display.port.get_texture().get_image().save_png(out_dir.path_join(str(view[0]) + "-picture.png"))
		var glass = seat.approach_display
		print("STARTUP_SHOT %s: %s | on the glass \"%s\" %s, up %.2f s, ticking %.2f, typing %.2f, sweep %.2f" % [view[0], seat.startup.message().replace("\n", " / "),
			glass.action.text, glass.checklist, glass.clock, glass.ticking, glass.typing, glass.sweeping])
	seat.free()
	quit()
