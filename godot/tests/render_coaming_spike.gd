## Realism spike: close views of the cockpit coaming under the game's daylight tone mapping.
## Run windowed: --path godot --xr-mode off --resolution 1600x900 -s res://tests/render_coaming_spike.gd
## -- --out=DIR [--classic]   (--classic renders v0.3.2's original coaming for comparison)
extends SceneTree

const Interior := preload("res://vr/cockpit_interior.gd")
const SHOTS := [
	["01-nameplate", Vector3(0.0, 0.95, 0.35), Vector3(0.0, 0.60, -1.0), 34.0],
	["02-starboard", Vector3(0.22, 0.93, 0.45), Vector3(0.72, 0.53, 0.05), 44.0],
	["03-stitching", Vector3(0.30, 0.80, -0.42), Vector3(0.50, 0.60, -0.66), 26.0],
	["04-panel-gap", Vector3(0.20, 0.76, -0.60), Vector3(0.375, 0.585, -0.83), 24.0],
	["05-grip", Vector3(0.24, 0.66, 0.50), Vector3(0.46, 0.455, 0.2), 24.0],
	["06-footwell", Vector3(0.0, 0.95, 0.55), Vector3(0.0, 0.14, -0.15), 52.0],
	["07-console", Vector3(0.36, 0.62, 0.86), Vector3(0.615, 0.385, 0.52), 30.0],
	["08-switches", Vector3(0.47, 0.50, 0.62), Vector3(0.615, 0.392, 0.42), 26.0],
	["09-nose-cage", Vector3(0.0, 0.92, 0.55), Vector3(0.0, 0.35, -1.3), 50.0],
]
var camera: Camera3D
var out_dir := ""
var shot := 0
var frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Interior.hd_parts = "--classic" not in OS.get_cmdline_user_args()
	preload("res://view/craft_materials.gd").hd = Interior.hd_parts
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
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES   # as craft_view.gd's daylight
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	var holder := WorldEnvironment.new()
	holder.environment = env
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var cabin := Interior.new()
	world.add_child(cabin)
	cabin.build()
	# The starboard lever as vr_cockpit.gd mounts it: shaft, then the grip 0.36 m up the pivot.
	var shaft := MeshInstance3D.new()
	shaft.mesh = preload("res://view/mesh_kit.gd").cyl(0.016, 0.016, 0.32, 12)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.75, 0.77, 0.8)
	steel.metallic = 0.9
	steel.roughness = 0.25
	shaft.material_override = steel
	shaft.position = Vector3(0.46, 0.26, 0.2)
	world.add_child(shaft)
	var grip := MeshInstance3D.new()
	grip.mesh = Interior.deck_mesh("Grip")
	grip.position = Vector3(0.46, 0.46, 0.2)
	world.add_child(grip)
	camera = Camera3D.new()
	camera.near = 0.01
	world.add_child(camera)
	camera.make_current()
	_place.call_deferred()


func _place() -> void:
	camera.position = SHOTS[shot][1]
	camera.look_at(SHOTS[shot][2], Vector3.UP)
	camera.fov = SHOTS[shot][3]


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 40:
		return false
	var path := out_dir.path_join(str(SHOTS[shot][0]) + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)
		return true
	print("COAMING SHOT ", path)
	shot += 1
	if shot == SHOTS.size():
		quit(0)
		return true
	frames = 0
	_place()
	return false
