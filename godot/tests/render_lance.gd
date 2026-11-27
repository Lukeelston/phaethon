## The Kiln's plasma lance (view/weapons/lance_mount.gd on Codex's view/arms/kiln_arms.gd) in the game's own VR cockpit
## with XR off, on a Network straight at 1,500 mph: from the seat and from outside with the GUN never armed (seat-stowed,
## out-stowed) and armed, the lance up out of the starboard foredeck (seat-armed, out-armed); the beam on a raider ahead
## (seat-burning, through the cockpit's view; out-burning, from behind and above the starboard side along it;
## side-burning, from beside the beam's line), a few frames into the burn; and the burst as it goes (seat-burst). Once
## armed the world is held still and the fire control stepped on its own, as tests/test_lance.gd does, so the raider
## stands where it is put. The view's own frame is not run: the dash's strip is never told the gun's words, and shows
## none of them.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_lance.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   [--dist=300]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const DT := 1.0 / 120.0
const SPEED := 1500.0 * 0.44704
const STRAIGHT := 1600.0
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
const OUT_EYE := Vector3(3.3, 2.2, 1.6)       # outside: behind the starboard foredeck and above it (the cockpit's own frame) ...
const OUT_AT := Vector3(0.6, 0.7, -2.2)       # ... looking at the lance
const BURN_EYE := Vector3(5.5, 3.2, 6.0)      # further back, along the beam's way
const BURN_AT := Vector3(0.0, 0.8, -40.0)
const SIDE_EYE := Vector3(60.0, 8.0, -80.0)   # beside the beam's line, 80 m ahead: the ribbon broadside
const SIDE_AT := Vector3(0.0, 2.0, -110.0)
var output := ""
var _way := 1
var _next_id := 995000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Lance screenshots need a rendering display.")
		quit(1)
		return
	var dist := 300.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--dist="):
			dist = float(arg.trim_prefix("--dist="))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Raids.pinned = true
	Raids.enabled = false
	Chase.pinned = true
	Chase.enabled = false
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.vehicle_override = "kiln"
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	_on_a_straight(game)
	for i in 30:
		_hold_speed(game)
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	_look_seat(game, cam)
	await _snap(game, null, "seat-stowed", 90)
	_look_out(game, cam, OUT_EYE, OUT_AT)
	await _snap(game, null, "out-stowed", 50)
	# Armed: the fire control and the arms are made; from here the world is still.
	game.gun_wanted = true
	for i in 2:
		_hold_speed(game)
		game._process(DT)
	var g = game.gunnery
	if g == null or g.mount.get("arms") == null:
		push_error("No fire control or arms were made on arming")
		quit(1)
		return
	game.traffic_net.cars.clear()
	_hold_speed(game)
	g.want_out = true
	g.power = 1.0
	for i in int(1.1 / DT):
		g.step(DT)
	_look_seat(game, cam)
	g.step(DT)
	await _snap(game, g, "seat-armed", 90)
	_look_out(game, cam, OUT_EYE, OUT_AT)
	g.step(DT)
	await _snap(game, g, "out-armed", 50)
	# A raider ahead, the gaze on it, the trigger held: a few frames into the burn.
	var raider = _raider(game, dist, 0.0)
	game.traffic_net._render()      # (traffic is held still too: drawn where the raider was put)
	for i in 10:
		_look_at(game, cam, g, raider)
		g.step(DT)
	g.hold_fire = true
	for i in 8:
		_look_at(game, cam, g, raider)
		g.step(DT)
	await _snap(game, g, "seat-burning", 70)
	_look_out(game, cam, BURN_EYE, BURN_AT)
	_redraw(game, g)
	await _snap(game, g, "out-burning", 55)
	_look_out(game, cam, SIDE_EYE, SIDE_AT)
	_redraw(game, g)
	await _snap(game, g, "side-burning", 60)
	var frames := 0
	while game.traffic_net.cars.has(raider) and frames < int(1.0 / DT):
		_look_at(game, cam, g, raider)
		g.step(DT)
		frames += 1
	g.hold_fire = false
	for i in 6:
		_look_seat(game, cam)
		g.step(DT)
	game.traffic_net._render()
	await _snap(game, g, "seat-burst", 70)
	print("LANCE RENDER: a raider %.0f m out, knocked out %s, %.2f s into the burn (%d hits, %d out)" % [dist, not game.traffic_net.cars.has(raider),
		(frames + 8) * DT, g.hits, g.kills])
	game.free()
	await process_frame
	quit()


## The sights, the beam and its glow drawn again for where the camera now is, nothing stepped.
func _redraw(game, g) -> void:
	g._draw(game.cam)
	g.mount._draw(g)


func _look_seat(game, cam: Camera3D) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * LOOK.normalized(), rig.basis.y)


## The gaze from the seat's eye on a raider's middle.
func _look_at(game, cam: Camera3D, g, c) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(g.to_render(Vector3(c.x, c.y, game.traffic_net.body_height(c))), rig.basis.y)


## From outside, in the cockpit's own frame (its shell).
func _look_out(game, cam: Camera3D, eye: Vector3, at: Vector3) -> void:
	var frame: Transform3D = game.shell.global_transform
	cam.global_position = frame * eye
	cam.look_at(frame * at, frame.basis.y)


func _snap(game, g, shot: String, fov: float) -> void:
	(game.cam as Camera3D).fov = fov      # (the caller stepped the fire control after placing the camera: its sights are drawn for it)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("lance-" + shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	if g == null:
		print("LANCE VIEW %s (unarmed: no fire control %s, no arms %s)" % [path, game.gunnery == null, game.shell.get_node("PodHull").get_node_or_null("Arms") == null])
	else:
		var m = g.mount
		print("LANCE VIEW %s deploy=%.2f burning=%s beam=%.1f m on=%s heat=%.2f status=\"%s\" hits=%d out=%d" % [path, m.deploy_t(), m.burning, m.beam_len,
			m.on_beam != null, m.heat(), m.status(), g.hits, g.kills])


## As tests/test_lance.gd: the start of a straight, level stretch of road.
func _on_a_straight(game) -> void:
	var sim = game.sim
	var span := int(ceil(STRAIGHT / float(Sim.NET_STEP)))
	var roads := [int(sim.pod.path)]
	for r in sim.roads.size():
		if r != roads[0]:
			roads.append(r)
	for r: int in roads:
		var R = sim.roads[r]
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 200:
			continue
		var from := clampi(int(sim.pod.hint), 100, R.N - span - 100) if r == roads[0] else 100
		for i in range(from, R.N - span - 100, 6):
			var th := atan2(R.ty[i], R.tx[i])
			var h0: float = sim.road_h(r, float(i))
			var ok := true
			for k in range(i, i + span + 1, 2):
				if absf(angle_difference(th, atan2(R.ty[k], R.tx[k]))) > deg_to_rad(0.15) or absf(sim.road_h(r, float(k)) - h0) > 1.0 \
						or sim.in_pressure(r, k):
					ok = false
					break
			if ok:
				sim.respawn_on(r, i, 1)
				print("LANCE RENDER: on road %s at sample %d" % [R.name, i])
				return


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * _way * SPEED
		b.vy = R.ty[i] * _way * SPEED
		b.vz = 0.0


## A raider `ahead` m on along the road from the pod and `left` m to its left, at a standstill.
func _raider(game, ahead: float, left: float):
	var T = game.traffic_net
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i0 := clampi(int(sim.pod.hint), 0, R.N - 1)
	var way := Vector2(R.tx[i0], R.ty[i0]) * _way
	var at := Vector2(sim.pod.x, sim.pod.y) + way * ahead + Vector2(-way.y, way.x) * left
	var near := i0
	for i in range(maxi(0, i0 - 10), mini(R.N - 1, i0 + int(3000.0 / float(Sim.NET_STEP)))):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	_next_id += 1
	c.id = _next_id
	c.kind = T.CAR
	c.road = sim.pod.path
	c.dir = _way
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = true
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	return c
