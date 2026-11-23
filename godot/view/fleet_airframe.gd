## One flight owns its material and holds only the selected airframe's meshes.
extends RefCounted

const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Kit := preload("res://view/mesh_kit.gd")
const FINISH := preload("res://view/fleet_finish.gdshader")
const ASSET_DIR := "res://art/pilot_fleet/"
const STROBES := {"orrery": Vector3(1.315, 0.24, 1.04), "kiln": Vector3(1.02, 0.54, 2.34), "vesper": Vector3(2.22, 0.58, 1.83)}
const CAB_HINGES := {"orrery": Vector3(1.295, -0.24, 0.77), "kiln": Vector3(1.396, -0.17, 0.70), "vesper": Vector3(1.252, -0.12, 0.69)}

var id: String
var parts := {}


static func supports(vehicle: String) -> bool:
	return STROBES.has(vehicle)


func _init(vehicle: String) -> void:
	id = vehicle
	var source := (load(ASSET_DIR + id + ".glb") as PackedScene).instantiate()
	var finish := load(ASSET_DIR + id + ".tres") as StandardMaterial3D
	var paint: Material = finish
	if Livery.accent() != null:
		var custom := ShaderMaterial.new()
		custom.shader = FINISH
		custom.set_shader_parameter("enamel", Livery.coat("paint"))
		custom.set_shader_parameter("albedo_map", finish.albedo_texture)
		custom.set_shader_parameter("normal_map", finish.normal_texture)
		custom.set_shader_parameter("orm_map", finish.roughness_texture)
		paint = custom
	for node: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		# The import is shared between flights. Only this flight owns the surface assignment.
		var own := node.mesh.duplicate() as ArrayMesh
		own.surface_set_material(0, paint)
		parts[node.name] = own
	source.free()


func part(key: StringName) -> ArrayMesh:
	return parts[key]


func mount(parent: Node3D, key: StringName, node_name: StringName) -> MeshInstance3D:
	var fitting := MeshInstance3D.new()
	fitting.name = node_name
	fitting.mesh = part(key)
	parent.add_child(fitting)
	return fitting


func dress_cab(hull: MeshInstance3D, closed: bool) -> void:
	hull.mesh = part(&"Cab")
	mount(hull, &"Seat", &"FleetSeat")
	var bonnet := mount(hull, &"Bonnet", &"ServiceBonnet")
	bonnet.set_meta(&"service_bonnet", true)
	bonnet.visible = closed


func strobe_at(side: float) -> Vector3:
	return STROBES[id] * Vector3(side, 1, 1)


func lights(side: float) -> ArrayMesh:
	var nav := Color("#f04638") if side < 0 else Color("#3be8a1")
	return Kit.compound([
		[Kit.ball(0.065, 12), Kit.at(strobe_at(side) + Vector3(0, 0, 0.08)), nav],
		[Kit.box(Vector3(0.18, 0.032, 0.045)), Kit.at(Vector3(side * 0.78, 0.36, 3.78)), Color("#f0583b")],
	])


func rotor_centres() -> Array:
	match id:
		Pilot.ORRERY: return [Vector3(0, 0.19, -3.57)]
		Pilot.KILN: return [Vector3(-0.47, 0.0, -3.98), Vector3(0.47, 0.0, -3.98)]
		_: return [Vector3(-0.80, 0.04, -4.29), Vector3(0.80, 0.04, -4.29)]


func fit_canopy(root: Node3D) -> void:
	var roof := mount(root, &"Roof", &"roof")
	var pane := mount(root, &"Glass", &"roof_glass")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.42, 0.67, 0.72, 0.069) if id == Pilot.ORRERY else Color(0.64, 0.66, 0.74, 0.065)
	glass.roughness = 0.09
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	pane.material_override = glass
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	roof.add_to_group("exterior")
	pane.add_to_group("exterior")
