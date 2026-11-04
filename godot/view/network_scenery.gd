## Recognizable regional silhouettes. Fifteen static compounds, two surfaces each;
## no lights, collision proxies or per-frame animation. Road clearance is conservative
## in world coordinates, including the shafts' carried (rather than simulated) plan.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const CELL := 1000.0
const RADIUS := 1100.0
const VIS := 140000.0
var landmarks: Array = [] # {node, x, y, biome, radius}
var occupied := {}
var _body: ShaderMaterial
var _glow: ShaderMaterial

func build(sim, world) -> void:
	_body = ShaderMaterial.new()
	_body.shader = preload("res://view/network_scenery.gdshader")
	_glow = _body.duplicate()
	_glow.set_shader_parameter("glow", 1.5)
	# Samples at <= 768 m intervals, padding cells covers the spaces between them.
	for r in sim.roads.size():
		var road = sim.roads[r]
		for i in range(0, road.N, 32):
			occupied[_cell(world._wxy(r, i))] = true
		occupied[_cell(world._wxy(r, road.N - 1))] = true
	for ci in sim.cities.size():
		var city: Dictionary = sim.cities[ci]
		var palette: Array = world.PALETTE[city.biome]
		for k in 3:
			var p := _anchor(Vector2(city.cx, city.cy), ci, k)
			if p == Vector2.INF:
				continue
			var mesh := _landmark(city.biome, k, palette)
			var instance := MeshInstance3D.new()
			instance.name = "%s_landmark_%d" % [city.biome, k]
			instance.mesh = mesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end = VIS
			add_child(instance)
			landmarks.append({"node": instance, "x": p.x, "y": p.y,
				"biome": city.biome, "radius": RADIUS})

func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

func clear_at(p: Vector2) -> bool:
	var c := _cell(p)
	# Two cells beyond the center: >= 2 km from sampled road points. This
	# covers the 1.1 km art radius, road half-width and the between-sample gap.
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			if occupied.has(c + Vector2i(dx, dy)):
				return false
	return true

func _anchor(center: Vector2, city: int, variant: int) -> Vector2:
	for attempt in 24:
		var angle := TAU * (float(variant) / 3.0 + float(attempt) / 24.0) + city * 0.41
		var distance := 11000.0 + variant * 7000.0 + (attempt / 8) * 3000.0
		var p := center + Vector2(cos(angle), sin(angle)) * distance
		if clear_at(p):
			return p
	return Vector2.INF

func _box(parts: Array, size: Vector3, position: Vector3, color: Color, yaw := 0.0) -> void:
	parts.append([Kit.box(size), Kit.at(position, Vector3(0, yaw, 0)), color])

func _cyl(parts: Array, top: float, bottom: float, height: float, position: Vector3, color: Color, sides := 12) -> void:
	parts.append([Kit.cyl(top, bottom, height, sides), Kit.at(position), color])

func _landmark(biome: String, variant: int, pal: Array) -> ArrayMesh:
	var body := []
	var lights := []
	var stone: Color = pal[0]
	var dark: Color = pal[1]
	var light: Color = pal[2]
	var scale_y := 0.85 + 0.15 * variant
	match biome:
		"verdant": # inhabited garden terraces, a split crown and suspended gardens
			for level in 6:
				var width := 1050.0 - level * 130.0
				var y := level * 160.0
				_box(body, Vector3(width, 150, width * 0.65), Vector3(0, y + 75, 0), stone, level * 0.045)
				_box(body, Vector3(width + 40, 18, width * 0.65 + 40), Vector3(0, y + 155, 0), Color(0.20, 0.39, 0.25), level * 0.045)
				_box(lights, Vector3(width * 0.8, 7, 9), Vector3(0, y + 127, width * 0.325 + 1), light)
			for side in [-1.0, 1.0]:
				_box(body, Vector3(100, 500, 110), Vector3(side * 140, 1130, 0), dark)
				_box(lights, Vector3(12, 370, 14), Vector3(side * 140, 1180, -58), light)
		"desert": # wind-cut stepped spire and three shaded satellite towers
			for level in 7:
				var radius := 380.0 - level * 43.0
				_cyl(body, radius * 0.70, radius, 180, Vector3(0, level * 180 + 90, 0), stone, 6)
				_cyl(lights, radius * 0.72, radius * 0.72, 8, Vector3(0, level * 180 + 175, 0), light, 6)
			for k in 3:
				var a := k * TAU / 3.0
				var p := Vector3(cos(a) * 620, 0, sin(a) * 620)
				_cyl(body, 85, 150, 440, p + Vector3.UP * 220, dark, 8)
				_cyl(body, 210, 210, 24, p + Vector3.UP * 420, stone, 8)
		"ice": # angular observatory towers; crossbars remain well off all roads
			for k in 3:
				var x := (k - 1) * 340.0
				var height := 1250.0 if k == 1 else 850.0
				_cyl(body, 15, 170, height, Vector3(x, height / 2.0, 0), stone, 5)
				_box(body, Vector3(75, height * 0.6, 65), Vector3(x, height * 0.48, -110), dark)
				_box(lights, Vector3(12, height * 0.62, 14), Vector3(x, height * 0.49, -145), light)
			_box(body, Vector3(820, 45, 110), Vector3(0, 460, 0), dark)
			_box(lights, Vector3(800, 8, 8), Vector3(0, 480, -59), light)
		"basalt": # heavy foundry stacks with buttresses, cooling rings and ember seams
			_box(body, Vector3(1350, 180, 650), Vector3(0, 90, 0), dark)
			for k in 3:
				var x := (k - 1) * 420.0
				var height := 900.0 + (k % 2) * 350.0
				_cyl(body, 130, 180, height, Vector3(x, height / 2.0 + 160, 0), stone, 10)
				for ring in 5:
					_cyl(body, 195, 195, 28, Vector3(x, 220 + ring * height / 5.0, 0), dark, 10)
				_cyl(lights, 135, 135, 20, Vector3(x, height + 165, 0), light, 10)
				_box(lights, Vector3(14, height * 0.7, 12), Vector3(x, height * 0.53, -170), light)
		_: # mesa communications citadel: strata, twin towers and a broad antenna
			for level in 4:
				_box(body, Vector3(1350 - level * 180, 140, 650 - level * 80), Vector3(0, level * 140 + 70, 0), stone if level % 2 == 0 else dark)
			for side in [-1.0, 1.0]:
				_box(body, Vector3(120, 650, 150), Vector3(side * 285, 800, 0), dark)
				_box(lights, Vector3(18, 500, 12), Vector3(side * 285, 840, -80), light)
			_box(body, Vector3(960, 65, 180), Vector3(0, 1140, 0), stone)
			for k in 7:
				_box(body, Vector3(18, 220 + 80 * (k % 2), 20), Vector3((k - 3) * 110, 1260, 0), dark)
			_box(lights, Vector3(900, 9, 12), Vector3(0, 1169, -93), light)
	for part in body + lights:
		part[1] = Transform3D(Basis.from_scale(Vector3(1, scale_y, 1)), Vector3.ZERO) * part[1]
	var mesh := Kit.compound(body)
	Kit.compound(lights, mesh)
	mesh.surface_set_material(0, _body)
	mesh.surface_set_material(1, _glow)
	return mesh

func sync(ox: float, oy: float, ground_height := 0.0) -> void:
	for landmark in landmarks:
		landmark.node.position = Vector3(landmark.x - ox, ground_height, -(landmark.y - oy))
