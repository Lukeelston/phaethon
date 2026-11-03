## Explicit XR-off diagnostic of the shipped VR scenes. Never verifies headset tracking.
extends Node

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Boot := preload("res://release/vr_boot.gd")
const Stops := ["range", "gp", "eridanus", "emergency", "network", "range"]

var checks := 0
var failures := 0
var evidence := ""
var _started_ms := 0
var _finished := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	evidence = OS.get_user_data_dir().path_join("pcvr-verification")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence = arg.trim_prefix("--evidence=")
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started_ms > 120000:
		check("VR scene diagnostic finishes within 120 seconds", false)
		_finish()

func check(label: String, passed: bool) -> bool:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
	return passed

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP pcvr-", name, " screenshot: headless display")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(name + " VR scene screenshot saved", image.save_png(evidence.path_join("pcvr-" + name + ".png")) == OK)

func _run() -> void:
	var xr := XRServer.find_interface("OpenXR")
	var xr_live := xr != null and xr.is_initialized()
	if OS.has_feature("template"):
		check("export carries the pcvr feature", OS.has_feature("pcvr"))
		check("export defaults to VR boot", ProjectSettings.get_setting_with_override("application/run/main_scene") == "res://release/vr_boot.tscn")
		check("export separates VR user data", OS.get_user_data_dir().ends_with("Phaethon-VR"))
	if not check("diagnostic is explicitly authorized with XR off acknowledged", Boot.startup_route(xr_live, OS.get_cmdline_user_args()) == "diagnostic"):
		_finish()
		return
	print("PHYSICAL VR UNVERIFIED: this checks VR scene construction with OpenXR off, not headset tracking, rendering, controller feel or comfort.")
	if not check("VR evidence directory is absolute", evidence.is_absolute_path()):
		_finish()
		return
	if not check("VR evidence directory is available", DirAccess.make_dir_recursive_absolute(evidence) == OK):
		_finish()
		return
	var sample := load("res://audio/engines/v8_mip0.wav") as AudioStreamWAV
	check("VR engine audio PCM16 resource is present", sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS)
	check("VR engine manifest is present", FileAccess.file_exists("res://audio/engines/manifest.json"))
	var expected_scheme := "triggers"
	if FileAccess.file_exists(Cockpit.PREFS):
		var prefs = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS))
		if prefs is Dictionary and Cockpit.QuestControlsScript.SCHEMES.has(prefs.get("scheme", "")):
			expected_scheme = prefs.scheme
	View.track_override = "range"
	View.job_override = "none"
	get_tree().change_scene_to_file("res://vr.tscn")
	await get_tree().scene_changed
	var overlay = get_tree().root.get_node("ReleasePause")
	for index in Stops.size():
		var stop: String = Stops[index]
		var view = get_tree().current_scene
		if not check(stop + " opens the real VR cockpit scene", view is Cockpit and view.scene_file_path == "res://vr.tscn"):
			_finish()
			return
		check(stop + " native track selection is correct", view._track() == stop)
		check(stop + " job selection is correct", not view.sim.job.is_empty() if stop == "emergency" else view.sim.job.is_empty())
		check(stop + " has XR origin and camera", view.origin is XROrigin3D and view.cam is XRCamera3D)
		check(stop + " has both controller nodes", view.hands.get("left") is XRController3D and view.hands.get("right") is XRController3D)
		check(stop + " controller trackers are assigned", view.hands.left.tracker == &"left_hand" and view.hands.right.tracker == &"right_hand")
		check(stop + " cockpit instruments are constructed", view.interior != null and view.dashboard != null and view.mode_switch != null and view.canopy != null and view.minimap_panel != null)
		check(stop + " uses default or saved control scheme", view.quest.scheme == expected_scheme)
		check(stop + " starts in first gear", view.quest.gear == 0)
		check(stop + " remains an explicitly flat diagnostic", not get_viewport().use_xr)
		var before: float = view.sim.time
		var start := Vector2(view.sim.pod.x, view.sim.pod.y)
		key(KEY_E, true)
		await frames(45)
		key(KEY_E, false)
		check(stop + " simulation advances", view.sim.time > before)
		if stop == "emergency":
			check("emergency job remains in a valid stage", view.sim.job.has("stage") and str(view.sim.job.stage) != "")
		else:
			check(stop + " keyboard can move the cockpit", Vector2(view.sim.pod.x, view.sim.pod.y).distance_to(start) > 0.05)
		key(KEY_X, true)
		await frames(2)
		key(KEY_X, false)
		check(stop + " throttle cut works", view.inp.thrL == 0.0 and view.inp.thrR == 0.0)
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
		overlay.set_paused(true)
		overlay.restart_game()
		overlay.return_to_menu()
		await frames(2)
		check(stop + " desktop pause cannot reroute VR", get_tree().current_scene == view and not get_tree().paused and not overlay.is_paused)
		if index < Stops.size() - 1:
			await shot(stop)
			view.switch_track()
			await get_tree().scene_changed
	# Leave gameplay through normal scene teardown before exiting the diagnostic.
	get_tree().change_scene_to_file("res://release/menu.tscn")
	await get_tree().scene_changed
	await frames(3)
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_E, KEY_X, KEY_ESCAPE]:
		key(code, false)
	print("EXPORTED VR RELEASE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	print("PHYSICAL VR UNVERIFIED: headset tracking, stereo rendering, controller feel and comfort still need a headset session.")
	get_tree().quit(0 if failures == 0 else 1)
