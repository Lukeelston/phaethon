## Reproducible actual craft/cockpit review views; no physics integration during capture.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const VR := preload("res://vr/vr_cockpit.gd")
var v
var cockpit
var cam: Camera3D
var frame := 0
var shot := 0
var output := ""
var names := ["exterior", "cockpit", "console", "binder", "wind6000", "pod_profile", "nacelle_profile"]

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty():
		output = OS.get_user_data_dir().path_join("vehicle_detail")
	DirAccess.make_dir_recursive_absolute(output)
	View.track_override = "range"
	View.job_override = "none"
	v = View.new()
	root.add_child(v)
	root.msaa_3d = Viewport.MSAA_4X

func _process(_delta: float) -> bool:
	frame += 1
	if frame < 3:
		return false
	if frame == 3:
		v.set_process(false)
		for child in v.get_children():
			if child is CanvasLayer:
				child.hide()
		cockpit = VR.new()
		cockpit.sim = v.sim
		cockpit.rig = Node3D.new()
		root.add_child(cockpit.rig)
		cockpit._build_cockpit()
		cockpit.rig.transform = v.craft.pod.transform
		cockpit.rig.position -= cockpit.rig.basis.y * v.craft.POD_FRAME_UP
		cam = Camera3D.new()
		root.add_child(cam)
		cam.current = true
		_place()
	if frame < 18:
		if shot == 3:
			v.craft.sync_cables(v.sim, 1.0 / 60.0)
		return false
	var path := output.path_join(names[shot] + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		quit(1)
		return true
	print("VEHICLE SHOT ", path)
	shot += 1
	if shot == names.size():
		cockpit.free()
		quit(0)
		return true
	frame = 4
	_place()
	return false

func _place() -> void:
	var craft = v.craft
	craft.pod.visible = shot in [0, 5, 6]
	cockpit.rig.visible = shot in [1, 2, 4]
	v.dust.visible = shot == 4
	v.cues.visible = shot == 4
	cam.fov = 65.0
	var xf: Transform3D = cockpit.rig.transform
	match shot:
		0:
			cam.position = xf * Vector3(14, 10, 12)
			cam.look_at(xf * Vector3(0, 0, -7))
		1, 4:
			cam.position = xf * VR.SEAT
			cam.look_at(xf * (VR.SEAT + Vector3(0, -0.1, -8)), xf.basis.y)
		2:
			cam.position = xf * Vector3(-0.12, 1.0, 0.85)
			cam.look_at(xf * Vector3(-0.59, 0.32, 0.25), xf.basis.y)
			cam.fov = 58.0
		3:
			var mid: Vector3 = (craft.engines[0].position + craft.engines[1].position) / 2.0
			cam.position = mid + xf.basis * Vector3(0, 1.7, -7)
			cam.look_at(mid + xf.basis * Vector3(0, 0, -2.9), xf.basis.y)
			cam.fov = 50.0
		5:
			cam.position = xf * Vector3(4, 2, 4)
			cam.look_at(xf * Vector3(0, 0.4, 0), xf.basis.y)
			cam.fov = 55.0
		6:
			var mid: Vector3 = craft.engines[1].position
			cam.position = mid + xf.basis * Vector3(5, 3, 6)
			cam.look_at(mid, xf.basis.y)
			cam.fov = 55.0
	if shot == 4:
		for body in v.sim.bodies:
			body.vx = cos(body.th) * 6000.0 * 0.44704
			body.vy = sin(body.th) * 6000.0 * 0.44704
		v.dust.sync(v.sim, 1.0 / 60.0)
		v.cues.sync(v.sim, 1.0 / 60.0)
		preload("res://view/canopy.gd").update(cockpit.canopy, 6000.0 * 0.44704, 0.0, "normal", 1.0 / 60.0)
