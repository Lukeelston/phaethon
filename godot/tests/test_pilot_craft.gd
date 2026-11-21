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
	check(id + " survives a handling change and respawn", sim.P.vehicle == id and sim.P.engineMass == sim.eL.m)
	return Vector2(steps * DT, yaw)


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
			if vr:
				check("the pilot sees the selected cabin", (game.shell.find_child("ShrikePlate", true, false) != null) == is_shrike)
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
