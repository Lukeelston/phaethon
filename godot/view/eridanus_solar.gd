## The fixed shutters of Eridanus' heat works, seen nearly face-on through the
## outbound portal. Dimensions are metres; local +Z faces the arriving light.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const CONCRETE := Color("#9c9d90")
const STEEL := Color("#454e50")
const RECESS := Color("#313c40")
const ALLOY := Color("#a2aba9")
const BRONZE := Color("#bc7842")
const CERAMIC := Color("#ddd7bd")
const AMBER := Color("#ffad52")
const CENTER := Vector3(0, 1250, 0)


static func _box(parts: Array, size: Vector3, at: Vector3, tint: Color, pitch := 0.0) -> void:
	parts.append([Kit.box(size), Kit.at(at, Vector3(pitch, 0, 0)), tint])


static func _strut(parts: Array, a: Vector3, b: Vector3, width: float, depth: float, tint: Color) -> void:
	var offset := b - a
	var frame := Basis(Quaternion(Vector3.UP, offset.normalized()))
	parts.append([Kit.box(Vector3(width, offset.length(), depth)), Transform3D(frame, (a + b) / 2.0), tint])


static func _annular_plate(inner: float, outer: float, depth: float, start: float, finish: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The rolled front lip, bevel and rear flange form the cross-section of the hoop.
	var profile := [Vector2(inner + 8, depth / 2), Vector2(outer - 12, depth / 2),
		Vector2(outer, depth / 2 - 12), Vector2(outer, -depth / 2 + 8),
		Vector2(outer - 8, -depth / 2), Vector2(inner + 6, -depth / 2),
		Vector2(inner, -depth / 2 + 6), Vector2(inner, depth / 2 - 8)]
	var steps := ceili((finish - start) / (PI / 36))
	for i in steps:
		var a := lerpf(start, finish, float(i) / steps)
		var b := lerpf(start, finish, float(i + 1) / steps)
		var ra := Vector3(cos(a), sin(a), 0)
		var rb := Vector3(cos(b), sin(b), 0)
		for j in profile.size():
			var q: Vector2 = profile[j]
			var next: Vector2 = profile[(j + 1) % profile.size()]
			var p0 := ra * q.x + Vector3.BACK * q.y
			var p1 := rb * q.x + Vector3.BACK * q.y
			var p2 := rb * next.x + Vector3.BACK * next.y
			var p3 := ra * next.x + Vector3.BACK * next.y
			var norm := (p2 - p0).cross(p1 - p0).normalized()
			for vertex in [p0, p1, p2, p0, p2, p3]:
				surface.set_normal(norm)
				surface.add_vertex(vertex)
	# Seams have a darker continuous hoop immediately behind them.
	return surface.commit()


static func array_mesh(body_material: Material, lamp_material: Material) -> ArrayMesh:
	var body: Array = []
	var lights: Array = []
	_box(body, Vector3(1540, 64, 560), Vector3(0, 28, 0), STEEL)
	_box(body, Vector3(1390, 82, 472), Vector3(0, 95, 0), CONCRETE)
	_box(body, Vector3(1040, 104, 382), Vector3(0, 183, 0), STEEL)
	# Splayed frames carry two giant trunnions. Leave the gap beneath the
	# aperture open, so the horizon is visible between the feet.
	for side: float in [-1.0, 1.0]:
		var axle := Vector3(side * 658, CENTER.y, 0)
		for z: float in [-155.0, 155.0]:
			_strut(body, Vector3(side * 512, 125, z * 1.32), axle + Vector3(0, 0, z * 0.34), 89, 91, CERAMIC)
			_strut(body, Vector3(side * 297, 207, z), Vector3(side * 653, 870, z * 0.57), 53, 65, STEEL)
		for k in 3:
			var y := 290.0 + k * 255.0
			_box(body, Vector3(135, 37, 320 - k * 57), Vector3(side * (531 + k * 37), y, 0), BRONZE)
		for dim in [[104.0, 175.0, STEEL], [80.0, 191.0, ALLOY], [52.0, 204.0, BRONZE]]:
			body.append([Kit.cyl(dim[0], dim[0], 43.0, 20),
				Kit.at(axle + Vector3(0, 0, dim[1]), Vector3(PI / 2, 0, 0)), dim[2]])
		_box(lights, Vector3(17, 122, 12), Vector3(side * 620, 890, 112), AMBER)
	body.append([_annular_plate(533, 673, 120, 0, TAU), Kit.at(CENTER), RECESS])
	for segment in 12:
		var a := segment * TAU / 12.0
		var b := (segment + 1) * TAU / 12.0
		var color := BRONZE if segment in [0, 1, 2, 6, 7, 8] else CERAMIC
		body.append([_annular_plate(550, 668, 36, a + 0.016, b - 0.016), Kit.at(CENTER + Vector3.BACK * 64), color])
	# A fixed bank of half-closed blades keeps the crescent sky cutout legible
	# at five miles. The lower edges catch a different value from the blade faces.
	_box(body, Vector3(36, 1090, 94), CENTER + Vector3(28, 0, 0), STEEL)
	for row in 9:
		var y := (row - 4) * 107.0
		var reach := sqrt(548.0 * 548.0 - y * y)
		var width := reach - 30.0
		var p := CENTER + Vector3(30 + width / 2, y, 7)
		_box(body, Vector3(width, 54, 96), p, ALLOY if row % 3 == 0 else STEEL, -0.30)
		_box(body, Vector3(width, 13, 20), p + Vector3(0, -9, 41), BRONZE)
	for k in 3:
		var y := (k - 1) * 260.0
		_box(lights, Vector3(15, 100, 12), CENTER + Vector3(28, y, 53), AMBER)
	var mesh := Kit.compound(body)
	Kit.compound(lights, mesh)
	mesh.surface_set_material(0, body_material)
	mesh.surface_set_material(1, lamp_material)
	return mesh


## Cooling galleries beyond the portal. Long concrete plinths, heat exchanger
## cabinets and staggered stacks read as large separate masses in peripheral vision.
static func add_gallery(parts: Array, lamps: Array, frame: Transform3D, tier: int) -> void:
	var body: Array = []
	var lights: Array = []
	var height := 38.0 + 16.0 * tier
	_box(body, Vector3(104, 10, 66), Vector3(0, 3, 0), CONCRETE)
	_box(body, Vector3(83, height, 44), Vector3(-4, 8 + height / 2, 1), STEEL)
	_box(body, Vector3(95, 7, 52), Vector3(-4, 10 + height, 1), CERAMIC)
	for k in 5:
		var x := -38.0 + 16.0 * k
		_box(body, Vector3(6, height + 2, 50), Vector3(x, height / 2 + 7, 0), CONCRETE)
		_box(body, Vector3(9, 7, 4), Vector3(x + 8, height + 2, 24), BRONZE)
		_box(lights, Vector3(8, 2, 3), Vector3(x + 8, height + 2, 26), AMBER)
	for k in 2:
		var h := height * (2.0 - 0.3 * k)
		var p := Vector3(22 - k * 28, h / 2 + height + 13, -5)
		body.append([Kit.cyl(5, 8, h, 8), Kit.at(p), ALLOY])
		body.append([Kit.cyl(7, 7, 9, 8), Kit.at(p + Vector3.UP * (h / 2 - 7)), BRONZE])
	for part in body:
		part[1] = frame * part[1]
		parts.append(part)
	for part in lights:
		part[1] = frame * part[1]
		lamps.append(part)
