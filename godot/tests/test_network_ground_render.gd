## The Network's floor, drawn: view/ground_network.gdshader against view/ground.gdshader's own Network answer,
## the same plane under the same light from the same eye, pixel for pixel (push 36: the Network's floor was
## given a shader of its own because the old one worked out a desert for every pixel first; see that shader).
## Run windowed (it reads frames back), as tests/test_network_streaming_render.gd:
## --xr-mode off --resolution 1280x720 --audio-driver Dummy -s res://tests/test_network_ground_render.gd
##   each of five eyes (40 m up a road's height over it, 3 km, 12 km, and 48 km up as from Mount Hyperion's
##   brink looking down and looking out), over two places in the map, with the landscapes' weights set as a
##   flight sets them: no pixel differs by more than 2 of 255 in any channel, and the pictures are not blank
## A shadow-casting sun stands over both (with nothing to cast one): the new shader asks for no shadow, and
## where none falls that changes nothing.
## Prints NETWORK GROUND RENDER PASS.
extends SceneTree

const Land := preload("res://view/network_landscape.gd")
const PERIOD := 4096.0
# the eye's height over the plane (m), its pitch down (degrees)
const EYES := [[40.0, 12.0], [3000.0, 35.0], [12000.0, 50.0], [48000.0, 60.0], [48000.0, 14.0]]
const PLACES := [Vector2(300000.0, 300000.0), Vector2(121337.0, 441012.0)]
var fails := 0


func check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	fails += int(not ok)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		check("a windowed renderer is required for frame readback", false)
		_finish()
		return
	root.msaa_3d = Viewport.MSAA_4X
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 62.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 450.0
	world.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.4, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	env.environment.fog_enabled = true
	env.environment.fog_density = 0.00002
	world.add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(940000.0, 940000.0)
	ground.mesh = plane
	var mat := ShaderMaterial.new()
	ground.material_override = mat
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.far = 470000.0
	cam.fov = 70.0
	world.add_child(cam)
	cam.make_current()
	# as NetworkLandscape.setup_ground gives a floor its regions, and CraftView its place and its landscapes' weights
	var centers := PackedVector3Array()
	var colors := PackedColorArray()
	for region in Land.REGIONS:
		centers.append(Vector3(region[1].x, region[1].y, region[2]))
		colors.append(region[3])
	var old_shader: Shader = load("res://view/ground.gdshader")
	var new_shader: Shader = load("res://view/ground_network.gdshader")
	for at: Vector2 in PLACES:
		for eye in EYES:
			cam.position = Vector3(0.0, float(eye[0]), 0.0)
			cam.rotation_degrees = Vector3(-float(eye[1]), 0.0, 0.0)
			var shots := []
			for shader in [old_shader, new_shader]:
				mat.shader = shader
				mat.set_shader_parameter("network_on", true)
				mat.set_shader_parameter("regions", centers)
				mat.set_shader_parameter("region_colors", colors)
				mat.set_shader_parameter("org", Vector2(fposmod(at.x, PERIOD), fposmod(at.y, PERIOD)))
				mat.set_shader_parameter("pod_y", at.y)
				mat.set_shader_parameter("absolute_org", at)
				mat.set_shader_parameter("verdant", 0.35)
				mat.set_shader_parameter("ice", 0.2)
				mat.set_shader_parameter("basalt", 0.3)
				mat.set_shader_parameter("mesa", 0.25)
				for k in 4:
					await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				image.convert(Image.FORMAT_RGB8)
				shots.append(image)
			var a: PackedByteArray = (shots[0] as Image).get_data()
			var b: PackedByteArray = (shots[1] as Image).get_data()
			var worst := 0
			var total := 0
			var low := 255
			var high := 0
			for k in range(0, mini(a.size(), b.size()), 7):      # (every seventh byte: each channel in turn, a third of a million of them)
				var d := absi(a[k] - b[k])
				worst = maxi(worst, d)
				total += d
				low = mini(low, a[k])
				high = maxi(high, a[k])
			var count := maxi(1, mini(a.size(), b.size()) / 7)
			check("%.0f m up, %.0f degrees down, over (%.0f, %.0f) km: the two differ by %d of 255 at most (%.3f on average), over a picture from %d to %d" % [
				eye[0], eye[1], at.x / 1000.0, at.y / 1000.0, worst, float(total) / count, low, high],
				a.size() == b.size() and a.size() > 100000 and worst <= 2 and high - low > 12)
	world.free()
	_finish()


func _finish() -> void:
	print("NETWORK GROUND RENDER %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(int(fails > 0))
