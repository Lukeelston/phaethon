## How well the traffic ahead reads from the seat (Luke, after the first flight with the fleet's
## models: "It's getting hard to see the upcoming cars"). The same nine vehicles stood on an open
## highway at set distances ahead of the parked pod, from 150 m to 6 km, seen from the seated eye:
## the cockpit's own view, a headset's field, and a long lens on the horizon. Run windowed, as
## render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_traffic_ahead.gd -- --mute --out=DIR [--tag=name] [--closed-nose]
extends "res://tests/render_terminal_art.gd"

# metres ahead, kind (the Network traffic's own numbers: car, slow pod, demon, transport), metres across from the pod
const AHEAD := [[150.0, 0, -45.0], [300.0, 1, 45.0], [500.0, 2, -90.0], [800.0, 3, 90.0], [1200.0, 0, 0.0],
	[1800.0, 1, -45.0], [2600.0, 2, 45.0], [4000.0, 0, -90.0], [6000.0, 3, 45.0]]
const PAINT := [Color(0.2, 0.35, 0.8), Color(0.82, 0.77, 0.62), Color(0.9, 0.1, 0.6), Color(0.9, 0.55, 0.15), Color(0.75, 0.12, 0.1),
	Color(0.38, 0.61, 0.65), Color(0.1, 0.9, 0.9), Color(0.15, 0.16, 0.18), Color(0.33, 0.49, 0.61)]
const LOOKS := [["wide", 0.0, -3.0], ["field", 96.0, -6.0], ["long", 22.0, 0.5]]   # name, field of view (0: the cockpit's own), pitch


func _run() -> void:
	var tag := "now"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Seat._nose_loaded = true
	if "--closed-nose" in OS.get_cmdline_user_args():
		preload("res://view/craft_model.gd").nose_closed = true
	if "--no-reflection" in OS.get_cmdline_user_args():   # the windscreen without its reflection of the cockpit
		preload("res://view/screen_reflection.gd").enabled = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var road := 2          # E3, open country: long and straight
	var at := 9000
	seat.sim.respawn_on(road, at, 1)
	seat._ride.clear()
	for i in 1600:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	for frame in 40:
		seat._process(STEP)
		await process_frame
	var net = seat.traffic_net
	var R = seat.sim.roads[road]
	var i0: int = clampi(seat.sim.pod.hint, 0, R.N - 1)
	var pod_lat: float = (seat.sim.pod.x - R.px[i0]) * R.nx[i0] + (seat.sim.pod.y - R.py[i0]) * R.ny[i0]
	var Car = net.get_script().Car
	net.cars.clear()
	for k in AHEAD.size():
		var c = Car.new()
		c.id = 100 + k
		c.kind = int(AHEAD[k][1])
		c.road = road
		c.dir = 1
		c.f = float(i0) + float(AHEAD[k][0]) / 24.0
		c.lat = pod_lat + float(AHEAD[k][2])
		c.v = 0.0
		c.owed = 0.0
		c.col = PAINT[k]
		net._place(c)
		net.cars.append(c)
	print("TRAFFIC AHEAD: %d vehicles from %.0f to %.0f m, the pod %.0f m across the road" % [net.cars.size(), AHEAD[0][0], AHEAD[AHEAD.size() - 1][0], pod_lat])
	var wide: float = seat.cam.fov
	for look in LOOKS:
		seat.cam.position = Vector3.ZERO
		seat.cam.fov = float(look[1]) if float(look[1]) > 0.0 else wide
		seat.cam.rotation_degrees = Vector3(float(look[2]), 0.0, 0.0)
		net._render()
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("ahead-%s-%s.png" % [tag, look[0]])
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("TRAFFIC AHEAD SHOT ", path)
	seat.free()
	quit()
