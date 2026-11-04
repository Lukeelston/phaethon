## Actual Vulkan regional inspection, including roads and high-speed sightlines.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
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
	var out := ProjectSettings.globalize_path("res://../evidence/v024-environment")
	DirAccess.make_dir_recursive_absolute(out)
	for region in v.landscape.REGIONS:
		var p: Vector2 = region[1]
		v.org_x = p.x
		v.org_y = p.y
		for k in 1400:
			v.landscape.sync(p.x,p.y)
		for k in 80:
			v.network_world.sync(p.x,p.y)
		v.ground_mat.set_shader_parameter("absolute_org",p)
		v.ground_mat.set_shader_parameter("org",Vector2(fposmod(p.x,4096),fposmod(p.y,4096)))
		v.cam.position = Vector3(-3500,700,5000)
		v.cam.look_at(Vector3(5000,400,-11000))
		v.cam.fov = 75
		for k in 5: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(region[0]+".png"))
		print("SHOT ",region[0]," tiles ",v.landscape.tiles.size()," terrain slice ",v.landscape.max_slice_ms," prop slice ",v.landscape.prop_slices_max)
		if region[0] in ["rocky","snow","plains"]:
			v.cam.position = Vector3(0,8,0)
			v.cam.look_at(Vector3(18000,130,-3000))
			for k in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join(region[0]+"-road.png"))
	v.free()
	quit()
