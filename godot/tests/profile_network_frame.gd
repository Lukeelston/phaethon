## Where the Network's main-thread frame goes, part by part, flying the timing harness's stretch
## (render_terminal_art.gd's benchmark: 240 samples of road at about 3,200 mph, three times over,
## the last two timed). Run windowed, as that harness:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/profile_network_frame.gd -- --mute --out=DIR [--bench-at=road,sample]
## Prints PROFILE lines: each part's mean and 95th percentile, ms a frame. The seat is a subclass
## whose _sync_world is the game's, a timer between each call; the roads' and the land's own sync
## report their parts through their profile switches. Traffic's drawing and its feed to the sim are
## timed by doing each a second time (they are idempotent), so they are not counted twice in "traffic".
extends "res://tests/render_terminal_art.gd"


class ProfiledSeat extends "res://vr/vr_cockpit.gd":
	var parts := {}        # name -> PackedFloat64Array of ms, a frame each
	var on := false

	func _mark(name: String, since: int) -> int:
		var now := Time.get_ticks_usec()
		if on:
			if not parts.has(name):
				parts[name] = PackedFloat64Array()
			parts[name].append((now - since) / 1000.0)
		return now

	func _sync_craft(delta: float) -> void:
		var t := Time.get_ticks_usec()
		super(delta)
		_mark("craft", t)

	func _place_camera(k: float) -> void:
		var t := Time.get_ticks_usec()
		super(k)
		_mark("camera and cockpit", t)

	func _update_hud() -> void:
		var t := Time.get_ticks_usec()
		super()
		_mark("hud", t)

	func _sync_world() -> void:
		var t := Time.get_ticks_usec()
		cues.sync(sim, 0.0)
		t = _mark("speed cues (again)", t)
		dust.sync(sim, 0.0)
		t = _mark("dust and spray (again)", t)
		craft.sync_cables(sim, 0.0)
		t = _mark("cables (again)", t)
		ground_mat.set_shader_parameter("org", Vector2(fposmod(org_x, GROUND_PERIOD), fposmod(org_y, GROUND_PERIOD)))
		ground_mat.set_shader_parameter("pod_y", org_y)
		landscape.sync(org_x, org_y)
		ground_mat.set_shader_parameter("absolute_org", Vector2(org_x, org_y))
		t = _mark("land", t)
		network_world.sync(org_x, org_y)
		t = _mark("roads", t)
		if terminal_lighting:
			terminal_lighting.sync(sim, org_x, org_y)
		_net_biome()
		t = _mark("lighting and biome", t)
		if partner:
			partner.update(get_process_delta_time())
		t = _mark("partner", t)
		traffic_net.update(get_process_delta_time())
		t = _mark("traffic", t)
		traffic_net._render()
		t = _mark("  traffic: drawing (again)", t)
		traffic_net._feed()
		t = _mark("  traffic: feed to the sim (again)", t)
		if minimap:
			minimap.marks = traffic_net.marks(sim.pod.x, sim.pod.y, 40000.0)
		t = _mark("map marks", t)
		if on:
			for k in network_world.stream_profile:
				if str(k).ends_with("_us"):
					var name := "  roads: " + str(k).trim_suffix("_us")
					if not parts.has(name):
						parts[name] = PackedFloat64Array()
					parts[name].append(float(network_world.stream_profile[k]) / 1000.0)
			for k in landscape.profile:
				var name := "  land: " + str(k).trim_suffix("_us")
				if not parts.has(name):
					parts[name] = PackedFloat64Array()
				parts[name].append(float(landscape.profile[k]) / 1000.0)

	func _process(delta: float) -> void:
		var t := Time.get_ticks_usec()
		super(delta)
		if on:
			if not parts.has("whole frame"):
				parts["whole frame"] = PackedFloat64Array()
			parts["whole frame"].append((Time.get_ticks_usec() - t) / 1000.0)
			for k in ["sim", "world", "hud"]:
				if not parts.has("game's own: " + k):
					parts["game's own: " + k] = PackedFloat64Array()
				parts["game's own: " + k].append(float(cpu[k]))


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
	seat = ProfiledSeat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	city = {"road": 3, "i": 7976}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-at="):
			var at := arg.trim_prefix("--bench-at=").split(",")
			city = {"road": int(at[0]), "i": int(at[1])}
	seat.network_world.profile_streaming = true
	seat.landscape.profiling = true
	_set_pose(0)
	for i in 5000:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
		if seat.landscape.pending.is_empty() and seat.landscape._job.is_empty() and seat.landscape._decor_job.is_empty() and i > 1200:
			break
	var road = seat.sim.roads[int(city.road)]
	for lap in 3:
		seat.on = lap > 0
		for frame in 480:
			var offset := frame / 2
			var idx := int(city.i) + offset
			_set_pose(offset)
			var dx: float = road.px[idx + 1] - road.px[idx]
			var dy: float = road.py[idx + 1] - road.py[idx]
			for body in seat.sim.bodies:
				body.x += dx * 0.5 * (frame % 2)
				body.y += dy * 0.5 * (frame % 2)
				body.vx = dx * 60.0
				body.vy = dy * 60.0
			seat._process(STEP)
			await process_frame
	var names: Array = seat.parts.keys()
	print("PROFILE at road %d sample %d: %d cars, %d chunks, %d tiles" % [int(city.road), int(city.i), seat.traffic_net.cars.size(), seat.network_world.chunks.size(), seat.landscape.tiles.size()])
	for name in names:
		var v: PackedFloat64Array = seat.parts[name]
		v.sort()
		var sum := 0.0
		for x in v:
			sum += x
		print("PROFILE %-36s mean %6.3f  p95 %6.3f ms" % [name, sum / v.size(), v[int(v.size() * 0.95)]])
	seat.free()
	quit()
