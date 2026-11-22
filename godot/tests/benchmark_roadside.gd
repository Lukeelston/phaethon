## Run from either checkout with --xr-mode off --audio-driver Dummy --fixed-fps 90
## -s <absolute path to this script> -- --mute --hot-start --out=<evidence directory>.
extends SceneTree
const Seat := preload("res://vr/vr_cockpit.gd")
const Outlook := preload("res://view/outlook.gd")
const RESOLUTION := Vector2i(4128, 2208)
const WARM := 60
const FRAMES := 120
# Road, sample (24 m spacing in the headset telemetry), direction of travel.
const VIEWS := [["E1", 2548, -1], ["Basalt", 738, 1]]
var target := SubViewport.new()
var seat
var output := ""
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Supply a writable --out= directory.")
		quit(1)
		return
	seed(52780)
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = output.path_join("review_")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	target.own_world_3d = true
	target.size = RESOLUTION
	target.msaa_3d = Viewport.MSAA_4X
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(target)
	seat = Seat.new()
	target.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	RenderingServer.viewport_set_measure_render_time(target.get_viewport_rid(), true)
	for fixture in VIEWS:
		await _measure(fixture[0], fixture[1], fixture[2])
		if failed: break
	target.free()
	quit(int(failed))

func _measure(road_name: String, sample: int, direction: int) -> void:
	var road_id := -1
	for i in seat.sim.roads.size():
		if seat.sim.roads[i].name == road_name:
			road_id = i
			break
	if road_id < 0 or sample >= seat.sim.roads[road_id].N:
		_fail("Missing road or sample: " + road_name)
		return
	seat.sim.respawn_on(road_id, sample, direction)
	seat._ride.clear()
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation = Vector3.ZERO
	var location := Vector2(seat.sim.pod.x, seat.sim.pod.y)
	var world = seat.network_world
	var land = seat.landscape
	var settled := false
	for step in 30000:
		world.sync(location.x, location.y)
		land.sync(location.x, location.y)
		if step % 60 == 0:
			await process_frame
			settled = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty() and land.pending.is_empty() and land._job.is_empty() and land._decor_job.is_empty() and not land._deco_want and land._deco_revealing.is_empty() and land._revealing.is_empty()
			if settled: break
	if not settled:
		_fail("Scenery did not settle at " + road_name)
		return
	var gpu := PackedFloat64Array()
	var render_cpu := PackedFloat64Array()
	var update_cpu := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var primitives := PackedFloat64Array()
	var vp := target.get_viewport_rid()
	for frame in WARM + FRAMES:
		seat.sim.respawn_on(road_id, sample, direction)
		seat._ride.clear()
		var start := Time.get_ticks_usec()
		seat._process(1.0 / 90.0)
		var cpu_ms := (Time.get_ticks_usec() - start) / 1000.0
		await RenderingServer.frame_post_draw
		if frame >= WARM:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			update_cpu.append(cpu_ms)
			draws.append(target.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
			primitives.append(target.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	var batches := 0
	var count := 0
	var tiers := [0, 0, 0]
	for tile: Dictionary in land.tiles.values():
		if not tile.has("deco"): continue
		tiers[tile.deco_near] += 1
		for batch: MultiMeshInstance3D in tile.deco.get_children():
			batches += 1
			count += batch.multimesh.instance_count
	var name := road_name.to_lower()
	var image := target.get_texture().get_image()
	if image.get_size() != RESOLUTION or image.save_jpg(output.path_join(name + ".jpg"), 0.92) != OK or Array(gpu).min() <= 0 or Array(draws).min() <= 0 or Array(primitives).min() <= 0:
		_fail("Missing rendered pixels, GPU timing or draws at " + road_name)
		return
	# Capture a control with only streamed prop batches hidden. A GPU readback verifies actual
	# occlusion and subpixel culling, which a frustum or an instance count alone cannot establish.
	for tile: Dictionary in land.tiles.values():
		if tile.has("deco"): tile.deco.hide()
	for frame in 3: await RenderingServer.frame_post_draw
	var control := target.get_texture().get_image()
	for tile: Dictionary in land.tiles.values():
		if tile.has("deco"): tile.deco.show()
	for frame in 3: await RenderingServer.frame_post_draw
	var restored := target.get_texture().get_image()
	var changed := 0
	for y in range(0, RESOLUTION.y, 4):
		for x in range(0, RESOLUTION.x, 4):
			var a := image.get_pixel(x, y)
			var b := control.get_pixel(x, y)
			var c := restored.get_pixel(x, y)
			if _difference(a,c) < 0.01 and _difference(a,b) > 0.05: changed += 1
	var close := await _close_view(name, land)
	var result := {"close_view":close, "road":road_name, "sample":sample, "direction":direction, "world_xy":[location.x, location.y], "size":[RESOLUTION.x, RESOLUTION.y], "gpu":RenderingServer.get_video_adapter_name(), "frames":FRAMES, "msaa":4, "tiles":tiers, "batches":batches, "instances":count, "draws":_stats(draws), "primitives":_stats(primitives), "gpu_ms":_stats(gpu), "render_cpu_ms":_stats(render_cpu), "update_cpu_ms":_stats(update_cpu), "visible_difference_samples":changed}
	var file := FileAccess.open(output.path_join(name + ".json"), FileAccess.WRITE)
	if file == null:
		_fail("Could not write result at " + road_name)
		return
	file.store_line(JSON.stringify(result, "\t"))
	print("ROADSIDE_BENCH ", JSON.stringify(result))
	if changed == 0 or close.is_empty():
		_fail("Missing visible scenery readback at " + road_name)

func _difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b)))

# Photograph one real roadside placement without moving or rebuilding the streamer.
func _close_view(label: String, land) -> Dictionary:
	var candidates := []
	for tile: Dictionary in land.tiles.values():
		if not tile.has("deco") or tile.deco_near != 0: continue
		for batch: MultiMeshInstance3D in tile.deco.get_children():
			if batch.name != ("service" if label == "e1" else "basalt"): continue
			var mesh := batch.multimesh.mesh
			for i in batch.multimesh.instance_count:
				var xf := batch.global_transform * batch.multimesh.get_instance_transform(i)
				var box := xf * mesh.get_aabb()
				candidates.append({"distance":box.get_center().distance_to(seat.cam.global_position), "bounds":box, "batch":batch})
	candidates.sort_custom(func(a,b): return a.distance < b.distance)
	for item in candidates.slice(0, 8):
		var result := await _photograph(label, item.batch, item.bounds, item.distance)
		if not result.is_empty(): return result
	return {}

func _photograph(label: String, subject: MultiMeshInstance3D, bounds: AABB, distance: float) -> Dictionary:
	var center := bounds.get_center()
	var radius := bounds.size.length() * 0.5
	var camera := Camera3D.new()
	camera.fov = 57
	camera.far = 90000
	target.add_child(camera)
	var result := {}
	for angle in [Vector3(1.1,0.7,1.6), Vector3(-1.1,0.8,-1.6), Vector3(0.2,1.5,-1.2)]:
		camera.global_position = center + (angle as Vector3).normalized() * radius * 2.35
		camera.look_at(center)
		camera.make_current()
		for frame in 3: await RenderingServer.frame_post_draw
		var image := target.get_texture().get_image()
		subject.hide()
		for frame in 3: await RenderingServer.frame_post_draw
		var hidden := target.get_texture().get_image()
		subject.show()
		var pixels := 0
		for y in range(RESOLUTION.y*3/8, RESOLUTION.y*5/8, 8):
			for x in range(RESOLUTION.x*3/8, RESOLUTION.x*5/8, 8):
				if _difference(image.get_pixel(x,y), hidden.get_pixel(x,y)) > 0.07: pixels += 1
		if pixels < 350: continue
		image.resize(1200, 642, Image.INTERPOLATE_LANCZOS)
		if image.save_jpg(output.path_join(label + "-prop.jpg"), 0.91) == OK:
			result = {"kind":String(subject.name), "meters_from_eye":distance, "relative_center":[center.x, center.y, center.z], "subject_samples":pixels}
		break
	camera.free()
	seat.cam.make_current()
	return result

func _stats(samples: PackedFloat64Array) -> Dictionary:
	samples.sort()
	return {"p50":samples[int(samples.size()*0.50)], "p95":samples[ceili(samples.size()*0.95)-1]}

func _fail(message: String) -> void:
	push_error(message)
	failed = true
