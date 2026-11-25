## A lazy armature for working panels cut from a single painted hull surface.
## The original mesh draws when closed, including in previously built liveries.
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const SILVER := Color("#b7c5c8")
const GRAPHITE := Color("#253239")
const BRONZE := Color("#c68a56")

var _skin: MeshInstance3D
var _closed: Mesh
var _opened: Mesh
var hinges: Array[Node3D] = []
var _glow: StandardMaterial3D
var _ports: Array[Node3D] = []
var _deployed := -1.0
var heat := 0.0:
	set(value):
		heat = clampf(value, 0.0, 1.0)
		if _glow:
			_glow.emission_energy_multiplier = lerpf(0.65, 4.5, heat)
			_glow.emission = _cool.lerp(_hot, heat)

var _cool: Color
var _hot: Color


func install(hull: Node3D, carrier: MeshInstance3D, scene: PackedScene, pivots: Array[Vector3]) -> void:
	name = &"Arms"
	hull.add_child(self)
	_skin = carrier
	_closed = _skin.mesh
	var material := _skin.get_active_material(0)
	var source := scene.instantiate()
	_opened = (source.get_node("Body") as MeshInstance3D).mesh.duplicate()
	_opened.surface_set_material(0, material)
	for i in 2:
		var hinge := Node3D.new()
		hinge.name = &"PortHatch" if i == 0 else &"StarboardHatch"
		add_child(hinge)
		hinge.position = pivots[i]
		var plate: Mesh = (source.get_node("Port" if i == 0 else "Starboard") as MeshInstance3D).mesh
		piece(hinge, &"Skin", plate, material, -pivots[i])
		hinges.append(hinge)
	source.free()


func pose(value: float) -> bool:
	var next := clampf(value, 0.0, 1.0)
	if next == _deployed:
		return false
	_deployed = next
	visible = next > 0.0
	_skin.mesh = _opened if visible else _closed
	return true


func _exit_tree() -> void:
	if is_instance_valid(_skin) and _skin.mesh == _opened:
		_skin.mesh = _closed


func luminous(cool: Color, hot: Color) -> StandardMaterial3D:
	_cool = cool
	_hot = hot
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = cool.lightened(0.22)
	_glow.emission_enabled = true
	_glow.roughness = 0.30
	heat = heat
	return _glow


static func piece(parent: Node3D, label: StringName, mesh: Mesh, material: Material,
		place := Vector3.ZERO) -> MeshInstance3D:
	var fitting := MeshInstance3D.new()
	fitting.name = label
	fitting.mesh = mesh
	fitting.material_override = material
	fitting.position = place
	parent.add_child(fitting)
	return fitting


func muzzle(parent: Node3D, label: StringName, place: Vector3) -> void:
	var marker := Marker3D.new()
	marker.name = label
	parent.add_child(marker)
	marker.position = place
	_ports.append(marker)


func muzzles() -> Array:
	var poses: Array[Transform3D] = []
	for p in _ports:
		poses.append(p.global_transform.orthonormalized())
	return poses
