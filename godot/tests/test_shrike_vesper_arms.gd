## The working panels and the four Shrike seats / Vesper pulse origin, on real hulls in two liveries.
extends SceneTree

const Craft := preload("res://view/craft_model.gd")
const Fleet := preload("res://view/fleet_airframe.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const Livery := preload("res://view/livery.gd")
const VesperRig := preload("res://view/arms/vesper_arms.gd")
const Seat := preload("res://vr/vr_cockpit.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, why: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(why)


func clear_of_windscreen(hull: Node3D, rig: Node3D) -> bool:
	var eye := Seat.EYE - Vector3.UP * Craft.POD_FRAME_UP
	var to_hull := hull.global_transform.affine_inverse()
	for part: MeshInstance3D in rig.find_children("*","MeshInstance3D",true,false):
		if not part.is_visible_in_tree():
			continue
		var pose := to_hull * part.global_transform
		for point in part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var sight: Vector3 = pose * point - eye
			if sight.z < 0 and absf(sight.x) < -sight.z*tan(deg_to_rad(19.0)) and absf(sight.y) < -sight.z*tan(deg_to_rad(14.0)):
				return false
	return true


func painted_area(mesh: Mesh) -> float:
	var faces := mesh.get_faces()
	var area := 0.0
	for i in range(0,faces.size(),3):
		area += (faces[i+1] - faces[i]).cross(faces[i+2] - faces[i]).length() * .5
	return area


func _run() -> void:
	for paint: String in ["factory","cobalt"]:
		Livery.current = paint
		for id: String in ["shrike","vesper"]:
			var hull := MeshInstance3D.new()
			root.add_child(hull)
			hull.transform = Transform3D(Basis(Vector3.UP,.73),Vector3(5.2,1.7,13.5))
			var carrier := hull
			var rig
			if id == "shrike":
				hull.mesh = Craft.pod_hull(true)
				Shrike.dress_pod(hull)
				carrier = hull.get_node("ShrikeStrakes")
			else:
				var fleet := Fleet.new(id)
				fleet.dress_cab(hull,false)
			var original := carrier.mesh
			var paint_mat := carrier.get_active_material(0)
			check(hull.get_node_or_null("Arms") == null, "Unarmed craft eagerly built its armature")
			if id == "shrike":
				rig = Shrike.ensure_arms(hull)
				check(rig == Shrike.ensure_arms(hull), "Shrike armature should be reused")
			else:
				rig = VesperRig.new()
				rig.build(hull)
			check(rig != null and not rig.visible and carrier.mesh == original, "Stowed hull must be exactly the original")
			rig.set_deploy(1.0)
			var first: Array = rig.muzzles()
			check(first.size() == (4 if id == "shrike" else 1), "Every seat or ring has its own socket")
			var triangles: int = carrier.mesh.surface_get_array_index_len(0)
			var area := painted_area(carrier.mesh)
			for hinge in rig.hinges:
				var plate: MeshInstance3D = hinge.get_node("Skin")
				check(plate.get_active_material(0) == paint_mat, "A hatch changed the livery or texture")
				triangles += plate.mesh.surface_get_array_index_len(0)
				area += painted_area(plate.mesh)
			if id == "shrike":
				check(triangles == original.surface_get_array_index_len(0), "Shrike painted triangles were added or lost")
			check(is_equal_approx(area,painted_area(original)), "Painted surface area changed across the hatch cut")
			for t: Transform3D in first:
				var p := hull.to_local(t.origin)
				if id == "shrike":
					check(p.y > .36 and absf(p.x) > 1.1 and p.z < -1.55, "Shrike cassettes should rise over the cockpit cheeks")
				else:
					check(p.y > .18 and p.x > .77 and p.z < -.6, "Vesper pulse cassette should rise above the starboard sill")
				check((-t.basis.z).dot(-hull.global_basis.z) > .999, "Global socket should face forward")
			if id == "shrike":
				check(rig.missile_mesh().get_surface_count() == 1, "Shared projectile needs exactly one surface")
				for slot in 4:
					rig.set_loaded(slot,false)
					check(not rig._rounds[slot].visible,"Round remains in an empty seat")
					rig.set_loaded(slot,true)
				for fraction: float in [.25,.50,.75,1.0]:
					rig.set_deploy(fraction)
					for frame: Transform3D in rig.muzzles():
						var sight := hull.to_local(frame.origin) - (Seat.EYE - Vector3.UP * Craft.POD_FRAME_UP)
						check(sight.y > -.05 and absf(sight.x) < -sight.z * tan(deg_to_rad(49.0)),
								"Shrike round outside the forward peripheral view at %s" % fraction)
			rig.heat = 1.6
			check(rig.heat == 1.0 and rig._glow.emission_energy_multiplier > 4.0, "Heat should clamp and drive the glass")
			rig.set_deploy(.5)
			var half: Array = rig.muzzles()
			rig.set_deploy(-.2)
			check(carrier.mesh == original and not rig.visible, "Disarm restores every original triangle")
			rig.set_deploy(.5)
			check(rig.muzzles() == half, "Halfway pose depends on the travel direction")
			rig.set_deploy(1.5)
			check(rig.muzzles() == first, "Redeployment should reproduce socket transforms")
			if paint == "factory":
				var tris := 0
				var draws := 0
				for part: MeshInstance3D in rig.find_children("*","MeshInstance3D",true,false):
					if part.name != &"Skin" and part.is_visible_in_tree():
						tris += part.mesh.get_faces().size() / 3
						draws += part.mesh.get_surface_count()
				print(id, ": ", tris, " added triangles, ", draws, " hardware surfaces + two original hatch surfaces")
			for fraction: float in [.10,.30,.55,.78,1.0]:
				rig.set_deploy(fraction)
				check(clear_of_windscreen(hull,rig), "Hardware in the central sightline at %s" % fraction)
			rig.free()
			check(carrier.mesh == original, "Removing an armed rig must restore its host")
			hull.free()
	print("SHRIKE VESPER ARMS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(int(failures > 0))
