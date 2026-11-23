## PCVR has an explicit startup gate. Normal launches never silently run flat.
extends Control

const UI := preload("res://release/release_config.gd")
const SESSION_WAIT_MS := 20000
const RETRY_MS := 1000

func _enter_tree() -> void:
	print("PCVR STAGE: boot scene ready at engine +", Time.get_ticks_msec(), " ms")

func _ready() -> void:
	_start.call_deferred()

static func selected_track(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--track="):
			var course := arg.trim_prefix("--track=")
			return course if UI.course_index(course) >= 0 else "range"
	return "range"

static func startup_route(xr_ready: bool, args: PackedStringArray) -> String:
	if "--verify-vr-release" in args:
		# Godot consumes --xr-mode before GDScript sees its argument list. Require
		# an explicit user acknowledgment as well as a non-initialized interface.
		return "diagnostic" if "--verify-xr-off" in args and not xr_ready else "setup"
	return "menu" if xr_ready else "setup"

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	var diagnostic := "--verify-vr-release" in args
	var xr_ready := xr != null and xr.is_initialized()
	if not diagnostic and DisplayServer.get_name() != "headless":
		xr_ready = await _wait_for_session()
	print("PCVR BOOT: feature=", OS.has_feature("pcvr"), " main=", ProjectSettings.get_setting_with_override("application/run/main_scene"), " data=", OS.get_user_data_dir(), " xr_ready=", xr_ready)
	var route := startup_route(xr_ready, args)
	preload("res://vr/flight_diagnostics.gd").log_headset(xr as OpenXRInterface)
	print("PCVR STARTUP: ", route)
	if route == "setup":
		get_viewport().use_xr = false
		if not diagnostic and OS.get_environment("PHAETHON_BOOT_ATTEMPT") == "1":
			get_tree().quit(75)
			return
		_show_setup("--verify-vr-release" in args)
		print("PCVR HANDOFF: setup screen ready")
		return
	if OS.get_environment("PHAETHON_SOURCE_BOOT") == "1" and "--source-direct-flight" in args:
		print("PCVR STAGE: loading source cockpit")
		get_tree().change_scene_to_file("res://vr.tscn")
		return
	var boot_course := selected_track(args)
	var View = load("res://view/craft_view.gd")
	View.track_override = "network" if UI.SPOTS.has(boot_course) else boot_course
	View.spot_override = UI.SPOTS.get(boot_course, "")
	View.job_override = "none"
	if route == "diagnostic":
		print("PCVR DIAGNOSTIC: OpenXR is explicitly off. Checking scene construction only; physical VR remains unverified.")
		var runner = load("res://release/verify_vr_runner.gd").new()
		get_tree().root.add_child.call_deferred(runner)
	else:
		var menu_script = load("res://release/vr_menu.gd")
		menu_script.remembered_course = selected_track(args)
		get_tree().change_scene_to_file(UI.VR_MENU_SCENE)

func _wait_for_session() -> bool:
	var status := Label.new()
	status.text = "Waiting for the PC OpenXR session…"
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(status)
	var until := Time.get_ticks_msec() + SESSION_WAIT_MS
	var next_attempt := 0
	var last_state := -1
	while Time.get_ticks_msec() < until:
		var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
		if xr != null:
			if not xr.is_initialized() and Time.get_ticks_msec() >= next_attempt:
				print("PCVR STAGE: initializing OpenXR at engine +", Time.get_ticks_msec(), " ms")
				xr.initialize()
				next_attempt = Time.get_ticks_msec() + RETRY_MS
			if xr.is_initialized():
				get_viewport().use_xr = true
				var state := xr.get_session_state()
				if state != last_state:
					print("PCVR STAGE: OpenXR session state=", state, " at engine +", Time.get_ticks_msec(), " ms")
					last_state = state
				if state in [OpenXRInterface.SESSION_STATE_SYNCHRONIZED, OpenXRInterface.SESSION_STATE_VISIBLE, OpenXRInterface.SESSION_STATE_FOCUSED]:
					status.queue_free()
					return true
		await get_tree().create_timer(0.1, true, false, true).timeout
	print("PCVR STAGE: OpenXR session deadline, last state=", last_state)
	status.queue_free()
	return false

func _show_setup(diagnostic_requested: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UI.make_theme()
	var background := ColorRect.new()
	background.color = UI.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 860
	content.add_theme_constant_override("separation", 20)
	center.add_child(content)
	content.add_child(UI.label("PHAETHON / EXPERIMENTAL PCVR", 17, UI.AMBER))
	content.add_child(UI.label("HEADSET SETUP NEEDED", 42))
	content.add_child(UI.label("The PC OpenXR session is not ready. Flight has not started.", 22))
	content.add_child(UI.label("1. Start your PC OpenXR runtime and make it the active runtime.\n2. Connect the headset to your PC (for example, Quest Link or Air Link).\n3. Enter the PC VR session, then close and relaunch this game.", 21, UI.MUTED))
	content.add_child(UI.label("This is the Windows PCVR build; it does not run directly on a standalone headset.\nUse the separate desktop build for flat-screen play.", 18, UI.MUTED))
	if diagnostic_requested:
		content.add_child(UI.label("Diagnostics: --xr-mode off -- --verify-vr-release --verify-xr-off\nDiagnostics cannot run inside a live headset session.", 17, UI.AMBER))
	var quit_button := UI.button("Quit to desktop", get_tree().quit, 56)
	content.add_child(quit_button)
	quit_button.grab_focus()
