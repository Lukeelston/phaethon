## Partner settings, startup/pause menus and VR quick-menu input boundaries.
## Run with --mute. Saves and restores the exact existing preference bytes.
extends SceneTree

const Settings := preload("res://release/game_settings.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const UI := preload("res://release/release_config.gd")
var saved := {}
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	for path in [Settings.PREFS, Cockpit.PREFS]:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	if FileAccess.file_exists(Settings.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	check("partner defaults off", not Settings.driving_partner_enabled())
	check("launch flags override without persisting", Settings.resolve_driving_partner(PackedStringArray(["--partner"])) and not Settings.driving_partner_enabled())
	Settings.set_driving_partner(true)
	check("no-partner wins without overwriting saved on", not Settings.resolve_driving_partner(PackedStringArray(["--partner", "--no-partner"])) and Settings.driving_partner_enabled())
	var overlay = root.get_node("ReleasePause")
	for vr in [false, true]:
		change_scene_to_file(UI.VR_MENU_SCENE if vr else UI.MENU_SCENE)
		await scene_changed
		for course in UI.COURSES:
			var menu = current_scene
			menu.set_process(false)
			check("startup restores partner VR=%s" % vr, menu.partner_checkbox.button_pressed)
			menu.partner_checkbox.button_pressed = false
			check("startup can save partner off", not Settings.driving_partner_enabled())
			menu.partner_checkbox.button_pressed = true
			if vr:
				menu.choose_course(course.id)
				menu.start_selected()
			else:
				menu.start_course(course.id)
			await scene_changed
			var view = current_scene
			view.set_process(false)
			check("%s partner built VR=%s" % [course.id, vr], view.partner_on and view.partner != null)
			view.partner.update(0.0)
			check("%s partner transform finite" % course.id, view.partner._pod.transform.origin.is_finite() and view.partner._pod.transform.basis.is_finite())
			if vr:
				if course.id == "network":
					_quick_menu(view)
					view.menu_open(true)
					view.menu.at = 2
					view.menu_choose()
				else:
					view.return_to_menu()
			else:
				overlay.set_paused(true)
				check("desktop pause shows current partner", overlay.partner_checkbox.button_pressed)
				overlay.partner_checkbox.button_pressed = false
				check("desktop pause toggles partner immediately", not view.partner_on and view.partner == null)
				overlay.partner_checkbox.button_pressed = true
				overlay.return_to_menu()
			await scene_changed
			check("%s returns to the correct startup menu VR=%s" % [course.id, vr], current_scene.scene_file_path == (UI.VR_MENU_SCENE if vr else UI.MENU_SCENE))
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				check("remove test-created " + path, DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved[path])
			file.close()
			check("restore exact bytes " + path, FileAccess.get_file_as_bytes(path) == saved[path])
	print("PARTNER MENU %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

func _quick_menu(c) -> void:
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = "right_hand"
	tracker.set_pose("default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, 2)
	XRServer.add_tracker(tracker)
	c._await_neutral_controls = false
	c.hands_live = true
	c.set_handling("speed")
	c.quest.scheme = "triggers"
	for body in c.sim.bodies:
		body.vx = 1000.0 * cos(c.sim.pair_th)
		body.vy = 1000.0 * sin(c.sim.pair_th)
	c.partner.update(0.0)
	c.traffic_net.update(1.0 / 60.0)
	tracker.set_input("ax_button", true)
	tracker.set_input("primary", Vector2(0.0, 1.0))
	c.menu_open(true)
	var initially_on: bool = c.partner_on
	c._menu_hands(c.hands.left, c.hands.right)
	check("held A and stick cannot select on menu entry", c.menu.at == 0 and c.partner_on == initially_on)
	c._set_hands(false)
	c._menu_hands(c.hands.left, c.hands.right)
	c._set_hands(true)
	c._menu_hands(c.hands.left, c.hands.right)
	check("held A and stick cannot select after focus regain", c.menu.at == 0 and c.partner_on == initially_on)
	var keys := []
	for item in c.menu.items:
		keys.append(item.key)
	check("quick menu has partner, controls, maps, resume", keys == ["partner", "scheme", "maps", "resume"])
	var time_before: float = c.sim.time
	var partner_before := Vector3(c.partner.x, c.partner.y, c.partner.z)
	var traffic_before: Array = c.traffic_net.cars.duplicate(true)
	for i in 8:
		c._process(0.05)
	check("quick menu freezes sim, partner and traffic", c.sim.time == time_before and Vector3(c.partner.x, c.partner.y, c.partner.z) == partner_before and c.traffic_net.cars == traffic_before)
	check("quick menu mutes audio", AudioServer.is_bus_mute(0))
	c.menu.at = keys.find("scheme")
	var scheme_before: String = c.quest.scheme
	c.menu_choose()
	check("scheme changes inside menu", c.quest.scheme != scheme_before and c.menu.open)
	c.quest.scheme = "triggers"
	c.menu.at = keys.find("resume")
	c.menu_choose()
	var gear_before: int = c.quest.gear
	var armed_before: bool = c.sim.armed
	c._read_input(0.05)
	check("held resume inputs require neutral and cannot fly", c._await_neutral_controls and c.quest.gear == gear_before and c.sim.armed == armed_before and not c.inp.reignite and c.inp.thrL == 0.0 and c.inp.thrR == 0.0 and c._a_held == 0.0)
	tracker.set_input("ax_button", false)
	tracker.set_input("primary", Vector2.ZERO)
	c._read_input(0.05)
	check("neutral releases quick-menu flight guard", not c._await_neutral_controls)
	tracker.set_input("primary", Vector2(0.0, 1.0))
	c._read_input(0.05)
	check("fresh stick flick shifts after menu", c.quest.gear == mini(gear_before + 1, 4))
	AudioServer.set_bus_mute(0, true)
	c.menu_open(true)
	c.menu_open(false)
	check("pre-existing mute survives quick menu", AudioServer.is_bus_mute(0))
	AudioServer.set_bus_mute(0, false)
	XRServer.remove_tracker(tracker)
