extends CanvasLayer

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")

var is_paused := false
var _was_muted := false
var _mouse_mode := Input.MOUSE_MODE_VISIBLE
var _screen: Control
var _resume: Button

func _ready() -> void:
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
	actions.add_child(UI.button("Restart this course", restart_game))
	actions.add_child(UI.button("Return to course menu", return_to_menu))
	actions.add_child(UI.button("Quit to desktop", quit_game))
	columns.add_child(UI.controls_panel())
	_screen.hide()
	get_tree().scene_changed.connect(_scene_changed)
	if "--verify-release" in OS.get_cmdline_user_args():
		var runner = load("res://release/verify_runner.gd").new()
		add_child.call_deferred(runner)

func _input(event: InputEvent) -> void:
	if not get_tree().current_scene is View:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		set_paused(not is_paused)
		get_viewport().set_input_as_handled()

func set_paused(value: bool) -> void:
	if value == is_paused:
		return
	if value and not get_tree().current_scene is View:
		return
	is_paused = value
	if value:
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
		_resume.grab_focus()

func resume_game() -> void:
	set_paused(false)

func restart_game() -> void:
	if not get_tree().current_scene is View:
		return
	resume_game()
	get_tree().reload_current_scene()

func return_to_menu() -> void:
	resume_game()
	get_tree().change_scene_to_file(UI.MENU_SCENE)

func quit_game() -> void:
	resume_game()
	get_tree().quit()

func _scene_changed() -> void:
	# Scene changes can also originate from existing game controls.
	resume_game()
