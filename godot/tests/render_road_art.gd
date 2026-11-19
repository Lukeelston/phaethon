## Matched pilot-seat captures and a rolling one-eye benchmark. Run each track separately:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_road_art.gd -- --track=network (or carving) --handling=speed --mute --out=DIR
## Optional: --captures-only, --benchmark-only, --motion (a 60 Hz, 36-frame burst).
extends "res://tests/render_terminal_art.gd"

const ROLL_FRAMES := 360
const WARM_FRAMES := 36

var network := false


func _run() -> void:
	var track := "network"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--track="):
			track = arg.trim_prefix("--track=")
	if track not in ["network", "carving"] or out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --track=network or carving and --out=DIR.")
		quit(1)
		return
	seed(197706)
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = track
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	network = track == "network"
	if root.use_xr or seat.sim.track_name != track:
		push_error("Road review requires a monoscopic pilot seat on the requested track.")
		quit(1)
		return

	# Name, road, sample, direction, lateral metres (+left), head yaw and pitch.
	var views := []
	if network:
		for c in seat.sim.cities:
			if c.name == "ERIDANUS":
				views.append(["01-terminal-exit", c.road, int(c.i) + 79, 1, -6.0, 0.0, -3.0])
				views.append(["02-daylight-deck", c.road, int(c.i) + 112, 1, -84.0, -43.0, -11.0])
		for junction in seat.sim.junctions:
			if seat.sim.roads[int(junction[0])].name == "E2" and seat.sim.roads[int(junction[3])].name == "OEridanus":
				var road = seat.sim.roads[int(junction[3])]
				var end: int = 0 if int(junction[4]) == 0 else road.N - 1
				seat.sim._nearest_on(int(junction[0]), road.px[end], road.py[end], (int(junction[1]) + int(junction[2])) / 2, 90)
				views.append(["03-interchange", junction[0], seat.sim._n_i + 6, -1, 126.0, 23.0, -6.0])
				views.append(["03b-express-shoulder", junction[0], seat.sim._n_i + 130, -1, 171.0, 58.0, -11.0])
				# A long eight-lane stretch clear of E2's ramp merge and amber approach.
				views.append(["03c-express-lanes", junction[0], 10000, 1, 8.0, -10.0, -5.0])
				views.append(["03d-express-lane-center", junction[0], 10000, 1, 22.5, -24.0, -6.0])
				# The same fixed point works on older builds that predate lane paint.
				if seat.network_world.has_method("_prepare_traffic_paint"):
					for station in range(9940, 10061):
						if seat.network_world._traffic_paint[int(junction[0])][station] != 2:
							push_error("E2 review station left the eight-lane travel section.")
							quit(1)
							return
				break
		for r in seat.sim.roads.size():
			if seat.sim.roads[r].name == "S5":
				views.append(["04-highway", r, 1000, 1, -64.0, -9.0, -3.0])
		if views.size() != 7:
			push_error("Could not resolve Network review roads.")
			quit(1)
			return
	else:
		var corner: Array = seat.gp_world.corners[0]
		var inside := float(corner[3])
		views.append(["05-carving-turn-in", 0, int(corner[0]) - 8, 1, -inside * 74.0, 0.0, -3.0])
		views.append(["06-carving-apex", 0, int(corner[1]), 1, inside * 68.0, inside * 40.0, -11.0])

	if "--benchmark-only" not in OS.get_cmdline_user_args():
		for v in views:
			var express := str(v[0]).begins_with("03c-") or str(v[0]).begins_with("03d-")
			if "--express-only" in OS.get_cmdline_user_args() and not express:
				continue
			_place(v)
			if not await _settle():
				quit(1)
				return
			seat.cam.rotation_degrees = Vector3(float(v[6]), float(v[5]), 0.0)
			# A seated look over the starboard sill, from the inside racing line.
			seat.cam.position = Vector3(0.18, 0.22, -0.08) if v[0] == "06-carving-apex" else Vector3.ZERO
			if express:
				seat.cam.position = Vector3(0.04, 0.16, -0.08)
			for frame in WARM_FRAMES:
				if not network or express or v[0] == "04-highway":
					_place(v, 0, true)
				seat._process(STEP)
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join(v[0] + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			print("ROAD_SHOT ", v[0], " pose=", str(v.slice(1)))
	if "--captures-only" not in OS.get_cmdline_user_args():
		var start: Array = views[-1] if network else views[0]
		_place(start)
		if not await _settle():
			quit(1)
			return
		seat.cam.rotation = Vector3.ZERO
		seat.cam.position = Vector3.ZERO
		await _roll(start)
	if "--motion" in OS.get_cmdline_user_args():
		var view: Array = views[-1] if network else views[0]
		_place(view)
		if not await _settle():
			quit(1)
			return
		seat.cam.rotation_degrees = Vector3(float(view[6]), float(view[5]), 0.0)
		seat.cam.position = Vector3.ZERO
		for frame in 100:
			_place(view, frame, true)
			seat._process(STEP)
			await process_frame
			if frame >= 28 and frame % 2 == 0:
				await RenderingServer.frame_post_draw
				var path := out_dir.path_join("motion-%03d.png" % frame)
				if root.get_texture().get_image().save_png(path) != OK:
					push_error("Couldn't save " + path)
					quit(1)
					return
	seat.free()
	quit()


func _place(view: Array, frame := 0, moving := false) -> void:
	var road: int = view[1]
	var direction: int = view[3]
	var base := int(view[2]) + direction * (frame / 4)
	var sim = seat.sim
	var stride: Vector2
	if network:
		sim.respawn_on(road, base, direction)
		var r = sim.roads[road]
		stride = Vector2(r.px[base + direction] - r.px[base], r.py[base + direction] - r.py[base])
	else:
		sim.respawn(-1, base)
		stride = Vector2(sim.tpx[base + direction] - sim.tpx[base], sim.tpy[base + direction] - sim.tpy[base])
	var side := Vector2(-stride.y, stride.x).normalized() * float(view[4])
	var shift := stride * (float(frame % 4) / 4.0) + side
	for body in sim.bodies:
		body.x += shift.x
		body.y += shift.y
		if moving:
			body.vx = stride.x / (4.0 * STEP)
			body.vy = stride.y / (4.0 * STEP)
	if frame == 0:
		seat._ride.clear()


func _settle() -> bool:
	if not network:
		return true
	for i in 6000:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 32 == 0:
			await process_frame
		if seat.network_world.wanted == 0 and seat.network_world._job.is_empty() and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty() and seat.landscape._decor_job.is_empty():
			return true
	push_error("Review streamers failed to settle.")
	return false


func _roll(start: Array) -> void:
	var viewport := root.get_viewport_rid()
	for lap in 3:
		var last := Time.get_ticks_usec()
		for frame in ROLL_FRAMES:
			_place(start, frame, true)
			var begin := Time.get_ticks_usec()
			seat._process(STEP)
			var update_ms := (Time.get_ticks_usec() - begin) / 1000.0
			await process_frame
			var now := Time.get_ticks_usec()
			if lap == 2:
				cpu.append(update_ms)
				elapsed.append((now - last) / 1000.0)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			last = now
	var result := {"viewport": str(root.size), "frames": cpu.size(), "track": Seat.track_override,
		"first_pose": start, "view_update_ms": _stats(cpu), "viewport_gpu_ms": _stats(gpu),
		"wall_frame_ms": _stats(elapsed), "draw_calls": _stats(draws)}
	var output := FileAccess.open(out_dir.path_join("timing.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))
	print("ROAD_BENCH ", JSON.stringify(result))
