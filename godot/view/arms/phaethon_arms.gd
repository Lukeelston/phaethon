## Twin arc projectors on folding elevators in the Phaethon's engine noses.
## craft.phaethon_arms() supplies this rig on first arm in both the flat and the VR view.
## The two engines move independently; all poses, including the mouths, are engine-local.
extends RefCounted

const Livery := preload("res://view/livery.gd")
const Finishes := preload("res://view/craft_materials.gd")
const Metal := preload("res://view/arms/phaethon_barrel.gdshader")
const Kit := preload("res://view/mesh_kit.gd")
const PIVOT := Vector3(0, 0.21, -3.29)
const LINK_LENGTH := 1.65
const HINGE_SPREAD := 0.37
const STOW_LIFT := 0.13
const FULL_LIFT := 1.57
const MOUTH_Z := -0.96
const STOW_Z := 0.42
const FULL_Z := -0.91
const RIM_STEPS := 16
const IRON := Color(0.16, 0.19, 0.22)
const STEEL := Color(0.47, 0.53, 0.56)
const BRONZE := Color(0.47, 0.27, 0.12)
const WELL := Color(0.025, 0.032, 0.038)
const CERAMIC := Color(0.30, 0.34, 0.37)

var _links: Array[MeshInstance3D] = []
var _carriages: Array[MeshInstance3D] = []
var _barrels: Array[MeshInstance3D] = []
var _ports: Array[Marker3D] = []
var _metal: ShaderMaterial
var _deploy := -1.0
var heat := 0.0:
	set(value):
		if heat == clampf(value, 0.0, 1.0):
			return
		heat = clampf(value, 0.0, 1.0)
		if _metal:
			_metal.set_shader_parameter("heat", heat)


func build(engines: Array[Node3D]) -> void:
	if not _ports.is_empty() or engines.size() != 2:
		return
	_metal = ShaderMaterial.new()
	_metal.shader = Metal
	_metal.set_shader_parameter("heat", heat)
	var bed := _cassette()
	var link := _link()
	var receiver := _receiver()
	var barrel := _projector()
	for engine in engines:
		var bay := _mount(engine, "PhaethonNoseBay", bed, Finishes.machined())
		bay.position = PIVOT
		for z: float in [-HINGE_SPREAD, HINGE_SPREAD]:
			var support := _mount(bay, "ForwardLink" if z < 0 else "AftLink", link, Finishes.machined())
			support.position.z = z
			_links.append(support)
		var carriage := _mount(bay, "Breech", receiver, Finishes.painted_metal())
		_carriages.append(carriage)
		var tube := _mount(carriage, "ArcProjector", barrel, _metal)
		_barrels.append(tube)
		var mouth := Marker3D.new()
		mouth.name = "Mouth"
		mouth.position.z = MOUTH_Z
		tube.add_child(mouth)
		_ports.append(mouth)
	set_deploy(0.0)


func set_deploy(t: float) -> void:
	var at := clampf(t, 0.0, 1.0)
	if _ports.is_empty() or at == _deploy:
		return
	_deploy = at
	# Equal-length front and rear links keep the carriage level. Drive its rise directly
	# so the last part of the motion still changes the silhouette from the tow pod.
	# Lead with a quick lift out of the intake's shadow, then carry the carriage
	# to its stop at a steady rate. The same curve governs the return stroke.
	var quick_lift := (1.0 - exp(-8.0 * at)) / (1.0 - exp(-8.0))
	var travel := lerpf(at, quick_lift, lerpf(0.47, 0.16, at))
	var rise := lerpf(STOW_LIFT, FULL_LIFT, travel)
	var angle := asin(rise / LINK_LENGTH)
	var carriage_position := Vector3(0.0, rise, LINK_LENGTH * cos(angle))
	for link in _links:
		link.rotation.x = -angle
	for carriage in _carriages:
		carriage.position = carriage_position
	for tube in _barrels:
		tube.position.z = lerpf(STOW_Z, FULL_Z, smoothstep(0.04, 0.98, at))
		tube.visible = at > 0.0


## Global frames ordered port, starboard. -Z always points along that engine's heading.
func muzzles() -> Array[Transform3D]:
	var frames: Array[Transform3D] = []
	for port in _ports:
		frames.append(port.global_transform)
	return frames


static func _mount(parent: Node3D, label: String, mesh: ArrayMesh, finish: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = finish
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_to_group("exterior")
	parent.add_child(node)
	return node


# A surface of revolution in the engine frame. Walk toward the nose along the
# outside profile and back along the inner wall to make a genuinely recessed mouth.
static func _turn(st: SurfaceTool, rear: Vector2, front: Vector2, tint: Color, coil := false) -> void:
	var delta := front - rear
	for i in RIM_STEPS:
		var a := TAU * i / RIM_STEPS
		var b := TAU * (i + 1) / RIM_STEPS
		# Four long dark flats break up the ceramic sleeve behind the nose collar.
		var finish := IRON if rear.y - front.y > 0.20 and i % 4 == 1 else tint
		for point: Vector3 in [Vector3(rear.x, rear.y, a), Vector3(rear.x, rear.y, b),
				Vector3(front.x, front.y, b), Vector3(rear.x, rear.y, a),
				Vector3(front.x, front.y, b), Vector3(front.x, front.y, a)]:
			var radial := Vector3(cos(point.z), sin(point.z), 0)
			st.set_normal((radial * -delta.y + Vector3.BACK * delta.x).normalized())
			st.set_color(finish)
			st.set_uv(Vector2(float(coil), 0))
			st.add_vertex(radial * point.x + Vector3.BACK * point.y)


# The low seam stays on the engine. The painted roof above it is part of the moving
# receiver, so the pilot sees the same physical assembly that carries the muzzle.
static func _cassette() -> ArrayMesh:
	# Guides straddle the two lift slots. Keep the front of the cassette behind
	# the intake lip and leave the twin fans and their dividing web clear.
	var parts := [
		[Finishes.beveled_plate(Vector3(0.19, 0.045, 2.53), 0.018), Kit.at(Vector3(0, 0.292, 1.06)), WELL],
	]
	var lip := Finishes.beveled_plate(Vector3(0.083, 0.056, 2.53), 0.020)
	for side: float in [-1.0, 1.0]:
		parts.append([lip, Kit.at(Vector3(side * 0.272, 0.29, 1.06)), IRON])
	return Kit.compound(parts, null, true)


static func _link() -> ArrayMesh:
	var parts := []
	var cheek := Finishes.beveled_plate(Vector3(0.095, 0.18, LINK_LENGTH), 0.052)
	var stiffener := Finishes.beveled_plate(Vector3(0.047, 0.070, LINK_LENGTH * 0.78), 0.023)
	var bridge := Finishes.beveled_plate(Vector3(0.35, 0.15, LINK_LENGTH * 0.58), 0.050)
	parts.append([bridge, Kit.at(Vector3(0, 0, LINK_LENGTH * 0.40)), IRON])
	var pin := Kit.cyl(0.10, 0.10, 0.44, 12)
	var cap := Kit.cyl(0.058, 0.058, 0.027, 12)
	for side: float in [-1.0, 1.0]:
		parts.append([cheek, Kit.at(Vector3(side * 0.17, 0, LINK_LENGTH * 0.5)), CERAMIC])
		parts.append([stiffener, Kit.at(Vector3(side * 0.215, 0.013, LINK_LENGTH * 0.5)), STEEL])
		for z: float in [0.0, LINK_LENGTH]:
			parts.append([cap, Kit.at(Vector3(side * 0.223, 0, z), Vector3(0, 0, PI * 0.5)), BRONZE])
	for z: float in [0.0, LINK_LENGTH]:
		parts.append([pin, Kit.at(Vector3(0, 0, z), Vector3(0, 0, PI * 0.5)), IRON])
	return Kit.compound(parts, null, true)


static func _receiver() -> ArrayMesh:
	var parts := [
		[Finishes.beveled_plate(Vector3(0.54, 0.31, 1.70), 0.075), Kit.at(Vector3(0, 0.045, 0)), IRON],
		[Finishes.beveled_plate(Vector3(0.59, 0.084, 1.82), 0.035), Kit.at(Vector3(0, 0.202, 0)), Livery.coat("engine")],
		[Finishes.beveled_plate(Vector3(0.45, 0.175, 0.12), 0.036), Kit.at(Vector3(0, 0.05, 0.852)), STEEL],
	]
	# Recessed rear vent and two side wear strips catch light even when the coil is cold.
	parts.append([Finishes.beveled_plate(Vector3(0.31, 0.10, 0.026), 0.010), Kit.at(Vector3(0, 0.06, 0.916)), WELL])
	var vent := Finishes.beveled_plate(Vector3(0.045, 0.096, 0.040), 0.012)
	for x: float in [-0.096, 0.0, 0.096]:
		parts.append([vent, Kit.at(Vector3(x, 0.06, 0.923)), BRONZE])
	# The aft casting flares over the shoulders of the intake. Its two enamel
	# cheeks rise with the breech, presenting a broad rear face to the tow pod.
	var cheek := Finishes.beveled_plate(Vector3(0.44, 0.11, 1.30), 0.047)
	var end_cap := Finishes.beveled_plate(Vector3(0.37, 0.090, 0.10), 0.032)
	var rail := Finishes.beveled_plate(Vector3(0.050, 0.058, 1.28), 0.017)
	for side: float in [-1.0, 1.0]:
		var tilt := Vector3(0, 0, side * 0.36)
		parts.append([cheek, Kit.at(Vector3(side * 0.434, 0.285, 0.07), tilt), Livery.coat("engine")])
		parts.append([end_cap, Kit.at(Vector3(side * 0.434, 0.278, 0.729), tilt), STEEL])
		parts.append([rail, Kit.at(Vector3(side * 0.263, 0.094, -0.05)), STEEL])
	return Kit.compound(parts, null, true)


static func _projector() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Socket shoulder, corrugated heat exchanger, insulated silver shank, then a
	# dark flared lip with a bright edge and an inner liner around the emitter.
	var section := Vector2(0.121, 0.16)
	var profile := [
		[0.129, -0.08, IRON], [0.126, -0.12, STEEL], [0.113, -0.135, STEEL],
		[0.105, -0.17, IRON],
	]
	for i in 3:
		var z := -0.18 - 0.062 * i
		profile.append_array([[0.119, z, STEEL], [0.119, z - 0.022, CERAMIC],
				[0.101, z - 0.033, IRON], [0.101, z - 0.052, BRONZE, true]])
	profile.append_array([[0.095, -0.39, STEEL], [0.083, -0.63, CERAMIC],
			[0.096, -0.645, STEEL], [0.096, -0.675, IRON], [0.083, -0.69, STEEL],
			[0.083, -0.77, IRON], [0.114, -0.81, STEEL], [0.114, -0.86, IRON],
			[0.106, -0.93, CERAMIC], [0.102, MOUTH_Z, STEEL],
			[0.074, MOUTH_Z, STEEL], [0.069, -0.945, BRONZE],
			[0.052, -0.87, WELL], [0.031, -0.862, BRONZE, true],
			[0.031, -0.80, WELL]])
	for entry: Array in profile:
		var next := Vector2(entry[0], entry[1])
		_turn(st, section, next, entry[2], entry.size() > 3)
		section = next
	st.index()
	return st.commit()
