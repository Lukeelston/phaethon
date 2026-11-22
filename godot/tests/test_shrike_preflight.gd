## Launch a short-tow Shrike from the VR board, then check the parts specific to its cockpit.
## Use --headless --xr-mode off --audio-driver Dummy --path godot -s res://tests/test_shrike_preflight.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const UI := preload("res://release/release_config.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
var failed := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	checks += 1
	failed += int(not ok)


func check_coaming(v) -> void:
	var coaming: MeshInstance3D = v.interior.get_node("SegmentedCoaming")
	var plate: MeshInstance3D = coaming.get_node("ShrikePlate")
	var meter: MeshInstance3D = coaming.get_node("TowLoad")
	var cover := coaming.mesh.generate_triangle_mesh()
	var targets := PackedVector3Array()
	for x: float in [-0.095, 0.0, 0.095]:
		targets.append(plate.transform * Vector3(x, 0, 0.011))
	for vertex in meter.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		targets.append(meter.transform * vertex)
	# (from the eye point the furniture is laid out round, and from where the pilot's eyes now are: he sits
	# Cockpit.SEAT_RISE higher since the fourteenth flight, and looks down on the coaming more steeply)
	var nearest := INF
	var farthest := -INF
	var backed := [0, 0, 0]
	var blocked := []
	var facing := INF
	for seat_eye: Vector3 in [Cockpit.SEAT, Cockpit.EYE]:
		var eye := coaming.to_local(v.shell.to_global(seat_eye))
		var behind := [0, 0, 0]
		for p in targets:
			var hit := cover.intersect_ray(eye, (p - eye).normalized())
			if hit.is_empty():
				continue
			var fitting := 1 if absf(p.x) < 0.11 else (0 if p.x < 0.0 else 2)
			behind[fitting] += 1
			var gap := eye.distance_to(hit.position) - eye.distance_to(p)
			nearest = minf(nearest, gap)
			farthest = maxf(farthest, gap)
		for fitting in 3:
			backed[fitting] = behind[fitting] if seat_eye == Cockpit.SEAT else mini(backed[fitting], behind[fitting])
		facing = minf(facing, plate.transform.basis.z.normalized().dot((eye - plate.transform.origin).normalized()))
		for part: MeshInstance3D in [v.interior.get_node("Dashboard"), v.dashboard.get_node("binnacle"), v.shell.get_node("PodHull")]:
			var surface := part.mesh.generate_triangle_mesh()
			var from := part.to_local(coaming.to_global(eye))
			for p in targets:
				var to := part.to_local(coaming.to_global(p))
				var hit := surface.intersect_ray(from, (to - from).normalized())
				if hit and from.distance_to(hit.position) < from.distance_to(to) - 0.001:
					blocked.append("%s from %s" % [part.name, "the old eye" if seat_eye == Cockpit.SEAT else "the raised eye"])
					break
	# An edge can bridge the seam between two coaming segments. Every fitting
	# needs backing; no part of the coaming may stand in front of its face.
	check("badge and tow windows face the eye, old and raised (the badge within %.0f deg of square on), %.1f to %.1f mm ahead of the coaming (%s contact rays at the fewest)" % [rad_to_deg(acos(clampf(facing, -1.0, 1.0))), 1000*nearest, 1000*farthest, backed],
		not backed.has(0) and nearest > 0.0 and farthest < 0.045 and facing > 0.7)
	check("the hull, dashboard and binnacle leave the badge and load windows in view from both (%s)" % [blocked], blocked.is_empty())
	# The coaming's map still carries the Phaethon's own nameplate under the badge (Shrike.NAMEPLATE): the badge
	# has to hide all of it. (As first remounted it left the bottom third showing, its lettering cut through.)
	var badge := plate.mesh.generate_triangle_mesh()
	var showing := 0
	for seat_eye: Vector3 in [Cockpit.SEAT, Cockpit.EYE]:
		var from: Vector3 = plate.to_local(v.shell.to_global(seat_eye))
		for ix in 21:
			for iy in 9:
				var p := Vector3(lerpf(Shrike.NAMEPLATE[0].x, Shrike.NAMEPLATE[1].x, ix / 20.0), lerpf(Shrike.NAMEPLATE[0].y, Shrike.NAMEPLATE[1].y, iy / 8.0), Shrike.NAMEPLATE[0].z)
				var to: Vector3 = plate.to_local(coaming.to_global(p))
				var hit := badge.intersect_ray(from, (to - from).normalized())
				if hit.is_empty() or from.distance_to(hit.position) > from.distance_to(to):
					showing += 1
	check("the badge hides the Phaethon nameplate painted on the coaming under it, from both eyes (%d of %d points of it showing)" % [showing, 2 * 21 * 9], showing == 0)


func check_jets(v) -> void:
	var model = v.craft
	var sim = v.sim
	sim.mode = "burner"
	for engine in [sim.eL, sim.eR]:
		engine.thrust = 1.45
		engine.vx = 1300.0
	v.inp.brkR = 0.8
	for frame in 120:
		model.sync(sim, v.inp, 1.0 / 60.0)
	var valid := true
	for k in 2:
		var flame: ShaderMaterial = model.flame_mats[k][0]
		var port: MeshInstance3D = model.engines[k].get_node("ShrikeFairing")
		var bore := port.mesh.generate_triangle_mesh()
		# Aft to the flame holder at five points inside the slot; an opaque bodywork cap would mask the pipe.
		for x: float in [-0.70, -0.35, 0.0, 0.35, 0.70]:
			var hit := bore.intersect_ray(Vector3(x, 0, 4.71), Vector3.FORWARD)
			if hit and (hit.position as Vector3).z > model.Jets.PIPE_Z:
				valid = false
		valid = valid and model.vanes[k].size() == 3 and model.nozzle_flaps[k].size() == 2 and model.flames[k].visible
		valid = valid and absf(model.vanes[k][0].rotation.y) > 0.1 and absf(model.nozzle_flaps[k][0].rotation.x) > 0.04
		valid = valid and float(flame.get_shader_parameter("reach")) > 3.0 and float(flame.get_shader_parameter("cell")) > 0.5 and float(flame.get_shader_parameter("burner")) > 0.95
	check("both imported fairings leave their tailpipes open; each nozzle drives its three vanes, both flaps and burner plume (%.1f°, %.1f m, %.2f m shock cell)" % [rad_to_deg(model.vane_angle), model.plume_len[0], model.jets[0].cell], valid)


func check_insertions(v) -> void:
	var missing := []
	var placed := 0
	for entry in UI.INSERTIONS:
		var spot := View.start_spot(entry[2])
		if spot.is_empty():
			continue
		v.sim.net.arrived = false
		if spot.size() == 1:
			v.sim.net.from = spot[0]
			v.sim.P.startRoad = -1
		else:
			v.sim.P.startRoad = spot[0]
			v.sim.P.startSample = spot[1]
			v.sim.P.startDir = spot[2]
		v.sim.respawn()
		v._follow_origin()
		v.pad.sync(0.0)
		var pod = v.sim.pod
		var ground: float = v.sim.net_height(pod.path, pod.hint)
		if v.pad.global_position.distance_to(v.wz(pod.x, pod.y, ground)) > 0.15 or v.pad.lines[2].text != "SHRIKE RS  OBSIDIAN":
			missing.append(entry[1])
		placed += 1
	check("the road and city insertions put the selected Shrike on its own marked pad (%d sites, misses %s)" % [placed, missing], placed >= 16 and missing.is_empty())


func _run() -> void:
	var old_exists := FileAccess.file_exists(Settings.PREFS)
	var old := FileAccess.get_file_as_bytes(Settings.PREFS) if old_exists else PackedByteArray()
	var vr_exists := FileAccess.file_exists(Cockpit.PREFS)      # (the cockpit saves its own choices: put them back too)
	var vr_old := FileAccess.get_file_as_bytes(Cockpit.PREFS) if vr_exists else PackedByteArray()
	Settings.set_selected_craft("phaethon")
	for entry in [["paint", "ember"], ["craft", "racer"], ["network_start", "summit"], ["time", "noon"], ["weather", "fair"]]:
		Settings.set_choice(entry[0], entry[1])
	View.best_dir = OS.get_user_data_dir().path_join("test_shrike_preflight_")
	Cockpit._startup_loaded = true
	Cockpit.cold_start = true
	change_scene_to_file("res://release/vr_menu.tscn")
	await scene_changed
	var menu = current_scene
	menu.focus_row(menu.buttons.find(menu.craft_selector.button))
	menu.activate()
	var paint: Button = menu.option_buttons.filter(func(b): return b.text.begins_with("Paint:"))[0]
	menu.focus_row(menu.buttons.find(paint))
	var choices := []
	for i in Livery.CHOICES.size():
		choices.append(Settings.choice("paint", Livery.ids()))
		if i < Livery.CHOICES.size()-1:
			menu.activate()
	check("the board selects Shrike, cycles all eight paints and displays Obsidian black", menu.craft_selector.selected == "shrike" and choices == Livery.ids() and paint.text.ends_with("Obsidian black"))
	menu.choose_course("network")
	menu.focus_row(menu.start_index)
	menu.activate()
	await scene_changed
	await process_frame
	var v = current_scene
	v.set_process(false)
	v._sync_world()
	v._apply_startup(0.0)
	v.pad.sync(3.0)
	check("summit pad board %s / %s / %s" % [v.pad.lines[0].text, v.pad.lines[1].text, v.pad.lines[2].text],
		v.sim.P.vehicle == "shrike" and Livery.current == "obsidian" and v.pad.lines[2].text == "SHRIKE RS  OBSIDIAN" and absf(v.sim.pod.z - 16000.0) < 100.0)
	var road_z: float = v.sim.net_height(v.sim.pod.path, v.sim.pod.hint)
	var left: Vector3 = v.pad.to_local(v.wz(v.sim.eL.x, v.sim.eL.y, road_z))
	check("Shrike's pad markers follow the short tow (port engine %.2f m forward, %.2f m from the centre)" % [-left.z, absf(left.x)],
		absf(-left.z-v.pad.ahead) < 0.3 and absf(absf(left.x)-v.sim.P.engineGap/2.0) < 0.2)
	check("cold pad has a red hold lamp, a closed gate and its power lead", v.startup.park and not v.startup.batt and v.pad.gate_open == 0.0 and v.pad.lead.visible and v.pad.big_lamp.material_override.albedo_color.r > 2.0)
	Outlook.tick(v, 0.0)
	var stars := v.get_node_or_null("outlook_stars") as MeshInstance3D
	check("daylight summit has the Sun Gate and stars", v.landscape.sun_gate.visible and stars != null and stars.visible and float(stars.material_override.get_shader_parameter("fade")) > 0.5)
	check_coaming(v)
	v._sync_craft(1.0)
	var lens: ShaderMaterial = v.craft.tail_lights.material_override
	check("cold parking brake holds both sides with the tail lamps unpowered", lens.get_shader_parameter("brakes") == Vector2.ONE and lens.get_shader_parameter("powered") == false)
	v.startup_work("batt", 1)
	for i in 90:
		v.startup.step(1.0 / 90.0, [0.0, 0.0], 1)
	v._apply_startup(1.0)
	v._sync_craft(1.0)
	check("BATT powers both parked brake lamps", lens.get_shader_parameter("powered") == true and lens.get_shader_parameter("brakes") == Vector2.ONE)
	v.startup.hot()
	v._apply_startup(1.0)
	v.pad.sync(3.0)
	check("released pad has a green lamp, a raised gate and the lead stowed", v.pad.gate_open == 1.0 and not v.pad.lead.visible and v.pad.big_lamp.material_override.albedo_color.g > 2.0)
	check_jets(v)
	check_insertions(v)
	if old_exists:
		var f := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		f.store_buffer(old)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	if vr_exists:
		var vf := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		vf.store_buffer(vr_old)
		vf.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	var passed := checks == 13 and failed == 0
	print("SHRIKE PREFLIGHT %s (%d checks, %d failures)" % ["PASS" if passed else "FAIL", checks, failed])
	quit(int(not passed))
