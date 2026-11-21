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


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(Settings.PREFS)
	var previous := FileAccess.get_file_as_bytes(Settings.PREFS) if prefs_existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("flight", "vehicle", 27)
	config.set_value("flight", "unrelated", "keep")
	config.save(Settings.PREFS)
	check("malformed preference recovers to original", Settings.selected_craft() == "phaethon")
	check("direct launch accepts the explicit vehicle", Sim.PilotCraft.resolve(["--vehicle=shrike"], "phaethon") == "shrike")
	var stock := trial("phaethon")
	var shrike := trial("shrike")
	print("1000 mph, then degrees after 0.5 s at 350 mph: Phaethon ", stock, ", Shrike ", shrike)
	check("Shrike launches faster at equal throttle", shrike.x < stock.x * 0.9 and stock.x < 10)
	check("Shrike turns in harder at equal entry speed", shrike.y > stock.y * 1.1 and stock.y > 0)
	for vr in [false, true]:
		var scene := "res://release/vr_menu.tscn" if vr else "res://release/menu.tscn"
		for id in ["shrike", "phaethon"]:
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
