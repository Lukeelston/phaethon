## A pair of retracting arc projectors in the webs between the Phaethon's intake bells.
## craft.phaethon_arms() supplies this rig on first arm in both the flat and the VR view.
## The two engines move independently; all poses, including the mouths, are engine-local.
extends RefCounted

const Livery := preload("res://view/livery.gd")
const Finishes := preload("res://view/craft_materials.gd")
const Metal := preload("res://view/arms/phaethon_barrel.gdshader")
const FACE := Vector3(0, 0.255, -4.008)
const DOOR_RADIUS := 0.145
const MOUTH_Z := -0.96
const STOW_Z := 1.035
const RIM_STEPS := 16
const IRON := Color(0.16, 0.19, 0.22)
const STEEL := Color(0.47, 0.53, 0.56)
const BRONZE := Color(0.47, 0.27, 0.12)
const WELL := Color(0.025, 0.032, 0.038)
const CERAMIC := Color(0.30, 0.34, 0.37)

var _doors: Array[MeshInstance3D] = []
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
	var socket := _socket()
	var leaf := _shutter()
	var barrel := _projector()
	for engine in engines:
		var bay := _mount(engine, "PhaethonNoseBay", socket, Finishes.machined())
		bay.position = FACE
		for sign_y: float in [1.0, -1.0]:
			var door := _mount(bay, "UpperIris" if sign_y > 0 else "LowerIris", leaf, Finishes.painted_metal())
			door.position.y = sign_y * DOOR_RADIUS
			door.rotation.z = 0.0 if sign_y > 0 else PI
			_doors.append(door)
		var tube := _mount(bay, "ArcProjector", barrel, _metal)
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
	# The enamel leaves fold aft into the cheeks first. The tube only crosses their
	# plane once the doors are open. Reversing t gives precisely the same path back.
	var angle := -0.5 * PI * smoothstep(0.0, 0.35, at)
	var extension := smoothstep(0.30, 1.0, at)
	for i in _doors.size():
		var base := Basis.IDENTITY if i % 2 == 0 else Basis(Vector3.BACK, PI)
		_doors[i].basis = base * Basis(Vector3.RIGHT, angle)
	for tube in _barrels:
		tube.position.z = lerpf(STOW_Z, 0.0, extension)
		tube.visible = extension > 0.0


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


static func _socket() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_turn(st, Vector2(0.152, 0.145), Vector2(0.165, 0.024), IRON)
	_turn(st, Vector2(0.165, 0.024), Vector2(0.159, 0), STEEL)
	_turn(st, Vector2(0.159, 0), Vector2(0.147, 0), STEEL)
	_turn(st, Vector2(0.147, 0), Vector2(0.139, 0.12), WELL)
	st.index()
	return st.commit()


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


## The upper cover, modelled about its top hinge. The opposite cover reuses it
## turned 180 degrees. A small inset at the straight edge leaves a split line.
static func _shutter() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coat := Livery.coat("engine")
	var centre := Vector3(0, -DOOR_RADIUS + 0.002, 0.001)
	for i in RIM_STEPS / 2:
		var a := PI * i / (RIM_STEPS / 2)
		var b := PI * (i + 1) / (RIM_STEPS / 2)
		var va := Vector3(cos(a), sin(a), 0)
		var vb := Vector3(cos(b), sin(b), 0)
		var inner_a := centre + 0.137 * va
		var inner_b := centre + 0.137 * vb
		var outer_a := centre + 0.143 * va + Vector3.BACK * 0.004
		var outer_b := centre + 0.143 * vb + Vector3.BACK * 0.004
		_facet(st, centre, inner_a, inner_b, coat)
		_facet(st, inner_a, outer_a, outer_b, coat)
		_facet(st, inner_a, outer_b, inner_b, coat)
		_facet(st, outer_a, outer_a + Vector3.BACK * 0.009, outer_b, IRON)
		_facet(st, outer_b, outer_a + Vector3.BACK * 0.009, outer_b + Vector3.BACK * 0.009, IRON)
		_facet(st, centre + Vector3.BACK * 0.013, outer_b + Vector3.BACK * 0.009, outer_a + Vector3.BACK * 0.009, IRON)
	var left := centre + Vector3.LEFT * 0.137
	var right := centre + Vector3.RIGHT * 0.137
	_facet(st, left, right + Vector3.BACK * 0.013, right, IRON)
	_facet(st, left, left + Vector3.BACK * 0.013, right + Vector3.BACK * 0.013, IRON)
	st.index()
	return st.commit()


static func _facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for vertex in [a, b, c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(vertex)
