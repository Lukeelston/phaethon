## The Orrery's three orbs (view/weapons/orb_mount.gd on Codex's view/arms/orrery_arms.gd) in the game's own VR cockpit with
## XR off, on a Network straight, the world held still once armed (the fire control stepped on its own, the craft at rest,
## as tests/test_orbs.gd does): from outside with the GUN never armed (out-stowed); armed, in orbit from the seat ahead
## (seat-orbit), looking up (seat-up), to the left and to the right (seat-left, seat-right), and from outside (out-orbit,
## out-orbit-high); docked on SAFE with the doors still open (out-docked); an orb striking a raider 300 m off, from beside
## the raider (strike) and from the seat (seat-strike); and from the seat with an orb 300 m out at a raider 600 m off, its
## streak behind it: straight ahead (seat-300) and 14 degrees to the right (seat-300-side). An orb going out flies almost
## straight away from the eye, so its streak is seen end-on from the seat, and ahead it lies behind the craft's own engines.
## Each shot's line tells the orbs' states and how far each is from the eye.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_orbs.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const SeatKit := preload("res://tests/seat_kit.gd")
const DT := 1.0 / 120.0
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
var output := ""
var seat := SeatKit.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Orb screenshots need a rendering display.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
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
	Seat.vehicle_override = "orrery"
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	seat.on_a_straight(game)
	for i in 30:
		seat.hold_speed(game)
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	_look_out(game, cam, Vector3(3.2, 2.2, -4.6), Vector3(0.0, 0.2, -1.5))
	await _snap(game, null, "out-stowed", 50)
	# Armed: the fire control and the arms are made; from here the world is still, the craft at rest.
	game.gun_wanted = true
	for i in 2:
		seat.hold_speed(game)
		game._process(DT)
	var g = game.gunnery
	if g == null or g.mount.get("arms") == null:
		push_error("No fire control or arms were made on arming")
		quit(1)
		return
	for b in [game.sim.eL, game.sim.eR, game.sim.pod]:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
	game.traffic_net.cars.clear()
	game.traffic_net._render()      # (traffic held still too, and none of it in the way)
	var d = Raids.new()      # (a director of the render's own, never updated: its raider is a raid's)
	game.add_child(d)
	d.traffic = game.traffic_net
	d.build(game)
	game.raids = d
	game.traffic_net.raids = d
	g.want_out = true
	g.power = 1.0
	var m = g.mount
	for i in int(2.2 / DT):
		g.step(DT)
	# In orbit, from the seat: ahead, up, to each side.
	for shot: Array in [["seat-orbit", LOOK, 90], ["seat-up", Vector3(0.0, 1.6, -1.0), 90], ["seat-left", Vector3(-1.0, 0.25, -0.15), 90],
			["seat-right", Vector3(1.0, 0.25, -0.15), 90]]:
		_look_seat(game, cam, shot[1])
		g.step(DT)
		await _snap(game, g, shot[0], shot[2])
	_look_out(game, cam, Vector3(7.0, 3.2, 7.0), Vector3(0.0, 0.8, 0.0))
	_redraw(game, g)
	await _snap(game, g, "out-orbit", 50)
	_look_out(game, cam, Vector3(0.0, 9.0, 4.0), Vector3(0.0, 1.0, 0.0))
	_redraw(game, g)
	await _snap(game, g, "out-orbit-high", 60)
	# SAFE: home and docked, the doors still open (the deploy held at 1 till the last is in).
	g.want_out = false
	for i in int(4.0 / DT):
		g.step(DT)
		if m.orbs.all(func(o) -> bool: return o.state == "docked"):
			break
	_look_out(game, cam, Vector3(1.6, 1.7, -4.2), Vector3(0.0, 0.0, -1.6))
	_redraw(game, g)
	await _snap(game, g, "out-docked", 45)
	g.want_out = true
	for i in int(2.5 / DT):
		g.step(DT)
	# An orb striking a raider 300 m ahead, on its own.
	var r = _raider(game, 300.0)
	var struck: int = m.strikes
	for i in int(1.5 / DT):
		_look_seat(game, cam, LOOK)
		g.step(DT)
		if m.strikes > struck:
			break
	await _snap(game, g, "seat-strike", 90)
	var at: Vector3 = g.to_render(Vector3(r.x, r.y, game.traffic_net.body_height(r)))
	var way: Vector3 = -game.rig.global_transform.basis.z
	cam.global_position = at - way * 22.0 + game.rig.global_transform.basis.x * 16.0 + Vector3.UP * 6.0
	cam.look_at(at, Vector3.UP)
	_redraw(game, g)
	await _snap(game, g, "strike", 50)
	# An orb 300 m out at a raider 600 m ahead, from the seat: its streak behind it.
	for i in int(3.0 / DT):
		g.step(DT)
		if m.orbs.all(func(o) -> bool: return o.state == "orbit"):
			break
	game.traffic_net.cars.clear()
	d.pack.clear()
	for o in m.orbs:
		o.rest = 0.0
	r = _raider(game, 600.0)
	for i in int(1.0 / DT):
		_look_seat(game, cam, LOOK)
		g.step(DT)
		if m.orbs.any(func(o) -> bool: return o.state == "out" and _here(game).distance_to(o.p) >= 300.0):
			break
	await _snap(game, g, "seat-300", 90)
	# ... and one at a raider 600 m off 14 degrees right of ahead, clear of the engines and the roof's pillars.
	for i in int(3.0 / DT):
		g.step(DT)
		if m.orbs.all(func(o) -> bool: return o.state == "orbit"):
			break
	game.traffic_net.cars.clear()
	d.pack.clear()
	for o in m.orbs:
		o.rest = 0.0
	r = _raider(game, 600.0, -14.0)
	var side := Vector3(0.25, -0.02, -1.0)      # (the gaze turned toward it: between the engines and the right pillar)
	for i in int(1.0 / DT):
		_look_seat(game, cam, side)
		g.step(DT)
		if m.orbs.any(func(o) -> bool: return o.state == "out" and _here(game).distance_to(o.p) >= 300.0):
			break
	await _snap(game, g, "seat-300-side", 90)
	game.free()
	await process_frame
	quit()


static func _here(game) -> Vector3:
	return Vector3(game.sim.pod.x, game.sim.pod.y, game.sim.pod.z)


## A raider `dist` m off, `bearing` degrees left of the road's way, standing, of the render's raid.
func _raider(game, dist: float, bearing := 0.0):
	var T = game.traffic_net
	var sim = game.sim
	var P := Vector2(sim.pod.x, sim.pod.y) + seat.road_way(game).rotated(deg_to_rad(bearing)) * dist
	var c = T.Car.new()
	c.id = 998001 + T.cars.size()
	c.kind = T.CAR
	c.road = sim.pod.path
	c.dir = seat.way
	c.f = sim.pod.hint
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = true
	T._place(c)
	c.x = P.x
	c.y = P.y
	c.v = 0.0
	T.cars.append(c)
	game.raids.pack.append(c)
	T._render()
	return c


## The streaks and sights drawn again for where the camera now is, nothing stepped.
func _redraw(game, g) -> void:
	g.mount._draw(g)
	g._draw(game.cam)


func _look_seat(game, cam: Camera3D, look: Vector3) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * look.normalized(), rig.basis.y)


## From outside, in the cockpit's own frame (its shell): from `from` at `to`.
func _look_out(game, cam: Camera3D, from: Vector3, to: Vector3) -> void:
	var frame: Transform3D = game.shell.global_transform
	cam.global_position = frame * from
	cam.look_at(frame * to, frame.basis.y)


func _snap(game, g, shot: String, fov: float) -> void:
	(game.cam as Camera3D).fov = fov
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("orbs-" + shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	if g == null:
		print("ORBS VIEW %s (unarmed: no fire control %s, no arms %s)" % [path, game.gunnery == null, game.shell.get_node("PodHull").get_node_or_null("Arms") == null])
		return
	var m = g.mount
	var eye: Vector3 = game.rig.global_transform * Seat.EYE
	var far := []
	for k in m.orbs.size():
		far.append(snappedf(eye.distance_to((m.arms.orbs[k] as Node3D).global_position), 0.01))
	print("ORBS VIEW %s deploy=%.2f states=%s from the seat's eye %s m, streaks %d, strikes %d" % [path, m.deploy_t(), m.orbs.map(func(o): return o.state), far, m.drawn.size(), m.strikes])
