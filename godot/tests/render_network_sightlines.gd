## Review changed towers, painted ramps and an actual fixed-eye Network scene.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const CanopyScript := preload("res://view/canopy.gd")
var v
var out := ""
func _initialize() -> void:
	_run.call_deferred()
func _warm(p: Vector2) -> void:
	v.org_x=p.x
	v.org_y=p.y
	for k in 3000: v.landscape.sync(p.x,p.y)
	for k in 160: v.network_world.sync(p.x,p.y)
	v.ground_mat.set_shader_parameter("absolute_org",p)
	v.ground_mat.set_shader_parameter("org",Vector2(fposmod(p.x,4096),fposmod(p.y,4096)))
	for tile in v.landscape.tiles.values():
		for child in tile.node.get_children():
			if child is MeshInstance3D: child.set_instance_shader_parameter("stream_reveal",1.0)
		if tile.has("deco"):
			for batch in tile.deco.get_children(): batch.set_instance_shader_parameter("stream_reveal",1.0)
func _shot(name: String) -> void:
	for k in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name+".png"))
	print("SIGHTLINE SHOT ",name)
func _run() -> void:
	View.track_override="network"
	View.job_override="none"
	View.best_dir=OS.get_user_data_dir().path_join("sightline_render_")
	v=View.new()
	root.add_child(v)
	v.set_process(false)
	v.craft.hide()
	for node in v.get_children():
		if node is CanvasLayer: node.hide()
	v.cues.hide()
	v.dust.hide()
	root.msaa_3d=Viewport.MSAA_4X
	out=ProjectSettings.globalize_path("res://../evidence/v026-world")
	DirAccess.make_dir_recursive_absolute(out)
	for index in [0,1,7,10]:
		var sh: Array=v.sim.shafts[index]
		var road=v.sim.roads[int(sh[0])]
		var i:=int(sh[1])
		var p: Vector2=v.network_world._wxy(int(sh[0]),i)
		_warm(p)
		var u:=Vector3(road.tx[i-1],0,-road.ty[i-1])
		var side:=Vector3(-u.z,0,u.x)
		v.cam.position=u*4000+side*18000+Vector3.UP*14000
		v.cam.look_at(Vector3(0,11000,0))
		v.cam.fov=80
		await _shot("tower-"+road.name.replace("+","plus").replace("-","minus"))
	if "--towers-only" in OS.get_cmdline_user_args():
		v.free()
		quit(0)
		return
	for index in [0,1,2]:
		var r:=int(v.sim.jumps[index][0])
		var road=v.sim.roads[r]
		var i:=int(road.N*0.8)
		var p: Vector2=v.network_world._wxy(r,i)
		_warm(p)
		v.cam.position=Vector3(0,v.network_world._h(r,i)+8,0)
		var target:=mini(i+25,road.N-1)
		v.cam.look_at(Vector3(road.px[target]-p.x,v.network_world._h(r,target)+8,-road.py[target]+p.y))
		v.cam.fov=80
		await _shot("ramp-"+road.name)
	# Full landscape from a cockpit-height sightline; actual canopy, same scene/camera each speed.
	var sh: Array=v.sim.shafts[0]
	var r:=int(sh[0])
	var road=v.sim.roads[r]
	var i:=maxi(5,int(sh[1])-55)
	var p: Vector2=v.network_world._wxy(r,i)
	_warm(p)
	v.cam.position=Vector3(0,8,0)
	v.cam.look_at(v.cam.position+Vector3(road.tx[i]*10000,0,-road.ty[i]*10000))
	v.cam.fov=100
	var canopy:=CanopyScript.build()
	root.add_child(canopy)
	canopy.basis=v.cam.basis
	canopy.position=v.cam.position-canopy.basis*Vector3(0,0.12,0.6)
	for mph in [0.0,6000.0]:
		CanopyScript.update(canopy,mph/2.236936,0.0,"normal",0.0)
		await _shot("cockpit-%d"%int(mph))
	canopy.free()
	v.free()
	quit(0)
