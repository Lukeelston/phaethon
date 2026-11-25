## Sweep every exposed piece of the Vesper carriage through its real shoulder pocket.
## The shell, door leaves, backings, well liner and trunnion sleeves obstruct solid parts.
extends SceneTree

const Fleet := preload("res://view/fleet_airframe.gd")


func _initialize() -> void:
	run.call_deferred()


func unique_edges(mesh: Mesh) -> Array:
	var points := mesh.get_faces()
	var edges := {}
	for i in points.size():
		var a := points[i]
		var b := points[i-i%3+(i+1)%3]
		if a != b:
			edges[[a,b] if a < b else [b,a]] = true
	return edges.keys()


func run() -> void:
	var hull := MeshInstance3D.new()
	root.add_child(hull)
	var fleet := Fleet.new("vesper")
	fleet.dress_cab(hull,false)
	var rig = fleet.ensure_arms(hull)
	rig.set_deploy(.001)
	if hull.find_child("SillCore",true,false) != null:
		push_error("The removed sill core was attached to the live armature")
		hull.free()
		quit(1)
		return
	var obstacles := {}
	for fixture: MeshInstance3D in [hull,rig.get_node("LiftWell"),rig.get_node("LiftTrunnion/RamSleeves")]:
		obstacles[fixture] = fixture.mesh.generate_triangle_mesh()
	for hinge: Node3D in rig.hinges:
		for panel: MeshInstance3D in hinge.get_children():
			obstacles[panel] = panel.mesh.generate_triangle_mesh()
	var edges_by_part := {}
	for part: MeshInstance3D in rig.get_node("PulseCarriage").find_children("*","MeshInstance3D",true,false):
		edges_by_part[part] = unique_edges(part.mesh)

	for step in range(1,101):
		rig.set_deploy(step/100.0)
		for part: MeshInstance3D in edges_by_part:
			for fixture: MeshInstance3D in obstacles:
				var pose := fixture.global_transform.affine_inverse()*part.global_transform
				var shell: TriangleMesh = obstacles[fixture]
				for edge in edges_by_part[part]:
					if not shell.intersect_segment(pose*edge[0],pose*edge[1]).is_empty():
						push_error("%s crosses %s at %d%% deployment" % [part.get_path(),fixture.get_path(),step])
						hull.free()
						quit(1)
						return
	hull.free()
	print("VESPER PULSE CASSETTE PASS (100 poses clear of cab, hatches, backings, well and ram sleeves)")
	quit()
