## Actual renderer checks of first-frame fade, followed by ramp/profile snapshots.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var failures := 0
func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	failures+=int(not ok)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		check("a windowed renderer is required for frame readback", false)
		_finish()
		return
	View.track_override="network"
	View.job_override="none"
	View.best_dir=OS.get_user_data_dir().path_join("stream_render_")
	var v=View.new()
	root.add_child(v)
	v.set_process(false)
	v.craft.hide()
	for child in v.get_children():
		if child is CanvasLayer: child.hide()
	root.msaa_3d=Viewport.MSAA_4X
	var land=v.landscape
	var p:=Vector2(300000,100000)
	for k in 9: land.sync(p.x,p.y)
	var key: Vector2i=land.tiles.keys()[0]
	land._decor_job={"key":key,"group":land.GROUPS-4,"batches":{"service":[Transform3D.IDENTITY]}}
	# The per-slice time budget can split the final four groups across calls.
	for group in 4:
		land._decorate_slice()
		if land._decor_job.is_empty(): break
	var tile: Dictionary=land.tiles[key]
	if not tile.has("deco") or tile.deco.get_child_count() == 0:
		check("the tile has a published decoration batch", false)
		_finish()
		return
	var initial:=true
	for batch in tile.deco.get_children():
		initial=initial and float(batch.get_instance_shader_parameter("stream_reveal"))==0.0
	check("new prop batches start invisible before their first rendered frame",initial)
	await process_frame
	await RenderingServer.frame_post_draw
	check("first rendered frame retains zero reveal",float(tile.deco.get_child(0).get_instance_shader_parameter("stream_reveal"))==0.0)
	tile.deco_born=Time.get_ticks_msec()-900
	tile.born=Time.get_ticks_msec()-900
	land.sync(p.x,p.y)
	var middle: float=tile.deco.get_child(0).get_instance_shader_parameter("stream_reveal")
	check("creation fade reaches half opacity gradually",middle>=0.49 and middle<0.55)
	var surface_match:=true
	for surface in tile.node.get_children():
		if surface is MeshInstance3D:
			var reveal: float=surface.get_instance_shader_parameter("stream_reveal")
			surface_match=surface_match and reveal>=0.49 and reveal<0.55
	check("wetland water and terrain share the gradual creation fade",tile.node.get_child_count()>=3 and surface_match)
	tile.deco_born=Time.get_ticks_msec()-2000
	tile.born=Time.get_ticks_msec()-2000
	land.sync(p.x,p.y)
	check("creation fade finishes at full opacity",float(tile.deco.get_child(0).get_instance_shader_parameter("stream_reveal"))==1.0)
	var out:=ProjectSettings.globalize_path("res://../evidence/v025-flow")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out=arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	for jump in 3:
		var r: int=v.sim.jumps[jump][0]
		var road=v.sim.roads[r]
		var middle_i: int=road.N/2
		p=Vector2(road.px[middle_i],road.py[middle_i])
		for k in 3000: land.sync(p.x,p.y)
		for k in 160: v.network_world.sync(p.x,p.y)
		v.ground_mat.set_shader_parameter("absolute_org",p)
		v.cam.position=Vector3(road.nx[middle_i]*5500,2600,-road.ny[middle_i]*5500)
		v.cam.look_at(Vector3(0,v.sim.net_height(r,middle_i)+350,0))
		v.cam.fov=75
		for t in land.tiles.values():
			for surface in t.node.get_children():
				if surface is MeshInstance3D: surface.set_instance_shader_parameter("stream_reveal",1.0)
		for k in 5: await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		check("saved rendered ramp %d" % jump, shot != null and not shot.is_empty()
			and shot.save_png(out.path_join("ramp-%d.png"%jump)) == OK)
	v.free()
	_finish()

func _finish() -> void:
	print("NETWORK STREAMING RENDER %s (%d failures)"%["PASS" if failures==0 else "FAIL",failures])
	quit(int(failures>0))
