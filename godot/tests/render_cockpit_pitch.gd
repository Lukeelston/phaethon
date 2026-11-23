## What the pilot sees from his seat, for a change to where he sits or how the pod stands under him (push
## 40: the seat an inch forward, the pod pitched nose-down, the drift slider; vr_cockpit.gd SEAT_FWD,
## POD_PITCH). The production seat (XR off) on the Network on a fair afternoon, through the cockpit's own
## camera at the eye point with the head turned for each view, at 3,355 mph:
##   1-straight        on a straight road, the head level
##   2-left-bend       in the road's sharpest banked bend, flown as a left one: the craft leaning into it,
##   3-right-bend      the cockpit rolled and stepped out as it is in one; and the same bend the other way
##   4-left-console    the head turned down to the left console: the SLIDE switch (and what is behind it)
##   5-start-panel     the head tipped up to the start panel on the roof's header
##   6-instruments     the head tipped down to the dials
## It uses nothing of the cockpit's that is newer than push 39, so the same tool pictures a checkout from
## before a change and one from after it: run it in each, and lay the two sets side by side.
## Run windowed: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_cockpit_pitch.gd -- --mute --out=DIR [--nose=open] [--views=1,2]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Canopy := preload("res://view/canopy.gd")
const STEP := 1.0 / 120.0
const SPEED := 1500.0            # m/s (3,355 mph)
const LEAD := 14                 # samples of road before the bend's steepest lean that she is put (the bend lies ahead)
# name, the place ("straight", "left", "right"), the head's turn (degrees up, degrees to the left), the field of view
const VIEWS := [
	["1-straight", "straight", 0.0, 0.0, 96.0],
	["2-left-bend", "left", 0.0, 0.0, 96.0],
	["3-right-bend", "right", 0.0, 0.0, 96.0],
	["4-left-console", "straight", -36.0, 72.0, 56.0],
	["5-start-panel", "straight", 34.0, 0.0, 84.0],
	["6-instruments", "straight", -25.0, 0.0, 62.0],
]

var seat
var out_dir := ""
var _flat_drift := false      # --no-drift-pitch: the pod as it stood in a slide before push 42 (POD_PITCH and no more)


func _initialize() -> void:
	_run.call_deferred()


## The road's own radius at a sample, m (+ a bend to the left as its samples run), over `half` samples either way.
func _radius(R, i: int, half := 12) -> float:
	var a := clampi(i - half, 0, int(R.N) - 1)
	var b := clampi(i + half, 0, int(R.N) - 1)
	var turned := angle_difference(atan2(R.ty[a], R.tx[a]), atan2(R.ty[b], R.tx[b]))
	var run := Vector2(R.px[b] - R.px[a], R.py[b] - R.py[a]).length()
	return run / turned if absf(turned) > 1e-6 else INF


## Where to take the pictures: [road, sample, direction] for the straight, and for the bend flown as a
## left one and as a right one (the same bend, from its other end).
func _places() -> Dictionary:
	var sim = seat.sim
	var bend := []
	var steepest := 0.0
	var straight := []
	var straightest := 0.0
	for r in sim.roads.size():
		var R = sim.roads[r]
		if R.deck or r == int(sim.NET_PRESSURE[0]) or int(R.N) < 400:
			continue
		if R.banked:
			for i in range(60, int(R.N) - 60):
				if absf(R.bank[i]) > steepest:
					steepest = absf(R.bank[i])
					bend = [r, i]
		for i in range(200, int(R.N) - 200, 50):
			var least := INF
			for k in range(-4, 5):
				least = minf(least, absf(_radius(R, i + k * 25, 25)))
			if least > straightest and not is_inf(least):
				straightest = least
				straight = [r, i]
	if bend.is_empty() or straight.is_empty():
		return {}
	var B = sim.roads[bend[0]]
	var left_as_sampled: bool = _radius(B, bend[1]) > 0.0
	var radius := absf(_radius(B, bend[1]))
	print("PITCH_SHOTS the bend: %s sample %d, its deck leaning %.1f degrees, radius %.1f km (%.0f g at %.0f mph); the straight: %s sample %d" % [
		B.name, bend[1], rad_to_deg(steepest), radius / 1000.0, SPEED * SPEED / radius / 9.81, SPEED * 2.236936, sim.roads[straight[0]].name, straight[1]])
	return {"straight": [straight[0], straight[1], 1, 0.0],
		"left": [bend[0], bend[1] - LEAD * (1 if left_as_sampled else -1), 1 if left_as_sampled else -1, SPEED * SPEED / radius / 9.81],
		"right": [bend[0], bend[1] + LEAD * (1 if left_as_sampled else -1), -1 if left_as_sampled else 1, -SPEED * SPEED / radius / 9.81]}


## A frame of the seat as the game runs one, the sim not stepped: she is where she was put, at speed, and
## turning under `g` of cornering load (+ a left turn).
func _frame(g: float) -> void:
	var sim = seat.sim
	var c = seat.craft
	sim.eL.w = g * 9.81 / SPEED
	sim.eR.w = sim.eL.w
	var all := [sim.eL, sim.eR, sim.pod]
	if c._prev_v.size() == 3:
		for k in 3:      # (the model reads a body's load from its change of velocity: this frame's is the turn's)
			c._prev_v[k] = [all[k].vx + sin(all[k].th) * g * 9.81 * STEP, all[k].vy - cos(all[k].th) * g * 9.81 * STEP]
	seat._follow_origin()
	seat._sync_craft(STEP)
	seat._place_camera(1.0)
	c.sync_cables(sim, STEP)
	seat._sync_world()
	seat._update_hud()
	seat._apply_shudder(STEP)
	seat._sync_rush(STEP)
	Canopy.update(seat.canopy, SPEED, sim.hblend, sim.mode, STEP)
	for hand in seat.hands.values():
		hand.get_child(0).visible = false
	await process_frame


func _run() -> void:
	var only := PackedStringArray()
	var nose_closed := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg == "--nose=open":
			nose_closed = false
		# (push 42, the drift: which craft, how far the slider is up, and the same picture without the nose's
		# extra pitch for the slide, to lay beside the one with it)
		if arg.begins_with("--vehicle="):
			Seat.vehicle_override = arg.trim_prefix("--vehicle=")
		if arg.begins_with("--slide="):
			Seat.slide_amount = float(arg.trim_prefix("--slide="))
		if arg == "--no-drift-pitch":
			_flat_drift = true
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
	CM.nose_closed = nose_closed
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._slide_loaded = true
	Seat.slide_feel = true
	Seat._rush_loaded = true
	Seat.speed_rush = true
	Seat._startup_loaded = true
	Seat._school_loaded = true
	Seat._map_loaded = true
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
	for i in 8:      # (a few frames of the game itself: the sim has stepped, and has its tow links to draw)
		await process_frame
	seat.set_process(false)
	seat.cruise = 0.0
	if root.use_xr or seat.sim.kind != "network":
		push_error("These pictures want the Network and a monoscopic viewport.")
		quit(1)
		return
	var places := _places()
	if places.is_empty():
		push_error("No banked bend or no straight was found on the Network's roads.")
		quit(1)
		return
	var sim = seat.sim
	var at := ""
	for view in VIEWS:
		var wanted := only.is_empty()
		for prefix in only:
			wanted = wanted or String(view[0]).begins_with(prefix)
		if not wanted:
			continue
		var place: Array = places[view[1]]
		if at != String(view[1]):      # put her there, at speed along the road, and bring the world in round her
			at = String(view[1])
			sim.respawn_on(int(place[0]), int(place[1]), int(place[2]))
			for b in sim.bodies:
				b.vx = SPEED * cos(b.th)
				b.vy = SPEED * sin(b.th)
			sim.pair_th = sim.pod.th      # (the engines' own heading is the sim's to work out as it steps: here it is told)
			seat._ride.clear()
			seat.craft._prev_v = []
			seat._comfort_roll = 0.0
			seat._comfort_roll_rate = 0.0
			seat._slide = 0.0
			seat._slide_rate = 0.0
			seat._slide_load = 0.0
			seat.cam.rotation = Vector3.ZERO
			for i in 1600:
				seat.network_world.sync(sim.pod.x, sim.pod.y)
				seat.landscape.sync(sim.pod.x, sim.pod.y)
				if i % 40 == 0:
					await process_frame
			for i in 360:      # three seconds of the turn: the lean, the cockpit's roll and its slide have settled
				await _frame(float(place[3]))
			print("PITCH_SHOTS at %s: the cockpit rolled %.1f degrees and stepped out %.1f, the craft leaning %.1f, %.0f mph, the shell %.1f mm forward of its place" % [at,
				rad_to_deg(seat._comfort_roll), rad_to_deg(seat._slide), rad_to_deg(seat.craft.bank[2]), seat._kmh() / 1.609344, -seat._rush_shift.z * 1000.0])
		seat.cam.rotation_degrees = Vector3(float(view[2]), float(view[3]), 0.0)
		seat.cam.fov = float(view[4])
		for i in 30:
			await _frame(float(place[3]))
		if _flat_drift and seat.get("_drift_pitch") != null:
			seat._drift_pitch = 0.0
			seat._place_shell()
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("PITCH_SHOT ", view[0])
	seat.free()
	quit()
