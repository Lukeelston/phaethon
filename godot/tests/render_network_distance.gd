## Actual Vulkan regional inspection, including roads and high-speed sightlines.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("landscape_render_")
	root.msaa_3d = Viewport.MSAA_4X
	v = View.new()
	root.add_child(v)
	v.set_process(false)
	v.craft.hide()
	v.hud.hide()
	v.minimap_2d.hide()
	v._skill_label.hide()
	v._skill_award_label.hide()
	var out := ProjectSettings.globalize_path("res://../evidence/v025-environment")
	DirAccess.make_dir_recursive_absolute(out)
	for region in v.landscape.REGIONS:
		var p: Vector2 = region[1]
		v.org_x = p.x
		v.org_y = p.y
		for k in 3000:
			v.landscape.sync(p.x,p.y)
		for k in 80:
			v.network_world.sync(p.x,p.y)
		v.ground_mat.set_shader_parameter("absolute_org",p)
		v.ground_mat.set_shader_parameter("org",Vector2(fposmod(p.x,4096),fposmod(p.y,4096)))
		v.cam.position = Vector3(-3500,700,5000)
		v.cam.look_at(Vector3(5000,400,-11000))
		v.cam.fov = 75
		for tile in v.landscape.tiles.values():
			for child in tile.node.get_children():
				if child is MeshInstance3D: child.set_instance_shader_parameter("stream_reveal",1.0)
			if tile.has("deco"):
				for batch in tile.deco.get_children(): batch.set_instance_shader_parameter("stream_reveal",1.0)
		for k in 5: await process_frame
		await RenderingServer.frame_post_draw
		# GPU MultiMesh transforms read back correctly here (headless does not retain them).
		var anchor_error := 0.0
		for key in v.landscape.tiles:
			var tile: Dictionary = v.landscape.tiles[key]
			if not tile.has("deco"): continue
			var groups := {}
			for prop in v.landscape.prop_records(key):
				if not groups.has(prop.kind): groups[prop.kind] = []
				groups[prop.kind].append(prop)
			for batch in tile.deco.get_children():
				var records: Array = groups[String(batch.name)]
				for i in records.size():
					var actual: Vector3 = batch.multimesh.get_instance_transform(i).origin
					var local: Vector2 = records[i].p-Vector2(key)*v.landscape.TILE
					anchor_error = maxf(anchor_error,actual.distance_to(Vector3(local.x,records[i].height + records[i].lift,-local.y)))
		if anchor_error>0.01:
			failures+=1
			print("FAIL rendered prop anchor ",region[0]," error ",anchor_error)
		root.get_texture().get_image().save_png(out.path_join(region[0]+".png"))
		print("SHOT ",region[0]," tiles ",v.landscape.tiles.size()," terrain slice ",v.landscape.max_slice_ms," prop slice ",v.landscape.prop_slices_max)
		if region[0] in ["rocky","snow","plains"]:
			# Actual on-road viewpoint outside a city's terminal hall.
			var nearest := INF
			var road_id := 0
			var sample_id := 0
			var wanted := p-Vector2(20000,0)
			for r in v.sim.roads.size():
				if v.network_world.shaft.maps.has(r): continue
				var road = v.sim.roads[r]
				for i in range(0,road.N,40):
					var q: Vector2 = v.network_world._wxy(r,i)
					var d := q.distance_squared_to(wanted)
					if d<nearest:
						nearest=d
						road_id=r
						sample_id=i
			var road = v.sim.roads[road_id]
			var q: Vector2 = v.network_world._wxy(road_id,sample_id)-p
			var elevation: float = v.sim.net_height(road_id,float(sample_id))
			var camera_world := p+q
			for k in 3000: v.landscape.sync(camera_world.x,camera_world.y)
			for k in 100: v.network_world.sync(camera_world.x,camera_world.y)
			v.ground_mat.set_shader_parameter("absolute_org",camera_world)
			v.cam.position = Vector3(0,elevation+8,0)
			v.cam.look_at(v.cam.position+Vector3(road.tx[sample_id]*10000,100,-road.ty[sample_id]*10000))
			for k in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(region[0]+"-road.png"))
	v.free()
	quit(int(failures>0))
