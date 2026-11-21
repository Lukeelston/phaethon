## Shrike RS bodywork. Shared static meshes use the same pivots as the moving
## brakes, rotors and nozzle. Forward is local -Z, and out points away from the pilot.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Fairings := preload("res://view/craft_fairings.gd")
const Finish := preload("res://view/craft_materials.gd")
const PETROL := Color("#12666a")
const IVORY := Color("#f1e5c9")
const COPPER := Color("#e49749")
const CARBON := Color("#243236")
const ALLOY := Color("#9caead")
const FIN_CANT := 0.76
static var engines := {}
static var seat_trim: ArrayMesh
static var pod_paint: StandardMaterial3D


## Revolve a strip between elliptic sections (z, half-width, half-height).
## Sections can turn back inside the intake, forming the lip and its recessed throat.
static func _strip(a: Vector3, b: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 32:
		for corner in [0, 1, 2, 0, 2, 3]:
			var sec := b if corner in [1, 2] else a
			var theta := TAU * float(j + int(corner >= 2)) / 32.0
			var c := cos(theta)
			var s := sin(theta)
			var dz := b.x - a.x
			st.set_normal(Vector3(dz * c * sec.z, dz * s * sec.y,
				-((b.y-a.y) * c*c * sec.z + (b.z-a.z) * s*s * sec.y)).normalized())
			st.add_vertex(Vector3(sec.y * c, sec.z * s, sec.x))
	return st.commit()


static func _blade(parts: Array, xf: Transform3D, scale_y: float, scale_z: float) -> void:
	# Spanwise paint bands follow the swept edges, including the clipped tip.
	var bands := [[0.0, -0.82, 1.60, CARBON], [0.15, -0.58, 1.68, IVORY],
		[1.12, 1.22, 2.09, PETROL], [1.29, 1.54, 2.17, COPPER], [1.43, 1.82, 2.22, COPPER]]
	for i in bands.size() - 1:
		var a: Array = bands[i]
		var b: Array = bands[i+1]
		var profile := PackedVector2Array([Vector2(a[0]*scale_y, a[1]*scale_z),
			Vector2(b[0]*scale_y, b[1]*scale_z), Vector2(b[0]*scale_y, b[2]*scale_z),
			Vector2(a[0]*scale_y, a[2]*scale_z)])
		parts.append([Fairings.fin(profile, 0.066), xf, a[3]])


static func _tail_root(out: float) -> Transform3D:
	return Kit.at(Vector3(out * 0.82, 0.26, 0.52), Vector3(0, 0, -out * FIN_CANT))


static func fin_tip(out: float) -> Vector3:
	return _tail_root(out) * Vector3(0, 1.40, 2.1)


static func engine(out: float) -> ArrayMesh:
	if engines.has(out):
		return engines[out]
	var parts := []
	# The two intake bells converge around the gearbox; the impellers remain visible.
	var rings := [Vector3(-3.57, 0.35, 0.35), Vector3(-3.98, 0.375, 0.375),
		Vector3(-4.10, 0.404, 0.402), Vector3(-4.13, 0.46, 0.445),
		Vector3(-4.03, 0.505, 0.487), Vector3(-3.84, 0.53, 0.503),
		Vector3(-3.71, 0.536, 0.506), Vector3(-3.02, 0.55, 0.49),
		Vector3(-2.80, 0.55, 0.48), Vector3(-1.70, 0.55, 0.43), Vector3(0.54, 0.45, 0.34)]
	var colors := [CARBON, ALLOY, IVORY, IVORY, PETROL, COPPER, IVORY, PETROL, PETROL, CARBON]
	for i in rings.size() - 1:
		var strip := _strip(rings[i], rings[i+1])
		for x in [-0.55, 0.55]:
			parts.append([strip, Kit.at(Vector3(x, 0, 0)), colors[i]])
	for x in [-0.55, 0.55]:
		parts.append([Kit.cyl(0.36, 0.36, 0.04, 24), Kit.at(Vector3(x, 0, -3.57), Vector3(PI/2, 0, 0)), CARBON])
	var spine := [Vector3(-3.12, 0.08, 0.12), Vector3(-2.42, 0.98, 0.42),
		Vector3(-1.12, 1.19, 0.50), Vector3(0.72, 1.18, 0.50),
		Vector3(1.75, 1.10, 0.44), Vector3(3.1, 1.02, 0.38)]
	for i in spine.size() - 1:
		parts.append([_strip(spine[i], spine[i+1]), Transform3D.IDENTITY, PETROL])
	parts.append([Kit.rounded_box(Vector3(0.64, 0.068, 1.49), 5.0), Kit.at(Vector3(0, 0.48, -0.55)), IVORY])
	_blade(parts, _tail_root(out), 1.0, 1.0)
	# Keel ties the exhaust case to its tow eye. Cheek blisters support the
	# forward brake pivots and the inboard binder emitter.
	parts.append([Fairings.fin(PackedVector2Array([Vector2(0, -0.82), Vector2(0.60, 0.43),
		Vector2(0.57, 0.62), Vector2(0, 0.57)]), 0.16),
		Kit.at(Vector3(0, -0.37, 2.88), Vector3(0, 0, PI)), ALLOY])
	parts.append([Kit.cyl(0.12, 0.12, 0.20), Kit.at(Vector3(0, -0.95, 3.4), Vector3(0, 0, PI/2)), CARBON])
	for side in [-1.0, 1.0]:
		parts.append([Kit.rounded_box(Vector3(0.34, 0.56, 1.35), 4.0),
			Kit.at(Vector3(side * 1.08, 0, -2.67)), PETROL])
		parts.append([Kit.rounded_box(Vector3(0.24, 0.22, 1.55), 4.0),
			Kit.at(Vector3(side * 0.93, 0.27, 2.98)), IVORY])
		for i in 5:
			parts.append([Kit.box(Vector3(0.19, 0.035, 0.065)),
				Kit.at(Vector3(side * 0.93, 0.377, 2.65 + 0.14*i), Vector3(-0.24,0,0)), CARBON])
	for y in [-0.36, 0.36]:
		parts.append([Kit.box(Vector3(2.0, 0.055, 0.28)), Kit.at(Vector3(0, y, 3.94)), ALLOY])
	engines[out] = Kit.compound(parts)
	return engines[out]


static func lights(out: float) -> ArrayMesh:
	return Kit.compound([
		[Kit.ball(0.057, 10), _tail_root(out) * Kit.at(Vector3(0, 1.18, 2.10)),
			Color("#ef413b") if out < 0 else Color("#49dc91")],
		[Kit.box(Vector3(0.44, 0.04, 0.035)), Kit.at(Vector3(0, 0.39, 4.0)), Color("#e84432")],
		[Kit.box(Vector3(0.09, 0.045, 0.08)), Kit.at(Vector3(out * 0.81, -0.39, -3.92)), IVORY]])


static func dress_pod(hull: MeshInstance3D) -> void:
	if seat_trim == null:
		var parts := []
		for side in [-1.0, 1.0]:
			_blade(parts, Kit.at(Vector3(side * 0.91, -0.18, 0.27), Vector3(0, 0, -side * 1.31)), 0.48, 0.69)
		seat_trim = Kit.compound(parts)
		pod_paint = Finish.painted_metal().duplicate()
		pod_paint.vertex_color_use_as_albedo = false
		pod_paint.albedo_color = PETROL
		pod_paint.clearcoat_enabled = true
		pod_paint.clearcoat = 0.8
	hull.set_surface_override_material(5, pod_paint)
	var trim := MeshInstance3D.new()
	trim.name = "ShrikeStrakes"
	trim.add_to_group("exterior")
	trim.mesh = seat_trim
	trim.material_override = Finish.painted_metal()
	hull.add_child(trim)


static func dress_coaming(coaming: MeshInstance3D, hd: bool) -> void:
	if hd:
		var original := coaming.mesh.surface_get_material(0) as BaseMaterial3D
		var livery := original.duplicate() as BaseMaterial3D
		livery.albedo_texture = load("res://art/cockpit/shrike_coaming.webp")
		coaming.set_surface_override_material(0, livery)
	var plate := MeshInstance3D.new()
	plate.name = "ShrikePlate"
	plate.position = Vector3(0, 0.578, -0.911)
	plate.mesh = Kit.compound([
		[Finish.beveled_plate(Vector3(0.216, 0.057, 0.014), 0.003), Transform3D.IDENTITY, ALLOY],
		[Finish.beveled_plate(Vector3(0.211, 0.052, 0.008), 0.002), Kit.at(Vector3(0, 0, 0.006)), CARBON],
		[Kit.cyl(0.003, 0.003, 0.003), Kit.at(Vector3(-0.097, 0, 0.011), Vector3(PI/2, 0, 0)), COPPER],
		[Kit.cyl(0.003, 0.003, 0.003), Kit.at(Vector3(0.097, 0, 0.011), Vector3(PI/2, 0, 0)), COPPER]])
	plate.material_override = Finish.machined()
	plate.add_to_group("exterior")
	coaming.add_child(plate)
	var mark := Label3D.new()
	mark.text = "SHRIKE  RS"
	mark.font_size = 60
	mark.pixel_size = 0.00047
	mark.outline_size = 0
	mark.modulate = IVORY
	mark.position.z = 0.0115
	mark.add_to_group("exterior")
	plate.add_child(mark)
