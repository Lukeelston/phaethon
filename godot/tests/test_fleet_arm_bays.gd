## Run headless with the flight guard. Exercise actual factory/livery cab meshes, both drawing targets,
## reversibility, launch sockets, thermal material, and the pilot's forward sight through deployment.
extends SceneTree

const Fleet := preload("res://view/fleet_airframe.gd")
const Paint := preload("res://view/livery.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Model := preload("res://view/craft_model.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func clear_forward(arms: Node3D) -> bool:
	var eye := Cockpit.EYE - Vector3.UP * Model.POD_FRAME_UP
	for piece: MeshInstance3D in arms.find_children("*", "MeshInstance3D", true, false):
		if not piece.is_visible_in_tree():
			continue
		var tri := piece.mesh.generate_triangle_mesh()
		var to_piece := piece.global_transform.affine_inverse() * arms.global_transform
		for dx in [-0.085,0.0,0.085]:
			for dy in [-0.065,0.0,0.065]:
				var direction := to_piece.basis * Vector3(dx,dy,-1.0)
				if not tri.intersect_ray(to_piece * eye,direction).is_empty():
					return false
	return true

func triangles(mesh: Mesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		var indices: int = mesh.surface_get_array_index_len(s)
		total += (indices if indices > 0 else mesh.surface_get_array_len(s)) / 3
	return total

func check_orb_launch(fleet, rig) -> void:
	var canopy: TriangleMesh = fleet.part(&"Roof").generate_triangle_mesh()
	var cab: TriangleMesh = rig.open_skin.generate_triangle_mesh()
	var leaves := {}
	for leaf: MeshInstance3D in rig.doors.values():
		leaves[leaf] = leaf.mesh.generate_triangle_mesh()
	for t in [.50, .625, .75, .875, 1.0]:
		rig.set_deploy(t)
		for orb: MeshInstance3D in rig.orbs:
			for offset in [-.032, .032]:
				var eye := Cockpit.EYE - Vector3.UP * Model.POD_FRAME_UP + Vector3.RIGHT * float(offset)
				var ray := orb.position - eye
				var seen := absf(ray.x) < -.6 * ray.z and absf(ray.y) < -.6 * ray.z
				seen = seen and canopy.intersect_segment(eye, orb.position).is_empty()
				seen = seen and cab.intersect_segment(eye, orb.position).is_empty()
				for leaf: MeshInstance3D in rig.doors.values():
					var xf := leaf.transform.affine_inverse()
					seen = seen and leaves[leaf].intersect_segment(xf * eye, xf * orb.position).is_empty()
				check(seen, "%s visible past cab, canopy posts and doors at %.3f, eye %.3f" % [orb.name, t, offset])

func run() -> void:
	Paint.pinned = true
	for id: String in ["orrery","kiln"]:
		for colour: String in [Paint.FACTORY,"cobalt"]:
			Paint.current = colour
			var fleet := Fleet.new(id)
			var flat := MeshInstance3D.new()
			root.add_child(flat)
			fleet.dress_cab(flat, true)
			check(flat.get_node_or_null("Arms") == null, "Arming is lazy in " + id)
			var flat_rig = fleet.ensure_arms()
			check(flat_rig.get_parent() == flat, "Flat hull " + id)
			var hull := MeshInstance3D.new()
			root.add_child(hull)
			hull.transform = Transform3D(Basis(Vector3.UP,.52),Vector3(5,3,-8))
			fleet.dress_cab(hull,false)
			var skin := hull.mesh
			var rig = fleet.ensure_arms()
			check(rig.get_parent() == hull and rig == fleet.ensure_arms() and rig != flat_rig, "VR visible hull and repeated build " + id)
			check(hull.mesh == skin and not rig.visible, "Factory-equivalent closed cab " + id)
			rig.heat = 1.5
			check(rig.heat == 1.0 and is_equal_approx(rig.finish.get_shader_parameter("heat"),1.0), "Heat reaches artwork " + id)
			var initial: Array = rig.muzzles()
			var docks: Array = rig.docks() if id == "orrery" else []
			var poses := []
			for t in [0.22,.48,.72,1.0]:
				rig.set_deploy(t)
				check(clear_forward(rig), "Pilot sight line %s at %.2f" % [id,t])
				poses.append(rig.muzzles())
			check(rig.visible and hull.mesh != skin and hull.mesh.surface_get_material(0) == skin.surface_get_material(0), "Open skin retains the flight's paint " + id)
			for leaf: MeshInstance3D in rig.doors.values():
				check(leaf.material_override == skin.surface_get_material(0), "Moving leaf carries original paint " + id)
			var open: Array = rig.muzzles()
			if colour == Paint.FACTORY:
				var extra := triangles(hull.mesh) - triangles(skin)
				var surfaces := 0
				for m: MeshInstance3D in rig.find_children("*","MeshInstance3D",true,false):
					extra += triangles(m.mesh)
					surfaces += m.mesh.get_surface_count()
				print("%s deployed: %d added full-detail triangles, %d added surfaces; closed: 0/0" % [id,extra,surfaces])
			check(open.size() == (3 if id == "orrery" else 1), "Emitter count " + id)
			for i in open.size():
				check(open[i].origin.distance_to(initial[i].origin) > .3 and open[i].basis.z.is_equal_approx(hull.global_basis.z), "Emitter moves and aims with the hull " + id)
				if id == "orrery":
					check(docks[i].is_equal_approx(rig.docks()[i]) and docks[i].origin.distance_to(initial[i].origin) < .13, "Orb stows in its fixed seat")
			if id == "orrery":
				if colour == Paint.FACTORY:
					check_orb_launch(fleet, rig)
				rig.orbs[1].position += Vector3.RIGHT
				rig.orbs[1].rotate_y(.62)
				var flown: Transform3D = rig.muzzles()[1]
				rig.set_deploy(1.0)
				check(rig.muzzles()[1].is_equal_approx(flown), "Fully armed mount releases the orbs to flight control")
			for step in [2,1,0]:
				rig.set_deploy([.22,.48,.72][step])
				var retraced: Array = rig.muzzles()
				for i in retraced.size():
					check(retraced[i].is_equal_approx(poses[step][i]), "Reversible motion " + id)
			rig.set_deploy(-1)
			check(hull.mesh == skin and not rig.visible, "Disarm restores stock skin " + id)
			flat.free()
			hull.free()
	print("FLEET ARM BAYS %s (%d checks, %d failures)" % ["PASS" if failures==0 else "FAIL",checks,failures])
	quit(int(failures>0))
