## The Talon in the garage (Luke, 2026-11-25: "Will you fix her garage and talon paint then merge?"): a Phaethon in another
## body, it stands in the Phaethon's bay, which holds either body (sim/pilot_craft.gd bay_of, has_bay).
##   the swap     on foot at the Phaethon's bay the walker's "park" button (P here, L3 on a pad, the left stick's click in
##                the headset) stands the other body there, saved (Settings.phaethon_body), in its own saved paint; at
##                any other bay it does nothing; a run-up bay refuses it and the prompt says why; the bay starts
##                fresh (a start-up worked there is not carried to the other body); on a pad, L3 swaps unless its
##                stick is pushed well over (a brisk walk is not a swap; a click that tilts it a little still is)
##   its paint    the paint control then acts on the Talon, under its own key; the Phaethon's stays
##   flying it    boarded, its cab is the Talon's plated hull; launched, the flight is the Talon's, with the switch moved in
##                its bay, saved for it; the menus' craft is the Talon
##   parked       a parked Talon is offered the garage, and arrives at the Phaethon's bay with the Talon standing there
##   remembered   the next visit finds the Talon there; a parked Phaethon arriving stands the Phaethon there again
##   Fly          from the menu afterwards, Fly flies the Talon
##   the gate     the Phaethon's bay's boarding gate stays Codex's (2.45 m out) with the Talon standing there, and the
##                Talon's collider is its hull proper (its wings reach past that gate: parked_airframe.gd HULL_REACH),
##                so a pilot at the gate stands clear of it; those bounds are read off the hull once and kept (a
##                Talon paint press or a second swap to it reads no mesh back), and equal ones read fresh
##   cost         the body's rebuild on the main thread (printed: BODY REBUILD)
## Its own settings file for the run: the default one is left as it was.
## Run headless with --xr-mode off -s res://tests/test_garage_talon.gd -- --mute
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Route := preload("res://release/garage_route.gd")
const View := preload("res://view/craft_view.gd")
const CM := preload("res://view/craft_model.gd")
const Menu := preload("res://release/menu.gd")
const Title := preload("res://release/title_stage.gd")
const Parked := preload("res://garage/parked_airframe.gd")
const PAD := 6      # (a pad device no driver has: its stick and L3 sent as events, as tests/test_release_input.gd does)
const GARAGE := "res://garage/garage.tscn"
var checks := 0
var failures := 0
var _left := 0
var _settings_before := ""
var _default_existed := false
var _default_settings := PackedByteArray()


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


## Its own settings file for the run, as tests/test_fly_last_used.gd has; the default file is the player's.
func _own_settings(file_name: String) -> void:
	_settings_before = Settings.prefs_path
	_default_existed = FileAccess.file_exists(_settings_before)
	_default_settings = FileAccess.get_file_as_bytes(_settings_before) if _default_existed else PackedByteArray()
	Settings.prefs_path = "user://%s-%d.cfg" % [file_name, OS.get_process_id()]
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))


func _settings_back() -> bool:
	if Settings.prefs_path != _settings_before and FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = _settings_before
	return FileAccess.file_exists(_settings_before) == _default_existed \
		and (not _default_existed or FileAccess.get_file_as_bytes(_settings_before) == _default_settings)


func _frames(count: int) -> void:
	for tick in count:
		await process_frame


## The next scene at `path` (another instance than the one the run is in), settled; null if it never came.
func _next(path: String) -> Node:
	var until := Time.get_ticks_msec() + 30000
	while current_scene == null or current_scene.get_instance_id() == _left or current_scene.scene_file_path != path:
		if Time.get_ticks_msec() > until:
			check(false, "Expected the scene " + path)
			return null
		await process_frame
	_left = current_scene.get_instance_id()
	await _frames(3)
	return current_scene


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = PAD
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pad_button(button: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.device = PAD
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _stand_at(garage, bay: String) -> void:
	garage.walker.set_seated(false, garage.environment.boarding_transform(bay))
	await _frames(2)


func _run() -> void:
	_own_settings("test-garage-talon")
	var title_before: bool = Title.enabled
	var remembered_before: String = Menu.remembered_course
	Title.enabled = false      # (the plain menu: the title's art is not under test)
	Route.enter(self, false, "range")
	var garage = await _next(GARAGE)
	if garage != null:
		await _talon(garage)
	change_scene_to_file(UI.MENU_SCENE)      # (out of the last flight before the statics are put back)
	await _next(UI.MENU_SCENE)
	View.vehicle_override = ""
	View.track_override = ""
	View.job_override = ""
	View.spot_override = ""
	View.garage_on_entry = {}
	View.pad_start = false
	Title.enabled = title_before
	Menu.remembered_course = remembered_before
	check(_settings_back(), "the default settings file is as it was (the run had its own)")
	print("GARAGE TALON %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _talon(garage) -> void:
	var hall = garage.environment
	var bay: Node3D = hall.bay_node(Pilot.STANDARD)
	check(Pilot.bay_of(Pilot.TALON) == Pilot.STANDARD and Pilot.has_bay(Pilot.TALON) and Pilot.bay_of(Pilot.KILN) == Pilot.KILN
		and Pilot.bay_of("no-such-craft") == "" and not Pilot.has_bay("no-such-craft") and Pilot.GARAGE_BAYS.size() == 6,
		"The Talon's bay is the Phaethon's; each other craft's its own; the hall keeps its six")
	check(hall.bay_craft(Pilot.STANDARD) == Pilot.STANDARD and bay.sim.P.vehicle == Pilot.STANDARD and Settings.phaethon_body() == Pilot.STANDARD,
		"Nothing saved, the Phaethon stands in its bay")
	# ---- elsewhere the body control does nothing
	await _stand_at(garage, "kiln")
	var kiln_model: Node3D = hall.bay_node("kiln").model
	_key(KEY_P)
	await _frames(1)
	check(hall.bay_craft("kiln") == "kiln" and hall.bay_node("kiln").model == kiln_model and Settings.phaethon_body() == Pilot.STANDARD
		and hall.bay_craft(Pilot.STANDARD) == Pilot.STANDARD, "At the Kiln's bay the body control does nothing")
	# ---- the swap
	await _stand_at(garage, Pilot.STANDARD)
	check(garage._prompts._hint.text.begins_with("I  Paint: Factory     P  Body: Phaethon"),
		"At the Phaethon's bay the prompt offers its paint and its body: \"%s\"" % garage._prompts._hint.text.get_slice("\n", 0))
	# (the Phaethon's start-up worked first, its PARK released: the swap starts the bay fresh)
	garage.interact()
	var phaethon_runup: Node = bay.get_node_or_null("Runup")
	if phaethon_runup != null:
		phaethon_runup.work("park", -1)
	var worked: bool = phaethon_runup != null and phaethon_runup.operated and not phaethon_runup.startup.park
	garage.leave_seat()
	await _frames(2)
	var reads: int = Parked.hull_reads
	var t0 := Time.get_ticks_usec()
	_key(KEY_P)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("BODY REBUILD the Talon %.1f ms" % ms)
	await _frames(1)
	check(hall.bay_node(Pilot.STANDARD) == bay and hall.bay_craft(Pilot.STANDARD) == Pilot.TALON and bay.sim.P.vehicle == Pilot.TALON
		and Settings.phaethon_body() == Pilot.TALON and bay.paint == Livery.built(Pilot.TALON) and hall.bay_node(Pilot.TALON) == bay,
		"P at the Phaethon's bay stands the Talon there, in its own saved paint (%s), and saves the choice" % bay.paint)
	check(worked and not garage._runups.has(Pilot.STANDARD) and bay.get_node_or_null("Runup") == null and bay.get_node_or_null("OccupiedCockpit") == null,
		"... starting the bay fresh: the Phaethon's worked start-up (its PARK released) and its cab are not carried to the Talon")
	check(Parked.hull_reads == reads + 1, "Standing the Talon there read its hull's bounds once (%d reads)" % (Parked.hull_reads - reads))
	check(garage._prompts._title.text == "E  Board Phaethon Talon" and garage._prompts._hint.text.contains("P  Body: Phaethon Talon"),
		"... and the prompt names the Talon (\"%s\")" % garage._prompts._title.text)
	var bounds: AABB = bay.model.pod.transform * bay.model.pod.mesh.get_aabb()
	var span := maxf(absf(bounds.position.x), absf(bounds.end.x))
	var gate := absf(bay.to_local(hall.boarding_transform(Pilot.STANDARD).origin).x)
	var collider := 0.0
	for body: StaticBody3D in bay._colliders:
		if String(body.name).begins_with("CockpitCollision"):
			var part := body.get_child(0) as CollisionShape3D
			var half: Vector3 = (part.shape as BoxShape3D).size * 0.5
			for corner in 8:
				var p := Vector3(half.x * (1 if corner & 1 else -1), half.y * (1 if corner & 2 else -1), half.z * (1 if corner & 4 else -1))
				collider = maxf(collider, absf(bay.to_local(part.global_transform * p).x))
	check(is_equal_approx(gate, 2.45) and span > 2.5 and collider > 0.9 and collider < gate - 0.29 - 0.1,
		"The Talon's wings reach %.2f m out; its collider, its hull proper, %.2f m; the bay's gate stays Codex's, %.2f m out, clear of it" % [span, collider, gate])
	# ---- its own paint
	var phaethon_paint: String = Livery.saved_for(Pilot.STANDARD)
	var ids := Livery.ids_for(Pilot.TALON)
	var next: String = ids[(ids.find(Livery.saved_for(Pilot.TALON)) + 1) % ids.size()]
	_key(KEY_I)
	await _frames(1)
	check(Livery.saved_for(Pilot.TALON) == next and Livery.saved_for(Pilot.STANDARD) == phaethon_paint and bay.paint == next
		and bay.model.pod.mesh == _talon_hull(next),
		"The paint control at that bay paints the Talon (%s, its own key), not the Phaethon (%s), and the hull wears it" % [next, phaethon_paint])
	# ---- a pad's L3: refused only with its stick pushed well over; a second swap to the Talon
	var standing := {}
	for push: float in [-0.8, -0.3, 0.0]:      # (walking briskly; a click that tilts the stick past the deadzone; centred)
		_pad_axis(JOY_AXIS_LEFT_Y, push)
		_pad_button(JOY_BUTTON_LEFT_STICK)
		await _frames(1)
		standing[push] = [hall.bay_craft(Pilot.STANDARD), Settings.phaethon_body()]
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	_key(KEY_P)      # (the keyboard's P, unguarded: the Phaethon, then the Talon again)
	await _frames(1)
	var keyed: String = hall.bay_craft(Pilot.STANDARD)
	_key(KEY_P)
	await _frames(1)
	check(standing[-0.8] == [Pilot.TALON, Pilot.TALON] and standing[-0.3] == [Pilot.STANDARD, Pilot.STANDARD]
		and standing[0.0] == [Pilot.TALON, Pilot.TALON] and keyed == Pilot.STANDARD and hall.bay_craft(Pilot.STANDARD) == Pilot.TALON,
		"On a pad, L3 with the left stick pushed well over (0.8) swaps nothing; tilted 0.3 or centred it swaps the body; P swaps it either way (%s)" % [standing])
	check(Parked.hull_reads == reads + 1 and bay.model.pod.mesh == _talon_hull(next)
		and Parked.talon_hull_bounds(bay.model.pod.mesh) == Parked.hull_bounds_of(bay.model.pod.mesh),
		"The Talon's paint press and its second swap read no hull back: its kept bounds, which equal ones read fresh")
	# ---- boarded and launched
	garage.interact()
	var cab: Node3D = bay.get_node_or_null("OccupiedCockpit")
	var hull := cab.get_node_or_null("ParkedShell/PodHull") as MeshInstance3D if cab else null
	check(garage.walker.seated and garage.seated_craft == Pilot.TALON and hull != null and hull.mesh == _talon_hull(next),
		"Boarded, the craft is the Talon and its cab is the Talon's plated hull in its paint")
	var runup: Node = bay.get_node_or_null("Runup")
	check(runup != null and runup.sim.P.vehicle == Pilot.TALON, "Its run-up is the Talon's (its engines' sounds are the Phaethon's bank)")
	runup.work("handling", 1)
	garage.launch_flight()
	var flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == Pilot.TALON and flight.sim.P.handling == "starfighter" and Settings.selected_craft() == Pilot.TALON
		and Settings.craft_setup(Pilot.TALON) == {"handling": "starfighter"} and Settings.craft_setup(Pilot.STANDARD).is_empty(),
		"Launched, the flight is the Talon's, with the MODE moved in its bay, saved for the Talon alone (%s)" % [Settings.craft_setup(Pilot.TALON)])
	# ---- parked, it is offered the garage and arrives at the Phaethon's bay
	check(flight.can_visit_garage(), "A parked Talon is offered the garage")
	var overlay = root.get_node("ReleasePause")
	overlay.set_paused(true)
	var button := overlay.find_child("Garage", true, false) as Button
	if not check(button != null and not button.disabled, "The pause menu's Pilot garage is on for a parked Talon"):
		overlay.set_paused(false)
		return
	button.pressed.emit()
	garage = await _next(GARAGE)
	if garage == null:
		return
	hall = garage.environment
	await _frames(2)
	var returned: Node = hall.bay_node(Pilot.STANDARD).get_node_or_null("Runup")
	check(hall.nearest_bay(garage.walker.global_position) == Pilot.STANDARD and hall.bay_craft(Pilot.STANDARD) == Pilot.TALON
		and returned != null and returned.telemetry.handling == "starfighter",
		"It arrives at the Phaethon's bay, the Talon standing there with its switches as it parked")
	# ---- a run-up bay refuses the swap (a desktop flight's engines run from its spawn: it arrives with them running)
	check(returned != null and returned.startup.batt and returned.startup.all_running(), "The parked desktop Talon's engines arrive running in its bay")
	# heard from outside, as a garage that is not muted plays them: the Phaethon's own idle (the Talon's sound bank)
	returned._muted = false
	returned._exterior_sound()
	returned._muted = true
	check(returned._outside.size() == 2 and returned._outside.all(func(e): return e.stream != null),
		"Heard from the floor, the Talon's running engines play the Phaethon's own idle (%d emitters)" % returned._outside.size())
	_key(KEY_P)
	await _frames(1)
	check(hall.bay_craft(Pilot.STANDARD) == Pilot.TALON and Settings.phaethon_body() == Pilot.TALON and garage._prompts._status.visible
		and garage._prompts._status.text == garage.REFUSED_RUNNING,
		"With its engines running, the Phaethon's bay refuses the swap and says why (\"%s\")" % garage._prompts._status.text)
	# ---- Fly from the menu afterwards
	garage.return_to_menu()
	var menu = await _next(UI.MENU_SCENE)
	if menu == null:
		return
	check(menu.find_child("FlyCraft", true, false).text.begins_with("Craft: Phaethon Talon"), "The menu names the Talon as the craft Fly will use")
	menu.choose_course("range")
	menu.fly()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == Pilot.TALON and flight.sim.P.handling == "starfighter", "Fly from the menu flies the Talon, in its saved set-up")
	# ---- the next visit finds the Talon there; a parked Phaethon stands the Phaethon there again
	menu = await _to_menu()
	if menu == null:
		return
	menu._open_garage()
	garage = await _next(GARAGE)
	if garage == null:
		return
	check(garage.environment.bay_craft(Pilot.STANDARD) == Pilot.TALON, "The next visit from the menu finds the Talon in the Phaethon's bay")
	garage.return_to_menu()
	menu = await _next(UI.MENU_SCENE)
	if menu == null:
		return
	Settings.set_selected_craft(Pilot.STANDARD)
	menu.choose_course("range")
	menu.fly()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	overlay.set_paused(true)
	(overlay.find_child("Garage", true, false) as Button).pressed.emit()
	garage = await _next(GARAGE)
	if garage == null:
		return
	check(garage.environment.bay_craft(Pilot.STANDARD) == Pilot.STANDARD and Settings.phaethon_body() == Pilot.STANDARD
		and garage.environment.nearest_bay(garage.walker.global_position) == Pilot.STANDARD,
		"A parked Phaethon arrives at its bay with the Phaethon standing there again")


## The Talon's plated hull in a paint, as the garage builds it (its palette, Talon.paint, and the livery both that paint).
func _talon_hull(livery: String) -> ArrayMesh:
	var was: String = CM.Talon.paint
	CM.Talon.paint = livery
	var mesh := CM.pod_hull_in(livery, false, true)
	CM.Talon.paint = was
	return mesh


func _to_menu() -> Node:
	var overlay = root.get_node("ReleasePause")
	overlay.set_paused(true)
	overlay.return_to_menu()
	return await _next(UI.MENU_SCENE)
