## A workshop fixture. Use the production bodywork and its installed fittings, pose them
## once on the service stands and leave the flight simulation and exhaust switched off.
extends Node3D

signal engine_stage_changed(engine: int, stage: String)

const Model := preload("res://view/craft_model.gd")
const Livery := preload("res://view/livery.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Flight := preload("res://sim/craft_sim.gd")
const Seat := preload("res://garage/garage_seat.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Tow := preload("res://view/tow_link.gd")
const SHELL_HEIGHT := .72
const ENGINE_HEIGHT := 1.56
const HULL_REACH := 1.30      # m out to either side: the Talon's hull proper (its wings reach 2.92; the Phaethon's hull 1.19)

var sim: Dictionary
var model: Model
var paint := Livery.FACTORY
var engine_centers: Array[Vector3] = []
var _colliders: Array[StaticBody3D] = []


## Build it again in place, as `id` in `finish` (a bay's paint changed): the airframe and its colliders go and come
## back; this node, its signals and whatever else stands on it (a run-up, a cab: the garage's) stay.
func rebuild(id: String, finish := Livery.FACTORY) -> void:
	if model != null:
		model.free()
		model = null
	for body in _colliders:
		body.free()
	_colliders.clear()
	engine_centers.clear()
	build(id, finish)


func build(id: String, finish := Livery.FACTORY) -> void:
	paint = finish
	var spec := Flight.DEFAULTS.merged(Pilot.tuning(id), true)
	spec["vehicle"] = id
	sim = {"P": spec, "traits": Pilot.traits(id)}      # (its traits too: the armed craft's gun mount reads its weapon's row)
	model = Model.new()
	model.name = "ParkedModel"
	model.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(model)
	# (the Talon's plating is built in its own palette, Model.Talon.paint, as its flight sets it: put back after)
	var talon_paint: String = Model.Talon.paint
	if id == Pilot.TALON:
		Model.Talon.paint = paint
	Livery.build_in(paint, model.build.bind(self))
	Model.Talon.paint = talon_paint
	model.pod.name = "DisplayCockpit"
	model.pod.transform = Seat.pod_pose() * Transform3D(Basis.IDENTITY, Vector3.UP * Model.POD_FRAME_UP)
	model.canopy.get_node("field").hide()
	model.binder_arc.hide()
	for lamp in model.light_meshes:
		lamp.hide()
	if model.fleet:
		var coaming: MeshInstance3D = model.fleet.mount(model.pod, &"Coaming", &"CockpitRim")
		coaming.position.y = -Model.POD_FRAME_UP
	elif Pilot.phaethon_based(id):      # (the Phaethon's seat, in the Talon too)
		var leather := Finish.tinted("leather", Color("#624534"))
		var back := _mesh(model.pod, Kit.rounded_box(Vector3(.62,.78,.15),4,9), leather)
		back.position = Vector3(0, .54 - Model.POD_FRAME_UP, 1.10)
		back.rotation.x = -.12
		var pan := _mesh(model.pod, Kit.rounded_box(Vector3(.59,.13,.51),4,9), leather)
		pan.position = Vector3(0,.145 - Model.POD_FRAME_UP,.86)
	# This is the same taut spacing used by the flight's spawn, before its first step.
	var half_gap: float = spec.engineGap * .5
	var half_pin: float = spec.podAnchorW * spec.podWidth * .5
	var lead: float = sqrt(spec.cableLen ** 2 - (half_gap - half_pin) ** 2) + (spec.engineLen + spec.podLen) * .5
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var engine: Node3D = model.engines[k]
		engine.position = Vector3(side * half_gap, ENGINE_HEIGHT - SHELL_HEIGHT, -lead)
		engine_centers.append(engine.position)
		model.flames[k].hide()
		model.strobes[k].hide()
		model.nozzle_lights[k].hide()
		model.binder_mats[k].albedo_color = Color("#343b42")
		var eye := engine.transform * Model.ENGINE_EYE
		var post := model.pod.transform * Vector3(side * half_pin, Model.POD_EYE_H, -spec.podLen * .5 - .10)
		var linkage := Tow.solve(eye, Basis.IDENTITY, post, model.pod.basis, model.link_rod)
		for j in 4:
			model.link_parts[k][j].transform = linkage[["swivel","barrel","rod","yoke"][j]]
		model.link_boots[k].scale.z = linkage.boot / Tow.BOOT
		var bar := BoxShape3D.new()
		bar.size = Vector3(.13, eye.distance_to(post), .13)
		_collider("TowLink", bar, Transform3D(Basis(Quaternion(Vector3.UP,(eye-post).normalized())),(post+eye)*.5))
		var fairing := engine.get_child(0) as MeshInstance3D
		_bounds_collider("Engine", fairing.mesh.get_aabb(), engine.transform)
	model._place_fin_batches()
	_bounds_collider("Cockpit", _hull_bounds(model.pod.mesh) if id == Pilot.TALON else model.pod.mesh.get_aabb(), model.pod.transform)
	# All six silhouettes remain in the hall. Fin screws, cold nozzle vanes, brake
	# leaves and thin trim only draw at distances where a pilot can discern them.
	for piece: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if piece.mesh and piece.get_aabb().size.length() < 1.50:
			piece.visibility_range_end = 19.0
			piece.visibility_range_end_margin = 1.5
	model.view = null


## The Talon's pod's bounds for its collider: its hull proper. Its wings reach 2.9 m out, past the Phaethon's bay's
## gate (2.45 m: the bay holds either body), so they are left out of it; a pilot at that gate is not put inside them.
func _hull_bounds(mesh: Mesh) -> AABB:
	var hull := AABB()
	var first := true
	for s in mesh.get_surface_count():
		for p: Vector3 in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if absf(p.x) > HULL_REACH:
				continue
			if first:
				hull = AABB(p, Vector3.ZERO)
				first = false
			else:
				hull = hull.expand(p)
	return hull


func _mat(colour: Color, unshaded := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _mesh(parent: Node3D, shape: Mesh, material: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = shape
	piece.material_override = material
	parent.add_child(piece)
	return piece


func _bounds_collider(label: String, bounds: AABB, frame: Transform3D) -> void:
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	_collider(label, shape, frame * Transform3D(Basis.IDENTITY, bounds.get_center()))


func _collider(label: String, shape: Shape3D, frame: Transform3D) -> void:
	var body := StaticBody3D.new()
	body.name = label + "Collision"
	add_child(body, true)
	_colliders.append(body)
	var part := CollisionShape3D.new()
	part.shape = shape
	part.transform = frame
	body.add_child(part)
