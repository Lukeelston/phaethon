## The menu/garage split (docs/superpowers/plans/2026-11-25-menu-garage-split.md; Luke: "the main menu should hold the
## map/game mode, but then any vehicle or additional adjustments should be made in codex's new garage", "Keep quick
## Fly"): the main menus choose where and how to fly and offer two actions, Fly (at once, in the craft last used) and
## Pilot garage (Codex's workshop, bound for the chosen map). The craft selector and the paint row leave them.
##   desktop   both layouts (over the title and plain): no Pilot craft or Paint button and no craft selector; Fly and
##             Garage; the six option rows; the remembered course chosen on entry, marked and named on Fly; a course
##             button chooses (no flight), marks it, names it on Fly and gives Fly the keyboard; Pilot garage bound for
##             the chosen course, and back at the menu that course chosen again; Fly flies the saved craft with its
##             saved switches on the chosen course, once, and Pilot garage after it does nothing; over the title, the
##             turntable shows the saved craft and only Role turns the camera to it
##   headset   the board (release/vr_menu.gd): no Pilot craft or Paint row and no craft selector; the stick's order is
##             the courses, the two switches, the six option rows, Fly, Pilot garage, Quit; the remembered course chosen
##             on entry and named on Fly; choose_course names another on Fly; A on a course row chooses it (no flight)
##             and moves the highlight to Fly; the turntable shows the saved craft, and Role, the one row that changes
##             it, re-dresses it and swings the board aside, every other row bringing the board back; Pilot garage bound
##             for the chosen course, and back at the board that course chosen again; Fly flies the saved craft with its
##             saved switches, cold, once, and Pilot garage after it does nothing
## Uses its own prefs file; puts View's statics, both menus' remembered courses, Title.enabled and vr_prefs.json back.
## Run headless with --xr-mode off -s res://tests/test_menu_split.gd -- --mute. Prints MENU SPLIT PASS.
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Garage := preload("res://release/garage_route.gd")
const Menu := preload("res://release/menu.gd")
const VrMenu := preload("res://release/vr_menu.gd")
const Title := preload("res://release/title_stage.gd")
const GARAGE_SCENE := "res://garage/garage.tscn"
const OPTIONS := ["Start:", "Time:", "Weather:", "Chase:", "Role:", "Raids:"]
var checks := 0
var failures := 0
var changes := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func _frames(count: int) -> void:
	for tick in count:
		await process_frame


func _scene(path: String) -> bool:
	var until := Time.get_ticks_msec() + 20000
	while current_scene == null or current_scene.scene_file_path != path:
		if Time.get_ticks_msec() > until:
			return check(false, "Expected scene " + path)
		await process_frame
	await _frames(2)
	return true


func _name(course: String) -> String:
	return UI.COURSES[UI.course_index(course)].name


func _course(menu: Node, course: String) -> Button:
	return menu.find_child("Course_" + course, true, false) as Button


## Is `course` the chosen one on the menu: its button marked, the others not, Fly naming it?
func _chosen(menu: Node, course: String) -> bool:
	var fly := menu.find_child("Fly", true, false) as Button
	if fly == null or fly.text != "Fly — " + _name(course) or menu.selected_course != course:
		return false
	for entry: Dictionary in UI.COURSES:
		var button := _course(menu, entry.id)
		if button == null or button.text != ("●  " if entry.id == course else "    ") + entry.name:
			return false
	return true


func _counted() -> void:
	changes += 1


## Is `course` the chosen one on the headset's board: its row marked, the others not, Fly naming it?
func _board_chosen(menu: Node, course: String) -> bool:
	if menu.selected_course != course or menu.start_button.text != "Fly — " + _name(course):
		return false
	for i in UI.COURSES.size():
		if menu.buttons[i].text != ("●  " if UI.COURSES[i].id == course else "    ") + UI.COURSES[i].name:
			return false
	return true


## A row of the headset's board as the stick's order names it: Fly and Garage by their node names, the rest by their text's head.
func _row(b: Button) -> String:
	if String(b.name) in ["Fly", "Garage"]:
		return String(b.name)
	return b.text.strip_edges().get_slice(":", 0).trim_prefix("●").strip_edges()


func _layout(titled: bool) -> void:
	var layout := "over the title" if titled else "plain"
	Title.enabled = titled
	Settings.set_selected_craft("kiln")
	Settings.set_craft_setup("kiln", {"handling": "starfighter"})
	Menu.remembered_course = "eridanus"
	change_scene_to_file(UI.MENU_SCENE)
	if not await _scene(UI.MENU_SCENE):
		return
	var menu = current_scene
	check((menu.stage != null) == titled, "%s: the menu is the layout asked for" % layout)
	# what the menu holds
	var unwanted := []
	var options := []
	for b: Button in menu.find_children("*", "Button", true, false):
		if b.text.contains("Pilot craft") or b.text.contains("Paint"):
			unwanted.append(b.text)
		for prefix: String in OPTIONS:
			if b.text.begins_with(prefix):
				options.append(prefix)
	check(unwanted.is_empty() and menu.get("craft_selector") == null, "%s: no Pilot craft or Paint button and no craft selector (%s)" % [layout, unwanted])
	var fly := menu.find_child("Fly", true, false) as Button
	var garage := menu.find_child("Garage", true, false) as Button
	check(fly != null and garage != null and garage.text == "Pilot garage", "%s: the menu has its Fly and Pilot garage buttons" % layout)
	options.sort()
	var wanted: Array = OPTIONS.duplicate()
	wanted.sort()
	check(options == wanted, "%s: the six option rows, each once (%s)" % [layout, options])
	if fly == null or garage == null:
		return
	# on entry the remembered course is the chosen one
	check(_chosen(menu, "eridanus"), "%s: on entry the remembered course is chosen, marked and named on Fly (\"%s\", \"%s\")" % [layout, fly.text, _course(menu, "eridanus").text])
	if titled:
		check(menu.stage.show_vehicle == "kiln", "%s: the turntable shows the saved craft (%s)" % [layout, menu.stage.show_vehicle])
		check(menu.look_buttons.size() == 1 and menu.look_buttons[0].text.begins_with("Role:"), "%s: only Role turns the camera to the turntable (%s)" % [layout, menu.look_buttons.map(func(b): return b.text)])
	# a course button chooses: no flight, the course marked and named on Fly, the keyboard on Fly
	_course(menu, "carving").pressed.emit()
	await _frames(3)
	check(current_scene == menu, "%s: a course button starts no flight" % layout)
	check(_chosen(menu, "carving") and Menu.remembered_course == "carving", "%s: ... it marks that course, names it on Fly and is remembered (\"%s\")" % [layout, fly.text])
	check(menu.get_viewport().gui_get_focus_owner() == fly, "%s: ... and gives Fly the keyboard (%s)" % [layout, menu.get_viewport().gui_get_focus_owner()])
	# Pilot garage: bound for the chosen course, and back at the menu that course is chosen
	_course(menu, "range").pressed.emit()
	garage.pressed.emit()
	check(Garage.destination_label() == _name("range"), "%s: Pilot garage enters bound for the chosen course (%s)" % [layout, Garage.destination_label()])
	if not await _scene(GARAGE_SCENE):
		return
	Menu.remembered_course = "gp"      # (as if forgotten: the way back must hand the menu its course)
	Garage.return_to_menu(self)
	if not await _scene(UI.MENU_SCENE):
		return
	menu = current_scene
	check(_chosen(menu, "range"), "%s: back from the garage the course chosen before the visit is chosen (%s)" % [layout, menu.selected_course])
	# Fly: the saved craft with its saved switches, on the chosen course, once; Pilot garage after it does nothing
	fly = menu.find_child("Fly", true, false) as Button
	_course(menu, "network").pressed.emit()      # (a map with no start handling of its own: the saved one is flown)
	changes = 0
	scene_changed.connect(_counted)
	fly.pressed.emit()
	var flown: String = View.vehicle_override
	check(flown == "kiln" and View.garage_on_entry.get("handling") == "starfighter" and View.track_override == UI.course_overrides("network")[0],
		"%s: Fly flies the saved craft (%s) with its saved switches (%s) on the chosen course (%s)" % [layout, flown, View.garage_on_entry, View.track_override])
	View.vehicle_override = "marker"
	menu.fly()
	check(View.vehicle_override == "marker", "%s: Fly pressed again does nothing" % layout)
	menu._open_garage()
	check(Garage.destination_label() == _name("range"), "%s: Pilot garage after Fly does nothing (%s)" % [layout, Garage.destination_label()])
	View.vehicle_override = flown
	await _frames(12)
	scene_changed.disconnect(_counted)
	check(changes == 1 and current_scene is View and current_scene.sim.kind == "network",
		"%s: one scene change, to the chosen course's flight (%d changes, %s)" % [layout, changes, current_scene.scene_file_path if current_scene else "none"])


## The headset's board (release/vr_menu.gd), as the desktop's: choose a map, then Fly or Pilot garage.
func _headset() -> void:
	Title.enabled = true
	Settings.set_selected_craft("vesper")
	Settings.set_craft_setup("vesper", {"slide": false})
	VrMenu.remembered_course = "eridanus"
	change_scene_to_file(UI.VR_MENU_SCENE)
	if not await _scene(UI.VR_MENU_SCENE):
		return
	var menu = current_scene
	menu.set_process(false)      # (no headset: this test is its controller)
	# what the board holds, in the stick's order
	var every: Array = []
	every.append_array(menu.buttons)
	every.append_array(menu.find_children("*", "Button", true, false))
	var unwanted := []
	for b: Button in every:
		if (b.text.contains("Pilot craft") or b.text.contains("Paint")) and not unwanted.has(b.text):
			unwanted.append(b.text)
	check(unwanted.is_empty() and menu.get("craft_selector") == null, "headset: no Pilot craft or Paint row and no craft selector (%s)" % [unwanted])
	var n: int = UI.COURSES.size()
	var rows: Array = menu.buttons
	var named: Array = rows.map(_row)
	var fly: Button = menu.start_button
	var at := n + 2 + OPTIONS.size()      # (where Fly stands in the stick's order)
	var ordered := false
	if rows.size() == at + 3:
		var options: Array = named.slice(n + 2, at)
		options.sort()
		var wanted: Array = OPTIONS.map(func(o: String) -> String: return o.trim_suffix(":"))
		wanted.sort()
		ordered = options == wanted and rows[n] == menu.collision_checkbox and rows[n + 1] == menu.partner_checkbox and rows[at] == fly and menu.start_index == at \
			and named[at] == "Fly" and named[at + 1] == "Garage" and rows[at + 1].text == "Pilot garage" and named[at + 2] == "Quit to desktop"
		for i in n:
			ordered = ordered and rows[i].text.strip_edges().ends_with(UI.COURSES[i].name)
	check(ordered, "headset: the stick's order is the courses, the two switches, the six option rows, Fly, Pilot garage, Quit (%s)" % " | ".join(named))
	# on entry the remembered course is chosen; choose_course names another on Fly; A on a course row chooses it and
	# moves the highlight to Fly (Enter, Enter flies it, as on the desktop)
	check(_board_chosen(menu, "eridanus"), "headset: on entry the remembered course is chosen, marked and named on Fly (\"%s\")" % fly.text)
	menu.choose_course("network")
	check(_board_chosen(menu, "network") and VrMenu.remembered_course == "network", "headset: choose_course marks another course, names it on Fly and is remembered (\"%s\")" % fly.text)
	menu.focus_row(UI.course_index("carving"))
	menu.activate()
	check(current_scene == menu and not menu.launching and _board_chosen(menu, "carving") and menu.focus_index == menu.start_index and menu.buttons[menu.focus_index] == fly,
		"headset: A on a course row chooses it (no flight) and moves the highlight to Fly (row %d of Fly's %d, \"%s\")" % [menu.focus_index, menu.start_index, fly.text])
	# the turntable: the saved craft on it; Role, the one row that changes it, re-dresses it (the patrol's own paint) and
	# swings the board aside while it has the highlight; every other row brings the board back
	check(menu.stage != null and menu.stage.show_vehicle == "vesper", "headset: the turntable shows the saved craft (%s)" % (menu.stage.show_vehicle if menu.stage != null else "no title"))
	var role: Button = null
	for b: Button in menu.buttons:
		if b.text.begins_with("Role:"):
			role = b
	check(role != null and menu.look_buttons.size() == 1 and menu.look_buttons[0] == role, "headset: Role is the one row that changes the turntable (%s)" % [menu.look_buttons.map(func(b): return b.text)])
	if role == null or menu.stage == null:
		return
	var dressed: String = menu.stage.show_livery
	role.pressed.emit()
	var patrol: String = menu.stage.show_livery
	role.pressed.emit()
	check(dressed != "police" and patrol == "police" and menu.stage.show_livery == dressed, "headset: a press of Role re-dresses the craft on show in the patrol's paint, and another back (%s, %s, %s)" % [dressed, patrol, menu.stage.show_livery])
	var role_row: int = menu.buttons.find(role)
	menu.focus_row(role_row)
	menu.update_swing(VrMenu.SWING_DWELL * 0.5)
	var passing: float = menu.swing
	menu.update_swing(VrMenu.SWING_DWELL)
	check(passing == 0.0 and menu.swing > 0.0, "headset: with the highlight on Role longer than SWING_DWELL the board swings aside (%.2f, then %.2f)" % [passing, menu.swing])
	var stayed := []
	for i in menu.buttons.size():
		if i == role_row:
			continue
		menu.focus_row(role_row)
		menu.update_swing(VrMenu.SWING_DWELL + VrMenu.SWING_S)
		var out: float = menu.swing
		menu.focus_row(i)
		menu.update_swing(VrMenu.SWING_S)
		var back: float = menu.swing
		menu.update_swing(1.0)
		if out != 1.0 or back != 0.0 or menu.swing != 0.0:
			stayed.append("%s (%.2f, %.2f, %.2f)" % [_row(menu.buttons[i]), out, back, menu.swing])
	check(stayed.is_empty(), "headset: on every other row the board swings back and stays (wrong: %s)" % [stayed])
	# Pilot garage: bound for the chosen course, and back at the board that course is chosen
	menu.choose_course("range")
	(menu.find_child("Garage", true, false) as Button).pressed.emit()
	check(Garage.destination_label() == _name("range"), "headset: Pilot garage enters bound for the chosen course (%s)" % Garage.destination_label())
	if not await _scene(GARAGE_SCENE):
		return
	VrMenu.remembered_course = "gp"      # (as if forgotten: the way back must hand the board its course)
	Garage.return_to_menu(self)
	if not await _scene(UI.VR_MENU_SCENE):
		return
	menu = current_scene
	menu.set_process(false)
	check(_board_chosen(menu, "range"), "headset: back from the garage the course chosen before the visit is chosen (%s)" % menu.selected_course)
	# Fly: the saved craft with its saved switches, on the chosen course, cold, once; Pilot garage after it does nothing
	menu.choose_course("network")
	changes = 0
	scene_changed.connect(_counted)
	Cockpit.cold_on_entry = false      # (so that only Fly can have set them)
	Cockpit.require_neutral_on_entry = false
	menu.start_selected()
	var flown: String = View.vehicle_override
	var entry: Dictionary = View.garage_on_entry
	check(flown == "vesper" and entry == {"slide": false} and View.track_override == "network" and Cockpit.cold_on_entry and Cockpit.require_neutral_on_entry,
		"headset: Fly flies the saved craft (%s) with its saved switches (%s) on the chosen course (%s), from cold (%s)" % [flown, entry, View.track_override, Cockpit.cold_on_entry])
	View.vehicle_override = "marker"
	menu.start_selected()
	check(View.vehicle_override == "marker", "headset: Fly pressed again does nothing")
	menu._open_garage()
	check(Garage.destination_label() == _name("range"), "headset: Pilot garage after Fly does nothing (%s)" % Garage.destination_label())
	View.vehicle_override = flown
	await _frames(12)
	scene_changed.disconnect(_counted)
	check(changes == 1 and current_scene is Cockpit and current_scene.sim.kind == "network",
		"headset: one scene change, to the chosen course's flight in the headset's cockpit (%d changes, %s)" % [changes, current_scene.scene_file_path if current_scene else "none"])


func _run() -> void:
	var settings_before := Settings.prefs_path
	var had_vr_prefs := FileAccess.file_exists(Cockpit.PREFS)
	var vr_prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if had_vr_prefs else PackedByteArray()
	var remembered_before: String = Menu.remembered_course
	var board_remembered_before: String = VrMenu.remembered_course
	var vehicle_before: String = View.vehicle_override
	var track_before: String = View.track_override
	var job_before: String = View.job_override
	var spot_before: String = View.spot_override
	var entry_before: Dictionary = View.garage_on_entry
	var pad_before: bool = View.pad_start
	Settings.prefs_path = "user://test-menu-split-%d.cfg" % OS.get_process_id()
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))

	await _layout(true)
	await _layout(false)
	await _headset()

	Title.enabled = true
	Menu.remembered_course = remembered_before
	VrMenu.remembered_course = board_remembered_before
	View.vehicle_override = vehicle_before
	View.track_override = track_before
	View.job_override = job_before
	View.spot_override = spot_before
	View.garage_on_entry = entry_before
	View.pad_start = pad_before
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = settings_before
	if had_vr_prefs:
		var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		file.store_buffer(vr_prefs)
		file.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	print("MENU SPLIT %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
