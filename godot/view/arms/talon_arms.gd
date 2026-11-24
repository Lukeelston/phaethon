## The Talon's two leading-edge bays. The raid controller supplies normalized deploy time and heat.
## Talon.wing_arms(visible_hull) fits one rig on first use. Neither rig nor meshes tick.
extends Node3D

const Talon := preload("res://view/talon_airframe.gd")
const Finish := preload("res://view/craft_materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const TRAVEL := 1.22
const STOWED_TIP_Z := -0.20
const SIDES := 16
const CARBON := Color(0.115, 0.14, 0.16)
const BLUED := Color(0.23, 0.30, 0.34)
const EDGE := Color(0.63, 0.69, 0.70)
const BORE := Color(0.032, 0.040, 0.045)
const COOL := Color(0.12, 0.04, 0.012)
const HOT := Color(1.0, 0.34, 0.055)

var hull: MeshInstance3D
var upper: MeshInstance3D
var lower: MeshInstance3D
var barrels: MeshInstance3D
var throats: StandardMaterial3D
var mouths: Array[Marker3D] = []
var deploy := 0.0
var heat := 0.0:
	set(value):
		heat = clampf(value, 0.0, 1.0)
		if throats:
			throats.emission = COOL.lerp(HOT, heat)
			throats.emission_energy_multiplier = 0.05 + 2.1 * heat


func build(visible_hull: MeshInstance3D) -> void:
	if hull != null:
		return
	hull = visible_hull
	name = "TalonArms"
	if get_parent() == null:
		hull.add_child(self)
	var pal: Dictionary = hull.mesh.get_meta(&"talon_palette")
	upper = _part("UpperShutters", _shutters(true, pal))
	lower = _part("LowerShutters", _shutters(false, pal))
	barrels = _part("WingGuns", _barrels())
	for side: float in [-1.0, 1.0]:
		var mouth := Marker3D.new()
		mouth.name = "PortMouth" if side < 0.0 else "StarboardMouth"
		mouth.position = _axis(side) + Vector3.BACK * STOWED_TIP_Z
		barrels.add_child(mouth)
		mouths.append(mouth)
	heat = heat
	hide()


func _part(label: String, mesh: ArrayMesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_to_group("exterior")
	add_child(part)
	return part


func set_deploy(t: float) -> void:
	var next := clampf(t, 0.0, 1.0)
	if next == deploy or not hull:
		return
	if deploy == 0.0:
		hull.mesh = Talon.with_gun_bays(hull.mesh)
	deploy = next
	if deploy == 0.0:
		hull.mesh = hull.mesh.get_meta(&"talon_stock")
		hide()
	else:
		show()
	# The shutters run aft into the wing. Their lips clear the tips before the guns advance.
	var door := smoothstep(0.0, 0.45, deploy)
	upper.position = Vector3(0, -0.033 * door, 0.60 * door)
	lower.position = Vector3(0, 0.033 * door, 0.60 * door)
	upper.visible = door < 1.0
	lower.visible = upper.visible
	barrels.position.z = -TRAVEL * smoothstep(0.26, 1.0, deploy)


func muzzles() -> Array:
	var transforms := []
	for mouth in mouths:
		transforms.append(mouth.global_transform)
	return transforms


static func _axis(side: float) -> Vector3:
	var row := Talon.gun_station((Talon.GUN_SPAN.x + Talon.GUN_SPAN.y) * 0.5)
	return Vector3(float(row[0]) * side, row[1], 0.0)


## The same wing stations, facet colours and painted metal as the non-moving leading edge.
static func _shutters(top: bool, pal: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var rows := []
		for x: float in [Talon.GUN_SPAN.x, Talon.GUN_SPAN.y]:
			var row := Talon.gun_station(x)
			var points := PackedVector3Array()
			for i in Talon.CHORD.size():
				points.append(Vector3(side * x, row[1] + row[4] * Talon.CAMBER[i], lerpf(row[2], row[3], Talon.CHORD[i])))
			rows.append(points)
		var a: PackedVector3Array = rows[0]
		var b: PackedVector3Array = rows[1]
		var normal := Vector3.UP if top else Vector3.DOWN
		for i: int in ([0, 1] if top else [9]):
			var j := (i + 1) % Talon.CHORD.size()
			var color: Color = (pal.metal if i == 0 else pal.trim) if top else pal.body
			Talon._face(st, a[i], a[j], b[j], normal, color)
			Talon._face(st, a[i], b[j], b[i], normal, color)
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, Finish.painted_metal())
	return mesh


## Axially profiled, hollow tips, interrupted heat vents and a faired breech. Both guns share two surfaces.
func _barrels() -> ArrayMesh:
	var metal := SurfaceTool.new()
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	# From the inner throat forward, around the chamfered lip, then aft to the slide.
	var profile := [
		Vector3(0.14, 0.031, 0), Vector3(0.025, 0.045, 0), Vector3(0.004, 0.047, 0),
		Vector3(0.0, 0.051, 1), Vector3(0.0, 0.064, 1), Vector3(0.009, 0.070, 1),
		Vector3(0.082, 0.070, 2), Vector3(0.090, 0.058, 1), Vector3(0.179, 0.056, 2),
		Vector3(0.188, 0.073, 1), Vector3(0.226, 0.073, 2), Vector3(0.233, 0.064, 1),
		Vector3(0.59, 0.064, 2), Vector3(0.61, 0.081, 1), Vector3(0.70, 0.081, 3),
		Vector3(0.72, 0.074, 1), Vector3(1.32, 0.072, 3)]
	var colors := [BORE, EDGE, BLUED, CARBON]
	for side: float in [-1.0, 1.0]:
		var centre := _axis(side) + Vector3.BACK * STOWED_TIP_Z
		for j in range(1, profile.size()):
			var front: Vector3 = profile[j - 1]
			var rear: Vector3 = profile[j]
			_ring(metal, centre, front.x, front.y, rear.x, rear.y, colors[int(rear.z)])
		for start: float in [0.26, 0.35, 0.44, 0.53]:
			for slot in 4:
				_ring(glow, centre, start, 0.065, start + 0.034, 0.065, Color.WHITE, slot * 4, 2)
		_ring(glow, centre, 0.033, 0.044, 0.058, 0.042, Color.WHITE)
	metal.index()
	var mesh := metal.commit()
	mesh.surface_set_material(0, Kit.polished(0.74, 0.32))
	glow.index()
	glow.commit(mesh)
	throats = StandardMaterial3D.new()
	throats.albedo_color = Color(0.21, 0.105, 0.045)
	throats.roughness = 0.32
	throats.metallic = 0.42
	throats.emission_enabled = true
	throats.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, throats)
	return mesh


static func _ring(st: SurfaceTool, centre: Vector3, z0: float, r0: float, z1: float, r1: float,
		color: Color, first := 0, count := SIDES) -> void:
	for i in range(first, first + count):
		var angle := TAU * i / SIDES
		var radial := Vector3(cos(angle), sin(angle), 0)
		var next := Vector3(cos(angle + TAU / SIDES), sin(angle + TAU / SIDES), 0)
		var p := centre + radial * r0 + Vector3.BACK * z0
		var q := centre + next * r0 + Vector3.BACK * z0
		var r := centre + next * r1 + Vector3.BACK * z1
		var s := centre + radial * r1 + Vector3.BACK * z1
		var normal := (radial + next).normalized() * (z1 - z0) + Vector3.FORWARD * (r1 - r0)
		Talon._face(st, p, q, r, normal, color)
		Talon._face(st, p, r, s, normal, color)
