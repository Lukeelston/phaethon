## The Phaethon's fixed cannons (view/weapons/fixed_guns_mount.gd on view/arms/phaethon_arms.gd, fired by
## view/gunnery.gd) in the game's own VR cockpit with XR off, on a Network straight at 1,500 mph: from the seat with
## the GUN never armed (seat-stowed); armed, the cannons out, a raider ahead off the bore (seat-out: the boresight ring
## and the lead pip); firing, the assist laying the bolts on it (seat-fire); the same from outside (out-fire) and at the
## starboard engine's nose (gun-close); and the raider knocked out (seat-burst). Once armed the world is held still
## and the fire control stepped on its own, as tests/test_fixed_guns.gd does, so the raider stands where it is put.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_fixed_guns.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   [--vehicle=phaethon|talon] [--deg=1.8] [--dist=600]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const DT := 1.0 / 120.0
const SPEED := 1500.0 * 0.44704
const STRAIGHT := 1600.0
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
var output := ""
var _way := 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fixed gun screenshots need a rendering display.")
		quit(1)
		return
	var vehicle := "phaethon"
	var deg := 1.8
	var dist := 600.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--vehicle="):
			vehicle = arg.trim_prefix("--vehicle=")
		elif arg.begins_with("--deg="):
			deg = float(arg.trim_prefix("--deg="))
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
	Seat.vehicle_override = vehicle
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
	# Armed: the fire control is made; from here the world is still.
	game.gun_wanted = true
	_hold_speed(game)
	game._process(DT)
	var g = game.gunnery
	if g == null:
		push_error("No fire control was made on arming (%s)" % vehicle)
		quit(1)
		return
	game.traffic_net.cars.clear()
	_hold_speed(game)
	g.want_out = true
	for i in int(1.1 / DT):
		g.step(DT)
	var raider = _put(game, g, deg, dist)
	_look_seat(game, cam)
	game.traffic_net._render()      # (traffic is held still too: drawn where the raider was put)
	g.step(DT)
	await _snap(game, g, "seat-out", 90)
	g.hold_fire = true
	for i in int(0.32 / DT):
		_look_seat(game, cam)
		g.step(DT)
	await _snap(game, g, "seat-fire", 90)
	var engine: Transform3D = game.craft.engines[1].global_transform
	var lead: Vector3 = g.to_render(g.aim_lead)
	cam.global_position = engine * Vector3(14.0, 7.0, 34.0)      # (behind, above and to starboard, clear of the cockpit's bubble)
	cam.look_at(engine.origin.lerp(lead, 0.04), Vector3.UP)
	game.traffic_net._render()
	g.step(DT)
	await _snap(game, g, "out-fire", 45)
	cam.global_position = engine * Vector3(2.0, 1.1, -8.5)
	cam.look_at(engine * Vector3(0.0, 0.0, -4.0), engine.basis.y)
	g.step(DT)
	await _snap(game, g, "gun-close", 40)
	var frames := 0
	while game.traffic_net.cars.has(raider) and frames < int(3.0 / DT):
		_look_seat(game, cam)
		g.step(DT)
		frames += 1
	g.hold_fire = false
	for i in 14:
		_look_seat(game, cam)
		g.step(DT)
	game.traffic_net._render()      # (knocked out: gone from traffic, and from its drawing)
	await _snap(game, g, "seat-burst", 90)
	print("FIXED GUNS RENDER: %s, raider %s after %.2f s of fire (%d shots, %d hits, %d out)" % [vehicle,
		"knocked out" if not game.traffic_net.cars.has(raider) else "still there", frames * DT, g.shots, g.hits, g.kills])
	game.free()
	await process_frame
	quit()


func _look_seat(game, cam: Camera3D) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * LOOK.normalized(), rig.basis.y)


func _snap(game, g, shot: String, fov: float) -> void:
	(game.cam as Camera3D).fov = fov      # (the caller stepped the fire control after placing the camera: its sights are drawn for it)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("fixed-guns-" + shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	if g == null:
		print("FIXED GUNS VIEW %s (unarmed: no fire control %s)" % [path, game.gunnery == null])
	else:
		print("FIXED GUNS VIEW %s deploy=%.2f aim=%s %.0f m on=%s pip=%s ring=%s shots=%d hits=%d out=%d" % [path, g.mount.deploy_t(), g.aim_kind,
			g.aim_dist, g.on_aim, g.sight.visible, g.bore_ring.visible if g.bore_ring else false, g.shots, g.hits, g.kills])


## As tests/test_fixed_guns.gd: the start of a straight, level stretch of road.
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
				print("FIXED GUNS RENDER: on road %s at sample %d" % [R.name, i])
				return


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * _way * SPEED
		b.vy = R.ty[i] * _way * SPEED
		b.vz = 0.0


## A raider `dist` m out along the bore, `deg` degrees to its left, at a standstill.
func _put(game, g, deg: float, dist: float):
	var T = game.traffic_net
	var sim = game.sim
	var ray: Array = g.mount.aim_ray(game.cam)
	var o: Vector3 = g.to_sim(ray[0])
	var d: Vector3 = GunneryScript.dir_to_sim(ray[1])
	var ahead := Vector2(d.x, d.y).normalized()
	var left := Vector2(-ahead.y, ahead.x)
	var at := Vector2(o.x, o.y) + (ahead * cos(deg_to_rad(deg)) + left * sin(deg_to_rad(deg))) * dist
	var R = sim.roads[sim.pod.path]
	var near := int(sim.pod.hint)
	for i in range(maxi(0, int(sim.pod.hint) - 10), mini(R.N - 1, int(sim.pod.hint) + int(3000.0 / float(Sim.NET_STEP)))):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	c.id = 990001
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
