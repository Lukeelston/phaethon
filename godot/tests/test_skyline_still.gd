## Run windowed for the picture check (tools/run_suite.ps1 finds this line); headless it checks the source only.
## A city's towers are the same buildings wherever the floating origin is (view/skyline.gdshader: the
## Network's skylines, view/network_world.gd, and the city GPs', view/craft_view.gd).
## (Luke, from the headset, 2026-11-22: "The buildings around cities jitter when i look at them." The shader
## chose each tower's upper tiers, its mast and its kind of facade from the tower's place, MODEL_MATRIX[3]. The
## view's origin floats with the craft, so that place is measured from the craft, and every tower was dealt
## another building with each metre flown.)
##   source     nothing in the shader's vertex stage reads the tower's place (this much needs no renderer)
##   picture    WITH A WINDOW: Eridanus' own towers drawn from 4.8 km, then again with the city and the eye moved
##              together by a metre each way, by 37 m aslant and by a kilometre and more. Nothing has changed
##              but where the origin is, so the picture must not: under 0.2% of the towers' pixels may differ by
##              more than 8 of 255 (as the shader was, 60% and more did). By day and with the windows lit; and
##              the same for plain boxes, as a city GP's towers are.
##   control    the eye alone moved 40 m does change the picture: the comparison can see the towers
## Prints SKYLINE STILL PASS. Without a window it checks the source alone, and says so.
## Run: Godot_v4.7.1-stable_win64.exe --xr-mode off --resolution 1280x720 --path godot -s res://tests/test_skyline_still.gd -- --mute
## (--out=DIR keeps each scene's picture and its last moved one, to look at.)
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const Kit := preload("res://view/mesh_kit.gd")
const SHADER := "res://view/skyline.gdshader"
const MOVES := [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(26.3, -26.4), Vector2(1000.5, -733.25)]
const MAY_CHANGE := 0.002     # of the towers' pixels
const CHANGED := 8            # of 255, in any channel
var fails := 0
var passed := 0
var stage: Node3D
var holder: Node3D
var towers: MultiMeshInstance3D
var eye: Camera3D
# The eye: over Eridanus' own road (the city's middle is 3 km north of its terminal, and no tower stands within
# 450 m of a road), 4.8 km from the middle and looking at it; in the towers' own frame (x east, z south).
const EYE_AT := Vector3(-3750.0, 300.0, 3000.0)
const LOOK_AT := Vector3(0.0, 250.0, 0.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_source()
	if DisplayServer.get_name() == "headless":
		print("  note the pictures need a window (run-tests.ps1 -Windowed): the shader's source was checked alone")
	else:
		await _pictures()
	print("SKYLINE STILL %s" % ("PASS" if fails == 0 else "FAIL (%d failed, %d passed)" % [fails, passed]))
	quit(1 if fails > 0 else 0)


## The vertex stage, comments out: it may measure the tower (MODEL_MATRIX's first three columns) but not place it.
func _source() -> void:
	var text := FileAccess.get_file_as_string(SHADER)
	var from := text.find("void vertex()")
	var to := text.find("void fragment()")
	var stage_text := ""
	if from >= 0 and to > from:
		for line in text.substr(from, to - from).split("\n"):
			stage_text += line.split("//")[0] + "\n"
	var reads := []
	for word in ["MODEL_MATRIX[3]", "NODE_POSITION_WORLD", "CAMERA_POSITION_WORLD", "INV_VIEW_MATRIX", "MODEL_MATRIX *", "MODEL_MATRIX*"]:
		if stage_text.contains(word):
			reads.append(word)
	_check("source: the towers' vertex stage (%d characters) reads nothing of where a tower is from the origin %s" % [stage_text.length(), reads],
		stage_text.length() > 200 and reads.is_empty())


func _pictures() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("skyline_still_")
	var v = ViewScript.new()
	root.add_child(v)
	v.set_process(false)
	# Eridanus' own towers, as the world built them, on a stage of their own: no craft, no road, no origin's
	# follower. (The mesh and the material outlive the view.)
	var built: MultiMeshInstance3D = null
	for sk in v.network_world.skylines:
		if String((sk[0] as Node).name) == "skyline_ERIDANUS":
			built = (sk[0] as Node).get_child(0) as MultiMeshInstance3D
	var city_mesh: MultiMesh = built.multimesh if built != null else null
	var city_look: ShaderMaterial = (built.material_override as ShaderMaterial).duplicate() if built != null else null
	v.free()
	_check("picture: the world built Eridanus' skyline, %d towers" % (city_mesh.instance_count if city_mesh != null else 0),
		city_mesh != null and city_mesh.instance_count > 200)
	if city_mesh == null:
		return
	root.msaa_3d = Viewport.MSAA_4X
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.45, 0.6, 0.85)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	world.environment.ambient_light_energy = 0.6
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 52.0, 0.0)
	stage.add_child(sun)
	holder = Node3D.new()
	stage.add_child(holder)
	towers = MultiMeshInstance3D.new()
	towers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	towers.custom_aabb = AABB(Vector3(-9000, 0, -9000), Vector3(18000, 1300, 18000))
	holder.add_child(towers)
	eye = Camera3D.new()
	eye.fov = 35.0
	eye.far = 120000.0
	stage.add_child(eye)
	eye.make_current()
	# plain boxes in a ring, as a city GP's towers are (craft_view.gd, _gp_skyline)
	var rng := RandomNumberGenerator.new()
	rng.seed = 39
	var ring := MultiMesh.new()
	ring.transform_format = MultiMesh.TRANSFORM_3D
	ring.use_colors = true
	ring.mesh = Kit.box(Vector3.ONE)
	ring.instance_count = 160
	for k in ring.instance_count:
		var tall := rng.randf_range(160.0, 900.0)
		var foot := rng.randf_range(70.0, 190.0)
		ring.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(foot, tall, foot * rng.randf_range(0.6, 1.4))).rotated(Vector3.UP, rng.randf() * PI),
			Vector3(rng.randf_range(-3200.0, 3200.0), tall / 2.0, rng.randf_range(-3000.0, 2600.0))))
		ring.set_instance_color(k, Color(0.5, 0.56, 0.6).lerp(Color(0.75, 0.7, 0.62), rng.randf()))
	for scene in [["Eridanus by day", city_mesh, 0.0], ["Eridanus, its windows lit", city_mesh, 1.0], ["plain boxes, as a city GP's", ring, 0.0]]:
		towers.multimesh = scene[1]
		var look: ShaderMaterial = city_look.duplicate()
		look.set_shader_parameter("night", scene[2])
		towers.material_override = look
		towers.visible = false
		var sky := await _picture(Vector2.ZERO, Vector2.ZERO)
		towers.visible = true
		var base := await _picture(Vector2.ZERO, Vector2.ZERO)
		var mask := _differs(base, sky, 2, PackedByteArray())
		var seen := _count(mask)
		var worst := 0.0
		var told := ""
		for move: Vector2 in MOVES:
			var moved := await _picture(move, move)
			var share := float(_count(_differs(moved, base, CHANGED, mask))) / maxf(seen, 1.0)
			worst = maxf(worst, share)
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--out=") and move == MOVES[-1]:
					var name := String(scene[0]).replace(",", "").replace("'", "").replace(" ", "-")
					DirAccess.make_dir_recursive_absolute(arg.trim_prefix("--out="))
					base.save_png(arg.trim_prefix("--out=").path_join(name + ".png"))
					moved.save_png(arg.trim_prefix("--out=").path_join(name + "-moved.png"))
					sky.save_png(arg.trim_prefix("--out=").path_join(name + "-sky.png"))
			told += "  %.3f%% moved (%.1f, %.1f) m" % [share * 100.0, move.x, move.y]
		var parallax := float(_count(_differs(await _picture(Vector2.ZERO, Vector2(40.0, 0.0)), base, CHANGED, mask))) / maxf(seen, 1.0)
		_check("picture: %s, its towers on %.1f%% of the picture; of their pixels changed with the origin's place:%s (may be %.1f%%)" % [
			scene[0], 100.0 * seen / maxf(mask.size(), 1.0), told, MAY_CHANGE * 100.0], seen > mask.size() / 20 and worst < MAY_CHANGE)
		_check("control: %s, the eye alone 40 m aside changes %.1f%% of them" % [scene[0], parallax * 100.0], parallax > 0.02)
	stage.free()


## The stage drawn with the city moved by `city` (m: x, z) and the eye by `head`: together, it is the origin alone that moved.
func _picture(city: Vector2, head: Vector2) -> Image:
	holder.position = Vector3(city.x, 0.0, city.y)
	var shift := Vector3(head.x, 0.0, head.y)
	eye.look_at_from_position(EYE_AT + shift, LOOK_AT + shift)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


## Every other pixel each way: 1 where a and b differ by more than `by` of 255 in any channel (and `within` says 1, if given).
func _differs(a: Image, b: Image, by: int, within: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var h := a.get_height()
	out.resize((w / 2) * (h / 2))
	var k := 0
	for y in range(0, h - 1, 2):
		var row := y * w * 3
		for x in range(0, w - 1, 2):
			var i := row + x * 3
			var differs := absi(da[i] - db[i]) > by or absi(da[i + 1] - db[i + 1]) > by or absi(da[i + 2] - db[i + 2]) > by
			out[k] = 1 if differs and (within.is_empty() or within[k] == 1) else 0
			k += 1
	return out


func _count(mask: PackedByteArray) -> int:
	var n := 0
	for b in mask:
		n += b
	return n


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
