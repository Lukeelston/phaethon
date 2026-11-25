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
## Uses its own prefs file; puts View's statics, the menu's remembered course, Title.enabled and vr_prefs.json back.
## Run headless with --xr-mode off -s res://tests/test_menu_split.gd -- --mute. Prints MENU SPLIT PASS.
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Garage := preload("res://release/garage_route.gd")
const Menu := preload("res://release/menu.gd")
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


func _run() -> void:
	var settings_before := Settings.prefs_path
	var had_vr_prefs := FileAccess.file_exists(Cockpit.PREFS)
	var vr_prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if had_vr_prefs else PackedByteArray()
	var remembered_before: String = Menu.remembered_course
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

	Title.enabled = true
	Menu.remembered_course = remembered_before
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
