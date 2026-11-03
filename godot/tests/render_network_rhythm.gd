## Inspect the real receiving pavement and new bend/straight transitions.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var v
var frame := 0
var shot := 0
var output := ""
var names := ["receiving_deck", "acceleration_straight", "next_bend"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty():
		output = OS.get_user_data_dir().path_join("network_rhythm")
	DirAccess.make_dir_recursive_absolute(output)
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("render_rhythm_%d_" % Time.get_ticks_usec())
	v = View.new()
	root.add_child(v)
	root.msaa_3d = Viewport.MSAA_4X

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		v.set_process(false)
		v.menu.open = true
		for child in v.get_children():
			if child is CanvasLayer:
				child.hide()
		var road: int = v.sim.jumps[0][1]
		var r = v.sim.roads[road]
		var sample: int = [80, 640, 820][shot]
		v.sim.respawn_on(road, sample, 1)
		v.craft.visible = false
		var x: float = r.px[sample]
		var y: float = r.py[sample]
		var h: float = v.sim.net_height(road, sample)
		v.eye = Vector3(x - r.tx[sample] * 300.0 + r.nx[sample] * 220.0,
			y - r.ty[sample] * 300.0 + r.ny[sample] * 220.0, h + 180.0)
		v.look = Vector3(x + r.tx[sample] * 1000.0, y + r.ty[sample] * 1000.0, h)
		v._follow_origin()
	if frame < 90:
		v._sync_world()
		v._place_camera(1.0)
		return false
	var path := output.path_join(names[shot] + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Cannot save " + path)
		quit(1)
		return true
	print("SHOT ", path)
	shot += 1
	if shot == names.size():
		quit(0)
		return true
	frame = 2
	return false
