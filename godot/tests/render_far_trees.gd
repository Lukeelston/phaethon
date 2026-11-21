## The trees' far shapes against the same trees drawn whole (view/network_biome_props.gd): the same
## pictures taken both ways in one run, from the seat and from a few hundred metres over the road,
## where the far country shows. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_far_trees.gd -- --mute --out=DIR [--at=road,sample]
## Saves NAME-far.png and NAME-whole.png, and prints how many pixels differ between each pair.
extends "res://tests/render_terminal_art.gd"

const Props := preload("res://view/network_biome_props.gd")
# Name, the eye's height over the seat (m), where it looks (degrees: up, left).
const VIEWS := [
	["seat", 0.0, Vector3(2, 0, 0)],
	["over-the-road", 350.0, Vector3(-6, 0, 0)],
	["over-the-road-aside", 350.0, Vector3(-8, 55, 0)],
	["high", 1500.0, Vector3(-14, -30, 0)],
]


func _detail(far: bool) -> void:
	Props.far_shapes = far
	var land = seat.landscape
	for key in land.tiles:
		land.tiles[key].erase("deco_near")
	land._detail_new = true
	land.sync(seat.sim.pod.x, seat.sim.pod.y)


func _run() -> void:
	var at := PackedStringArray(["0", "1500"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--at="):
			at = arg.trim_prefix("--at=").split(",")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat._nose_loaded = true
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	city = {"road": int(at[0]), "i": int(at[1])}
	_set_pose(0)
	var land = seat.landscape
	for i in 12000:      # every tile's props in, not only the nearest
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		land.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 60 == 0:
			await process_frame
		if i > 1200 and land.pending.is_empty() and land._job.is_empty() and land._decor_job.is_empty() and not land._deco_want and land._deco_revealing.is_empty():
			break
	var trees := 0
	var with_props := 0
	for key in land.tiles:
		if land.tiles[key].has("deco"):
			with_props += 1
			for batch in land.tiles[key].deco.get_children():
				trees += (batch as MultiMeshInstance3D).multimesh.instance_count
	print("FAR_TREES at %s sample %s: %d tiles with props, %d of them near, %d things planted" % [seat.sim.roads[int(at[0])].name, at[1], with_props, land.near_tiles, trees])
	for kind in Props.new().far:
		var lib = land.prop_library
		print("FAR_TREES %s: %d triangles whole, %d in its far shape, %d in its distant one" % [kind, Props.triangles(lib.cache[kind]), Props.triangles(lib.far[kind]), Props.triangles(lib.distant[kind])])
	for view in VIEWS:
		var pictures := {}
		for far in [true, false]:
			_detail(far)
			seat.cam.position = Vector3(0.0, float(view[1]), 0.0)
			seat.cam.rotation_degrees = view[2]
			for frame in 6:
				seat._process(STEP)
				await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(out_dir.path_join("%s-%s.png" % [view[0], "far" if far else "whole"]))
			pictures[far] = image
		var a: Image = pictures[true]
		var b: Image = pictures[false]
		var differ := 0
		for y in range(0, a.get_height(), 2):
			for x in range(0, a.get_width(), 2):
				var p := a.get_pixel(x, y)
				var q := b.get_pixel(x, y)
				if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.12:
					differ += 1
		print("FAR_TREES view %s: %.2f%% of pixels differ" % [view[0], 400.0 * differ / (a.get_width() * a.get_height())])
	_detail(true)
	seat.free()
	quit()
