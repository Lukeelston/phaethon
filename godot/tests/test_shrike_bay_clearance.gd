## Sweep the complete cassette and its hoist through the actual machined cheek on both nose variants.
extends SceneTree

const Craft := preload("res://view/craft_model.gd")
const Shrike := preload("res://view/shrike_airframe.gd")

func _initialize() -> void:
	run.call_deferred()


func edges(mesh: Mesh) -> PackedVector3Array:
	var vertices := mesh.get_faces()
	var unique := {}
	for i in vertices.size():
		var a := vertices[i]
		var b := vertices[i-i%3+(i+1)%3]
		if a != b:
			unique[[a,b] if a < b else [b,a]] = true
	var result := PackedVector3Array()
	for edge in unique:
		result.append(edge[0])
		result.append(edge[1])
	return result


func sweep(closed_nose: bool) -> bool:
	Craft.nose_closed = closed_nose
	var pod := MeshInstance3D.new()
	root.add_child(pod)
	pod.mesh = Craft.pod_hull(true)
	var stowed := pod.mesh
	Shrike.dress_pod(pod)
	var rig := Shrike.ensure_arms(pod)
	rig.set_deploy(.001)
	var cheek: MeshInstance3D = pod.get_node("ShrikeStrakes")
	var fixtures := {}
	for obstacle: MeshInstance3D in [pod,cheek,rig.get_node("CrossShaftBearings")]:
		fixtures[obstacle] = obstacle.mesh.generate_triangle_mesh()
	var moving_edges := {}
	for side in 2:
		for leaf: MeshInstance3D in rig.hinges[side].get_children():
			fixtures[leaf] = leaf.mesh.generate_triangle_mesh()
		var tray: Node3D = rig._trays[side]
		for part: MeshInstance3D in [tray,tray.get_node("Round1"),tray.get_node("Round2"),
				rig._rockers[side],rig._sleeves[side],rig._slides[side]]:
			moving_edges[part] = edges(part.mesh)
	var steps := PackedFloat32Array()
	for i in 101:
		steps.append(i / 1000.0)
	for i in range(11,101):
		steps.append(i / 100.0)
	for t in steps:
		rig.set_deploy(t)
		for part: MeshInstance3D in moving_edges:
			var points: PackedVector3Array = moving_edges[part]
			for obstacle: MeshInstance3D in fixtures:
				var frame := obstacle.global_transform.affine_inverse() * part.global_transform
				var solid: TriangleMesh = fixtures[obstacle]
				for i in range(0,points.size(),2):
					if not solid.intersect_segment(frame * points[i],frame * points[i+1]).is_empty():
						push_error("%s crosses %s at %.3f, closed nose %s" % [part.get_path(),obstacle.get_path(),t,closed_nose])
						pod.free()
						return false
	rig.set_deploy(0)
	if pod.mesh != stowed:
		push_error("Disarming failed to restore the exact stowed pod")
		pod.free()
		return false
	rig.set_deploy(1)
	Craft.set_nose_closed(not closed_nose,root)
	var changed_nose := Craft.pod_hull(true)
	if pod.mesh == changed_nose:
		push_error("Changing nose style closed the deployed cheek recess")
		pod.free()
		return false
	rig.free()
	if pod.mesh != changed_nose:
		push_error("Removing the rig failed to restore the selected nose")
		pod.free()
		return false
	pod.free()
	return true


func run() -> void:
	for closed: bool in [false,true]:
		if not sweep(closed):
			quit(1)
			return
	print("SHRIKE CHEEK CLEARANCE PASS (382 poses, both cassettes, both nose variants)")
	quit()
