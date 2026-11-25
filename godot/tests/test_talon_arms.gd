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


## The rig on this hull, built on it the first time it is asked for. (A flight's craft builds its own with the craft,
## view/craft_model.gd; here a bare hull stands in for it: build() takes a hull for a preview.)
static func _rig(hull: MeshInstance3D) -> Arms:
	var rig := hull.get_node_or_null("TalonArms") as Arms
	if rig == null:
		rig = Arms.new()
		rig.build(hull)
	return rig


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
	var arms: Arms = _rig(hull)
	_check(arms == _rig(hull) and arms.get_parent() == hull, "Build is lazy and unique to this hull")
	_check(hull.mesh == stock and not arms.visible and not stock.has_meta(&"talon_bays"), "Never brought out, the guns leave the stock wing as it was")
	var tris := {}
	for bays: String in ["", "open", "sealed"]:
		var skin: ArrayMesh = Talon.with_bays(stock, bays)
		tris[bays] = skin.surface_get_array_index_len(skin.surface_find_by_name(Talon.SURFACE)) / 3
	_check(Talon.with_bays(stock, "") == stock and tris[""] < tris["open"] and tris["open"] < tris["sealed"] and Talon.with_bays(stock, "sealed") == Talon.with_bays(Talon.with_gun_bays(stock), "sealed"),
		"The stock skin has no bays, the open one the sills, the sealed one the shut carriages too, each made once (%s)" % [tris])
	_check(arms.carriage.material_override == hull.mesh.surface_get_material(8), "Carriage shells match the wing finish")
	var colors: PackedColorArray = arms.carriage.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var trim: Color = Talon.palette("cobalt").trim
	var painted := false
	for c in colors:
		if maxf(absf(c.r - trim.r), maxf(absf(c.g - trim.g), absf(c.b - trim.b))) < 0.005:
			painted = true
	_check(painted, "Carriage shells use this hull's painted leading strip")
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
		_check(is_equal_approx(side * p.x, Talon.GUN_X), "Bore sits inside its own wing opening")
		_check((-deployed[i].basis.z).is_equal_approx(-hull.global_basis.z), "Muzzle -Z follows rolled and yawed hull")
		var low: Vector3 = hull.to_local(stowed[i].origin)
		_check(p.y - low.y > 0.39 and low.z - p.z > Arms.TRAVEL + 0.32, "The actual barrel rises above its wing and travels forward on the lift arms")
		var eye := Seat.EYE - Vector3.UP * Model.POD_FRAME_UP
		var azimuth := rad_to_deg(atan2(absf(p.x), eye.z - p.z))
		var altitude := rad_to_deg(atan2(p.y - eye.y, eye.z - p.z)) - rad_to_deg(Seat.POD_PITCH)
		_check(azimuth > 18 and azimuth < 38 and altitude > -1 and altitude < 15,
				"The muzzle is visible through the windshield, clear of the central flight line")
	_check(arms.caps.basis.z.dot(Vector3.BACK) < 0 and arms.carriage.position.y > 0.39, "Caps clear the bores on the raised carriage")
	for link: MeshInstance3D in arms.links:
		var pin := link.transform * (Vector3.BACK * Arms.LIFT_ARM)
		var travel := Vector3(0, sin(Arms.LOW_ANGLE), cos(Arms.LOW_ANGLE)) * Arms.LIFT_ARM
		_check((link.position + travel + arms.carriage.position).is_equal_approx(pin), "Each pivot stays attached to the raised carriage")
	for quarter in 4:
		var start := quarter * 0.25
		var end := start + 0.25
		arms.set_deploy(start)
		var housing_start := arms.carriage.position
		var from := hull.to_local(arms.muzzles()[0].origin)
		arms.set_deploy(end)
		var to := hull.to_local(arms.muzzles()[0].origin)
		_check(arms.carriage.position.distance_to(housing_start) > 0.085, "The painted carriage stays in motion through each quarter")
		_check(to.distance_to(from) > 0.085, "The real gun travels in each quarter of the transition")
		arms.set_deploy(start)
		_check(from.is_equal_approx(hull.to_local(arms.muzzles()[0].origin)), "Stow reverses the same forward-visible path")
	arms.heat = 2.0
	_check(arms.heat == 1.0 and arms.throats.emission.is_equal_approx(Arms.HOT), "Both throats follow normalized heat")
	arms.heat = -1
	_check(arms.heat == 0.0 and arms.throats.emission.is_equal_approx(Arms.COOL), "Both throats cool")
	arms.set_deploy(0.54)
	_check(arms.muzzles()[0].is_equal_approx(middle[0]), "Deployment reverses through the same geometry")
	Model.set_nose_closed(not Model.nose_closed, root)
	_check(hull.mesh.get_meta(&"talon_bays", "") == "open" and not neighbour.mesh.has_meta(&"talon_stock"), "Opening the nose preserves the armed wing on its owner only")
	arms.set_deploy(-0.1)
	var nose_stock := Model.pod_hull(false, true)      # (the stock skin for the nose as it now is)
	_check(not arms.visible and hull.mesh == Talon.with_bays(nose_stock, "sealed") and hull.mesh.get_meta(&"talon_stock") == nose_stock
		and neighbour.mesh == nose_stock and arms.muzzles()[0].is_equal_approx(stowed[0]),
		"Full stow seals the guns into this hull's wing (her shut carriages; the neighbour's stays stock) and restores the original mouth position")
	Model.set_nose_closed(not Model.nose_closed, root)
	_check(hull.mesh == Talon.with_bays(Model.pod_hull(false, true), "sealed"), "Opening the nose again keeps the sealed wing")
	var triangles := 0
	var surfaces := 0
	for part: MeshInstance3D in [arms.carriage, arms.caps, arms.barrels, arms.links[0], arms.links[1]]:
		surfaces += part.mesh.get_surface_count()
		for index in part.mesh.get_surface_count():
			triangles += int(part.mesh.surface_get_array_index_len(index) / 3.0)
	print("TALON ARMS geometry: %d triangles, %d moving surfaces while deployed." % [triangles, surfaces])
	print("TALON ARMS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
