## Realism spike: a transport's train on the steepest plain road in the Network, seen from the
## side, to show the vehicles following the grade. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_traffic_grade.gd -- --mute --out=DIR [--level]
## --level draws it as v0.3.2 did: every car level, at the lead's height.
extends "res://tests/render_terminal_art.gd"


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var net = seat.traffic_net
	var level := "--level" in OS.get_cmdline_user_args()
	net.grade = not level
	# the steepest stretch of plain road: its grade over twelve samples
	var best := [-1, 0, 0.0]
	for r in seat.sim.roads.size():
		var R = seat.sim.roads[r]
		if R.role != "" or not seat.sim._net_h.has(r) or seat.network_world.shaft.maps.has(r):
			continue
		for i in range(60, R.N - 20, 2):
			var rise: float = seat.sim.net_height(r, i + 6.0) - seat.sim.net_height(r, i - 6.0)
			if rise / 288.0 > float(best[2]):
				best = [r, i, rise / 288.0]
	if int(best[0]) < 0:
		push_error("No graded road found.")
		quit(1)
		return
	var road: int = best[0]
	var at: int = best[1]
	print("TRAFFIC GRADE: road %d sample %d climbs %.1f%%, %.0f m up" % [road, at, 100.0 * float(best[2]), seat.sim.net_height(road, float(at))])
	seat.sim.respawn_on(road, at - 50, 1)
	seat._ride.clear()
	for i in 1600:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	for frame in 40:
		seat._process(STEP)
		await process_frame
	if net.cars.is_empty():
		push_error("No traffic to place.")
		quit(1)
		return
	var car = net.cars[0]
	for c in net.cars:
		if c.kind == net.TRANSPORT:
			car = c
	car.kind = net.TRANSPORT
	car.road = road
	car.f = float(at)
	car.dir = 1
	car.lat = 60.0
	car.v = 0.0
	car.owed = 0.0
	net._place(car)
	net._render()
	# from beside the middle of its train, a little above it, looking across the road
	var R = seat.sim.roads[road]
	var mid := at - int((net.TRAIN - 1) * net.TRAIN_GAP / 48.0)
	var h: float = seat.sim.net_height(road, float(mid))
	var target := Vector3(R.px[mid] + R.nx[mid] * 60.0 - seat.org_x, h + 8.0, -(R.py[mid] + R.ny[mid] * 60.0 - seat.org_y))
	var eye := Vector3(R.px[mid] - R.nx[mid] * 150.0 - seat.org_x, h + 22.0, -(R.py[mid] - R.ny[mid] * 150.0 - seat.org_y))
	seat.cam.fov = 44.0
	seat.cam.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("traffic-grade-%s.png" % ("level" if level else "graded"))
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Couldn't save " + path)
		quit(1)
		return
	print("TRAFFIC GRADE SHOT ", path)
	seat.free()
	quit()
