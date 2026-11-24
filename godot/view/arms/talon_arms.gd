## The Talon's two leading-edge bays. The raid controller supplies normalized deploy time and heat.
## Talon.wing_arms(visible_hull) fits one rig on first use. Neither rig nor meshes tick.
extends Node3D

const Talon := preload("res://view/talon_airframe.gd")
const Finish := preload("res://view/craft_materials.gd")
const Kit := preload("res://view/mesh_kit.gd")
const TRAVEL := 0.83
const STOWED_TIP_Z := Talon.GUN_FRONT + 0.085
const LIFT_ARM := 0.53
const LOW_ANGLE := deg_to_rad(9.0)
const HIGH_ANGLE := deg_to_rad(69.0)
const PIVOTS := [-1.48, -0.78]
const PIVOT_Y := -0.022
const SIDES := 16
const CARBON := Color(0.115, 0.14, 0.16)
const BLUED := Color(0.23, 0.30, 0.34)
const EDGE := Color(0.63, 0.69, 0.70)
const BORE := Color(0.032, 0.040, 0.045)
const COOL := Color(0.12, 0.04, 0.012)
const HOT := Color(1.0, 0.34, 0.055)

var hull: MeshInstance3D
var carriage: MeshInstance3D
var caps: MeshInstance3D
var links: Array[MeshInstance3D] = []
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
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	Talon.add_gun_carriages(skin, pal)
	skin.index()
	carriage = _part("GunCarriages", skin.commit())
	carriage.material_override = Finish.painted_metal()
	skin = SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	Talon.add_gun_caps(skin, pal)
	skin.index()
	caps = _part("MuzzleCaps", skin.commit())
	caps.material_override = carriage.material_override
	barrels = _part("WingGuns", _barrels())
	var link_mesh := _lift_links(pal)
	for z: float in PIVOTS:
		var link := _part("FrontLinks" if links.is_empty() else "RearLinks", link_mesh)
		link.position = Vector3(0, PIVOT_Y, z)
		link.material_override = Finish.painted_metal()
		links.append(link)
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
	# Parallel lift arms keep the two bores level as their housings rise and advance.
	# Their painted backs clear the cockpit rails before the inner tubes extend.
	var lift := lerpf(LOW_ANGLE, HIGH_ANGLE, smoothstep(0.0, 1.0, deploy))
	for link in links:
		link.rotation.x = -lift
	var raised := Vector3(0, sin(lift) - sin(LOW_ANGLE), cos(lift) - cos(LOW_ANGLE)) * LIFT_ARM
	carriage.position = raised
	var cap_rotation := Basis(Vector3.RIGHT, deg_to_rad(104.0) * smoothstep(0, 0.50, deploy))
	caps.transform = Transform3D(cap_rotation, raised + Talon.SHUTTER_PIN - cap_rotation * Talon.SHUTTER_PIN)
	barrels.position = raised + Vector3.FORWARD * TRAVEL * smoothstep(0.30, 1, deploy)


func muzzles() -> Array:
	var transforms := []
	for mouth in mouths:
		transforms.append(mouth.global_transform)
	return transforms


static func _axis(side: float) -> Vector3:
	return Vector3(Talon.GUN_X * side, Talon.GUN_Y, 0.0)


## Two cheek links around each breech. They share across port and starboard, and this
## one mesh fits both pivot stations. Titanium eyes catch the changing light in flight.
static func _lift_links(pal: Dictionary) -> ArrayMesh:
	var parts := []
	var pin := Kit.cyl(.046, .046, .223, 12)
	var boss := Kit.cyl(.042, .042, .008, 12)
	var beam := Kit.rounded_box(Vector3(.038, .068, LIFT_ARM), 6.0, 6)
	for side: float in [-1.0, 1.0]:
		var x := Talon.GUN_X * side
		for offset: float in [-.091, .091]:
			parts.append([beam, Kit.at(Vector3(x + offset, 0, LIFT_ARM * .5)), pal.panel])
		for z: float in [0.0, LIFT_ARM]:
			parts.append([pin, Kit.at(Vector3(x, 0, z), Vector3(0, 0, PI / 2)), pal.metal])
			parts.append([boss, Kit.at(Vector3(x - side * .114, 0, z), Vector3(0, 0, PI / 2)), pal.trim])
	return Kit.compound(parts, null, true)


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
