## Godot --headless --path godot -s res://tests/test_raid_flyer_art.gd
extends SceneTree

const Art := preload("res://view/raid_flyer_art.gd")
var failed := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	check(not ResourceLoader.has_cached(Art.DRONE_PATH) and not ResourceLoader.has_cached(Art.GUNSHIP_PATH),
			"Preloading the art API keeps both flyer scenes out of the off-state resource cache")
	var ship: Node3D
	if "--gunship-first" in OS.get_cmdline_user_args():
		ship = Art.gunship()
		check(ResourceLoader.has_cached(Art.GUNSHIP_PATH) and not ResourceLoader.has_cached(Art.DRONE_PATH),
				"Spawning only the gunship leaves the drone scene unloaded")
	var drones := Art.drone_batch()
	if ship == null:
		check(ResourceLoader.has_cached(Art.DRONE_PATH) and not ResourceLoader.has_cached(Art.GUNSHIP_PATH),
				"Spawning only drones leaves the gunship scene unloaded")
		ship = Art.gunship()
	root.add_child(drones)
	var mm := drones.multimesh
	check(mm.instance_count == 10 and mm.visible_instance_count == 0, "Batch starts empty with space for the whole swarm")
	for i in 10:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(i * 6.0, 0, 0)))
	mm.visible_instance_count = 10
	check(drones.material_override == Art.FINISH and mm.mesh.get_surface_count() == 1, "All drones share one atlas surface")
	check(mm.mesh.get_aabb().size.x > 5 and mm.mesh.get_aabb().size.x < 7, "Drone width is in metres")
	root.add_child(ship)
	var pivot := ship.get_node("TurretPivot") as Node3D
	var cradle := pivot.get_node("Cradle") as Node3D
	var nozzle := cradle.get_node("Muzzle") as Node3D
	var hull := ship.get_node("Body") as MeshInstance3D
	check(hull.mesh.get_aabb().size.z > 19, "Gunship is larger than its escort")
	var triangles := 0
	for part: MeshInstance3D in [hull, pivot, cradle]:
		check(part.mesh.get_surface_count() == 1 and part.material_override == Art.FINISH, "Gunship uses a single atlas surface for each rigid part")
		triangles += part.mesh.surface_get_array_index_len(0) / 3
	var home := nozzle.global_transform
	pivot.rotation.y = PI * 0.5
	cradle.rotation.x = -0.40
	check(home.origin.distance_to(nozzle.global_position) > 2, "Ventral bearing turns the entire cradle")
	var forward := -nozzle.global_basis.z
	check(forward.dot(Vector3.LEFT) > 0.90 and forward.y < -0.30, "Yaw and pitch reorient the muzzle without turning the hull")
	check(hull.transform == Transform3D.IDENTITY and not ship.is_processing(), "Inactive art has no frame callback")
	print("RAID FLYER ART %s: %d triangles per drone, %d per gunship, %d failures" % [
			"PASS" if failed == 0 else "FAIL", mm.mesh.surface_get_array_index_len(0) / 3, triangles, failed])
	quit(int(failed != 0))
