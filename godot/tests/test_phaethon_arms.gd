## Link travel, cockpit sightlines, livery, heat and heading on the production engines.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_phaethon_arms.gd -- --mute
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Arms := preload("res://view/arms/phaethon_arms.gd")
const PREFS := "user://vr_prefs.json"

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)      # (put back as it was found, at the end)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.vehicle_override = Pilot.STANDARD
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Livery.pinned = true
	Livery.current = "cobalt"
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for frame in 8:
		game._process(1.0 / 120.0)
	var engines: Array[Node3D] = game.craft.engines
	# (The raids build the rig with the craft, view/craft_model.gd, and fire it through its fixed guns' mount; until
	# the GUN switch first brings it out nothing of it is drawn.)
	var drawn := false
	for engine in engines:
		var bay := engine.get_node_or_null("PhaethonNoseBay") as Node3D
		drawn = drawn or (bay != null and bay.is_visible_in_tree())
	_check(engines.size() == 2 and not drawn, "Flight starts with no cannon geometry drawn")
	var rig: Arms = game.craft.arms
	_check(rig != null and game.craft.weapon != null and game.craft.weapon.get("arms") == rig, "Flat/VR craft carries one rig, fired through its fixed guns' mount")
	if not rig:
		quit(1)
		return
	_check(rig.muzzles().size() == 2 and rig._ports.size() == 2, "Two muzzle transforms")
	var colors: PackedColorArray = rig._carriages[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var matches_paint := false
	for paint in colors:
		var difference := paint - Livery.coat("engine")
		if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) <= 1.0 / 255.0:
			matches_paint = true
			break
	_check(matches_paint, "Breech roof takes its paint from the current nacelle livery")
	for tube in rig._barrels:
		_check(not tube.visible, "Stowed emitter hidden")
	var cam: Camera3D = game.cam
	for i in engines.size():
		for side: float in [-0.032, 0.032]:
			var eye := cam.global_transform.translated_local(Vector3.RIGHT * side)
			var last_elevation := -PI
			for step in 5:
				rig.set_deploy(step * 0.25)
				# The trailing edge of the actual breech is the surface facing the pilot.
				var local := eye.affine_inverse() * rig._carriages[i].to_global(Vector3(0, 0.22, 0.88))
				var elevation := atan2(local.y, -local.z)
				_check(local.z < 0 and absf(rad_to_deg(elevation)) < 25.0 and absf(rad_to_deg(atan2(local.x, -local.z))) < 30.0, "Breech stays in the forward view of both eyes")
				if step > 0:
					_check(elevation - last_elevation > deg_to_rad(0.40), "Actual breech rises visibly throughout each quarter of the stroke")
				last_elevation = elevation
			var keep_clear := true
			for mesh: MeshInstance3D in engines[i].get_node("PhaethonNoseBay").find_children("*", "MeshInstance3D", true, false):
				var xf := eye.affine_inverse() * mesh.global_transform
				for v: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var point := xf * v
					if absf(point.x) < -point.z * tan(deg_to_rad(3.0)):
						keep_clear = false
			_check(keep_clear, "Deployed geometry clears the central 6 degrees for each eye")
	rig.set_deploy(0.27)
	var partial := rig._carriages[0].transform
	var partial_link := rig._links[0].transform
	var partial_barrel := rig._barrels[0].transform
	rig.set_deploy(2.0)
	_check(rig._barrels[0].visible and rig._barrels[1].visible and is_equal_approx(rig._barrels[0].position.z, Arms.FULL_Z), "Full extension clamps to the forward stop")
	for i in engines.size():
		var relative := engines[i].global_transform.affine_inverse() * rig.muzzles()[i]
		_check(relative.origin.z < -4.0 and relative.origin.y > 1.15 and relative.basis.z.is_equal_approx(Vector3.BACK), "Mouth clears nose and fin while facing along its engine")
		_check(rig._ports[i].position.is_equal_approx(Vector3.BACK * Arms.MOUTH_Z), "Muzzle transform sits at the real barrel lip")
		for j in 2:
			var link_tip := rig._links[i * 2 + j].to_global(Vector3.BACK * Arms.LINK_LENGTH)
			var mating_pin := rig._carriages[i].to_global(Vector3.BACK * Arms.HINGE_SPREAD * (-1.0 if j == 0 else 1.0))
			_check(link_tip.distance_to(mating_pin) < 0.001, "Each elevator arm stays connected to its receiver")
	var before := rig.muzzles()
	engines[0].rotate_y(0.31)
	engines[0].rotate_z(0.12)
	var after := rig.muzzles()
	_check(after[0].basis.z.is_equal_approx(engines[0].global_basis.z) and not after[0].basis.z.is_equal_approx(before[0].basis.z) and after[1].is_equal_approx(before[1]), "Independent engine headings update only their own muzzle")
	rig.heat = 1.5
	_check(rig.heat == 1.0 and rig._metal.get_shader_parameter("heat") == 1.0 and rig._barrels[0].material_override == rig._barrels[1].material_override, "Both emitter materials respond to clamped heat together")
	rig.set_deploy(0.27)
	_check(rig._carriages[0].transform.is_equal_approx(partial) and rig._links[0].transform.is_equal_approx(partial_link) and rig._barrels[0].transform.is_equal_approx(partial_barrel), "Disarming retraces the receiver, link and barrel poses exactly")
	rig.set_deploy(-2.0)
	_check(not rig._barrels[0].visible and is_equal_approx(rig._carriages[0].position.y, Arms.STOW_LIFT), "Restowing seats the carriage against the engine")
	_check(engines[0].get_node("PhaethonNoseBay").is_visible_in_tree() and engines[1].get_node("PhaethonNoseBay").is_visible_in_tree(), "Once brought out, the seated breech stays drawn when stowed")
	var tris := 0
	var bay: MeshInstance3D = engines[0].get_node("PhaethonNoseBay")
	var meshes := bay.find_children("*", "MeshInstance3D", true, false)
	meshes.append(bay)
	for mesh: MeshInstance3D in meshes:
		_check(mesh.mesh.get_surface_count() == 1, "Each moving part uses one surface")
		tris += mesh.mesh.surface_get_array_index_len(0) / 3
	_check(2 * tris < 8500 and 2 * meshes.size() == 10, "Twin engine mounts stay within the cockpit geometry budget")
	print("PHAETHON TWIN PROJECTORS: %d triangles, %d single-surface instances" % [2 * tris, 2 * meshes.size()])
	print("PHAETHON ARMS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.free()
	await process_frame
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	quit(int(failures > 0))
