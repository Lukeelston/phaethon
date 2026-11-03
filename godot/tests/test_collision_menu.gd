## Actual desktop/VR menus, persistence, restart and city-GP transitions in both states.
extends SceneTree
const Settings := preload("res://release/game_settings.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const UI := preload("res://release/release_config.gd")
var checks := 0
var failures := 0
var saved := {}

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	failures += int(not passed)
	print(("PASS " if passed else "FAIL ") + label)

func _run() -> void:
	for path in [Settings.PREFS, Cockpit.PREFS]:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	if FileAccess.file_exists(Settings.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS))
	check("fresh release preference defaults OFF", not Settings.obstacle_collisions_enabled())
	var overlay = root.get_node("ReleasePause")
	for vr in [false, true]:
		var menu_path: String = UI.VR_MENU_SCENE if vr else UI.MENU_SCENE
		change_scene_to_file(menu_path)
		await scene_changed
		for enabled in [false, true]:
			for course in UI.COURSES:
				var menu = current_scene
				await process_frame
				menu.set_process(false)
				if vr:
					menu.focus_row(UI.COURSES.size())
					menu.consume_controller(0.0, false, true)
					if menu.collision_checkbox.button_pressed != enabled:
						menu.consume_controller(0.0, true, true)
				else:
					menu.collision_checkbox.button_pressed = enabled
				check("checkbox persists %s in VR=%s" % [enabled, vr], Settings.obstacle_collisions_enabled() == enabled)
				if vr:
					menu.choose_course(course.id)
					menu.focus_row(menu.start_index)
					menu.consume_controller(0.0, false, true)
					menu.consume_controller(0.0, true, true)
				else:
					menu.start_course(course.id)
				await scene_changed
				var view = current_scene
				view.set_process(false)
				check("%s launch carries %s in VR=%s" % [course.id, enabled, vr], view.sim.P.obstacleCollisions == enabled)
				if vr:
					check("checkbox did not bypass neutral entry", view._await_neutral_controls)
					view._respawn()
				else:
					overlay.restart_game()
					await scene_changed
					view = current_scene
					view.set_process(false)
				check("%s restart keeps %s in VR=%s" % [course.id, enabled, vr], view.sim.P.obstacleCollisions == enabled)
				if course.id == "network":
					check("traffic feeder follows the checkbox", view.traffic_net.collide == enabled)
					for city in view.sim.cities:
						if city.name == "DUNES":
							view.sim.respawn_on(int(city.road), int(city.i), 1)
					view.enter_city_gp()
					await scene_changed
					view = current_scene
					view.set_process(false)
					check("city GP keeps obstacle setting", view.sim.track_name == "gp_dunes" and view.sim.P.obstacleCollisions == enabled)
				if vr:
					view.return_to_menu()
				else:
					overlay.return_to_menu()
				await scene_changed
				check("return restores checkbox %s in VR=%s" % [enabled, vr], current_scene.collision_checkbox.button_pressed == enabled)
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				check("remove test-created " + path, DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved[path])
			file.close()
			check("restore exact bytes " + path, FileAccess.get_file_as_bytes(path) == saved[path])
	print("COLLISION MENU %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
