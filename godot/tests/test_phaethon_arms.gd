## Rail direction, shutter timing, livery, heat and the pilot's sightline on the production engines.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_phaethon_arms.gd -- --mute
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Arms := preload("res://view/arms/phaethon_arms.gd")

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
	_check(engines.size() == 2 and not engines[0].has_node("PhaethonNoseBay") and not engines[1].has_node("PhaethonNoseBay"), "Flight starts with no cannon geometry")
	var rig: Arms = game.craft.phaethon_arms()
	_check(rig != null and game.craft.phaethon_arms() == rig, "Flat/VR craft accessor builds one rig lazily")
	if not rig:
		quit(1)
		return
	_check(rig.muzzles().size() == 2 and rig._ports.size() == 2, "Two muzzle transforms")
	var paint: Color = rig._doors[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR][0]
	var difference := paint - Livery.coat("engine")
	_check(maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) <= 1.0 / 255.0,
			"Painted shutters match the chosen nacelle paint within vertex colour precision")
	for tube in rig._barrels:
		_check(not tube.visible, "Stowed barrel hidden")
	rig.set_deploy(0.27)
	var partial: Transform3D = rig._doors[0].transform
	_check(absf(partial.basis.z.y) > 0.5 and not rig._barrels[0].visible, "Hatches move before the tubes")
	rig.set_deploy(2.0)
	_check(rig._barrels[0].visible and rig._barrels[1].visible and is_zero_approx(rig._barrels[0].position.z), "Full extension clamps to the forward stop")
	for i in engines.size():
		var pose := rig.muzzles()[i]
		var relative := engines[i].global_transform.affine_inverse() * pose
		_check(relative.origin.distance_to(Arms.FACE + Vector3.BACK * Arms.MOUTH_Z) < 0.001 and relative.basis.z.is_equal_approx(Vector3.BACK), "Mouth is at the actual lip in nacelle space")
		# The physical left and right eyes must both keep the central road sightline.
		for eye_offset: float in [-0.032, 0.032]:
			var eye: Transform3D = game.rig.global_transform.translated_local(Seat.EYE + Vector3.RIGHT * eye_offset)
			var keep_clear := true
			for mesh: MeshInstance3D in [rig._barrels[i], rig._doors[2 * i], rig._doors[2 * i + 1], engines[i].get_node("PhaethonNoseBay")]:
				var xf := eye.affine_inverse() * mesh.global_transform
				for v: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					var point := xf * v
					if absf(point.x) < -point.z * tan(deg_to_rad(3.0)):
						keep_clear = false
			_check(keep_clear, "Deployed geometry clears the central 6 degrees for each eye")
	var before := rig.muzzles()
	engines[0].rotate_y(0.31)
	engines[0].rotate_z(0.12)
	var after := rig.muzzles()
	_check(after[0].basis.z.is_equal_approx(engines[0].global_basis.z) and not after[0].basis.z.is_equal_approx(before[0].basis.z) and after[1].is_equal_approx(before[1]), "Independent engine headings update only their own muzzle")
	rig.heat = 1.5
	_check(rig.heat == 1.0 and rig._metal.get_shader_parameter("heat") == 1.0 and rig._barrels[0].material_override == rig._barrels[1].material_override, "Both emitter materials respond to clamped heat together")
	rig.set_deploy(0.27)
	_check(rig._doors[0].transform.is_equal_approx(partial), "Reversing deploy retraces the door path")
	rig.set_deploy(-2.0)
	_check(not rig._barrels[0].visible and rig._doors[0].basis.is_equal_approx(Basis.IDENTITY), "Restowing returns to the original closed pose")
	var tris := 0
	for mesh: MeshInstance3D in [rig._barrels[0], rig._doors[0], rig._doors[1], engines[0].get_node("PhaethonNoseBay")]:
		_check(mesh.mesh.get_surface_count() == 1, "One surface per independently moved part")
		tris += mesh.mesh.surface_get_array_index_len(0) / 3
	print("PHAETHON TWIN PROJECTORS: %d triangles across the two engines, 8 single-surface instances while deployed" % (2 * tris))
	print("PHAETHON ARMS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	game.free()
	await process_frame
	quit(int(failures > 0))
