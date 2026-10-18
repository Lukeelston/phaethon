extends SceneTree
func _initialize() -> void:
	for p in ["res://view/range_world.gd", "res://view/landmark.gd", "res://view/speed_cues.gd", "res://view/traffic.gd",
			"res://view/dust.gd", "res://view/craft_model.gd", "res://view/horizon.gd", "res://view/mesh_kit.gd", "res://view/route_features.gd", "res://view/gp_world.gd", "res://input/quest_controls.gd", "res://vr/dashboard.gd",
			"res://view/craft_view.gd", "res://vr/vr_cockpit.gd"]:
		var s = load(p)
		print(p, " -> ", "OK" if s != null and s.can_instantiate() else "FAILED")
	quit()
