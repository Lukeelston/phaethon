## How distant traffic reads from the seat (Luke, after the seventeenth flight: "Make distant
## traffic readable - right now it just looks like a blur of taillights from far away"), drawn at
## a headset's own pixel density: the camera's field is narrowed until the middle of the frame
## has PPD pixels a degree (a Quest 3's eye buffer has about that in its middle), so a pixel here
## is a pixel there and a x4 crop shows what the eye is given. MSAA 4x, as in the headset.
##   ladder   the same five vehicles (car, slow pod, demon, a transport's train, a racer) side by
##            side, at 0.5, 1, 2, 4, 8 and 16 km ahead on an open highway: a frame a distance
##   open     the production spawner's own traffic on that highway, the pod going its way
##   busy     the same on E1 through Basalt's interchange with N1, where it is thickest in open country
##   city     the same in Eridanus city (190 to 220 vehicles), down the road and across it
## Beside every frame a .json: where each vehicle is on the picture and how far off.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_traffic_far.gd -- --mute --out=DIR [--tag=name] [--time=night]
##    [--scenes=ladder,open,city] [--no-glow] [--no-lamps] [--no-bodies]
extends "res://tests/render_terminal_art.gd"

const PPD := 20.0
const LADDER_M := [500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
const LADDER_KINDS := [[0, -90.0, Color(0.2, 0.35, 0.8)], [1, -45.0, Color(0.82, 0.77, 0.62)], [2, 0.0, Color(0.1, 0.9, 0.9)],
	[3, 45.0, Color(0.9, 0.55, 0.15)], [4, 90.0, Color(1.0, 0.25, 0.65)]]   # kind, m left of the road's middle, paint
const OPEN_AT := [2, 9000]     # E3, open country: long and straight
const BUSY_AT := [0, 3000]     # E1 through Basalt's N1 interchange: its thickest traffic outside a city's walls (tests/benchmark_network_traffic.gd's rail)
const WARM := 2400             # frames of the production spawner before a picture of its traffic
var tag := "now"


func _run() -> void:
	var scenes := PackedStringArray(["ladder", "open", "busy", "city"])
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
		if arg.begins_with("--scenes="):
			scenes = arg.trim_prefix("--scenes=").split(",")
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	var net = seat.traffic_net
	if "--no-glow" in OS.get_cmdline_user_args():
		for node in seat.find_children("*", "WorldEnvironment", true, false):
			(node as WorldEnvironment).environment.glow_enabled = false
	if "--no-lamps" in OS.get_cmdline_user_args():
		net._beams.visible = false
	if "--no-bodies" in OS.get_cmdline_user_args():
		for kind in net._mm:
			(net._mm[kind] as Node3D).visible = false
	print("TRAFFIC FAR: %s, %s, viewport %s, scenes %s" % [tag, outlook.time, root.size, scenes])
	if "ladder" in scenes:
		await _settle(int(OPEN_AT[0]), int(OPEN_AT[1]))
		for d in LADDER_M:
			_stand(int(OPEN_AT[0]), [d])
			await _shoot("ladder-%05d" % int(d), -1.5, 0.0, int(OPEN_AT[0]))
		_stand(int(OPEN_AT[0]), LADDER_M)      # and all six rungs at once: what hides what
		await _shoot("ladder-all", -1.5, 0.0, int(OPEN_AT[0]))
	if "open" in scenes:
		await _settle(int(OPEN_AT[0]), int(OPEN_AT[1]))
		await _flow(int(OPEN_AT[0]), int(OPEN_AT[1]))
		await _shoot("open", -1.5, 0.0, int(OPEN_AT[0]))
	if "busy" in scenes:
		await _settle(int(BUSY_AT[0]), int(BUSY_AT[1]))
		await _flow(int(BUSY_AT[0]), int(BUSY_AT[1]))
		await _shoot("busy", -1.5, 0.0, int(BUSY_AT[0]))
	if "city" in scenes:
		await _settle(int(city.road), int(city.i))
		await _flow(int(city.road), int(city.i))
		await _shoot("city", -1.5, 0.0, int(city.road))
		await _shoot("city-left", -1.5, 55.0, int(city.road))
		await _shoot("city-right", -1.5, -55.0, int(city.road))
		await _shoot("city-behind", -1.5, 180.0, int(city.road))
	seat.free()
	quit()


## The pod parked on a road, the world round it streamed in and the cockpit settled.
func _settle(road: int, at: int) -> void:
	seat.sim.respawn_on(road, at, 1)
	seat._ride.clear()
	for i in 1600:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	seat.traffic_net.cars.clear()
	for frame in 40:
		seat._process(STEP)
		await process_frame


## The ladder's vehicles stood on the road at each of `rungs` m ahead of the pod.
func _stand(road: int, rungs: Array) -> void:
	var net = seat.traffic_net
	var R = seat.sim.roads[road]
	var i0: int = clampi(seat.sim.pod.hint, 0, R.N - 1)
	var Car = net.get_script().Car
	net.cars.clear()
	var id := 100
	for d in rungs:
		for row in LADDER_KINDS:
			var c = Car.new()
			c.id = id
			id += 1
			c.kind = int(row[0])
			c.road = road
			c.dir = 1
			c.f = float(i0) + float(d) / 24.0
			c.lat = float(row[1])
			c.v = 0.0
			c.owed = 0.0
			c.col = row[2]
			if c.kind == 4:
				c.name = "VEGA"
			net._place(c)
			net.cars.append(c)
	net._render()


## The production spawner's own traffic round the pod: the pod railed up its road to `at` at 1,440 m/s
## (a sample every two frames of 1/120 s, as tests/benchmark_network_traffic.gd rails it) for up to WARM
## frames, so the traffic ahead of it is what a pilot under way has ahead: held still, everything going
## its way runs off over the horizon and the road ahead is empty.
func _flow(road: int, at: int) -> void:
	var net = seat.traffic_net
	var R = seat.sim.roads[road]
	var frames := mini(WARM, 2 * (at - 2))
	net.cars.clear()
	for frame in frames:
		_rail(road, at - (frames - frame) / 2, 0.5 * ((frames - frame) % 2))
		net.update(STEP)
		if frame % 24 == 0:
			await process_frame
	seat.sim.respawn_on(road, at, 1)
	seat._ride.clear()
	for frame in 3:
		seat._process(STEP)
		await process_frame
	_rail(road, at, 0.0)
	var kinds := [0, 0, 0, 0, 0]
	for c in net.cars:
		kinds[c.kind] += 1
	print("TRAFFIC FAR flow on %s: %d vehicles (cars %d, slow pods %d, demons %d, transports %d, racers %d), %d spawned" % [
		R.name, net.cars.size(), kinds[0], kinds[1], kinds[2], kinds[3], kinds[4], net.spawned])


func _rail(road: int, sample: int, fraction: float) -> void:
	var sim = seat.sim
	var R = sim.roads[road]
	sim.respawn_on(road, sample, 1)
	var dx: float = R.px[sample + 1] - R.px[sample]
	var dy: float = R.py[sample + 1] - R.py[sample]
	for body in sim.bodies:
		body.x += dx * fraction
		body.y += dy * fraction
		body.vx = dx * 60.0
		body.vy = dy * 60.0
	seat._follow_origin()


## A picture from the seat, `yaw` degrees left of ahead, and where every vehicle is on it.
func _shoot(name: String, pitch: float, yaw: float, road: int) -> void:
	var cam: Camera3D = seat.cam
	cam.position = Vector3.ZERO
	cam.fov = rad_to_deg(2.0 * atan(root.size.y * 0.5 * PI / 180.0 / PPD))
	cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
	var net = seat.traffic_net
	net._render()
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s-%s.png" % [tag, name])
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Couldn't save " + path)
		quit(1)
		return
	var sim = seat.sim
	var eye := cam.global_position
	var to_px: Vector2 = Vector2(root.size) / root.get_visible_rect().size      # (unproject_position answers in the window's own units, not the picture's pixels)
	var rows := []
	for c in net.cars:
		var h: float = 1.0 + (sim.net_height(c.road, c.f) if sim._net_h.has(c.road) else 0.0)
		var p := Vector3(c.x - seat.org_x, h + 2.0, -(c.y - seat.org_y))
		if cam.is_position_behind(p):
			continue
		var s := cam.unproject_position(p) * to_px
		if s.x < 0.0 or s.y < 0.0 or s.x >= root.size.x or s.y >= root.size.y:
			continue
		rows.append({"id": c.id, "kind": c.kind, "road": c.road, "m": snappedf(eye.distance_to(p), 1.0), "x": snappedf(s.x, 0.1), "y": snappedf(s.y, 0.1),
			"toward": c.hx * (eye.x + seat.org_x - c.x) + c.hy * (seat.org_y - eye.z - c.y) > 0.0})
	# the pilot's own road at the ladder's distances: where on the picture each lies
	var R = sim.roads[road]
	var i0: int = clampi(sim.pod.hint, 0, R.N - 1)
	var marks := []
	for d in LADDER_M:
		var i := clampi(i0 + int(float(d) / 24.0), 0, R.N - 1)
		var h: float = sim.net_height(road, float(i)) if sim._net_h.has(road) else 0.0
		var p := Vector3(R.px[i] - seat.org_x, h, -(R.py[i] - seat.org_y))
		if not cam.is_position_behind(p):
			var s := cam.unproject_position(p) * to_px
			marks.append({"m": d, "x": snappedf(s.x, 0.1), "y": snappedf(s.y, 0.1)})
	var out := FileAccess.open(out_dir.path_join("%s-%s.json" % [tag, name]), FileAccess.WRITE)
	out.store_string(JSON.stringify({"name": name, "tag": tag, "size": [root.size.x, root.size.y], "fov": cam.fov, "ppd": PPD,
		"vehicles": rows, "road": marks}))
	out.close()
	print("TRAFFIC FAR SHOT %s: %d vehicles in the picture of %d, field %.1f deg" % [path, rows.size(), net.cars.size(), cam.fov])
