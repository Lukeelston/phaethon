## Menu selection, native handling, and the two assemblies that actually get flown.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const LEVERS := {"thrL": 0.82, "thrR": 0.82, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)


func trial(id: String) -> Vector2:
	var sim := Sim.new({"vehicle": id, "track": "range", "startY": -3000.0})
	var steps := 0
	while sqrt(sim.pod.vx**2 + sim.pod.vy**2) < 447.04 and steps < 4800:
		sim.step(LEVERS, DT)
		steps += 1
	sim.restart()
	for body in sim.bodies:
		body.vx = 350.0 * 0.44704
		body.vy = 0.0
	var split := LEVERS.duplicate()
	split.thrL = 0.30
	for i in 240:
		sim.step(split, DT)
	var yaw := rad_to_deg(sim.pod.th)
	check(id + " remains intact in the split-lever turn", sim.mode == "normal" and not sim.binder_broken)
	sim.set_handling("starfighter")
	sim.respawn()
	var idle := {"thrL":0.0, "thrR":0.0, "brkL":0.0, "brkR":0.0, "repair":false, "reignite":true}
	var gp_preset := Sim.new({"vehicle":id, "track":"gp"})
	check(id + " restores its GP yaw damping on respawn", is_equal_approx(sim.P.yawDamp, gp_preset.P.yawDamp))
	for mode in ["speed", "starfighter"]:
		idle.handling = mode
		for i in 500:
			sim.step(idle, DT)
		var expected: float = gp_preset.P.yawDamp if mode == "starfighter" else Sim.DEFAULTS.yawDamp
		check(id + " blends into its " + mode + " yaw damping", is_equal_approx(sim.P.yawDamp, expected))
	check(id + " survives a handling change and respawn", sim.P.vehicle == id and sim.P.engineMass == sim.eL.m)
	return Vector2(steps * DT, yaw)


func check_airframe(craft) -> void:
	var material: StandardMaterial3D = craft.engines[0].get_node("ShrikeFairing").get_active_material(0)
	check("paint, surface finish and relief use the imported maps", material.albedo_texture != null and material.roughness_texture == material.metallic_texture and material.ao_texture == material.roughness_texture and material.normal_texture != null)
	for k in 2:
		var body: ArrayMesh = craft.engines[k].get_node("ShrikeFairing").mesh
		check("engine %d batches its fixed surfaces into one paint material" % k, body.get_surface_count() == 1 and body.surface_get_material(0) == material and not craft.engines[k].has_node("NacelleShell"))
		var fan_a: MeshInstance3D = craft.rotors[k][0].get_child(0)
		var fan_b: MeshInstance3D = craft.rotors[k][1].get_child(0)
		check("engine %d has a mirrored compressor pair on independent shafts" % k, fan_a.mesh == fan_b.mesh and fan_a.transform.basis.determinant() * fan_b.transform.basis.determinant() < 0)
		var brake: Mesh = craft.front_flaps[k][0].get_child(0).mesh
		var aft: Mesh = craft.flaps[k][0].get_child(0).mesh
		check("engine %d has separate textured front and aft leaves" % k, brake != aft and brake.surface_get_material(0) == material and aft.surface_get_material(0) == material)


func check_pod_controls(game, vr: bool) -> void:
	var model = game.craft
	var hull: MeshInstance3D = model.tail_lights.get_parent()
	check("brakes and lamps ride on the pilot's visible hull", hull.is_visible_in_tree() and model.pod_flaps.all(func(f): return f.get_parent() == hull))
	var previous_mesh: Mesh = hull.mesh
	var closed: bool = model.nose_closed
	model.set_nose_closed(not closed, game)
	check("nose switch preserves the Shrike hardware", hull.mesh != previous_mesh and bool(hull.mesh.get_meta(&"shrike_hull", false)) and hull.has_node("ShrikeStrakes"))
	model.set_nose_closed(closed, game)
	check("nose switch restores the previous hull", hull.mesh == previous_mesh)
	if vr:
		check("the pilot sits in the same bucket shown from chase", game.shell.get_node("seat_back").mesh == model.pod.get_node("seat_back").mesh)
	var previous: Dictionary = game.inp.duplicate()
	for demand: Vector2 in [Vector2(.85, .0), Vector2(.0, .85), Vector2(.85, .85), Vector2.ZERO]:
		game.inp.brkL = demand.x
		game.inp.brkR = demand.y
		game._sync_craft(1.0)
		var lights: Vector2 = model.tail_lights.material_override.get_shader_parameter("brakes")
		check("rear lamps follow each lever at " + str(demand), lights.is_equal_approx(demand))
		check("pod brake doors follow the common brake demand", is_equal_approx(model.pod_flap_open, minf(demand.x, demand.y)))
		if vr:
			game._place_camera(1.0)
			var angle := Vector2(game.brake_paddles[0].rotation.x, game.brake_paddles[1].rotation.x)
			check("brake paddles show the correct independent travel", angle.is_equal_approx(demand * deg_to_rad(-18.0)))
	game.inp = previous


func check_fleet(game, id: String, vr: bool) -> void:
	var model = game.craft
	var art = model.fleet
	check(id + " has the selected airframe", art != null and art.id == id)
	if not art:
		return
	var hull: MeshInstance3D = game.shell.get_node("PodHull") if vr else model.pod
	check(id + " shows its own cab, seat and roof", hull.is_visible_in_tree() and hull.mesh == art.part(&"Cab")
			and hull.get_node("FleetSeat").mesh == art.part(&"Seat")
			and (game.canopy if vr else model.canopy).get_node("roof").mesh == art.part(&"Roof"))
	if vr:
		check_sight_lines(game, hull)
	var closed: bool = model.nose_closed
	model.set_nose_closed(not closed, game)
	check(id + " service bonnet follows the nose switch", hull.get_node("ServiceBonnet").visible != closed)
	model.set_nose_closed(closed, game)
	var previous: Dictionary = game.inp.duplicate()
	var started := float(game.sim.pod.x)
	game.inp = LEVERS.duplicate()
	for frame in 180:
		game.sim.step(game.inp, 1.0 / 120.0)
		game._sync_craft(1.0 / 120.0)
	game._place_camera(1.0)
	model.sync_cables(game.sim)
	check(id + " tows the cab under its own power", absf(game.sim.pod.x - started) > 1.0 and not game.sim.binder_broken)
	for k in 2:
		var engine: Node3D = model.engines[k]
		var fairing: MeshInstance3D = engine.get_node_or_null("FleetFairing")
		check(id + " carries the correct engine " + str(k), fairing != null and fairing.mesh == art.part(&"Port" if k == 0 else &"Starboard"))
		var bore := fairing.mesh.generate_triangle_mesh()
		var open := true
		for x in [-0.70, -0.35, 0.0, 0.35, 0.70]:
			var hit := bore.intersect_ray(Vector3(x, 0, 4.71), Vector3.FORWARD)
			open = open and (hit.is_empty() or hit.position.z <= model.Jets.PIPE_Z)
		check(id + " nozzle has an open exhaust path " + str(k), open and model.flames[k].visible)
		var ends: Array = model.cable_ends[k]
		check(id + " drawbar meets both hardpoints " + str(k), ends.size() == 2
				and ends[0].distance_to(engine.transform * model.ENGINE_EYE) < 0.002
				and ends[1].distance_to(model._pod_anchor(game.sim, k)) < 0.002 and model.link_span[k] > 2.0)
	game.inp.brkL = 0.84
	game.inp.brkR = 0.30
	game._sync_craft(1.0)
	var loads: Vector2 = model.tail_lights.material_override.get_shader_parameter("brakes")
	check(id + " left and right brakes work independently", loads.is_equal_approx(Vector2(0.84, 0.30)) and model.flap_open[0] > model.flap_open[1])
	check(id + " cab brake doors and lamps travel with the visible cab", model.tail_lights.get_parent() == hull and model.pod_flaps[0].get_parent() == hull)
	var hinge: Vector3 = model.pod_flaps[1].position
	var skin := hull.mesh.generate_triangle_mesh().intersect_ray(hinge + Vector3.RIGHT, Vector3.LEFT)
	check(id + " cab brake hinge sits on the outside of its armour", not skin.is_empty()
			and hinge.x > skin.position.x and hinge.x - skin.position.x < 0.012)
	game.inp = previous


func check_sight_lines(game, hull: MeshInstance3D) -> void:
	# Both eyes at seated height and a slightly lower head must see all five dials
	# through the full authored cab, including the optional service cover.
	var seen := true
	var obstacles := [hull, hull.get_node("FleetSeat"), hull.get_node("ServiceBonnet"),
			game.canopy.get_node("roof"), game.interior.get_node("SegmentedCoaming")]
	for fitting: MeshInstance3D in obstacles:
		var surface := fitting.mesh.generate_triangle_mesh()
		for eye_x in [-0.033, 0.033]:
			for drop in [0.0, 0.04]:
				var eye := fitting.to_local(game.shell.to_global(game.EYE + Vector3(eye_x, -drop, 0)))
				for dial_x in [-0.212, -0.116, 0.0, 0.116, 0.212]:
					for dial_y in [0.0, 0.046]:
						var dial := fitting.to_local(game.dashboard.to_global(Vector3(dial_x, dial_y, 0.01)))
						var hit := surface.intersect_ray(eye, eye.direction_to(dial))
						if hit and eye.distance_to(hit.position) < eye.distance_to(dial) - 0.002:
							seen = false
							print("Sight line blocked ", game.sim.P.vehicle, " ", fitting.name, " dial ", dial_x, " ", dial_y)
	check(game.sim.P.vehicle + " left and right eye can see all five dials", seen)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(Settings.PREFS)
	var previous := FileAccess.get_file_as_bytes(Settings.PREFS) if prefs_existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("flight", "vehicle", 27)
	config.set_value("flight", "unrelated", "keep")
	config.save(Settings.PREFS)
	check("malformed preference recovers to original", Settings.selected_craft() == "phaethon")
	check("direct launch accepts the explicit vehicle", Sim.PilotCraft.resolve(["--vehicle=shrike"], "phaethon") == "shrike")
	for id in ["orrery", "kiln", "vesper"]:
		var result := trial(id)
		check(id + " reaches 1,000 mph and turns under differential thrust", result.x < 10.0 and result.y > 0)
		print(id, " 1000 mph seconds / split-lever yaw degrees ", result)
	var stock := trial("phaethon")
	var shrike := trial("shrike")
	print("1000 mph, then degrees after 0.5 s at 350 mph: Phaethon ", stock, ", Shrike ", shrike)
	check("Shrike launches faster at equal throttle", shrike.x < stock.x * 0.9 and stock.x < 10)
	check("Shrike turns in harder at equal entry speed", shrike.y > stock.y * 1.1 and stock.y > 0)
	# (A flight chosen from the VR board now begins cold, parked with both air brakes held out: these checks are of a
	# craft that is running, as the packaged build's own verifier asks for.)
	preload("res://vr/vr_cockpit.gd").cold_start = false
	preload("res://vr/vr_cockpit.gd")._startup_loaded = true      # (... whatever the saved choice says)
	for vr in [false, true]:
		var scene := "res://release/vr_menu.tscn" if vr else "res://release/menu.tscn"
		for id in ["shrike", "orrery", "kiln", "vesper", "phaethon"]:
			change_scene_to_file(scene)
			await scene_changed
			var menu = current_scene
			check("menu recalls the persisted craft", menu.craft_selector.selected == Settings.selected_craft())
			if vr:
				menu.focus_row(menu.buttons.find(menu.craft_selector.button))
				menu.activate()
				menu.choose_course("range")
				menu.focus_row(menu.start_index)
				menu.activate()
			else:
				menu.craft_selector.button.pressed.emit()
				menu.start_course("range")
			await scene_changed
			var game = current_scene
			await process_frame
			await process_frame
			var is_shrike: bool = id == "shrike"
			check("selected and saved " + id, game.sim.P.vehicle == id and Settings.selected_craft() == id)
			check("both engine fairings match the selection", game.craft.engines.all(func(e): return e.has_node("ShrikeFairing") == is_shrike))
			check("visible pod trim matches the selection", game.craft.pod.has_node("ShrikeStrakes") == is_shrike)
			if is_shrike:
				check_airframe(game.craft)
				check_pod_controls(game, vr)
			if game.craft.Fleet.supports(id):
				check_fleet(game, id, vr)
			if vr:
				check("the pilot sees the selected cabin", (game.shell.find_child("ShrikePlate", true, false) != null) == is_shrike)
				check("tow instrument matches the selection", (game.tow_meter != null) == is_shrike)
				if is_shrike:
					game.craft.cable_strain.assign([0.23, 0.97])
					game._update_hud()
					var loads: Vector2 = game.tow_meter.get_shader_parameter("loads")
					check("port and starboard load indications respond independently", loads.is_equal_approx(Vector2(0.23, 0.97)))
			var gap: float = game.craft.engines[0].position.distance_to(game.craft.engines[1].position)
			check("rendered engine separation matches the chassis", absf(gap - game.sim.P.engineGap) < 0.1)
	config.load(Settings.PREFS)
	check("cycling craft preserves other settings", config.get_value("flight", "unrelated", "") == "keep")
	if prefs_existed:
		var file := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		file.store_buffer(previous)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	print("PILOT CRAFT ", "PASS" if failures == 0 else "FAIL")
	quit(int(failures > 0))
