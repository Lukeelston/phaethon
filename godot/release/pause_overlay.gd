extends CanvasLayer

const View := preload("res://view/craft_view.gd")
const Garage := preload("res://release/garage_route.gd")
const UI := preload("res://release/release_config.gd")

var is_paused := false
var _was_muted := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _screen: Control
var _resume: Button
var _garage: Button
var partner_checkbox: CheckBox
var _flight_options: GridContainer

func _ready() -> void:
	if OS.has_feature("pcvr"):
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process_input(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.theme = UI.make_theme()
	add_child(_screen)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.04, 0.055, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	center.add_child(columns)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 400
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(actions)
	actions.add_child(UI.label("PHAETHON / FLIGHT HOLD", 15, UI.AMBER))
	actions.add_child(UI.label("PAUSED", 56))
	actions.add_child(UI.label("Even bad ideas need a breather.", 20, UI.MUTED))
	_resume = UI.button("Resume flight  ·  Esc", resume_game)
	actions.add_child(_resume)
	partner_checkbox = UI.partner_checkbox()
	partner_checkbox.toggled.connect(_set_partner)
	actions.add_child(partner_checkbox)
	_flight_options = GridContainer.new()
	_flight_options.columns = 2
	actions.add_child(_flight_options)
	var destinations := HBoxContainer.new()
	actions.add_child(destinations)
	_garage = UI.button("Pilot garage", _open_garage)
	_garage.name = "Garage"
	for button: Button in [UI.button("Restart this course", restart_game), _garage]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		destinations.add_child(button)
	actions.add_child(UI.button("Return to course menu", return_to_menu))
	actions.add_child(UI.button("Quit to desktop", quit_game))
	columns.add_child(UI.controls_panel())
	_screen.hide()
	get_tree().scene_changed.connect(_scene_changed)
	if "--verify-release" in OS.get_cmdline_user_args():
		var runner = load("res://release/verify_runner.gd").new()
		add_child.call_deferred(runner)

func _input(event: InputEvent) -> void:
	if not _desktop_gameplay():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_paused(not is_paused)
		get_viewport().set_input_as_handled()

func set_paused(value: bool) -> void:
	if OS.has_feature("pcvr"):
		return
	if value == is_paused:
		return
	if value and not _desktop_gameplay():
		return
	is_paused = value
	if value:
		_garage.disabled = not get_tree().current_scene.can_visit_garage()
		_garage.tooltip_text = "Park at your launch point to enter" if _garage.disabled else ""
		_refresh_flight_options()
		_was_muted = AudioServer.is_bus_mute(0)
		_mouse_mode = Input.mouse_mode
		AudioServer.set_bus_mute(0, true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		AudioServer.set_bus_mute(0, _was_muted)
		Input.mouse_mode = _mouse_mode
	get_tree().paused = value
	_screen.visible = value
	if value:
		partner_checkbox.set_pressed_no_signal(get_tree().current_scene.partner_on)
		_resume.grab_focus()

func _set_partner(enabled: bool) -> void:
	if _desktop_gameplay():
		get_tree().current_scene.set_partner(enabled)

func _refresh_flight_options() -> void:
	# The launch menu can change these preferences while the overlay is hidden.
	for child in _flight_options.get_children():
		child.free()
	var camera := UI.option_button("Camera", "flat_camera", View.FLAT_CAMERAS, 15, _set_camera)
	var nose := UI.option_button("Nose", "flat_nose", [["open", "Open"], ["closed", "Closed"]], 15, _set_nose)
	var hour := UI.option_button("Time", "time", UI.Outlook.TIMES, 15, _set_outlook)
	var weather := UI.option_button("Weather", "weather", UI.Outlook.WEATHERS, 15, _set_outlook)
	camera.name = "Camera"
	nose.name = "Nose"
	hour.name = "Hour"
	weather.name = "Weather"
	for option: Button in [camera, nose, hour, weather]:
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_flight_options.add_child(option)

func _set_camera(id: String) -> void:
	var view := get_tree().current_scene as View
	view.flat_camera = id
	view._place_camera(1.0)

func _set_nose(id: String) -> void:
	View.CraftModelScript.set_nose_closed(id == "closed", get_tree().current_scene)

func _set_outlook(_id: String) -> void:
	UI.Outlook.load_saved()
	UI.Outlook.apply(get_tree().current_scene)

func resume_game() -> void:
	set_paused(false)

func restart_game() -> void:
	if not _desktop_gameplay():
		return
	View.pad_start = get_tree().current_scene.pad != null
	resume_game()
	get_tree().reload_current_scene()

func _open_garage() -> void:
	var flight := get_tree().current_scene as View
	if not is_paused or not flight or not flight.can_visit_garage():
		return
	resume_game()
	Garage.enter_parked(get_tree(), flight, false)


func return_to_menu() -> void:
	if not _desktop_gameplay():
		return
	resume_game()
	get_tree().change_scene_to_file(UI.MENU_SCENE)

func quit_game() -> void:
	resume_game()
	get_tree().quit()

func _scene_changed() -> void:
	# Scene changes can also originate from existing game controls.
	resume_game()

func _desktop_gameplay() -> bool:
	var scene := get_tree().current_scene
	return not OS.has_feature("pcvr") and scene is View and scene.scene_file_path != "res://vr.tscn"
