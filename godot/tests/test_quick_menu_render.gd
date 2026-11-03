## Rendered gate: the cockpit quick menu needs a visible dark backing.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const VR := preload("res://vr/vr_cockpit.gd")

class Cockpit extends VR:
	func _load_prefs() -> Dictionary:
		return {"scheme": "triggers", "handling": "speed"}
	func _save_prefs() -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_quick_menu_render_")
	var v := Cockpit.new()
	root.add_child(v)
	for f in 12:
		await process_frame
	v.menu_open(true)
	# World destination markers use priority 100 and disable depth testing.
	# A bright patch models that layer crossing the flight-hold panel.
	var marker := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	marker.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 1, 1, 0.99)
	material.no_depth_test = true
	material.render_priority = 100
	marker.material_override = material
	v.menu_panel.add_child(marker)
	marker.position = Vector3(0.35, 0.14, 0.02)
	for f in 60:
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://../evidence/v017-quick-menu-render.png")
	var failures := int(screenshot.save_png(path) != OK)
	var marker_screen := v.cam.unproject_position(marker.global_position)
	var marker_luma := screenshot.get_pixelv(Vector2i(marker_screen)).get_luminance()
	var covered := marker_luma < 0.3
	failures += int(not covered)
	print("%s menu covers priority-100 world marker (luminance %.3f)" % ["PASS" if covered else "FAIL", marker_luma])
	for point in [Vector3(0.44, 0.25, 0), Vector3(0.44, 0.1, 0), Vector3(0.44, -0.12, 0)]:
		var screen := v.cam.unproject_position(v.menu_panel.to_global(point))
		var color := screenshot.get_pixelv(Vector2i(screen))
		var good := color.get_luminance() < 0.25
		failures += int(not good)
		print("%s backing at %s luminance %.3f" % ["PASS" if good else "FAIL", screen, color.get_luminance()])
	marker.queue_free()
	for f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	v.menu_open(false)
	v.queue_free()
	await process_frame
	print("QUICK MENU RENDER %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
