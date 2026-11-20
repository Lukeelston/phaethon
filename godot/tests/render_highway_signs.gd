## Matched cockpit views of the E2 city exit, split interchange and launch. The
## camera stays in the production seat. Pass --out=DIR after Godot's -- separator.
extends "res://tests/render_road_art.gd"

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		quit(1)
		return
	seed(197706)
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	network = true
	var e2 := -1
	for i in seat.sim.roads.size():
		if seat.sim.roads[i].name == "E2":
			e2 = i
	if e2 < 0 or root.use_xr:
		quit(1)
		return
	var city_at := 0
	var split_at := 0
	for key in seat.network_world._signs:
		if key.x != e2:
			continue
		for spec in seat.network_world._signs[key]:
			if spec[1] != 1 or (spec.size() > 4 and spec[4].get("decision",false)):
				continue
			if spec[2] == "city" and spec[3][0] == "ERIDANUS":
				city_at = spec[0]
			if spec[2] == "exit" and spec[3][0] == "EXIT" and absi(spec[0]-10750)<250:
				split_at = spec[0]
	if city_at==0 or split_at==0:
		quit(1)
		return
	# Same eye height, lane and distance to the corresponding sign across both builds.
	for v in [["city", e2, city_at-11, 1, -60.0, 0.0, 6.0],
			["split", e2, split_at-7, 1, 0.0, 0.0, 12.0],
			["ascent", e2, 10926, 1, 105.0, -38.0, 11.0],
			["advance", e2, 10375, 1, -72.0, 0.0, 2.0]]:
		_place(v)
		if not await _settle():
			quit(1)
			return
		seat.cam.rotation_degrees = Vector3(v[6], v[5], 0)
		for step in 20:
			_place(v, 0, true)
			seat._process(STEP)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(v[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			quit(1)
			return
		print("HIGHWAY SIGN SHOT ", path)
	seat.free()
	quit()
