extends Control

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UI.make_theme()
	var background := ColorRect.new()
	background.color = UI.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var accent := ColorRect.new()
	accent.color = UI.AMBER
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 3
	add_child(accent)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 48)
	for edge in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 52)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UI.label("EXPERIMENTAL DESKTOP BUILD", 15, UI.AMBER))
	left.add_child(UI.label("PHAETHON", 68))
	left.add_child(UI.label("Two engines. One cockpit.\nWe know it’s a little fucky.", 25))
	var breathing_room := Control.new()
	breathing_room.custom_minimum_size.y = 6
	left.add_child(breathing_room)
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 14, UI.MUTED))
	var sprint := UI.button("01    100-mile sprint  ·  Start here", start_course.bind("range"), 64)
	left.add_child(sprint)
	left.add_child(UI.button("02    Grand Prix  ·  Starfighter circuit", start_course.bind("gp"), 64))
	left.add_child(UI.button("03    Eridanus  ·  Explore the long course", start_course.bind("eridanus"), 64))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UI.label("A rough, playable physics experiment.\nExpect odd handling, rough edges and spectacular mistakes.", 16, UI.MUTED))
	left.add_child(UI.button("Quit to desktop", get_tree().quit, 42))
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(right)
	right.add_child(UI.controls_panel())
	sprint.grab_focus()

func start_course(course: String) -> void:
	if course not in ["range", "gp", "eridanus"]:
		return
	View.track_override = course
	View.job_override = "none"
	get_tree().change_scene_to_file(UI.GAME_SCENE)
