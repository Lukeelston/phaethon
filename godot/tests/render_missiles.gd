## The Shrike's look-to-lock missiles (view/weapons/missile_mount.gd on Codex's view/arms/shrike_arms.gd) in the game's
## own VR cockpit with XR off, on a Network straight at 1,500 mph: from the seat and from outside with the GUN never
## armed (seat-stowed, out-stowed) and armed, the cassettes up over the cheeks (seat-armed, out-armed); three raiders
## ahead locked, a bracket on each (seat-locked); the volley leaving the rails (rail-launch: the frame it leaves, close
## by the port cassette; seat-launch and side-launch, from the seat and from beside its line, 3 frames on); the volley in
## flight, each raider still bracketed (seat-volley, looking along it at the raiders through a narrower view, and
## out-volley, from behind the craft); and the strikes (seat-strike). Once armed the world is held still and the fire
## control stepped on its own, as tests/test_missiles.gd does, so the raiders stand where they are put. A missile flying
## away from the eye is seen end on: a short bright mark, its dart too small to see.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_missiles.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   [--dist=800]
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
const OUT_EYE := Vector3(-3.4, 2.3, 3.1)      # outside: behind the port cheek and above it (the cockpit's own frame) ...
const OUT_AT := Vector3(0.2, 0.75, -1.5)      # ... looking at the cassettes
const OUT_VOLLEY_EYE := Vector3(-4.5, 3.0, 7.0)      # ... and further back, along the way the volley goes
const OUT_VOLLEY_AT := Vector3(0.0, 0.5, -30.0)
const RAIL_EYE := Vector3(-2.6, 1.7, -4.2)    # by the port cassette, ahead of it and out, looking back at its mouths
const RAIL_AT := Vector3(-1.25, 1.05, -1.9)
const SIDE_EYE := Vector3(-28.0, 5.0, -30.0)  # beside the volley's line, 30 m ahead: the streaks broadside
const SIDE_AT := Vector3(0.0, 1.5, -40.0)
var output := ""
var _way := 1
var _next_id := 993000


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Missile screenshots need a rendering display.")
		quit(1)
		return
	var dist := 800.0
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
	Seat.vehicle_override = "shrike"
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
	# Three raiders ahead, locked in turn by the gaze.
	var R = game.sim.roads[game.sim.pod.path]
	var hw: float = R.w[clampi(int(game.sim.pod.hint), 0, R.N - 1)] * 0.5
	var three := []
	for k in 3:
		three.append(_raider(game, dist, (float(k) - 1.0) * minf(45.0, 0.5 * hw)))
	game.traffic_net._render()      # (traffic is held still too: drawn where the raiders were put)
	for c in three:
		for i in int(0.45 / DT):
			_look_at(game, cam, g, c)
			g.step(DT)
	_look_at(game, cam, g, three[1])
	g.step(DT)
	await _snap(game, g, "seat-locked", 60)
	# The volley: the frame it leaves the rails, then 3 frames on, then in flight with each raider bracketed still.
	g.hold_fire = true
	_look_seat(game, cam)
	g.step(DT)
	g.hold_fire = false
	_look_out(game, cam, RAIL_EYE, RAIL_AT)
	_redraw(game, g)
	await _snap(game, g, "rail-launch", 50)
	for i in 3:
		_look_seat(game, cam)
		g.step(DT)
	await _snap(game, g, "seat-launch", 90)
	_look_out(game, cam, SIDE_EYE, SIDE_AT)
	_redraw(game, g)
	await _snap(game, g, "side-launch", 60)
	for i in 9:
		_look_seat(game, cam)
		g.step(DT)
	_look_at(game, cam, g, three[1])
	_redraw(game, g)
	await _snap(game, g, "seat-volley", 25)
	_look_out(game, cam, OUT_VOLLEY_EYE, OUT_VOLLEY_AT)
	_redraw(game, g)
	await _snap(game, g, "out-volley", 55)
	var frames := 0
	while not g.mount.missiles.is_empty() and frames < int(3.0 / DT):
		_look_seat(game, cam)
		g.step(DT)
		frames += 1
	for i in 10:
		_look_seat(game, cam)
		g.step(DT)
	game.traffic_net._render()
	await _snap(game, g, "seat-strike", 60)
	print("MISSILES RENDER: three raiders %.0f m out, %d knocked out %.2f s after the volley (%d shots, %d hits, %d out)" % [dist,
		three.filter(func(c) -> bool: return not game.traffic_net.cars.has(c)).size(), (frames + 13) * DT, g.shots, g.hits, g.kills])
	game.free()
	await process_frame
	quit()


## The sights, the missiles and their streaks drawn again for where the camera now is, nothing stepped.
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
	var path := output.path_join("missiles-" + shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	if g == null:
		print("MISSILES VIEW %s (unarmed: no fire control %s, no arms %s)" % [path, game.gunnery == null, game.shell.get_node("PodHull").get_node_or_null("Arms") == null])
	else:
		var m = g.mount
		var shown := 0
		for b: MeshInstance3D in m.brackets:
			shown += int(b.visible)
		print("MISSILES VIEW %s deploy=%.2f locks=%d in flight=%d brackets=%d rounds=%d status=\"%s\" shots=%d hits=%d out=%d" % [path, m.deploy_t(),
			m.locks.size(), m.missiles.size(), shown, m.loaded, m.status(), g.shots, g.hits, g.kills])
		var eye: Vector3 = (game.cam as Camera3D).global_position
		var far := []
		for mi: Dictionary in m.missiles:
			far.append(snappedf(eye.distance_to(g.to_render(mi.p)), 0.1))
		if not far.is_empty():
			print("  the missiles %s m from the eye, %.0f m out" % [far, m.missiles[0].t * (m.missiles[0].v as Vector3).length()])


## As tests/test_missiles.gd: the start of a straight, level stretch of road.
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
				print("MISSILES RENDER: on road %s at sample %d" % [R.name, i])
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
