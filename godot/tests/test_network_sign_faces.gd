## Real sign meshes: readable text outside both faces, with direction-safe rear information.
## Non-headless runs also save front/rear evidence for every board kind.
extends SceneTree

const World := preload("res://view/network_world.gd")
const Sim := preload("res://sim/craft_sim.gd")
var failures := 0
var checked := 0
var examples := {}
var world
var sim
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checked += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _run() -> void:
	sim = Sim.new({"track": "network"})
	world = World.new()
	root.add_child(world)
	world.build(sim, null)
	# Render the same real builders used by streaming, not a replacement sign fixture.
	for key in world._signs:
		for spec in world._signs[key]:
			if spec[2] == "terminal" and int(spec[1]) < 0:
				continue # the opposite planned terminal occupies the exact same gantry
			var node := Node3D.new()
			root.add_child(node)
			var r := int(key.x)
			var R = sim.roads[r]
			var i := int(spec[0])
			world._sign(node, R, r, R.px[i], R.py[i], spec)
			var travel := Vector3(R.tx[i], 0.0, -R.ty[i]) * float(spec[1])
			_check_board(node, spec, travel)
			if not examples.has(spec[2]):
				examples[spec[2]] = [node, travel]
				node.hide()
			else:
				node.free()
	_check("all eight planned sign kinds exercised", examples.size() == 8)
	# Terminal specs are paired in the planner. Their renderer must not stack coincident faces.
	var terminal_count := 0
	for key in world._signs:
		var node := Node3D.new()
		root.add_child(node)
		for spec in world._signs[key]:
			if spec[2] != "terminal":
				continue
			var R = sim.roads[int(key.x)]
			var i := int(spec[0])
			world._sign(node, R, int(key.x), R.px[i], R.py[i], spec)
		var faces := node.get_children().filter(func(c): return c is MeshInstance3D and c.mesh is QuadMesh)
		if not faces.is_empty():
			terminal_count += 1
			_check("terminal pair has only two outward faces", faces.size() == 2)
		node.free()
	_check("five terminal gantries checked", terminal_count == 5)
	if DisplayServer.get_name() != "headless":
		await _render_examples()
	print("NETWORK SIGN FACES %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checked, failures])
	quit(0 if failures == 0 else 1)

func _check_board(node: Node3D, spec: Array, travel: Vector3) -> void:
	var tag := "%s %s dir %d" % [spec[2], spec[3][0], spec[1]]
	var faces := node.get_children().filter(func(c): return c is MeshInstance3D and c.mesh is QuadMesh)
	var labels := node.get_children().filter(func(c): return c is Label3D)
	_check(tag + " has two separate faces", faces.size() == 2)
	for side in [-1.0, 1.0]:
		var outward: Vector3 = travel * side
		var face = null
		for candidate in faces:
			if candidate.basis.z.dot(outward) > 0.99:
				face = candidate
		_check(tag + " outward face %d" % int(side), face != null)
		if face == null:
			continue
		var words := []
		for label in labels:
			if label.basis.z.dot(outward) < 0.99:
				continue
			words.append(label.text)
			_check(tag + " text is upright and not reflected", label.basis.y.dot(Vector3.UP) > 0.99 and label.basis.determinant() > 0.99 and not label.double_sided)
			_check(tag + " text outside lit face", (label.position - face.position).dot(outward) > 0.1)
			# Test actual solid triangles between an observer and the label. This catches a back
			# label accidentally put inside the slab even if its orientation and text are correct.
			var blocked := false
			for child in node.get_children():
				if not child is MeshInstance3D or child.mesh is QuadMesh:
					continue
				var points: PackedVector3Array = child.mesh.get_faces()
				for k in range(0, points.size(), 3):
					if Geometry3D.segment_intersects_triangle(label.position + outward * 20.0, label.position, child.transform * points[k], child.transform * points[k + 1], child.transform * points[k + 2]) != null:
						blocked = true
			_check(tag + " text unobstructed by actual gantry mesh", not blocked)
			var font: Font = label.font if label.font else ThemeDB.fallback_font
			var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
			_check(tag + " words fit within board", width < face.mesh.size.x * 0.98)
			if side < 0 and spec[2] in ["jump", "fork"]:
				var local: Vector3 = face.basis.inverse() * (label.position - face.position)
				var panel_start: float = face.mesh.size.x * (0.5 - World.ARROW_PANEL)
				_check(tag + " words stay left of animated arrow", local.x + width / 2.0 <= panel_start - 3.9 and local.x - width / 2.0 >= -face.mesh.size.x / 2.0 + 3.9)
		if spec[2] in ["jump", "fork"]:
			var material: ShaderMaterial = face.material_override
			_check(tag + " steady words on both faces", is_zero_approx(float(material.get_shader_parameter("flash_hz"))))
			var arrow_shader := material.shader.resource_path.ends_with("arrow_board.gdshader")
			_check(tag + " arrow only on valid approach", arrow_shader == (side < 0))
			if arrow_shader:
				var angle: float = material.get_shader_parameter("angle")
				_check(tag + " arrow points toward correct branch", is_equal_approx(angle, deg_to_rad(52.0) if spec[2] == "jump" else PI / 2.0))
		if side < 0:
			_check(tag + " retains front instructions", words == spec[3])
		elif spec[2] in ["jump", "fork"]:
			_check(tag + " rear preserves ascent and minimum only", words.size() == 3 and words[0] == spec[3][0] and words[1] == spec[3][1] and words[2] == "APPROACH OTHER SIDE")
		elif spec[2] == "terminal":
			_check(tag + " rear preserves terminal name", words == spec[3])
		else:
			var identifier: String = spec[3][1] if spec[2] == "brake" else spec[3][0]
			_check(tag + " rear replaces directional instructions", words == [identifier, "OPPOSITE APPROACH"])

func _render_examples() -> void:
	world.hide()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.16, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	camera = Camera3D.new()
	camera.far = 5000.0
	camera.fov = 55.0
	root.add_child(camera)
	root.msaa_3d = Viewport.MSAA_4X
	for kind in ["jump", "fork", "corner", "exit", "city", "end", "brake", "terminal"]:
		var node: Node3D = examples[kind][0]
		var travel: Vector3 = examples[kind][1]
		node.show()
		var face: MeshInstance3D
		for child in node.get_children():
			if child is MeshInstance3D and child.mesh is QuadMesh:
				face = child
		var centre := face.position
		for side in [-1.0, 1.0]:
			camera.position = centre + travel * side * face.mesh.size.x * 0.95
			camera.look_at(centre)
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var filename := "network-sign-%s-%s.png" % [kind, "front" if side < 0 else "rear"]
			var path := "res://../evidence/" + filename
			_check("saved " + filename, root.get_texture().get_image().save_png(path) == OK)
			print("SIGN RENDER ", path)
			if side < 0 and kind in ["jump", "fork"]:
				# Sample the arrow's interior in two real rendered frames, clear of border lamps.
				var front: MeshInstance3D
				for candidate in node.get_children():
					if candidate is MeshInstance3D and candidate.mesh is QuadMesh and candidate.basis.z.dot(-travel) > 0.99:
						front = candidate
				var size: Vector2 = front.mesh.size
				var a := camera.unproject_position(front.to_global(Vector3(size.x * (0.5 - World.ARROW_PANEL * 0.9), size.y * 0.35, 0.0)))
				var b := camera.unproject_position(front.to_global(Vector3(size.x * (0.5 - World.ARROW_PANEL * 0.1), -size.y * 0.35, 0.0)))
				var before: Image = root.get_texture().get_image()
				await create_timer(0.23).timeout
				await RenderingServer.frame_post_draw
				var after: Image = root.get_texture().get_image()
				var changed := 0
				for y in range(maxi(0, floori(minf(a.y, b.y))), mini(before.get_height(), ceili(maxf(a.y, b.y))), 3):
					for x in range(maxi(0, floori(minf(a.x, b.x))), mini(before.get_width(), ceili(maxf(a.x, b.x))), 3):
						var ca := before.get_pixel(x, y)
						var cb := after.get_pixel(x, y)
						if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.05:
							changed += 1
				_check(kind + " arrow animates in rendered frames (%d changed samples)" % changed, changed > 20)
				_check("saved animated " + kind, after.save_png("res://../evidence/network-sign-%s-animated.png" % kind) == OK)
		node.hide()
