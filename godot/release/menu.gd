extends Control

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")

var collision_checkbox: CheckBox
var partner_checkbox: CheckBox
var craft_selector := preload("res://release/craft_selector.gd").new()

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
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 52)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UI.label("EXPERIMENTAL DESKTOP BUILD", 15, UI.AMBER))
	left.add_child(UI.label("PHAETHON", 50))
	left.add_child(UI.label("Two engines. One cockpit.\nWe know it’s a little fucky.", 25))
	var breathing_room := Control.new()
	breathing_room.custom_minimum_size.y = 6
	left.add_child(breathing_room)
	left.add_child(craft_selector)
	craft_selector.build(false)
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 14, UI.MUTED))
	var sprint: Button
	var course_list: Container = left
	if UI.COURSES.size() > 6:   # eight and more: two abreast, or the list runs off the window
		course_list = GridContainer.new()
		(course_list as GridContainer).columns = 2
		course_list.add_theme_constant_override("h_separation", 8)
		course_list.add_theme_constant_override("v_separation", 6)
		left.add_child(course_list)
	for course in UI.COURSES:
		var button := UI.button(course.name, start_course.bind(course.id), 42)
		button.name = "Course_" + course.id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		course_list.add_child(button)
		if course.id == "range":
			sprint = button
	collision_checkbox = UI.collision_checkbox()
	partner_checkbox = UI.partner_checkbox()
	var flight_options := HBoxContainer.new()
	flight_options.add_theme_constant_override("separation", 24)
	flight_options.add_child(collision_checkbox)
	flight_options.add_child(partner_checkbox)
	left.add_child(flight_options)
	left.add_child(UI.label("Collisions: pillars and traffic. Guardrails stay on.", 14, UI.MUTED))
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
	if UI.course_index(course) < 0:
		return
	var overrides := UI.course_overrides(course)
	View.vehicle_override = craft_selector.selected
	View.track_override = overrides[0]
	View.job_override = overrides[1]
	View.spot_override = overrides[2]
	get_tree().change_scene_to_file(UI.GAME_SCENE)
