## Fixed moving Vulkan workload; no headset or FPS claims. Same route before/after.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("distance_benchmark_")
	root.msaa_3d = Viewport.MSAA_4X
	v = View.new()
	root.add_child(v)
	v.set_process(false)
	v.craft.hide()
	v.hud.hide()
	v.minimap_2d.hide()
	v._skill_label.hide()
	v._skill_award_label.hide()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	if "--settled" in OS.get_cmdline_user_args():
		for i in 4000:
			v.network_world.sync(30000,500000)
			v.landscape.sync(30000,500000)
			if i%80==0: await process_frame
		var decorations := 0
		for tile in v.landscape.tiles.values():
			if tile.has("deco"): decorations+=1
		var ready: bool = v.landscape.pending.is_empty() and v.landscape._job.is_empty() and v.landscape._decor_job.is_empty()
		print("SETTLED_START ",JSON.stringify({"ready":ready,"tiles":v.landscape.tiles.size(),"decorations":decorations}))
		if not ready:
			v.free()
			quit(1)
			return
	var cpu := []
	var gpu := []
	var frames := []
	var road_cpu := []
	var terrain_cpu := []
	v.network_world.profile_streaming=true
	var last := Time.get_ticks_usec()
	for i in 2100:
		# 700 warmup frames, then 70 km at 6,700 mph, 60 Hz simulated travel.
		var p := Vector2(30000.0+maxi(0,i-700)*50.0,500000.0)
		var start := Time.get_ticks_usec()
		v.network_world.sync(p.x,p.y)
		var road_end := Time.get_ticks_usec()
		v.landscape.sync(p.x,p.y)
		if i>=700:
			road_cpu.append(float(road_end-start)/1000.0)
			terrain_cpu.append(float(Time.get_ticks_usec()-road_end)/1000.0)
		v.ground_mat.set_shader_parameter("absolute_org",p)
		v.cam.position = Vector3(0,280,0)
		v.cam.look_at(Vector3(10000,400,0))
		if i>=700: cpu.append(float(Time.get_ticks_usec()-start)/1000.0)
		await process_frame
		if i>=700:
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			frames.append(float(Time.get_ticks_usec()-last)/1000.0)
		last=Time.get_ticks_usec()
	print("DISTANCE_BENCH ",JSON.stringify({"stream_cpu_ms":stats(cpu),"road_cpu_ms":stats(road_cpu),"terrain_cpu_ms":stats(terrain_cpu),"render_gpu_ms":stats(gpu),"frame_ms":stats(frames),"terrain_tiles":v.landscape.tiles.size(),"road_chunks":v.network_world.chunks.size(),"road_phase_max_us":v.network_world.stream_profile}))
	v.free()
	quit()
func stats(a: Array) -> Dictionary:
	a.sort()
	var total := 0.0
	for x in a: total+=x
	return {"mean":total/a.size(),"p50":a[a.size()/2],"p95":a[int(a.size()*0.95)],"max":a[-1]}
