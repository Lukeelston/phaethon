## Shrike RS bodywork. Shared static meshes use the same pivots as the moving
## brakes, rotors and nozzle. Forward is local -Z, and out points away from the pilot.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const PETROL := Color("#12666a")
const IVORY := Color("#f1e5c9")
const COPPER := Color("#e49749")
const CARBON := Color("#243236")
const ALLOY := Color("#9caead")
static var meshes: Dictionary
static var pod_paint: StandardMaterial3D
static var fittings: ShaderMaterial


## Only a selected Shrike loads these meshes and maps. Both engines, all four
## fans, the moving leaves and the pilot shell share one atlas and material.
static func part(id: StringName) -> Mesh:
	if meshes.is_empty():
		var scene := (load("res://art/shrike/bodywork.glb") as PackedScene).instantiate()
		var finish := load("res://art/shrike/enamel.tres") as StandardMaterial3D
		for node in scene.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = node.mesh
			mesh.surface_set_material(0, finish)
			meshes[node.name] = mesh
		scene.free()
	return meshes[id]


static func fin_tip(out: float) -> Vector3:
	return Vector3(out * (0.77 + 1.62*sin(0.76)), 0.25 + 1.62*cos(0.76), 1.98)


static func lights(out: float) -> ArrayMesh:
	return Kit.compound([
		[Kit.ball(0.057, 10), Kit.at(fin_tip(out) + Vector3(-0.08*out, -0.09, 0.09)),
			Color("#ef413b") if out < 0 else Color("#49dc91")],
		[Kit.box(Vector3(0.44, 0.04, 0.035)), Kit.at(Vector3(0, 0.39, 4.0)), Color("#e84432")],
		[Kit.box(Vector3(0.09, 0.045, 0.08)), Kit.at(Vector3(out * 0.81, -0.39, -3.92)), IVORY]])


static func dress_pod(hull: MeshInstance3D) -> void:
	if pod_paint == null:
		pod_paint = Finish.painted_metal().duplicate()
		pod_paint.vertex_color_use_as_albedo = false
		pod_paint.albedo_color = PETROL
		pod_paint.clearcoat_enabled = true
		pod_paint.clearcoat = 0.8
		fittings = ShaderMaterial.new()
		fittings.shader = preload("res://view/shrike_trim.gdshader")
	hull.set_surface_override_material(3, fittings)
	hull.set_surface_override_material(5, pod_paint)
	hull.set_surface_override_material(6, fittings)
	var trim := MeshInstance3D.new()
	trim.name = "ShrikeStrakes"
	trim.add_to_group("exterior")
	trim.mesh = part(&"PodStrakes")
	hull.add_child(trim)


static func dress_coaming(coaming: MeshInstance3D, hd: bool) -> ShaderMaterial:
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

	# Recessed load windows on either side of the badge follow the coaming's arc.
	var bars := SurfaceTool.new()
	bars.begin(Mesh.PRIMITIVE_TRIANGLES)
	var housings := []
	for side in [-1.0, 1.0]:
		var mount := Kit.at(Vector3(side*0.180, 0.578, -0.888), Vector3(0, -side*0.34, 0))
		housings.append([Finish.beveled_plate(Vector3(0.139,0.048,0.012),0.003), mount, CARBON])
		var legend := Label3D.new()
		legend.text = "L  TOW" if side < 0.0 else "TOW  R"
		legend.font_size = 40
		legend.pixel_size = 0.00030
		legend.outline_size = 0
		legend.modulate = IVORY
		legend.transform = mount * Transform3D(Basis.IDENTITY, Vector3(0,-0.011,0.008))
		legend.add_to_group("exterior")
		coaming.add_child(legend)
		for corner in [0,2,1,0,3,2]:
			var x := -0.063 if corner in [0,3] else 0.063
			var y := 0.001 if corner in [0,1] else 0.016
			bars.set_uv(Vector2(0.5 + side*x/0.126, 0.25 if side < 0.0 else 0.75))
			bars.set_normal(mount.basis.z)
			bars.add_vertex(mount * Vector3(x,y,0.007))
	var surround := MeshInstance3D.new()
	surround.mesh = Kit.compound(housings)
	surround.material_override = Finish.powder_coat()
	surround.add_to_group("exterior")
	coaming.add_child(surround)
	var glass := MeshInstance3D.new()
	glass.name = "TowLoad"
	glass.mesh = bars.commit()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.add_to_group("exterior")
	var meter := ShaderMaterial.new()
	meter.shader = preload("res://view/shrike_tow_meter.gdshader")
	glass.material_override = meter
	coaming.add_child(glass)
	return meter
