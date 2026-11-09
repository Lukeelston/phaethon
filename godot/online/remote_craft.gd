## A remote player's pod and engine transforms, never interpreted using the local road.
extends Node3D
const Craft := preload("res://view/craft_model.gd")
const Kit := preload("res://view/mesh_kit.gd")
var bodies: Array[Node3D] = [] # pod, left engine, right engine
var cables: Array[MeshInstance3D] = []
var plumes: Array[MeshInstance3D] = []
var label: Label3D

func build(pilot_name: String) -> void:
	var finish := Kit.polished(0.55, 0.38)
	finish.albedo_color = Color(0.2, 0.85, 0.95)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.3, 0.9, 1.0)
	for i in 3:
		var body := MeshInstance3D.new()
		body.mesh = Craft.pod_hull() if i == 0 else Craft._engine_body(-1.0 if i == 1 else 1.0)
		body.material_override = finish
		add_child(body)
		bodies.append(body)
		if i > 0:
			var lights := MeshInstance3D.new()
			lights.mesh = Craft._engine_lights(-1.0 if i == 1 else 1.0)
			lights.material_override = Kit.vertex_colors(true)
			body.add_child(lights)
			var plume := MeshInstance3D.new()
			plume.mesh = Kit.box(Vector3(1.8, 0.35, 1.0))
			plume.material_override = glow
			body.add_child(plume)
			plumes.append(plume)
			var cable := MeshInstance3D.new()
			cable.mesh = Kit.box(Vector3(0.10, 0.10, 1.0))
			cable.material_override = glow
			add_child(cable)
			cables.append(cable)
	label = Label3D.new()
	label.text = pilot_name
	label.font_size = 40
	label.pixel_size = 0.04
	label.modulate = Color(0.4, 0.95, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)

func apply_pose(pose: PackedFloat64Array, origin_x: float, origin_y: float) -> void:
	for i in 3:
		var start := 2 + i * 7
		# Subtract in scalar doubles BEFORE constructing the float32 Vector3.
		var p := Vector3(pose[start] - origin_x, pose[start+1], pose[start+2] + origin_y)
		var q := Quaternion(pose[start+3], pose[start+4], pose[start+5], pose[start+6]).normalized()
		bodies[i].transform = Transform3D(Basis(q), p)
	label.position = bodies[0].position + Vector3(0, 6, 0)
	var distance := bodies[0].position.length()
	label.pixel_size = clampf(distance * 0.0008, 0.04, 15.0)
	for i in 2:
		var push: float = pose[23 + i]
		var length := 1.0 + push * (9.0 if pose[25] > 0 else 2.0)
		plumes[i].visible = push > 0.02
		plumes[i].scale.z = length
		plumes[i].position.z = 4.0 + length / 2.0
		var a: Vector3 = bodies[i+1].transform * Craft.ENGINE_EYE
		var b: Vector3 = bodies[0].transform * Vector3(-0.7 if i == 0 else 0.7, Craft.POD_EYE_H, -2.0)
		var span := a-b
		if span.length() > 0.01:
			var up := bodies[0].basis.y
			if absf(span.normalized().dot(up)) > 0.99: up = bodies[0].basis.x
			cables[i].transform = Transform3D(Basis.looking_at(span, up) * Basis.from_scale(Vector3(1, 1, span.length())), (a+b)*0.5)
