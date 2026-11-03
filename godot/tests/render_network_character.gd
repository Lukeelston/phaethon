## Actual Network world, regional landmark and road-distance screenshots.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
var frame := 0
var shot := 0
var output := ""
var names := ["verdant", "desert", "ice", "basalt", "mesa"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty():
		output = OS.get_user_data_dir().path_join("network_character")
	DirAccess.make_dir_recursive_absolute(output)
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("render_character_%d_" % Time.get_ticks_usec())
	v = View.new()
	root.add_child(v)
	root.msaa_3d = Viewport.MSAA_4X

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		# _ready creates the HUD and enables _process after root.add_child returns.
		# Freeze here, before moving the camera rig, so the parked fixture never
		# integrates a teleported pod against its old engine positions.
		v.set_process(false)
		v.menu.open = true
		for child in v.get_children():
			if child is CanvasLayer:
				child.hide()
		var landmark: Dictionary = v.network_world.scenery.landmarks[shot * 3]
		var x: float = landmark.x
		var y: float = landmark.y
		v.sim.pod.x = x - 3000.0
		v.sim.pod.y = y - 3200.0
		v.sim.pod.off_road = true
		v.sim.pod.z = 600.0
		for body in v.sim.bodies:
			body.vx = 0.0
			body.vy = 0.0
		v.craft.visible = false
		v.eye = Vector3(v.sim.pod.x, v.sim.pod.y, 600.0)
		v.look = Vector3(x, y, 600.0)
		v._follow_origin()
	if frame < 75:
		v._sync_world()
		v._place_camera(1.0)
		return false
	var path := output.path_join(names[shot] + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Cannot save " + path)
		quit(1)
		return true
	print("SHOT ", path, " biome=", v.biome, " time=", v.sim.time)
	shot += 1
	if shot == names.size():
		quit(0)
		return true
	frame = 2
	return false
