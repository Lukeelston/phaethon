## Codex's pilot garage on the spike line (merged onto Raids stage 1 and push 45): its six bays, with the Talon kept out
## of them and still flown from the menus, and each parked craft in its own saved paint (view/livery.gd's per-craft
## keys: "paint" for the Phaethon, "paint_<id>" for the others), outside and in its occupied cab, the Vesper's Star
## Command among them; building the bays leaves the flight's paint (Livery.current) as it was; nothing parked carries a
## raid or a live gun, with Raids on.
## Run headless with --xr-mode off -s res://tests/test_garage_fleet_paint.gd -- --mute
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Flat := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const GARAGE := "res://garage/garage.tscn"
const SENTINEL := "obsidian"      # the flight's paint while the garage builds: none of the bays wears it
const SAVED := {"phaethon": "crimson", "kiln": "cobalt", "vesper": "star_command"}      # (the rest: Factory)
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func _scene(path: String) -> bool:
	var until := Time.get_ticks_msec() + 20000
	while current_scene == null or current_scene.scene_file_path != path:
		if Time.get_ticks_msec() > until:
			return check(false, "Expected scene " + path)
		await process_frame
	await process_frame
	return true


func _atlas(mesh: Mesh) -> ShaderMaterial:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	return mesh.surface_get_material(0) as ShaderMaterial


## Is a fleet craft's atlas material painted in a livery: Star Command's own atlas, Factory's as it was painted, or a
## repaint in the livery's paint?
func _wears(material: ShaderMaterial, livery: String) -> bool:
	if material == null:
		return false
	var repainted: bool = material.get_shader_parameter("repaint") == true
	if livery == Livery.STAR_COMMAND:
		var map := material.get_shader_parameter("albedo_map") as Texture2D
		return map != null and map.resource_path.ends_with("vesper_star_command.webp") and not repainted
	if Livery.is_factory(livery):
		var map := material.get_shader_parameter("albedo_map") as Texture2D
		return not repainted and map != null and not map.resource_path.ends_with("vesper_star_command.webp")
	var enamel = material.get_shader_parameter("to_r")      # (the enamel's colour: view/fleet_airframe.gd repaint, mask channel R)
	return repainted and enamel is Color and (enamel as Color).is_equal_approx(Livery.coat("paint", livery))


func _board(garage, id: String) -> Node3D:
	garage.walker.set_seated(false, garage.environment.boarding_transform(id))
	garage.interact()
	if not check(garage.seated_craft == id and garage.walker.seated, "Board the parked " + id):
		return null
	return garage.environment.bay_node(id).get_node_or_null("OccupiedCockpit")


func _armed_nodes(top: Node) -> Array:
	return _scripted(top, "res://view/network_raids.gd") + _scripted(top, "res://view/gunnery.gd")


func _scripted(top: Node, path: String) -> Array:
	var found := []
	for node in top.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script and script.resource_path == path:
			found.append(node)
	return found


func _garage(garage) -> void:
	var hall = garage.environment
	var built: Array = hall._bays.keys()
	check(built == Pilot.GARAGE_BAYS and Pilot.GARAGE_BAYS.size() == 6 and hall.bay_node(Pilot.TALON) == null,
		"The hall builds its six bays in their order and none for the Talon")
	check(not garage.walker.seated and garage.walker.global_position.distance_to(hall.spawn_transform().origin) < .2,
		"With the Talon selected a visit starts on foot at the entrance")
	check(Livery.current == SENTINEL, "Building the six bays leaves the flight's paint as it was")
	for id: String in Pilot.GARAGE_BAYS:
		var bay = hall.bay_node(id)
		var want := Livery.for_craft(id, SAVED.get(id, Livery.FACTORY))
		check(bay.paint == want and bay.paint == Livery.built(id), "The %s is parked in its own saved paint (%s)" % [id, want])
	for id: String in ["orrery", "kiln", "vesper"]:
		var bay = hall.bay_node(id)
		check(_wears(_atlas(bay.model.fleet.part(&"Cab")), Livery.built(id)), "The %s's hull wears %s from the aisle" % [id, Livery.built(id)])
	var vesper_cab := _board(garage, "vesper")
	var hull := vesper_cab.get_node_or_null("ParkedShell/PodHull") as MeshInstance3D if vesper_cab else null
	check(hull != null and _wears(_atlas(hull.mesh), Livery.STAR_COMMAND), "Boarded, the Vesper's cab wears its Star Command atlas")
	garage.leave_seat()
	var kiln_cab := _board(garage, "kiln")
	hull = kiln_cab.get_node_or_null("ParkedShell/PodHull") as MeshInstance3D if kiln_cab else null
	check(hull != null and _wears(_atlas(hull.mesh), "cobalt"), "Boarded, the Kiln's cab wears its own cobalt")
	garage.leave_seat()
	var basilisk_cab := _board(garage, "basilisk")
	check(basilisk_cab != null and basilisk_cab.find_child("GunSwitch", true, false) != null and basilisk_cab._gun != null,
		"The parked Basilisk's cab has its GUN switch (shown SAFE: the garage does not work it)")
	garage.leave_seat()
	var phaethon_cab := _board(garage, "phaethon")
	check(phaethon_cab != null and phaethon_cab.find_child("GunSwitch", true, false) == null and _scripted(phaethon_cab, "res://view/turret.gd").is_empty(),
		"The parked Phaethon's cab builds with no gun hardware of the Basilisk's")
	garage.walker.cockpit_control_requested.emit("power")
	await process_frame
	garage.leave_seat()
	check(Livery.current == SENTINEL, "Boarding four bays leaves the flight's paint as it was")
	var phaethon = hall.bay_node("phaethon")
	check(phaethon.model.arms != null and phaethon.model.arms._deploy <= 0.0 and not phaethon.model.arms._shown,
		"The parked Phaethon's cannons stay stowed in its engines")
	check(_armed_nodes(root).is_empty(), "Nothing in the garage builds a raid director or a fire control")


func _talon_flight() -> void:
	var menu = current_scene
	check(menu.craft_selector.selected == Pilot.TALON, "The desktop menu still offers the Talon as the pilot craft")
	menu.start_course("network")
	if not await _scene(UI.GAME_SCENE):
		return
	var flight = current_scene
	check(flight is Flat and flight.sim.P.vehicle == Pilot.TALON, "The menu's Start flies the Talon")
	for tick in 10:
		await process_frame
	check(not _scripted(root, "res://view/network_raids.gd").is_empty(),
		"With Raids on, the flight builds its raid director (the garage's check would have found one)")
	check(not flight.can_visit_garage(), "A parked Talon is not offered the garage, which has no bay for it")
	var pause_menu = root.get_node("ReleasePause")
	pause_menu.set_paused(true)
	var button := pause_menu.find_child("Garage", true, false) as Button
	check(button != null and button.disabled and button.tooltip_text.contains("no bay"), "The pause menu's Pilot garage is off for a Talon, and says why")
	pause_menu.set_paused(false)
	# The same flight in the Phaethon is offered it (the rule is the bay, not the place or the time).
	Flat.vehicle_override = Pilot.STANDARD
	Flat.track_override = "network"
	Flat.pad_start = true
	change_scene_to_file(UI.GAME_SCENE)
	await process_frame
	if not await _scene(UI.GAME_SCENE):
		return
	flight = current_scene
	for tick in 10:
		await process_frame
	check(flight.sim.P.vehicle == Pilot.STANDARD and flight.can_visit_garage(), "A parked Phaethon at the same launch site is offered the garage")


func _run() -> void:
	var settings_before := Settings.prefs_path
	var had_vr_prefs := FileAccess.file_exists(Cockpit.PREFS)
	var vr_prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if had_vr_prefs else PackedByteArray()
	var paint_before := Livery.current
	Settings.prefs_path = "user://test-garage-paint-%d.cfg" % OS.get_process_id()
	Settings.set_selected_craft(Pilot.TALON)
	for id: String in SAVED:
		Settings.set_choice(Livery.key_for(id), SAVED[id])
	Settings.set_choice("raids", "on")      # (Raids on: still, nothing parked builds a raid director or a fire control)
	Livery.current = SENTINEL
	change_scene_to_file(UI.MENU_SCENE)
	if await _scene(UI.MENU_SCENE):
		var enter := current_scene.find_child("Garage", true, false) as Button
		if check(enter != null and enter.is_visible_in_tree(), "The desktop menu offers the Pilot garage"):
			enter.pressed.emit()
			if await _scene(GARAGE):
				await _garage(current_scene)
				current_scene.return_to_menu()
				if await _scene(UI.MENU_SCENE):
					await _talon_flight()
	Livery.current = paint_before
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = settings_before
	if had_vr_prefs:
		var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		file.store_buffer(vr_prefs)
		file.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	print("GARAGE FLEET PAINT %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
