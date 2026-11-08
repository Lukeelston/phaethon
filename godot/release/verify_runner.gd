## Explicit packaged-build diagnostic. Only created with -- --verify-release.
## Exercises the exported player's real UI, simulation, audio and scene lifecycle.
extends Node

const View := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
const MENU_SCENE := "res://release/menu.tscn"
const COURSES := ["range", "gp", "eridanus", "emergency", "network", "carving", "network"]

var failures := 0
var checks := 0
var evidence := ""
var capture: AudioEffectCapture
var _started_ms := 0
var _finished := false
var _settings_existed := false
var _settings_before := PackedByteArray()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	evidence = OS.get_user_data_dir().path_join("release-verification")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence = arg.trim_prefix("--evidence=")
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started_ms > 120000:
		check("verification finishes within 120 seconds", false)
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

func _run() -> void:
	_settings_existed = FileAccess.file_exists(Settings.PREFS)
	if _settings_existed:
		_settings_before = FileAccess.get_file_as_bytes(Settings.PREFS)
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
	var overlay = get_tree().root.get_node("ReleasePause")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 3.0
	AudioServer.add_bus_effect(0, capture)
	var case_index := 0
	for course in COURSES:
		var menu = get_tree().current_scene
		var collisions := case_index % 2 == 1
		var partner_enabled := case_index % 2 == 0
		case_index += 1
		menu.collision_checkbox.button_pressed = collisions
		menu.partner_checkbox.button_pressed = partner_enabled
		check(course + " collision checkbox persists", Settings.obstacle_collisions_enabled() == collisions)
		check(course + " partner checkbox persists", Settings.driving_partner_enabled() == partner_enabled)
		if case_index <= 2:
			await shot("menu-obstacles-" + ("on" if collisions else "off"))
		var buttons := menu.find_children("*", "Button", true, false)
		if not check(course + " launch button is available", buttons.size() >= 4):
			_finish()
			return
		capture.clear_buffer()
		buttons[COURSES.find(course)].pressed.emit()
		await get_tree().scene_changed
		var view = get_tree().current_scene
		if not check(course + " opens CraftView", view is View):
			_finish()
			return
		check(course + " scene loaded", view.sim.kind == course if course in ["range", "network"] else view.sim.track_name == ("eridanus" if course == "emergency" else course))
		check(course + " opens its selected mission", not view.sim.job.is_empty() if course == "emergency" else view.sim.job.is_empty())
		check(course + " launch respects obstacle collisions", view.sim.P.obstacleCollisions == collisions)
		check(course + " launch builds the selected partner state", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		check(course + " skill tracker and audio loaded", view.skill_score != null and view.skill_audio != null)
		if course == "gp":
			check("Grand Prix starts in starfighter mode", view.sim.P.handling == "starfighter")
		if course == "carving":
			check("Carving starts in Speedcraft with race dressing", view.sim.P.handling == "speed" and view.gp_world != null and view.gp_world.corners.size()>10)
		var start := Vector2(view.sim.pod.x, view.sim.pod.y)
		# Background window focus changes can clear a synthetic held key.
		# Feed the intended hold each frame, as the VR diagnostic already does.
		for frame in 150:
			key(KEY_E, true)
			await frames(1)
		key(KEY_E, false)
		var position := Vector2(view.sim.pod.x, view.sim.pod.y)
		check(course + " keyboard accelerates craft", position.distance_to(start) > 1.0 and view.inp.thrL > 0.0 and view.inp.thrR > 0.0)
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
		check(course + " restart keeps selected course", view.sim.kind == course if course in ["range", "network"] else view.sim.track_name == ("eridanus" if course == "emergency" else course))
		check(course + " restart clears throttle", view.inp.thrL == 0.0 and view.inp.thrR == 0.0)
		check(course + " restart retains obstacle collisions", view.sim.P.obstacleCollisions == collisions)
		check(course + " restart retains partner", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		check(course + " restart starts a fresh skill run", view.skill_score.total == 0)
		if course == "network":
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
