## The craft's power's controls from the pilot's seat (sim/pilot_craft.gd TRAITS; vr_cockpit.gd: the guarded POWER
## switch on the left console's inboard face up front, under the SLIDE switch and beside the left lever, its button
## forward of it; since flight 34, when they were beside his thigh). The production seat (XR off) on the range,
## standing still, through the cockpit's own camera at the eye point with the head turned to them:
##   power          the head turned down and left to the console's front: the switch, the button, the lever, SLIDE
##   power-close    the same, nearer: the legends, the guards, the ring
##   power-wide     wider: the console's front with them on it, the lever and the map
##   lever-map      where the left grip at full throttle passes under the map's screen (give --levers=1)
##   port-wide      the left lever, the console's front, the map and the dash's left end at once
##   console-front  the console's front from a little higher: the SLIDE switch, and under it the power's controls
## --state=ready|active|charging|safe stands the power there first (the ring steady, pulsing, dark; the switch at SAFE).
## --vehicle=<id> for a craft's own cockpit. --levers=0.87 stands the throttle levers there (else at idle).
## Run windowed: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_power_controls.gd -- --mute --out=DIR [--views=power,power-close] [--state=ready] [--vehicle=kiln]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Canopy := preload("res://view/canopy.gd")
const STEP := 1.0 / 120.0
# name, the head's turn (degrees up, degrees to the left), the field of view
const VIEWS := [
	["power", -38.0, 51.0, 45.0],
	["power-close", -38.0, 51.0, 22.0],
	["power-wide", -30.0, 48.0, 70.0],
	["lever-map", -29.0, 41.0, 40.0],
	["port-wide", -24.0, 40.0, 80.0],
	["console-front", -33.0, 52.0, 45.0],
]

var seat
var out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func _frame() -> void:
	var sim = seat.sim
	seat._follow_origin()
	seat._sync_craft(STEP)
	seat._place_camera(1.0)
	seat.craft.sync_cables(sim, STEP)
	seat._sync_world()
	seat._update_hud()
	seat._apply_shudder(STEP)
	if seat.has_method("_show_console"):
		seat._show_console(STEP)
	if seat.power_switch:
		seat.power_switch.power = 1.0
		seat.power_switch.show_state(not seat.power_armed, 0.0 if seat.power_armed else 1.0, false)
	if seat.power_button:
		seat.power_button.show_state(seat.power_ring(), 1.0, STEP)
	Canopy.update(seat.canopy, 0.0, sim.hblend, sim.mode, STEP)
	for hand in seat.hands.values():
		hand.get_child(0).visible = false
	await process_frame


func _run() -> void:
	var only := PackedStringArray()
	var state := "ready"
	var levers := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--state="):
			state = arg.trim_prefix("--state=")
		if arg.begins_with("--levers="):
			levers = float(arg.trim_prefix("--levers="))
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
	Seat._nose_loaded = true
	CM.nose_closed = true
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._slide_loaded = true
	Seat.slide_feel = true
	Seat._rush_loaded = true
	Seat.speed_rush = false
	Seat._startup_loaded = true
	Seat._school_loaded = true
	Seat._map_loaded = true
	Seat._options_loaded = true
	Seat._power_loaded = true
	Seat.power_armed = state != "safe"
	Seat.map_whole = true
	Seat.cold_start = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.benchmark_flight = true
	for i in 8:
		await process_frame
	seat.set_process(false)
	seat.cruise = 0.0
	seat.inp.thrL = levers
	seat.inp.thrR = levers
	var sim = seat.sim
	match state:      # the power where it is asked to be
		"active":
			sim.power_state = "active"
		"charging":
			sim.power_state = "charging"
		_:
			sim.power_state = "ready"
	print("POWER_SHOTS %s: %s, the switch at %s, the ring %s" % [sim.P.vehicle, seat.power_title(), "ARM" if seat.power_armed else "SAFE", seat.power_ring()])
	for view in VIEWS:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or String(view[0]) == prefix
		if not wanted:
			continue
		seat.cam.rotation_degrees = Vector3(float(view[1]), float(view[2]), 0.0)
		seat.cam.fov = float(view[3])
		for i in 30:
			await _frame()
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("POWER_SHOT ", view[0])
	seat.free()
	quit()
