## The two side consoles from the pilot's seat (push 44: their spare toggles and two knobs made to do real things;
## vr/console_switches.gd). The production seat (XR off) on the Network on a fair afternoon, standing still on a
## straight road, through the cockpit's own camera at the eye point with the head turned to each console:
##   L-console, R-console      the head turned down to the console, the whole of it
##   L-close, R-close          the same, nearer: the three toggles and their legends
##   L-knobs, R-knobs          the head turned further aft: the knobs (TAC DIM aft on the left, TAC WARN forward on the right)
##   L-levers, R-levers        the throttle levers pushed to full (they stand at idle in the others)
## It asks nothing of the cockpit that a checkout from before the switches lacks, so the same tool pictures the
## consoles as they were: run it in each, and lay the two sets side by side.
##   --on=tactical,field       stand these OPTIONS lines on (by their keys) before the pictures; the rest off
##   --dim=0.4 --pace=0.6      and the knobs there (else at 1)
## Run windowed: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_console_switches.gd -- --mute --out=DIR [--views=L,R-close] [--on=...]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Canopy := preload("res://view/canopy.gd")
const STEP := 1.0 / 120.0
# name, the head's turn (degrees up, degrees to the left), the field of view, the throttles (0 idle .. 1 full)
const VIEWS := [
	["L-console", -37.0, 74.0, 58.0, 0.0],
	["R-console", -37.0, -74.0, 58.0, 0.0],
	["L-close", -34.0, 77.0, 30.0, 0.0],
	["R-close", -34.0, -77.0, 30.0, 0.0],
	["L-knobs", -31.0, 108.0, 34.0, 0.0],
	["R-knobs", -32.0, -100.0, 34.0, 0.0],
	["L-levers", -37.0, 74.0, 58.0, 1.0],
	["R-levers", -37.0, -74.0, 58.0, 1.0],
]

var seat
var out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


## A frame of the seat as the game runs one, the sim not stepped.
func _frame(levers: float) -> void:
	var sim = seat.sim
	seat._follow_origin()
	seat._sync_craft(STEP)
	seat._place_camera(1.0)
	seat.craft.sync_cables(sim, STEP)
	seat._sync_world()
	seat._update_hud()
	seat._apply_shudder(STEP)
	seat._sync_rush(STEP)
	Canopy.update(seat.canopy, 0.0, sim.hblend, sim.mode, STEP)
	if seat.has_method("_show_console"):
		seat._show_console(STEP)
	for pivot: Node3D in seat.lever_pivots:
		pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, levers))
	for hand in seat.hands.values():
		hand.get_child(0).visible = false
	await process_frame


func _run() -> void:
	var only := PackedStringArray()
	var on := PackedStringArray()
	var knob := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--on="):
			on = arg.trim_prefix("--on=").split(",", false)
		if arg.begins_with("--dim="):
			knob["dim"] = float(arg.trim_prefix("--dim="))
		if arg.begins_with("--pace="):
			knob["pace"] = float(arg.trim_prefix("--pace="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true      # (the pilot's saved choices stay out of the pictures)
	CM.nose_closed = true
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._slide_loaded = true
	Seat.slide_feel = true
	Seat._rush_loaded = true
	Seat.speed_rush = true
	Seat._startup_loaded = true
	Seat._school_loaded = true
	Seat._map_loaded = true
	Seat._options_loaded = true
	Seat.map_whole = true
	Seat.map_scheme = 0
	Seat.cold_start = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.benchmark_flight = true      # (nothing written to the pilot's file, and no flight report on the way out)
	for i in 8:      # (a few frames of the game itself: the sim has stepped, and has its tow links to draw)
		await process_frame
	seat.set_process(false)
	seat.cruise = 0.0
	if root.use_xr or seat.sim.kind != "network":
		push_error("These pictures want the Network and a monoscopic viewport.")
		quit(1)
		return
	var sim = seat.sim
	for i in 800:
		seat.network_world.sync(sim.pod.x, sim.pod.y)
		seat.landscape.sync(sim.pod.x, sim.pod.y)
		if i % 40 == 0:
			await process_frame
	# the switches as asked (a checkout from before them has none: its consoles as they were)
	var console = seat.get("console")
	if console != null:
		for key: String in console.KEYS:
			seat.console_set(key, on.has(key))
		for key: String in knob:
			console.set_knob(key, float(knob[key]))
		var states := []
		for key: String in console.KEYS:
			states.append("%s %s" % [key, "ON" if seat.option_on(key) else "off"])
		print("CONSOLE_SHOTS %s; dim %.2f, pace %.2f" % [", ".join(states), console.knob_value("dim"), console.knob_value("pace")])
	else:
		print("CONSOLE_SHOTS a cockpit from before the console's switches: as it was")
	for view in VIEWS:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or String(view[0]).begins_with(prefix)
		if not wanted:
			continue
		seat.cam.rotation_degrees = Vector3(float(view[1]), float(view[2]), 0.0)
		seat.cam.fov = float(view[3])
		for i in 40:
			await _frame(float(view[4]))
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("CONSOLE_SHOT ", view[0])
	seat.free()
	quit()
