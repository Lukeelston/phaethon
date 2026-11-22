## The Aurora Line is a single pressure vessel. Its clear span has no asphalt
## ribbon through it. Repeated sections share meshes; only the two pressure
## locks need their own glass shape. Hardware is culled in kilometre blocks.
## Each lock has a takeoff and landing area (view/aurora_stations.gd): a pad to stop on outside its
## seal, the distances and lights that bring a craft to it from inside, and the lock's own cycle.
extends Node3D

const PressureSkin := preload("res://sim/pressure_surface.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Stations := preload("res://view/aurora_stations.gd")
const SIDES := 96
const BAYS := 16
const SPACING := 3072.0
const STEEL := Color(0.34, 0.45, 0.49)
const TITANIUM := Color(0.68, 0.78, 0.78)
const GASKET := Color(0.075, 0.14, 0.17)
const COPPER := Color(0.91, 0.48, 0.22)
var span := 0.0
var blocks := 0
var _sx := 0.0
var _sy := 0.0
var _height := 0.0
var _tx := 0.0
var _ty := 0.0
var _length := 0.0
var _anchor := -1000
var _glass_shapes: Array[Mesh] = []
var _frame_shapes: Array[Mesh] = []
var _horizon_slots: Array = []
var _detail_slots: Array[MeshInstance3D] = []
var _stations := Node3D.new()
var seal_fields: Array[ShaderMaterial] = []   # each lock's field across its bore, southwest then northeast (the stations work them)
var stations                                  # view/aurora_stations.gd
var glazing := ShaderMaterial.new()
var metal := StandardMaterial3D.new()

func build(sim) -> void:
	name = "AuroraPressureLine"
	var route: Array = sim.NET_PRESSURE
	var road = sim.roads[route[0]]
	var i: int = route[1]
	_sx = road.px[i]
	_sy = road.py[i]
	_tx = road.tx[i]
	_ty = road.ty[i]
	_height = sim.net_height(route[0], i)
	basis = Basis(Vector3(road.nx[i], 0, -road.ny[i]), Vector3.UP, Vector3(road.tx[i], 0, -road.ty[i]))
	span = (route[2] - i) * road.len[i]
	blocks = ceili(span / SPACING)
	var length := span / blocks
	_length = length
	glazing.shader = preload("res://view/aurora_glass.gdshader")
	metal.vertex_color_use_as_albedo = true
	metal.vertex_color_is_srgb = true
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED
	metal.metallic = 0.43
	metal.roughness = 0.38
	for lock in [0, 1, -1]:
		_glass_shapes.append(_glass(length, lock))
		_frame_shapes.append(_frames(length, lock))
	var distant := _distant_frame(length)
	# A map-length object would dirty hundreds of out-of-sight transforms on
	# every floating-origin move. Recycle only the blocks within draw range.
	for k in 2 * (ceili(88000.0 / length) + 1) + 1:
		_horizon_slots.append([_instance(_glass_shapes[0], 0, 0, 88000, "Glass"),
			_instance(distant, 0, 17000, 88000, "DistantCollars")])
	for k in 2 * (ceili(17000.0 / length) + 1) + 1:
		_detail_slots.append(_instance(_frame_shapes[0], 0, 0, 17000, "Collars"))
	add_child(_stations)
	for end in [0.0, span]:
		_airlock(end, 1.0 if end == 0.0 else -1.0)
	var compressor := _compressor()
	var names := ["SOUTHWEST LOCK", "BASALT", "WEST RELAY", "ERIDANUS", "EAST RELAY", "GLACIER", "NORTHEAST LOCK"]
	for station in names.size():
		var at := span * station / (names.size() - 1)
		_instance(compressor, at, 0, 65000, "Compressor")
		_station_plate(at, names[station], station)
	stations = Stations.new()
	add_child(stations)
	stations.build(sim, self)

func sync(ox: float, oy: float) -> void:
	var along := (ox - _sx) * _tx + (oy - _sy) * _ty
	var across := (oy - _sy) * _tx - (ox - _sx) * _ty
	visible = absf(across) < 91000 and along > -91000 and along < span + 91000
	if not visible:
		return
	var center := clampi(floori(along / _length), 0, blocks - 1)
	var z := _length * center
	position = Vector3((_sx + _tx * z) - ox, _height, oy - (_sy + _ty * z))
	if center == _anchor:
		return
	_anchor = center
	_stations.position.z = -z
	stations.place(z)
	for k in _horizon_slots.size():
		var block := center + k - _horizon_slots.size() / 2
		var active := block >= 0 and block < blocks
		var pane: MeshInstance3D = _horizon_slots[k][0]
		for piece in _horizon_slots[k]:
			piece.visible = active
			piece.position.z = (block - center) * _length
		if active:
			pane.mesh = _glass_shapes[_shape_index(block)]
			pane.set_instance_shader_parameter("sector", float(block) / blocks)
	for k in _detail_slots.size():
		var block := center + k - _detail_slots.size() / 2
		var piece := _detail_slots[k]
		piece.visible = block >= 0 and block < blocks
		if piece.visible:
			piece.position.z = (block - center) * _length
			piece.mesh = _frame_shapes[_shape_index(block)]

func _shape_index(block: int) -> int:
	if block == 0:
		return 1
	return 2 if block == blocks - 1 else 0

func _instance(mesh: Mesh, z: float, near: float, far_distance: float, label: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.position.z = z
	mi.visibility_range_begin = near
	mi.visibility_range_end = far_distance
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if label in ["PressureLock", "PressureField", "Compressor"]:
		_stations.add_child(mi)
	else:
		add_child(mi)
	return mi

func _fold(z: float, length: float, lock: int) -> float:
	if lock == 0:
		return 1.0
	return smoothstep(0.0, PressureSkin.APRON, z if lock > 0 else length - z)

# Loft a row around the pressure hull. A positive offset is always outside
# the vehicle's contact surface. UV runs continuously across the polar seam.
func _row(st: SurfaceTool, z: float, fold: float, offset: float, color: Color, sides: int, uv_y: float, scallop := 0.0) -> void:
	for j in sides + 1:
		var u := float(j) / sides
		var a := u * TAU
		var p := PressureSkin.section(a, fold)
		var n := PressureSkin.normal(a, fold)
		var shoulder := pow(0.5 + 0.5 * cos(a * 8.0), 3.0)
		p -= n * (offset + shoulder * scallop)
		st.set_color(color)
		st.set_normal(Vector3(n.x, n.y, 0))
		st.set_uv(Vector2(u, uv_y))
		st.add_vertex(Vector3(p.x, p.y, z))

func _join(st: SurfaceTool, base: int, sides: int) -> void:
	for j in sides:
		var v := base + j
		for index in [v, v + sides + 1, v + 1, v + 1, v + sides + 1, v + sides + 2]:
			st.add_index(index)

func _glass(length: float, lock: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(glazing)
	var rows := 32 if lock != 0 else 1
	for k in rows + 1:
		var z := length * k / rows
		_row(st, z, _fold(z, length, lock), 0, Color.WHITE, SIDES, SPACING * k / rows)
		if k > 0:
			_join(st, (k - 1) * (SIDES + 1), SIDES)
	return st.commit()

func _collar(st: SurfaceTool, base: int, z: float, length: float, lock: int, profile: Array, sides: int) -> int:
	for k in profile.size():
		var ring_z: float = z + profile[k][0]
		_row(st, ring_z, _fold(ring_z, length, lock), profile[k][1], profile[k][2], sides, 0, profile[k][3])
		if k > 0:
			_join(st, base + (k - 1) * (sides + 1), sides)
	return base + profile.size() * (sides + 1)

func _frames(length: float, lock: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(metal)
	var base := 0
	for k in BAYS:
		var z := length * (k + 0.5) / BAYS
		# Rubber seal, two machined shoulders and a copper retaining band.
		var major := k % 4 == 0
		var width := 4.2 if major else 1.55
		var flare := 11.0 if major else 2.2
		var profile := [[-width, 0.32, GASKET, 0], [-width * 0.76, 1.5, TITANIUM, 0],
			[-width * 0.52, 4.3, STEEL, flare], [0.0, 4.8, COPPER if major else STEEL, flare],
			[width * 0.55, 3.4, STEEL, flare], [width * 0.78, 0.7, TITANIUM, 0], [width, 0.32, GASKET, 0]]
		base = _collar(st, base, z, length, lock, profile, 64)
	return st.commit()

func _distant_frame(length: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(metal)
	var base := 0
	for k in 4:
		var z := length * (k * 4 + 0.5) / BAYS
		base = _collar(st, base, z, length, 0, [[-5, 3, STEEL, 10], [5, 3, TITANIUM, 10]], 32)
	return st.commit()

func _airlock(z: float, way: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(metal)
	var base := 0
	for d in [0.0, 24.0, 77.0]:
		var profile := [[-6, 0.5, GASKET, 0], [-4, 6, TITANIUM, 11], [-2, 13, COPPER, 26],
			[2, 13, COPPER, 26], [4, 6, STEEL, 11], [6, 0.5, GASKET, 0]]
		base = _collar(st, base, d * way, 0, 1, profile, SIDES)
	_instance(st.commit(), z, 0, 52000, "PressureLock")
	# A translucent field spans the open bore; the brightness lives at its lip.
	var disk := SurfaceTool.new()
	disk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var field := ShaderMaterial.new()
	field.shader = preload("res://view/aurora_seal.gdshader")
	disk.set_material(field)
	seal_fields.append(field)
	for j in SIDES:
		for a in [-1.0, TAU * j / SIDES, TAU * (j + 1) / SIDES]:
			var p := Vector2(0, PressureSkin.RADIUS) if a < 0 else PressureSkin.section(a, 0)
			disk.set_uv(Vector2(p.x / (2.0 * PressureSkin.RADIUS) + 0.5, p.y / (2.0 * PressureSkin.RADIUS)))
			disk.add_vertex(Vector3(p.x, p.y, 0.0))
	_instance(disk.commit(), z, 0, 4500, "PressureField")

# Eight saddle-mounted pressure accumulators sit outside a braced octagonal
# frame. The four larger ones have copper-banded service heads and cooling fins.
func _compressor() -> ArrayMesh:
	var parts := []
	var center := Vector3.UP * PressureSkin.RADIUS
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var radial := Vector3(sin(a), -cos(a), 0)
		var next := Vector3(sin(a + PI / 4.0), -cos(a + PI / 4.0), 0)
		var axis := Basis(Vector3.RIGHT, PI / 2.0)
		var pod := center + radial * 208.0
		var radius := 17.0 if k % 2 == 0 else 11.5
		for end in [-1.0, 1.0]:
			var face: Vector3 = Vector3.BACK * end * 45.0
			var anchor := center + radial * 180.0 + face
			_strut(parts, anchor, center + next * 206.0 + face, 3.4, STEEL)
			_strut(parts, anchor, center + next * 206.0 - face, 1.4, TITANIUM)
			_strut(parts, center + radial * 161.0 + face * 1.35, pod + face * 0.7, 4.5, GASKET)
			parts.append([Kit.cyl(radius * 0.67, radius * 0.67, 4, 20),
				Transform3D(axis, pod + face * 1.13), COPPER])
			parts.append([Kit.cyl(radius * 0.43, radius * 0.43, 6, 20),
				Transform3D(axis, pod + face * 1.19), GASKET])
		parts.append([Kit.cyl(radius, radius, 96.0, 24), Transform3D(axis, pod), TITANIUM])
		for dz in [-43.0, -36.0, -19.0, 0.0, 19.0, 36.0, 43.0]:
			parts.append([Kit.cyl(radius + 1.8, radius + 1.8, 2.0, 24),
				Transform3D(axis, pod + Vector3.BACK * dz), COPPER if absf(dz) > 40.0 else GASKET])
	# Enamel header with an inset ID panel, readable from either approach.
	parts.append([Kit.box(Vector3(163, 29, 8)), Kit.at(Vector3(0, 355, 0)), TITANIUM])
	parts.append([Kit.box(Vector3(159, 25, 9)), Kit.at(Vector3(0, 355, 0)), Color(0.035, 0.15, 0.18)])
	var mesh := Kit.compound(parts)
	mesh.surface_set_material(0, metal)
	return mesh

func _strut(parts: Array, a: Vector3, b: Vector3, radius: float, color: Color) -> void:
	var axis := Basis(Quaternion(Vector3.UP, (b-a).normalized()))
	parts.append([Kit.cyl(radius, radius, a.distance_to(b), 8), Transform3D(axis, (a+b)*0.5), color])

func _station_plate(z: float, station: String, index: int) -> void:
	for facing in [-1, 1]:
		var label := Label3D.new()
		label.text = "AURORA   /   S20     •     %02d\n%s    /    101 kPa" % [index + 1, station]
		label.font_size = 72
		label.pixel_size = 0.105
		label.outline_size = 0
		label.modulate = Color(0.84, 1.0, 0.91)
		label.double_sided = false
		label.rotation.y = 0.0 if facing > 0 else PI
		label.position = Vector3(0, 355, z + facing * 5.0)
		label.visibility_range_end = 4500.0
		_stations.add_child(label)
