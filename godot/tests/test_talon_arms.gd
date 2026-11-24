## Both physical breeches, paint, mounting frames, reversibility and the pilot's forward cone.
extends SceneTree

const Model := preload("res://view/craft_model.gd")
const Talon := preload("res://view/talon_airframe.gd")
const Seat := preload("res://vr/vr_cockpit.gd")
const Arms := preload("res://view/arms/talon_arms.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(reason)


func _run() -> void:
	var hull := MeshInstance3D.new()
	root.add_child(hull)
	Talon.paint = "cobalt"
	hull.mesh = Model.pod_hull(false, true)
	var stock := hull.mesh
	var neighbour := MeshInstance3D.new()
	neighbour.mesh = stock
	root.add_child(neighbour)
	hull.transform = Transform3D(Basis.from_euler(Vector3(0.21, -0.76, 0.42)), Vector3(190, 3, -26))
	_check(hull.get_child_count() == 0, "A never-armed Talon has no separate weapon")
	var arms: Arms = Talon.wing_arms(hull)
	_check(arms == Talon.wing_arms(hull) and arms.get_parent() == hull, "Build is lazy and unique to this hull")
	_check(hull.mesh == stock and not arms.visible, "Stowed guns use the original sealed wing")
	_check(arms.upper.mesh.surface_get_material(0) == hull.mesh.surface_get_material(8), "Shutters match the wing finish")
	var colors: PackedColorArray = arms.upper.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var trim: Color = Talon.palette("cobalt").trim
	var painted := false
	for c in colors:
		if maxf(absf(c.r - trim.r), maxf(absf(c.g - trim.g), absf(c.b - trim.b))) < 0.005:
			painted = true
	_check(painted, "Shutters use this hull's painted leading strip")
	var stowed := arms.muzzles()
	arms.set_deploy(0.54)
	var middle := arms.muzzles()
	_check(arms.visible and hull.mesh.has_meta(&"talon_stock") and neighbour.mesh == stock, "Open the pilot's wing only")
	arms.set_deploy(1.4)
	var deployed := arms.muzzles()
	_check(arms.deploy == 1.0 and deployed.size() == 2, "Two deployed wing-root guns")
	for i in 2:
		var p: Vector3 = hull.to_local(deployed[i].origin)
		var side := -1.0 if i == 0 else 1.0
		_check(side * p.x > Talon.GUN_SPAN.x and side * p.x < Talon.GUN_SPAN.y, "Bore sits inside its own wing opening")
		_check((-deployed[i].basis.z).is_equal_approx(-hull.global_basis.z), "Muzzle -Z follows rolled and yawed hull")
		_check(is_equal_approx(stowed[i].origin.distance_to(deployed[i].origin), Arms.TRAVEL), "Barrel slides its full travel")
		var eye := Seat.EYE - Vector3.UP * Model.POD_FRAME_UP
		var nearest_azimuth := rad_to_deg(atan2(absf(p.x) - 0.09, eye.z - p.z))
		_check(nearest_azimuth > 30 and p.y + 0.09 < eye.y, "Forward 60-degree sight cone and horizon clear at full deployment")
	_check(not arms.upper.visible and not arms.lower.visible, "Shutters fully withdrawn at the deployed stop")
	arms.heat = 2.0
	_check(arms.heat == 1.0 and arms.throats.emission.is_equal_approx(Arms.HOT), "Both throats follow normalized heat")
	arms.heat = -1
	_check(arms.heat == 0.0 and arms.throats.emission.is_equal_approx(Arms.COOL), "Both throats cool")
	arms.set_deploy(0.54)
	_check(arms.muzzles()[0].is_equal_approx(middle[0]), "Deployment reverses through the same geometry")
	Model.set_nose_closed(not Model.nose_closed, root)
	_check(hull.mesh.has_meta(&"talon_stock") and not neighbour.mesh.has_meta(&"talon_stock"), "Opening the nose preserves the armed wing on its owner only")
	arms.set_deploy(-0.1)
	_check(not arms.visible and not hull.mesh.has_meta(&"talon_stock") and arms.muzzles()[0].is_equal_approx(stowed[0]), "Full stow restores the appropriate stock shell and original mouth position")
	var triangles := 0
	var surfaces := 0
	for part: MeshInstance3D in [arms.upper, arms.lower, arms.barrels]:
		surfaces += part.mesh.get_surface_count()
		for index in part.mesh.get_surface_count():
			triangles += int(part.mesh.surface_get_array_index_len(index) / 3.0)
	print("TALON ARMS geometry: %d triangles, %d moving surfaces, 2 surfaces visible fully open." % [triangles, surfaces])
	print("TALON ARMS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
