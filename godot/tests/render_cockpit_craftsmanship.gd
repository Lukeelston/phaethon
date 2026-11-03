## Actual-renderer closeups of the service consoles and working mode switch. This fixture
## deliberately adds no render-only details to the production fittings. Use alongside the
## seated/full-pod renders and test_cables, which checks real vertices against hull clearance.
## Run windowed: --path godot --resolution 1400x1000 -s res://tests/render_cockpit_craftsmanship.gd -- --out=DIR
extends SceneTree

const Interior := preload("res://vr/cockpit_interior.gd")
const Switch := preload("res://vr/mode_switch.gd")
var camera: Camera3D
var shot := 0
var frames := 0
var out_dir := ""
var names := ["console_left", "console_right", "knurl_and_fasteners", "mode_switch"]
var eyes := [Vector3(-0.36, 0.91, 1.03), Vector3(0.32, 0.91, 1.03), Vector3(-0.545, 0.49, 0.78), Vector3(0.585, 0.655, 0.315)]
var targets := [Vector3(-0.615, 0.37, 0.46), Vector3(0.615, 0.37, 0.46), Vector3(-0.615, 0.402, 0.725), Vector3(0.585, 0.43, 0.08)]


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("cockpit_craftsmanship")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.msaa_3d = Viewport.MSAA_4X
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.15, 0.23, 0.36)
	sky.sky_horizon_color = Color(0.75, 0.81, 0.85)
	sky.ground_horizon_color = Color(0.55, 0.59, 0.62)
	sky.ground_bottom_color = Color(0.11, 0.13, 0.16)
	env.sky.sky_material = sky
	env.ambient_light_energy = 0.7
	var environment := WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48, -30, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	world.add_child(light)
	var cabin := Interior.new()
	world.add_child(cabin)
	cabin.build()
	var mode := Switch.new()
	world.add_child(mode)
	mode.transform = Switch.mount()
	mode.build()
	camera = Camera3D.new()
	camera.near = 0.015
	camera.fov = 48
	world.add_child(camera)
	camera.make_current()
	_place.call_deferred()


func _place() -> void:
	camera.position = eyes[shot]
	camera.look_at(targets[shot], Vector3.UP)
	camera.fov = 40 if shot == 3 else 48


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 30:
		return false
	var image := root.get_texture().get_image()
	var path := out_dir.path_join(names[shot] + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save cockpit closeup: %s (%s)" % [path, error])
		quit(1)
		return true
	print("COCKPIT CLOSEUP ", path)
	shot += 1
	if shot == names.size():
		quit(0)
		return true
	frames = 0
	_place()
	return false
