## The GUN switch from the pilot's seat (Raids, 2026-11-24: vr_cockpit.gd gun_switch_mount; the Phaethon's and the
## Talon's on the starboard console's inboard face up front, outboard of the right lever and under the MODE switch;
## the Basilisk's on its starboard sill). The production seat (XR off) on the range, standing still, through the
## cockpit's own camera at the eye point with the head turned to it:
##   gun            the head turned down and right to the console's front: the switch, the right lever, MODE
##   gun-close      the same, nearer: the legends, the guards, the bat
##   gun-wide       wider: the console's front with it on it, the lever, the MODE switch and the dash's right end
##   starboard      the right lever, the console and the dash's right end at once
##   sill           the Basilisk's: the head turned right to its sill
## --gun=on stands the switch at GUN (else SAFE); --gun=hide takes it away (the cockpit as it was before it: the
## switch is the only thing it adds). --vehicle=<id> for a craft's own cockpit. --levers=0.87 stands the throttle
## levers there (else at idle).
## Run windowed: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_gun_switch.gd -- --mute --out=DIR [--views=gun,gun-close] [--gun=on] [--vehicle=talon]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Canopy := preload("res://view/canopy.gd")
const STEP := 1.0 / 120.0
# name, the head's turn (degrees up, degrees to the left), the field of view
const VIEWS := [
	["gun", -37.0, -50.0, 45.0],
	["gun-close", -37.0, -50.0, 22.0],
	["gun-wide", -30.0, -45.0, 70.0],
	["starboard", -24.0, -40.0, 80.0],
	["sill", -8.0, -68.0, 60.0],
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
	for sw in [seat.mode_switch, seat.slide_switch, seat.power_switch]:
		if sw:
			sw.power = 1.0
	if seat.gun_switch:
		seat.gun_switch.power = 1.0
		seat.gun_switch.show_state(not seat.gun_wanted, 0.0 if seat.gun_wanted else 1.0, false)
	Canopy.update(seat.canopy, 0.0, sim.hblend, sim.mode, STEP)
	for hand in seat.hands.values():
		hand.get_child(0).visible = false
	await process_frame


func _run() -> void:
	var only := PackedStringArray()
	var gun_on := false
	var gun_hidden := false
	var levers := 0.0
	var vehicle := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg == "--gun=on":
			gun_on = true
		if arg == "--gun=hide":
			gun_hidden = true
		if arg.begins_with("--levers="):
			levers = float(arg.trim_prefix("--levers="))
		if arg.begins_with("--vehicle="):
			vehicle = arg.trim_prefix("--vehicle=")
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
	Seat.power_armed = true
	Seat.map_whole = true
	Seat.cold_start = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	if vehicle != "":
		Seat.vehicle_override = vehicle
	seat = Seat.new()
	root.add_child(seat)
	seat.benchmark_flight = true
	for i in 8:
		await process_frame
	seat.set_process(false)
	seat.cruise = 0.0
	seat.inp.thrL = levers
	seat.inp.thrR = levers
	seat.gun_wanted = gun_on      # (the switch alone: no fire control is stepped here, so nothing comes out)
	if gun_hidden and seat.gun_switch:
		seat.gun_switch.free()
		seat.gun_switch = null
	print("GUN_SHOTS %s: the GUN switch %s, at %s" % [seat.sim.P.vehicle, ("at GUN" if gun_on else "at SAFE") if seat.gun_switch else "not fitted",
		seat.gun_switch.position if seat.gun_switch else Vector3.ZERO])
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
		print("GUN_SHOT ", view[0])
	seat.free()
	quit()
