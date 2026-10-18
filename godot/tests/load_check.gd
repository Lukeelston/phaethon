extends SceneTree
func _initialize() -> void:
	for p in ["res://view/range_world.gd", "res://view/landmark.gd", "res://view/craft_view.gd", "res://vr/vr_cockpit.gd"]:
		var s = load(p)
		print(p, " -> ", "OK" if s != null and s.can_instantiate() else "FAILED")
	quit()
