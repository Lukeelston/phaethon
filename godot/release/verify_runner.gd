## Explicit packaged-build diagnostic. Only created with -- --verify-release.
## Exercises the exported player's real UI, simulation, audio and scene lifecycle.
extends Node

const View := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
const UI := preload("res://release/release_config.gd")
const MENU_SCENE := "res://release/menu.tscn"
const COURSES := ["range", "gp", "eridanus", "emergency", "network", "carving", "coast", "network", "drop", "aurora"]

var failures := 0
var checks := 0
var evidence := ""
var capture: AudioEffectCapture
var _case_started_ms := 0
var _case_name := "launch"
var _finished := false
var _settings_existed := false
var _settings_before := PackedByteArray()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_case_started_ms = Time.get_ticks_msec()
	evidence = OS.get_user_data_dir().path_join("release-verification")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence = arg.trim_prefix("--evidence=")
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _case_started_ms > 120000:
		check("%s finishes within 120 seconds" % _case_name, false)
		_finish()

func check(label: String, passed: bool) -> bool:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
	return passed

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP ", name, " screenshot: headless display")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(name + " screenshot saved", image.save_png(evidence.path_join(name + ".png")) == OK)

## Exercise the public garage controls against exported resources, including the
## cabin components shared with XR that the desktop preset used to exclude.
func _garage_visit() -> bool:
	var title = get_tree().current_scene
	var enter := title.find_child("Garage", true, false) as Button
	if not check("desktop title offers the pilot garage", enter != null and enter.is_visible_in_tree()):
		return false
	enter.pressed.emit()
	await frames(3)
	var garage = get_tree().current_scene
	if not check("packed garage opens", garage != null and garage.scene_file_path == "res://garage/garage.tscn"):
		return false
	var craft := Settings.selected_craft()
	var alternate := "kiln" if craft == "vesper" else "vesper"
	garage.walker.global_transform = garage.environment.boarding_transform(alternate)
	garage.walker.interact_requested.emit()
	var bay: Node3D = garage.environment.bay_node(alternate)
	var runup = bay.get_node_or_null("Runup")
	if not check("alternate service bay boards with its own cold engines", runup != null and not runup.startup.batt and runup.startup.stage == ["off", "off"]):
		return false
	var parked_at := bay.global_transform
	garage.walker.cockpit_control_requested.emit("power")
	await frames(3)
	check("occupied bay accepts battery power on the stands", runup.startup.batt and runup.startup.power > 0.0 and bay.global_transform.is_equal_approx(parked_at))
	garage.walker.cockpit_control_requested.emit("power")
	check("alternate bay powers back down", not runup.startup.batt and runup.startup.stage == ["off", "off"])
	garage.walker.interact_requested.emit()
	garage.walker.global_transform = garage.environment.boarding_transform(craft)
	garage.interact()
	if not check("pilot boards the selected craft", garage.seated_craft == craft and garage.walker.seated):
		return false
	garage.launch_flight()
	await frames(3)
	var flight := get_tree().current_scene as View
	if not check("garage launches the selected pilot craft on the Network", flight != null and flight.sim.P.vehicle == craft and flight.sim.kind == "network"):
		return false
	var pilot := flight.pod_mesh.get_node_or_null("ChasePilot")
	check("desktop flight carries the seated pilot", pilot != null and pilot.get_child_count() > 0)
	var overlay = get_tree().root.get_node("ReleasePause")
	overlay.set_paused(true)
	var park := overlay.find_child("Garage", true, false) as Button
	if not check("parked flight can enter the garage", park != null and not park.disabled):
		return false
	park.pressed.emit()
	await frames(3)
	garage = get_tree().current_scene
	if not check("parked pilot returns on foot beside the same craft", garage != null and garage.scene_file_path == "res://garage/garage.tscn" and not garage.walker.seated and garage.environment.nearest_bay(garage.walker.global_position) == craft):
		return false
	garage.return_to_menu()
	await frames(3)
	return check("garage returns to desktop title", get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MENU_SCENE)


func _run() -> void:
	_settings_existed = FileAccess.file_exists(Settings.PREFS)
	if _settings_existed:
		_settings_before = FileAccess.get_file_as_bytes(Settings.PREFS)
	if OS.has_feature("template"):
		var notices := OS.get_executable_path().get_base_dir().path_join("THIRD_PARTY.md")
		if not check("THIRD_PARTY.md ships beside the desktop executable", FileAccess.file_exists(notices)):
			_finish()
			return
	if not check("evidence directory is absolute", evidence.is_absolute_path()):
		_finish()
		return
	if not check("evidence directory is available", DirAccess.make_dir_recursive_absolute(evidence) == OK):
		_finish()
		return
	check("exported default main scene is menu", ProjectSettings.get_setting("application/run/main_scene") == MENU_SCENE)
	DirAccess.make_dir_recursive_absolute(evidence.path_join("profile"))
	View.best_dir = evidence.path_join("profile/")
	var engine_sample := load("res://audio/engines/v8_mip0.wav") as AudioStreamWAV
	check("PCM16 engine import", engine_sample != null and engine_sample.format == AudioStreamWAV.FORMAT_16_BITS)
	# Autoloads initialize before the main scene, so wait for the normal launch.
	while get_tree().current_scene == null:
		await get_tree().process_frame
	await frames(5)
	if not check("normal launch opens the course menu", get_tree().current_scene.scene_file_path == MENU_SCENE):
		_finish()
		return
	await shot("menu")
	if not await _garage_visit():
		_finish()
		return
	var overlay = get_tree().root.get_node("ReleasePause")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(0, capture)
	var case_index := 0
	var courses: Array = ["network"] if "--network-only" in OS.get_cmdline_user_args() else COURSES
	for course in courses:
		_case_started_ms = Time.get_ticks_msec()
		_case_name = course
		var track: String = "network" if UI.SPOTS.has(course) else course
		var menu = get_tree().current_scene
		var collisions := case_index % 2 == 1
		var partner_enabled := case_index % 2 == 0
		var pilot_craft: String = Settings.Craft.ORDER[(case_index + 1) % Settings.Craft.ORDER.size()]
		for press in menu.craft_selector.Craft.ORDER.size():
			if menu.craft_selector.selected == pilot_craft:
				break
			menu.craft_selector.button.pressed.emit()
		case_index += 1
		menu.collision_checkbox.button_pressed = collisions
		menu.partner_checkbox.button_pressed = partner_enabled
		check(course + " collision checkbox persists", Settings.obstacle_collisions_enabled() == collisions)
		check(course + " partner checkbox persists", Settings.driving_partner_enabled() == partner_enabled)
		if case_index <= 2:
			await shot("menu-obstacles-" + ("on" if collisions else "off"))
		var button := menu.find_child("Course_" + course, true, false) as Button
		if not check(course + " launch button is available", button != null):
			_finish()
			return
		capture.clear_buffer()
		button.pressed.emit()
		await get_tree().scene_changed
		var view = get_tree().current_scene
		if not check(course + " opens CraftView", view is View):
			_finish()
			return
		check(course + " scene loaded", view.sim.kind == track if track in ["range", "network"] else view.sim.track_name == ("eridanus" if course == "emergency" else course))
		if UI.SPOTS.has(course):
			check(course + " starts on its named road", view.sim.roads[view.sim.pod.path].name == UI.SPOTS[course])
		if course == "aurora":
			check("Aurora starts on the southwest pressure-lock approach", view.sim.pod.path == View.CraftSimScript.NET_PRESSURE[0]
				and view.sim.pod.hint < View.CraftSimScript.NET_PRESSURE[1] and view.network_world.pressure_line.is_visible_in_tree())
		check(course + " opens its selected mission", not view.sim.job.is_empty() if course == "emergency" else view.sim.job.is_empty())
		check(course + " launch respects obstacle collisions", view.sim.P.obstacleCollisions == collisions)
		check(course + " launches " + pilot_craft, view.sim.P.vehicle == pilot_craft and view.craft.engines[0].has_node("ShrikeFairing") == (pilot_craft == "shrike"))
		if view.craft.Fleet.supports(pilot_craft):
			check(course + " loads the packed engine and cab", view.craft.engines[0].get_node("FleetFairing").mesh == view.craft.fleet.part(&"Port")
					and view.craft.pod.mesh == view.craft.fleet.part(&"Cab"))
		check(course + " launch builds the selected partner state", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		check(course + " skill tracker and audio loaded", view.skill_score != null and view.skill_audio != null)
		if course == "gp":
			check("Grand Prix starts in starfighter mode", view.sim.P.handling == "starfighter")
		if course == "carving":
			check("Carving starts in Speedcraft with race dressing", view.sim.P.handling == "speed" and view.gp_world != null and view.gp_world.corners.size()>10)
		var start := Vector2(view.sim.pod.x, view.sim.pod.y)
		if course == "network":
			check("Network starts on a released roadside pad", view.pad != null and view.pad.released and view.pad.gate_open == 1.0 and absf(view.pad.home[3]) > 0.1)
			await shot("network-start")
		# Background window focus changes can clear a synthetic held key.
		# Feed the intended hold each frame, as the VR diagnostic already does.
		for frame in 150:
			key(KEY_E, true)
			await frames(1)
		key(KEY_E, false)
		var position := Vector2(view.sim.pod.x, view.sim.pod.y)
		check(course + " keyboard accelerates craft", position.distance_to(start) > 1.0 and view.inp.thrL > 0.0 and view.inp.thrR > 0.0)
		if course == "network":
			print("NETWORK_FLIGHT display=%s course=%s aircraft=%s distance_m=%.2f speed_mph=%.2f left=%.2f right=%.2f" % [
				DisplayServer.get_name(), view.sim.kind, pilot_craft, position.distance_to(start),
				view._kmh() / 1.609344, view.inp.thrL, view.inp.thrR])
		await shot(course)
		if course == "range":
			var buffer := capture.get_buffer(capture.get_frames_available())
			var peak := 0.0
			for sample in buffer:
				peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
			print("AUDIO_CAPTURE peak=", peak, " frames=", buffer.size())
			check("generated audio is non-silent", peak > 0.001)
		key(KEY_X, true)
		await frames(2)
		key(KEY_X, false)
		check(course + " X cuts both throttles", view.inp.thrL == 0.0 and view.inp.thrR == 0.0)
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
		check(course + " Escape pauses", get_tree().paused and overlay.is_paused)
		var before: float = view.sim.time
		var score_before: float = view.skill_score.time
		await frames(3)
		check(course + " pause freezes simulation", view.sim.time == before)
		check(course + " pause freezes skill tracking", view.skill_score.time == score_before)
		check(course + " pause mutes output", AudioServer.is_bus_mute(0))
		check(course + " pause shows current partner setting", overlay.partner_checkbox.button_pressed == partner_enabled)
		if course == "network":
			var before_camera: Vector3 = view.cam.position
			var before_hull: Mesh = view.craft.pod.mesh
			var before_nose: bool = view.craft.nose_closed
			var before_hour: String = View.Outlook.time
			var before_weather: String = View.Outlook.weather
			overlay.find_child("Camera", true, false).pressed.emit()
			overlay.find_child("Nose", true, false).pressed.emit()
			overlay.find_child("Hour", true, false).pressed.emit()
			overlay.find_child("Weather", true, false).pressed.emit()
			check("Network pause moves the live chase camera", before_camera.distance_to(view.cam.position) > 1.0)
			check("Network pause changes the actual hull", view.craft.pod.get_node("ServiceBonnet").visible != before_nose if view.craft.fleet else view.craft.pod.mesh != before_hull)
			check("Network pause changes the current hour", View.Outlook.time != before_hour and View.Outlook.time == Settings.choice("time", View.Outlook.ids(View.Outlook.TIMES)))
			check("Network pause changes the current weather", View.Outlook.weather != before_weather and View.Outlook.weather == Settings.choice("weather", View.Outlook.ids(View.Outlook.WEATHERS)))
			check("Network pause applies the selected sky to this flight", View.Outlook._applied and View.Outlook._aloft_view == view.get_instance_id())
			await shot("network-pause")
		overlay.partner_checkbox.button_pressed = not partner_enabled
		check(course + " pause toggles the actual partner", view.partner_on != partner_enabled and (view.partner != null) != partner_enabled and Settings.driving_partner_enabled() != partner_enabled)
		overlay.partner_checkbox.button_pressed = partner_enabled
		if course == "range":
			await shot("pause")
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
		await frames(3)
		check(course + " Escape resumes simulation and audio", not get_tree().paused and not overlay.is_paused and not AudioServer.is_bus_mute(0) and view.sim.time > before)
		overlay.set_paused(true)
		var old_id: int = view.get_instance_id()
		overlay.restart_game()
		await get_tree().scene_changed
		view = get_tree().current_scene
		check(course + " restart restores playable scene", not get_tree().paused and view is View and view.get_instance_id() != old_id)
		check(course + " restart keeps selected course", view.sim.kind == track if track in ["range", "network"] else view.sim.track_name == ("eridanus" if course == "emergency" else course))
		check(course + " restart clears throttle", view.inp.thrL == 0.0 and view.inp.thrR == 0.0)
		check(course + " restart retains obstacle collisions", view.sim.P.obstacleCollisions == collisions)
		check(course + " restart retains pilot craft", view.sim.P.vehicle == pilot_craft)
		check(course + " restart retains partner", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		check(course + " restart starts a fresh skill run", view.skill_score.total == 0)
		if course == "network":
			check("Network restart restores the starting pad", view.pad != null and view.pad.released and view.pad.gate_open == 1.0)
			check("Network restart retains chase camera", view.flat_camera == Settings.choice("flat_camera", ["far", "near"]))
			check("Network traffic follows obstacle checkbox", view.traffic_net.collide == collisions)
			for city in view.sim.cities:
				if city.name == "DUNES":
					view.sim.respawn_on(int(city.road), int(city.i), 1)
			view.enter_city_gp()
			await get_tree().scene_changed
			view = get_tree().current_scene
			check("city GP preserves obstacle collisions", view.sim.track_name == "gp_dunes" and view.sim.P.obstacleCollisions == collisions)
			check("city GP preserves partner", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		await frames(2)
		overlay.set_paused(true)
		overlay.return_to_menu()
		await get_tree().scene_changed
		check(course + " return to menu", get_tree().current_scene.scene_file_path == MENU_SCENE and not get_tree().paused and not overlay.is_paused)
		check(course + " menu restores obstacle checkbox", get_tree().current_scene.collision_checkbox.button_pressed == collisions)
		check(course + " menu restores partner checkbox", get_tree().current_scene.partner_checkbox.button_pressed == partner_enabled)
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_E, KEY_X, KEY_ESCAPE]:
		key(code, false)
	var overlay = get_tree().root.get_node_or_null("ReleasePause")
	if overlay:
		overlay.resume_game()
	if capture:
		for index in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
			if AudioServer.get_bus_effect(0, index) == capture:
				AudioServer.remove_bus_effect(0, index)
	if _settings_existed:
		var settings := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		if settings:
			settings.store_buffer(_settings_before)
			settings.close()
		check("diagnostic restores exact game settings", settings != null and FileAccess.get_file_as_bytes(Settings.PREFS) == _settings_before)
	elif FileAccess.file_exists(Settings.PREFS):
		check("diagnostic removes only game settings it created", DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS)) == OK)
	print("EXPORTED RELEASE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
