## Actual batched traffic meshes, close three-quarter and driver-distance views; no player prefs.
## Godot --path godot --resolution 1600x900 -s res://tests/render_traffic_character.gd -- --out=DIR
extends SceneTree

const Traffic := preload("res://view/network_traffic.gd")
const Kit := preload("res://view/mesh_kit.gd")
var traffic
var camera: Camera3D
var title: Label
var out_dir := ""
var frames := 0
var shot := 0
var pictures: Array[Image] = []
var names := ["commuter", "shuttle", "hotrod", "freight", "racer", "driver_distance"]
var colors := [Color(0.2, 0.48, 0.72), Color(0.82, 0.75, 0.53), Color(0.85, 0.12, 0.43), Color(0.95, 0.53, 0.12), Color(0.36, 0.8, 0.98)]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("traffic_character")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.msaa_3d = Viewport.MSAA_4X
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.055, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.78, 0.95)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var env := WorldEnvironment.new()
	env.environment = environment
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 2.1
	root.add_child(sun)
	var floor := MeshInstance3D.new()
	floor.mesh = Kit.box(Vector3(500, 0.4, 650))
	floor.position = Vector3(0, -0.4, -160)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.075, 0.09, 0.11)
	floor_material.roughness = 0.88
	floor.material_override = floor_material
	root.add_child(floor)
	traffic = Traffic.new()
	root.add_child(traffic)
	traffic._build_meshes()
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 2000.0
	root.add_child(camera)
	camera.current = true
	title = Label.new()
	title.position = Vector2(48, 35)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 0.98))
	root.add_child(title)
	_place.call_deferred()


func _place() -> void:
	for kind in traffic._mm:
		var mm: MultiMesh = traffic._mm[kind].multimesh
		mm.visible_instance_count = 0
		if shot == kind or shot == 5:
			var p := Vector3.ZERO if shot < 5 else Vector3((kind - 2) * 24.0, 0.0, -100.0 - kind * 14.0)
			mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3.ONE * 2.0), p))
			mm.set_instance_color(0, colors[kind])
			mm.visible_instance_count = 1
	traffic._beams.multimesh.visible_instance_count = 0
	if shot < 5:
		camera.position = Vector3(28, 17, -37)
		camera.look_at(Vector3(0, 3, 0))
	else:
		camera.position = Vector3(0, 6, 80)
		camera.look_at(Vector3(0, 3, -130))
	title.text = "PHAETHON  /  " + names[shot].replace("_", " ").to_upper()


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 12:
		return false
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join(names[shot] + ".png"))
	pictures.append(img)
	shot += 1
	if shot == names.size():
		var sheet := Image.create(1600, 1350, false, Image.FORMAT_RGB8)
		for i in pictures.size():
			var tile := pictures[i].duplicate() as Image
			tile.resize(800, 450, Image.INTERPOLATE_LANCZOS)
			tile.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(tile, Rect2i(0, 0, 800, 450), Vector2i((i % 2) * 800, (i / 2) * 450))
		sheet.save_jpg(out_dir.path_join("traffic_character_sheet.jpg"), 0.94)
		print("TRAFFIC CHARACTER RENDER ", out_dir)
		quit()
		return true
	frames = 0
	_place()
	return false
