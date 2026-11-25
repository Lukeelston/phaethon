## The per-craft switch set-up store (release/game_settings.gd's craft_setup) and Garage.fly, the menus' Fly button:
## it starts at once in the craft last used, with that craft's saved switches and paint. Nothing saved is the Phaethon
## in its Factory paint; a hand-edited value is dropped; the engine state is never saved; a launch in one craft leaves
## another's set-up as it was; a half-valid stored set-up keeps its valid part; a set-up for a craft that is not one is
## not saved. A course with its own start handling (the sim's rule: a Grand Prix circuit Starfighter, Carving
## Speedcraft) keeps it: Fly leaves out the saved handling there, not the slide; the Range and the Network take the
## saved handling. The Talon with nothing saved flies with no set-up.
## The rule, as sequences through the menus, the flights, the pause menu and the garage (the controller's ruling of
## 2026-11-25: the set-up is what the pilot last set for a craft, and nothing else):
##   desktop   Fly to the Grand Prix, Esc, Pilot garage (saves nothing), walk back, Fly to the Sprint: Speedcraft; M there
##             is saved, M on the Grand Prix is the course's and is not. A bay's MODE moved and launched is saved, and the
##             next visit's untouched launch and Fly both start in it, and the pause menu's restart of that Fly too; a
##             bay launch onto the Grand Prix with "speed"
##             saved starts in the course's Starfighter, and that flight's live handling, handed back to its bay and
##             launched with untouched, is not saved
##   headset   Fly, OPTIONS, PILOT GARAGE (saves nothing), walk back, Fly, MODE thrown to Starfighter, hold Menu, Fly:
##             Starfighter. On the Grand Prix a MODE throw is not saved, a SLIDE throw is. The Kiln's saved slide (GRIP,
##             from its bay) is its flight's alone, a city's GP entered from it included: not written to
##             vr_prefs.json, not the Vesper's start
## Uses its own prefs file; puts View's statics, the menus' remembered courses, Title.enabled, the cockpit's slide and
## vr_prefs.json back.
## Run headless with --xr-mode off -s res://tests/test_fly_last_used.gd -- --mute
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Switch := preload("res://vr/mode_switch.gd")
const Garage := preload("res://release/garage_route.gd")
const Menu := preload("res://release/menu.gd")
const VrMenu := preload("res://release/vr_menu.gd")
const Title := preload("res://release/title_stage.gd")
const GARAGE_SCENE := "res://garage/garage.tscn"
const VR_SCENE := "res://vr.tscn"
var checks := 0
var failures := 0
var _left := 0      # the instance id of the scene the sequence is in (_next waits for another)


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


## A launch changes the scene on the next idle frame; let it settle (the flight is not under test) before the next.
func _settle() -> void:
	for tick in 5:
		await process_frame


func _frames(count: int) -> void:
	for tick in count:
		await process_frame


## The next scene, at `path` (a launch or a way back changes it on an idle frame), once it has settled; null if it never came.
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


## A sequence starts with nothing saved.
func _fresh() -> void:
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))


func _vr_prefs() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else null
	return d if d is Dictionary else {}


## The pilot's own headset choices, as a player's vr_prefs.json has them, read again by the next headset flight.
func _seed_vr_prefs(prefs: Dictionary) -> void:
	var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
	file.store_string(JSON.stringify(prefs))
	file.close()
	Cockpit._slide_loaded = false


## Walk to a bay and board its craft.
func _board(garage: Node, craft: String) -> bool:
	garage.walker.set_seated(false, garage.environment.boarding_transform(craft))
	garage.walker.interact_requested.emit()
	return check(garage.walker.seated and garage.seated_craft == craft, "The pilot boards the %s (%s)" % [craft, garage.seated_craft])


## A switch in the seated bay, worked as its cockpit's lever works it (garage/garage_runup.gd work).
func _bay_switch(garage: Node, craft: String, control: String, dir: int) -> void:
	garage.environment.bay_node(craft).get_node("Runup").work(control, dir)


## The desktop pause menu's Return to course menu.
func _desktop_to_menu() -> Node:
	var overlay = root.get_node("ReleasePause")
	overlay.set_paused(true)
	overlay.return_to_menu()
	return await _next(UI.MENU_SCENE)


## The desktop pause menu's Pilot garage, from a flight parked at its launch point; false if it is not offered.
func _desktop_park(label: String) -> bool:
	var overlay = root.get_node("ReleasePause")
	overlay.set_paused(true)
	var button := overlay.find_child("Garage", true, false) as Button
	if not check(button != null and not button.disabled, label + ": the parked flight offers the garage"):
		overlay.set_paused(false)
		return false
	button.pressed.emit()
	return true


## The headset's quick menu: OPTIONS, then PILOT GARAGE (vr_cockpit.gd menu_choose), from a flight parked at its launch point.
func _headset_park(flight: Node) -> bool:
	flight.menu_open(true)
	for choice in ["options", "garage"]:
		for index in flight.menu.items.size():
			if flight.menu.key() == choice:
				break
			flight.menu.move(1)
		if not check(flight.menu.key() == choice, "headset: the quick menu offers " + choice):
			flight.menu_open(false)
			return false
		flight.menu_choose()
	return true


## A hand pushed through one of the cockpit's guarded switches (MODE, SLIDE: vr/mode_switch.gd), down or up, the way the
## cockpit's hands loop works them (vr_cockpit.gd _work_controls); the other hand well away.
func _throw(flight: Node, sw: Node3D, down: bool) -> void:
	var hand := XRController3D.new()
	var other := XRController3D.new()
	root.add_child(hand)
	root.add_child(other)
	other.global_position = Vector3(0.0, -100.0, 0.0)
	flight.hands_live = true
	flight._await_neutral_controls = false
	for y: float in ([0.03, 0.0] if down else [0.0, 0.03]):
		hand.global_position = sw.global_transform * Vector3(0.0, y, 0.05) - hand.global_basis * Switch.TIP
		if sw == flight.slide_switch:
			flight._work_controls(hand, other, 1.0 / 60.0)
		else:
			flight._work_controls(other, hand, 1.0 / 60.0)
	hand.queue_free()
	other.queue_free()


func _run() -> void:
	var settings_before := Settings.prefs_path
	var vehicle_before: String = View.vehicle_override
	var track_before: String = View.track_override
	var job_before: String = View.job_override
	var spot_before: String = View.spot_override
	var entry_before: Dictionary = View.garage_on_entry
	var pad_before: bool = View.pad_start
	var title_before: bool = Title.enabled
	var remembered_before: String = Menu.remembered_course
	var board_remembered_before: String = VrMenu.remembered_course
	var slide_before: bool = Cockpit.slide_feel
	var slide_loaded_before: bool = Cockpit._slide_loaded
	var had_vr_prefs := FileAccess.file_exists(Cockpit.PREFS)
	var vr_prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if had_vr_prefs else PackedByteArray()
	Settings.prefs_path = "user://test-fly-last-used-%d.cfg" % OS.get_process_id()
	_fresh()

	check(Settings.selected_craft() == Pilot.STANDARD, "Nothing saved: the Phaethon is the craft")
	check(Settings.craft_setup(Pilot.STANDARD).is_empty(), "Nothing saved: no switch set-up")
	check(Livery.is_factory(Livery.saved_for(Pilot.STANDARD)) and Livery.built(Pilot.STANDARD) == "ember",
		"Nothing saved: the Phaethon is built in its Factory paint")

	Settings.set_craft_setup("kiln", {"handling": "starfighter", "slide": false, "startup": 1, "paint": "x"})
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": false},
		"Only handling and slide are kept (the engine state and the rest are dropped): %s" % Settings.craft_setup("kiln"))
	Settings.set_craft_setup("kiln", {"slide": true})
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": true}, "A later save merges over the saved set-up")
	check(Settings.craft_setup(Pilot.STANDARD).is_empty(), "One craft's set-up is not another's")
	Settings.set_craft_setup("no-such-craft", {"handling": "starfighter"})
	var stored := ConfigFile.new()
	stored.load(Settings.prefs_path)
	check(Settings.craft_setup(Pilot.STANDARD).is_empty() and not stored.has_section_key("garage", "no-such-craft"),
		"A set-up for a craft that is not one is not saved (not as the Phaethon's either): %s" % Settings.craft_setup(Pilot.STANDARD))

	var config := ConfigFile.new()
	config.load(Settings.prefs_path)
	config.set_value("garage", "kiln", {"handling": "banana", "slide": "yes"})
	config.save(Settings.prefs_path)
	check(Settings.craft_setup("kiln").is_empty(), "A hand-edited value is dropped")
	Settings.set_craft_setup("kiln", {"handling": "banana"})
	check(Settings.craft_setup("kiln").is_empty(), "An invalid handling saves nothing")
	config.load(Settings.prefs_path)
	check(config.get_value("garage", "kiln") == {"handling": "banana", "slide": "yes"}, "... and leaves the stored value alone")
	config.set_value("garage", "kiln", {"handling": "starfighter", "slide": "yes"})
	config.save(Settings.prefs_path)
	check(Settings.craft_setup("kiln") == {"handling": "starfighter"}, "A half-valid stored set-up keeps its valid handling only: %s" % Settings.craft_setup("kiln"))
	Settings.set_craft_setup("kiln", {"handling": "starfighter", "slide": true})

	Garage.launch_flight(self, "vesper", {"vesper": {"handling": "starfighter"}, "kiln": {"slide": false}})
	check(Settings.selected_craft() == "vesper", "A launch saves the selected craft")
	check(Settings.craft_setup("vesper") == {"handling": "starfighter"}, "A launch saves the launched craft's switches")
	check(Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": true}, "A launch in the Vesper leaves the Kiln's set-up as it was")
	await _settle()

	Settings.set_selected_craft("kiln")
	Garage.fly(self, false, "range")
	check(View.vehicle_override == "kiln", "Fly flies the selected craft")
	check(View.garage_on_entry == {"handling": "starfighter", "slide": true}, "Fly carries the saved set-up onto the pad: %s" % View.garage_on_entry)
	check(View.track_override == UI.course_overrides("range")[0], "Fly starts at the chosen course")
	await _settle()
	Garage.fly(self, false, "network")
	check(View.garage_on_entry == {"handling": "starfighter", "slide": true} and View.track_override == "network",
		"Fly carries the saved handling onto the Network too: %s" % View.garage_on_entry)
	await _settle()

	# a course with its own start handling keeps it; the saved slide still comes
	Settings.set_craft_setup("kiln", {"handling": "speed"})
	Garage.fly(self, false, "gp")
	check(View.garage_on_entry == {"slide": true} and View.track_override == "gp",
		"Fly on the Grand Prix leaves out the saved handling (the course starts in Starfighter), keeps the slide: %s" % View.garage_on_entry)
	await _settle()
	Settings.set_selected_craft("orrery")
	Settings.set_craft_setup("orrery", {"handling": "starfighter"})
	Garage.fly(self, false, "carving")
	check(View.vehicle_override == "orrery" and View.garage_on_entry == {} and View.track_override == "carving",
		"Fly on Carving leaves out the saved handling (the course starts in Speedcraft): %s" % View.garage_on_entry)
	check(Settings.craft_setup("orrery") == {"handling": "starfighter"} and Settings.craft_setup("kiln") == {"handling": "speed", "slide": true},
		"... and the saved set-ups are kept as they were")
	await _settle()

	Settings.set_selected_craft("talon")
	var coat := ""
	for entry: Array in Livery.choices_for("talon"):
		if not Livery.is_factory(entry[0]):
			coat = entry[0]
			break
	Settings.set_choice(Livery.key_for("talon"), coat)
	View.vehicle_override = ""
	Garage.fly(self, false, "range")
	check(View.vehicle_override == "talon" and not coat.is_empty() and Livery.built("talon") == coat,
		"Fly flies the Talon (it has no garage bay) in its saved paint (%s)" % coat)
	check(Settings.craft_setup("talon").is_empty() and View.garage_on_entry == {}, "... with nothing saved for it, it is handed no set-up: %s" % View.garage_on_entry)
	await _settle()

	View.vehicle_override = "marker"
	View.garage_on_entry = {"marker": true}
	var setup_before := Settings.craft_setup("kiln")
	Settings.set_selected_craft("kiln")
	Garage.fly(self, false, "no-such-course")
	check(View.vehicle_override == "marker" and View.garage_on_entry == {"marker": true} and Settings.selected_craft() == "kiln"
		and Settings.craft_setup("kiln") == setup_before, "An unknown course changes nothing")
	await _settle()

	# the rule, as sequences
	Title.enabled = false      # (the plain menus: the title's art is not under test)
	await _desktop_course_handling()
	await _desktop_bay_launches()
	await _headset_mode_throw()
	await _headset_slide_lent()
	change_scene_to_file(UI.MENU_SCENE)      # (out of the last flight before the statics are put back)
	await _next(UI.MENU_SCENE)

	View.vehicle_override = vehicle_before
	View.track_override = track_before
	View.job_override = job_before
	View.spot_override = spot_before
	View.garage_on_entry = entry_before
	View.pad_start = pad_before
	Title.enabled = title_before
	Menu.remembered_course = remembered_before
	VrMenu.remembered_course = board_remembered_before
	Cockpit.slide_feel = slide_before
	Cockpit._slide_loaded = slide_loaded_before
	if had_vr_prefs:
		var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		file.store_buffer(vr_prefs)
		file.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	_fresh()
	Settings.prefs_path = settings_before
	print("FLY LAST USED %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


## The desktop: Fly to the Grand Prix (the course's Starfighter), Esc, Pilot garage: nothing saved; walk back, Fly to the
## 100-mile Sprint: Speedcraft. M there is the pilot's and is saved; M on the Grand Prix is the course's and is not.
func _desktop_course_handling() -> void:
	_fresh()
	Settings.set_selected_craft("kiln")
	change_scene_to_file(UI.MENU_SCENE)
	var menu = await _next(UI.MENU_SCENE)
	if menu == null:
		return
	menu.choose_course("gp")
	menu.fly()
	var flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and flight.sim.P.handling == "starfighter", "desktop: Fly to the Grand Prix starts the Kiln in the course's Starfighter (%s)" % flight.sim.P.handling)
	if not _desktop_park("desktop, the Grand Prix"):
		return
	check(Settings.craft_setup("kiln").is_empty(), "desktop: entering the garage from a parked Grand Prix flight saves nothing (%s)" % Settings.craft_setup("kiln"))
	var garage = await _next(GARAGE_SCENE)
	if garage == null:
		return
	garage.return_to_menu()
	menu = await _next(UI.MENU_SCENE)
	if menu == null:
		return
	menu.choose_course("range")
	menu.fly()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "speed", "desktop: walked back from the garage, Fly to the 100-mile Sprint starts in Speedcraft (%s)" % flight.sim.P.handling)
	flight.toggle_handling()      # (M)
	check(flight.handling_ask == "starfighter" and Settings.craft_setup("kiln") == {"handling": "starfighter"},
		"desktop: M on the Sprint is saved to the craft's set-up (%s)" % Settings.craft_setup("kiln"))
	menu = await _desktop_to_menu()
	if menu == null:
		return
	menu.choose_course("gp")
	menu.fly()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	flight.toggle_handling()
	check(flight.handling_ask == "speed" and Settings.craft_setup("kiln") == {"handling": "starfighter"},
		"desktop: M on the Grand Prix is the course's, not saved (%s, %s)" % [flight.handling_ask, Settings.craft_setup("kiln")])


## The desktop's bays: the Kiln's MODE moved to Starfighter and launched (saved); the next visit, untouched, it launches in
## Starfighter, and Fly too. Its MODE moved to Speedcraft and launched (saved); a bay launch onto the Grand Prix, nothing
## moved, starts in the course's Starfighter; parked there, its live Starfighter is handed back to its bay, and launched
## with untouched it is flown (the bay shows it) and not saved.
func _desktop_bay_launches() -> void:
	_fresh()
	change_scene_to_file(UI.MENU_SCENE)
	var menu = await _next(UI.MENU_SCENE)
	if menu == null:
		return
	menu.choose_course("range")
	menu._open_garage()
	var garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	_bay_switch(garage, "kiln", "handling", 1)
	garage.launch_flight()
	var flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and flight.sim.P.handling == "starfighter" and Settings.craft_setup("kiln") == {"handling": "starfighter"},
		"desktop: day one, the Kiln's MODE moved to Starfighter in its bay: launched in it, and saved (%s, %s)" % [flight.sim.P.handling, Settings.craft_setup("kiln")])
	menu = await _desktop_to_menu()
	if menu == null:
		return
	menu.choose_course("range")
	menu._open_garage()
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	garage.launch_flight()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "starfighter", "desktop: the next visit, the Kiln launched untouched starts in its saved Starfighter (%s)" % flight.sim.P.handling)
	menu = await _desktop_to_menu()
	if menu == null:
		return
	menu.choose_course("range")
	menu.fly()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "starfighter", "desktop: ... and Fly starts it in Starfighter (%s)" % flight.sim.P.handling)
	var overlay = root.get_node("ReleasePause")
	overlay.set_paused(true)
	overlay.restart_game()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and flight.sim.P.handling == "starfighter", "desktop: ... and the pause menu's Restart this course restarts it in Starfighter (%s)" % flight.sim.P.handling)
	# the Grand Prix
	menu = await _desktop_to_menu()
	if menu == null:
		return
	menu.choose_course("range")
	menu._open_garage()
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	_bay_switch(garage, "kiln", "handling", -1)
	garage.launch_flight()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "speed" and Settings.craft_setup("kiln") == {"handling": "speed"},
		"desktop: the Kiln's MODE moved to Speedcraft: launched in it, and saved (%s, %s)" % [flight.sim.P.handling, Settings.craft_setup("kiln")])
	menu = await _desktop_to_menu()
	if menu == null:
		return
	menu.choose_course("gp")
	menu._open_garage()
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	garage.launch_flight()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.track_name == "gp" and flight.sim.P.handling == "starfighter",
		"desktop: a bay launch onto the Grand Prix with \"speed\" saved and no switch moved starts in the course's Starfighter (%s)" % flight.sim.P.handling)
	if not _desktop_park("desktop, a bay launch onto the Grand Prix"):
		return
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	garage.launch_flight()
	flight = await _next(UI.GAME_SCENE)
	if flight == null:
		return
	check(flight.sim.track_name == "gp" and flight.sim.P.handling == "starfighter" and Settings.craft_setup("kiln") == {"handling": "speed"},
		"desktop: the parked Grand Prix flight's Starfighter, handed back to its bay and launched with untouched, is flown and not saved (%s, %s)" % [flight.sim.P.handling, Settings.craft_setup("kiln")])


## The headset: Fly, OPTIONS, PILOT GARAGE: nothing saved; walk back, Fly, MODE thrown to Starfighter: saved; hold Menu,
## Fly: Starfighter. Then the Grand Prix: a MODE throw there is the course's and is not saved, a SLIDE throw is.
func _headset_mode_throw() -> void:
	_fresh()
	_seed_vr_prefs({"handling": "speed", "slide": "on"})
	Settings.set_selected_craft("kiln")
	change_scene_to_file(UI.VR_MENU_SCENE)
	var board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	board.set_process(false)      # (no headset: this test is its controller)
	board.choose_course("range")
	board.start_selected()
	var flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and flight.sim.P.handling == "speed", "headset: Fly starts the Kiln in the pilot's Speedcraft (%s)" % flight.sim.P.handling)
	if not _headset_park(flight):
		return
	check(Settings.craft_setup("kiln").is_empty(), "headset: OPTIONS, PILOT GARAGE from a parked flight saves nothing (%s)" % Settings.craft_setup("kiln"))
	var garage = await _next(GARAGE_SCENE)
	if garage == null:
		return
	garage.return_to_menu()
	board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	board.set_process(false)
	board.start_selected()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	_throw(flight, flight.mode_switch, true)
	check(flight.handling_ask == "starfighter" and Settings.craft_setup("kiln") == {"handling": "starfighter"},
		"headset: walked back, Fly, the MODE switch thrown to Starfighter in flight: saved to the craft's set-up (%s, %s)" % [flight.handling_ask, Settings.craft_setup("kiln")])
	flight.return_to_menu()      # (Menu held)
	board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	board.set_process(false)
	board.start_selected()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "starfighter", "headset: ... Menu held, Fly starts in Starfighter (%s)" % flight.sim.P.handling)
	# the Grand Prix
	flight.return_to_menu()
	board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	board.set_process(false)
	board.choose_course("gp")
	board.start_selected()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.handling == "starfighter" and flight.mode_switch.down and not flight.slide_switch.down,
		"headset: Fly to the Grand Prix, the course's Starfighter, the slide on (%s, %s)" % [flight.sim.P.handling, Cockpit.slide_feel])
	_throw(flight, flight.mode_switch, false)
	_throw(flight, flight.slide_switch, true)
	check(flight.handling_ask == "speed" and not Cockpit.slide_feel and Settings.craft_setup("kiln") == {"handling": "starfighter", "slide": false},
		"headset: on the Grand Prix a MODE throw is the course's, not saved; a SLIDE throw is (%s, %s, %s)" % [flight.handling_ask, Cockpit.slide_feel, Settings.craft_setup("kiln")])


## The headset's slide: the Kiln's SLIDE moved to GRIP in its bay and launched with onto the Network (saved: the Kiln's
## alone). Its flight is in GRIP, and so is the city's GP it goes on into; vr_prefs.json keeps the pilot's own SLIDE; the
## Vesper, with none saved, starts in the pilot's SLIDE; the Kiln again, in its own GRIP.
func _headset_slide_lent() -> void:
	_fresh()
	_seed_vr_prefs({"handling": "speed", "slide": "on"})
	change_scene_to_file(UI.VR_MENU_SCENE)
	var board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	board.set_process(false)
	board.choose_course("network")
	board._open_garage()
	var garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	_bay_switch(garage, "kiln", "slide", -1)
	garage.launch_flight()
	var flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and not Cockpit.slide_feel and Settings.craft_setup("kiln") == {"slide": false},
		"headset: the Kiln's SLIDE moved to GRIP in its bay: its flight is in GRIP, and it is saved for it (%s, %s)" % [Cockpit.slide_feel, Settings.craft_setup("kiln")])
	for city in flight.sim.cities:      # (on to a city's GP: the flight's scene again, on that circuit)
		if city.name == "DUNES":
			flight.sim.respawn_on(int(city.road), int(city.i), 1)
	flight.enter_city_gp()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.track_name == "gp_dunes" and flight.sim.P.vehicle == "kiln" and not Cockpit.slide_feel,
		"headset: ... and the city's GP it goes on into is still the Kiln's flight, in its GRIP (%s, %s)" % [flight.sim.track_name, Cockpit.slide_feel])
	flight.return_to_menu()      # (Menu held: it saves the pilot's headset choices)
	board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	check(_vr_prefs().get("slide") == "on", "headset: the Kiln's GRIP is not written to vr_prefs.json (%s)" % _vr_prefs().get("slide"))
	board.set_process(false)
	board._open_garage()
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "vesper"):
		return
	garage.launch_flight()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "vesper" and Cockpit.slide_feel and Settings.craft_setup("vesper").is_empty(),
		"headset: the Vesper, none saved, starts in the pilot's SLIDE, not the Kiln's GRIP (%s, %s)" % [Cockpit.slide_feel, Settings.craft_setup("vesper")])
	flight.return_to_menu()
	board = await _next(UI.VR_MENU_SCENE)
	if board == null:
		return
	check(_vr_prefs().get("slide") == "on", "headset: ... and vr_prefs.json still has the pilot's SLIDE (%s)" % _vr_prefs().get("slide"))
	board.set_process(false)
	board._open_garage()
	garage = await _next(GARAGE_SCENE)
	if garage == null or not _board(garage, "kiln"):
		return
	garage.launch_flight()
	flight = await _next(VR_SCENE)
	if flight == null:
		return
	check(flight.sim.P.vehicle == "kiln" and not Cockpit.slide_feel, "headset: the Kiln again, untouched: its own saved GRIP (%s)" % Cockpit.slide_feel)
