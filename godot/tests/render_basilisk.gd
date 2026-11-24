## The Basilisk and its gun, in the game: outside with the gun stowed and out, the sponson close, the
## seat's view ahead and toward the gun, the GUN switch, and the gun firing where the view looks; "probe" puts a
## puff, a flash and a bolt just ahead of the seat. With --track=network: a vehicle brought up ahead, locked,
## fired on and knocked out (net-car, net-seat-aim, net-seat-fire, net-burst, net-out-burst).
## Needs a window: --xr-mode off -s res://tests/render_basilisk.gd -- --mute --out=ABSOLUTE_DIRECTORY
## [--track=network] [--views=a,b,...]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const DT := 1.0 / 120.0
const FIRE_AT := Vector3(0.42, -0.012, -1)   # (the seat's look while it fires: the ground well off, clear of the right engine)
var output := ""
var track := "range"
var only := []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Basilisk screenshots need a rendering display.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--track="):
			track = arg.trim_prefix("--track=")
		elif arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = "ember"
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = track
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.vehicle_override = Pilot.BASILISK
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for i in 12:
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	if track == "network":
		await _network_shots(game, cam)
		game.free()
		await process_frame
		quit()
		return
	var shots := ["out-stowed", "seat-ahead-stowed", "switch", "out-deployed", "sponson", "seat-ahead", "seat-right", "seat-fire", "out-fire", "probe"]
	for shot: String in shots:
		if not only.is_empty() and not only.has(shot):
			if shot == "out-stowed" or shot == "seat-ahead-stowed" or shot == "switch":
				continue
		if shot == "out-deployed":
			game.gun_wanted = true
			_look_seat(game, cam, Vector3(0.35, -0.05, -1))
			for i in 200:
				game._process(DT)
		if not only.is_empty() and not only.has(shot):
			continue
		var cab: Transform3D = game.shell.get_node("PodHull").global_transform
		match shot:
			"out-stowed", "out-deployed":
				cam.global_position = cab * Vector3(5.5, 2.4, -6.5)
				cam.look_at(cab * Vector3(0.6, 0.15, -0.6), cab.basis.y)
				cam.fov = 40
			"sponson":
				cam.global_position = cab * Vector3(2.6, 1.2, -2.4)
				cam.look_at(cab * Vector3(1.13, 0.35, -0.75), cab.basis.y)
				cam.fov = 34
			"seat-ahead-stowed", "seat-ahead":
				_look_seat(game, cam, Vector3(0.0, -0.06, -1))
				cam.fov = 90
			"seat-right":
				_look_seat(game, cam, Vector3(0.75, 0.05, -0.65))
				cam.fov = 90
			"switch":
				_look_seat(game, cam, Vector3(0.80, -0.12, -0.25))
				cam.fov = 75
			"seat-fire":
				_look_seat(game, cam, FIRE_AT)
				cam.fov = 90
				game.gunnery.hold_fire = true
				for i in 70:
					game._process(DT)
					_look_seat(game, cam, FIRE_AT)
			"probe":
				_look_seat(game, cam, Vector3(0, 0, -1))
				var g = game.gunnery
				var ahead: Vector3 = cam.global_position - cam.global_transform.basis.z * 25.0
				g._add_fx(g.to_sim(ahead), "dust", 30.0, 6.0)
				g._add_fx(g.to_sim(ahead + cam.global_transform.basis.x * 6.0), "flash", 30.0, 4.0)
				g._bolts.append({"a": g.to_sim(ahead - cam.global_transform.basis.x * 8.0), "b": g.to_sim(ahead - cam.global_transform.basis.x * 8.0 - cam.global_transform.basis.z * 200.0), "t": 0.02, "dur": 30.0, "car": null, "kind": "ground"})
				game._process(DT)
				_look_seat(game, cam, Vector3(0, 0, -1))
				cam.fov = 70
			"out-fire":
				_look_seat(game, cam, FIRE_AT)
				for i in 30:
					game._process(DT)
					_look_seat(game, cam, FIRE_AT)
				cam.global_position = cab * Vector3(-3.0, 3.0, 9.0)
				cam.look_at(cab * Vector3(8.0, -1.0, -60.0), cab.basis.y)
				cam.fov = 50
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join("basilisk-" + shot + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not write " + path)
			quit(1)
			return
		var g = game.gunnery
		print("BASILISK VIEW %s  t=%.2f yaw=%.1f pitch=%.1f aim=%s %.0f m shots=%d fouled=%s on=%s" % [path, game.craft.turret.t,
			rad_to_deg(game.craft.turret.yaw), rad_to_deg(game.craft.turret.pitch), g.aim_kind if g else "-", g.aim_dist if g else 0.0,
			g.shots if g else 0, g.fouled if g else false, g.on_aim if g else false])
	game.free()
	await process_frame
	quit()


## The seat's eye looking along `dir` (the rig's frame, level under the pod's pitch: +X starboard, -Z ahead).
func _look_seat(game, cam: Camera3D, dir: Vector3) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * dir.normalized(), rig.basis.y)


## On the Network: the gun out, a vehicle picked ahead, the gaze held on it, the trigger held until it is
## gone: the sight on it, the gun firing, and the burst, from the seat and from outside.
func _network_shots(game, cam: Camera3D) -> void:
	game.gun_wanted = true
	_look_seat(game, cam, Vector3(0.3, -0.03, -1))
	for i in 160:
		game._process(DT)
		_look_seat(game, cam, Vector3(0.3, -0.03, -1))
	var g = game.gunnery
	var traffic = game.traffic_net
	# Bring one vehicle up the craft's own road to a few hundred metres ahead, in a lane to the right.
	var sim = game.sim
	for c in traffic.cars:
		if c.road == sim.pod.path and not c.craft and c != traffic.racer:
			var lanes: Array = traffic._lanes[c.road]
			c.lane = lanes.size() - 2 if c.dir > 0 else 1
			var R = sim.roads[c.road]
			var i := clampi(int(sim.pod.hint), 0, R.N - 1)
			var way := 1.0 if R.tx[i] * sim.pod.vx + R.ty[i] * sim.pod.vy >= 0.0 else -1.0
			if Vector2(sim.pod.vx, sim.pod.vy).length() < 1.0:      # (parked: the way the engines lie ahead of the pod)
				way = 1.0 if R.tx[i] * (sim.eL.x - sim.pod.x) + R.ty[i] * (sim.eL.y - sim.pod.y) >= 0.0 else -1.0
			c.f = clampf(float(sim.pod.hint) + way * 19.0, 0.0, R.N - 2.0)
			c.dir = int(way)
			c.lane = lanes.size() - 2 if c.dir > 0 else 1
			for k in ["v", "vdes", "cruise", "cruise_goal", "vcap"]:
				c.set(k, 45.0)      # (a hauler at a hundred miles an hour, going our way)
			traffic._place(c)
			print("BASILISK: brought vehicle %d up the road (lane %d)" % [c.id, c.lane])
			break
	for i in 4:
		game._process(DT)
	var target = null
	var best := INF
	var eye: Vector3 = game.rig.global_transform * Seat.EYE
	var ahead: Vector3 = -game.rig.global_transform.basis.z
	for c in traffic.cars:
		if c.craft or c == traffic.racer:
			continue
		var at: Vector3 = g.to_render(Vector3(c.x, c.y, traffic._drawing.height(c.road, c.f) + 3.0))
		var to: Vector3 = at - eye
		var d := to.length()
		var T := preload("res://view/turret.gd")
		var lay: Vector2 = T.lay_for(game.craft.turret.global_transform.basis.inverse() * to)
		var gun: Vector3 = game.craft.turret.global_transform * game.craft.turret.trunnion()
		if d > 120.0 and d < 2400.0 and to.normalized().dot(ahead) > 0.0 and T.reachable(lay) and not g._crosses_engines(gun, at) and d < best:
			best = d
			target = c
	if target == null:
		print("BASILISK: no vehicle in the gun's reach; cars: ", traffic.cars.size())
		return
	print("BASILISK: target %d kind %d at %.0f m (road %d f %.1f dir %d v %.0f; pod road %d hint %d, pressure %s, deck %s)" % [target.id, target.kind, best,
		target.road, target.f, target.dir, target.v, sim.pod.path, sim.pod.hint, sim.in_pressure(sim.pod.path, sim.pod.hint), sim.roads[sim.pod.path].deck])
	var car_at: Vector3 = g.to_render(Vector3(target.x, target.y, traffic._drawing.height(target.road, target.f) + 3.0))
	cam.global_position = car_at + (eye - car_at).normalized() * 70.0 + Vector3.UP * 12.0
	cam.look_at(car_at, Vector3.UP)
	await _snap(game, cam, "net-car", 50)
	var frames := 0
	var shot_at := {"net-seat-aim": 10, "net-seat-fire": 0, "net-burst": 0}
	var kills0: int = g.kills
	while frames < 900:
		frames += 1
		var alive: bool = traffic.cars.has(target)
		if alive:
			var at: Vector3 = g.to_render(Vector3(target.x, target.y, traffic._drawing.height(target.road, target.f) + 3.0))
			cam.global_position = game.rig.global_transform * Seat.EYE
			cam.look_at(at, game.rig.global_transform.basis.y)
		g.hold_fire = frames > 30
		game._process(DT)
		if frames == 10:
			await _snap(game, cam, "net-seat-aim", 90)
		if frames == 48:
			await _snap(game, cam, "net-seat-fire", 90)
		if g.kills > kills0:
			for i in 14:
				game._process(DT)
			await _snap(game, cam, "net-burst", 90)
			var cab: Transform3D = game.shell.get_node("PodHull").global_transform
			var boom: Vector3 = g.to_render(g._fx.back().p) if not g._fx.is_empty() else cab.origin
			cam.global_position = cab * Vector3(-5.0, 4.5, 10.0)
			cam.look_at(boom, Vector3.UP)
			cam.fov = 40
			await _snap(game, cam, "net-out-burst", 40)
			print("BASILISK: knocked out after %d frames, %d shots, %d hits" % [frames, g.shots, g.hits])
			return
	print("BASILISK: not knocked out in %d frames (%d shots, %d hits)" % [frames, g.shots, g.hits])


func _snap(game, cam: Camera3D, shot: String, fov: float) -> void:
	cam.fov = fov
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("basilisk-" + shot + ".png")
	root.get_texture().get_image().save_png(path)
	var g = game.gunnery
	print("BASILISK VIEW %s aim=%s %.0f m lock=%.2f shots=%d hits=%d fouled=%s on=%s yaw=%.1f" % [path, g.aim_kind, g.aim_dist, g.lock, g.shots, g.hits,
		g.fouled, g.on_aim, rad_to_deg(game.craft.turret.yaw)])
