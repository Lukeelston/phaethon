extends Control

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")
const CraftSelector := preload("res://release/craft_selector.gd")
const Title := preload("res://release/title_stage.gd")
const SPINE := 500.0          # in the title, the menu's column down the left edge is this wide (of the window's 1280) ...
const STRIP := 150.0          # ... and the controls' strip along the bottom of the rest this high: the picture has what is left
const LOOK_DWELL := 0.2       # s a button that changes the turntable's craft has the pointer or the keyboard before the camera turns to it
const CRAFT_SHARE := 2.3      # (no title) the pilot craft's button's stretch beside three others: its share of the row beside two (1.5 of 3.5)

var collision_checkbox: CheckBox
var partner_checkbox: CheckBox
var craft_selector: CraftSelector
var stage: Node3D             # the title: the scene the menu lies over (release/title_stage.gd; null with Title.enabled off)
var art := Rect2()            # ... and the part of the window its picture is composed in
var look_buttons: Array[Button] = []     # the buttons that change the craft on the title's turntable: pilot craft, paint, role
var _look_for := 0.0

func _ready() -> void:
	if "--benchmark" in OS.get_cmdline_user_args():
		var runner = preload("res://release/flight_benchmark.gd").new()
		add_child(runner)
		return
	craft_selector = CraftSelector.new()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UI.make_theme()
	stage = Title.make("flat")
	if stage != null:
		add_child(stage)
		_over_title()
		return
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
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 14, UI.MUTED))
	var sprint: Button
	var course_list: Container = left
	if UI.COURSES.size() > 6:   # eight and more: two abreast, or the list runs off the window
		course_list = GridContainer.new()
		(course_list as GridContainer).columns = 3 if UI.COURSES.size() > 8 else 2      # (nine: a fifth row of two pushed Quit out of a 720-line window)
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
	# Rows that step through choices (after the courses: the release check counts buttons from the top). Four
	# abreast each, the first of each widest; a third row would push Quit out of a 720-line window. Codex's
	# pilot-craft selector gives its button to the second row (its own two lines do not fit either), with Role,
	# Chase and Raids beside it narrower (their words are short): it keeps the share of the row it had beside two.
	left.add_child(craft_selector)
	craft_selector.build(false)
	craft_selector.remove_child(craft_selector.button)
	craft_selector.visible = false
	craft_selector.button.add_theme_font_size_override("font_size", 15)
	craft_selector.button.clip_text = true
	var paint_row := UI.paint_button(15)
	craft_selector.button.pressed.connect(UI.refresh_paint.bind(paint_row))      # (each craft has its own paint)
	for row: Array in [[UI.insertion_button(15), paint_row, UI.time_button(15), UI.weather_button(15)], [craft_selector.button, UI.craft_button(15), UI.chase_button(15), UI.raids_button(15)]]:
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		left.add_child(options)
		for k in row.size():
			var option: Button = row[k]
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.size_flags_stretch_ratio = 1.0 if k > 0 else (CRAFT_SHARE if option == craft_selector.button else 1.5)
			options.add_child(option)
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


## The menu over the title (Luke, 2026-11-22: "a title screen using this as a reference", a box cover).
## The scene fills the window from one fixed camera. The menu is the cover's spine: a dark column down
## the left edge with everything the old menu had, in the same order (the courses two abreast, the option
## rows three deep). The flight controls are a strip along the bottom of the rest, and the picture is
## composed in what is left, with the cover's strap line across its foot. The panels are not solid: the
## scene carries on under them.
func _over_title() -> void:
	var accent := ColorRect.new()
	accent.color = UI.AMBER
	accent.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	accent.offset_bottom = 3
	add_child(accent)
	var spine := PanelContainer.new()
	spine.name = "Spine"
	var backing := UI.box(Color(0.030, 0.043, 0.075, 0.90))
	backing.set_corner_radius_all(0)
	backing.border_color = UI.AMBER
	backing.border_width_right = 2
	backing.content_margin_left = 28
	backing.content_margin_right = 26
	backing.content_margin_top = 16
	backing.content_margin_bottom = 14
	spine.add_theme_stylebox_override("panel", backing)
	spine.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	spine.offset_right = SPINE
	add_child(spine)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	spine.add_child(left)
	left.add_child(UI.label("EXPERIMENTAL DESKTOP BUILD", 14, UI.AMBER))
	left.add_child(UI.label("PHAETHON", 36))
	left.add_child(UI.label("Two engines. One cockpit. We know it’s a little fucky.", 15))
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 13, UI.MUTED))
	var sprint: Button
	var course_list := GridContainer.new()
	course_list.columns = 2
	course_list.add_theme_constant_override("h_separation", 8)
	course_list.add_theme_constant_override("v_separation", 5)
	left.add_child(course_list)
	for course in UI.COURSES:
		var button := UI.button(course.name, start_course.bind(course.id), 36)
		button.name = "Course_" + course.id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.clip_text = true
		course_list.add_child(button)
		if course.id == "range":
			sprint = button
	collision_checkbox = UI.collision_checkbox(16)
	partner_checkbox = UI.partner_checkbox(16)
	var flight_options := HBoxContainer.new()
	flight_options.add_theme_constant_override("separation", 18)
	flight_options.add_child(collision_checkbox)
	flight_options.add_child(partner_checkbox)
	left.add_child(flight_options)
	left.add_child(UI.label("Collisions: pillars and traffic. Guardrails stay on.", 13, UI.MUTED))
	# the rows that step through choices, after the courses (the release check counts buttons from the top)
	left.add_child(craft_selector)
	craft_selector.build(false)
	craft_selector.remove_child(craft_selector.button)
	craft_selector.visible = false
	craft_selector.button.add_theme_font_size_override("font_size", 14)
	craft_selector.button.clip_text = true
	var paint := UI.paint_button(14)
	craft_selector.button.pressed.connect(UI.refresh_paint.bind(paint))      # (each craft has its own paint: after the selector's own handler)
	var role := UI.craft_button(14)
	look_buttons = [craft_selector.button, paint, role]
	for look in look_buttons:
		look.pressed.connect(_showcase_changed)      # (after the button's own handler: the choice is saved by then)
	_showcase_changed()
	# (Raids beside Chase and Role: the pilot craft's button keeps its row to itself for its long names)
	for row: Array in [[UI.insertion_button(14), paint], [UI.time_button(14), UI.weather_button(14)], [UI.chase_button(14), role, UI.raids_button(14)], [craft_selector.button]]:
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		left.add_child(options)
		for option: Button in row:
			option.custom_minimum_size.y = 34
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			options.add_child(option)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UI.label("A rough, playable physics experiment. Expect odd\nhandling, rough edges and spectacular mistakes.", 14, UI.MUTED))
	left.add_child(UI.button("Quit to desktop", get_tree().quit, 38))
	# the flight controls: a strip along the bottom of the picture's side
	var strip := UI.controls_strip()
	strip.name = "Controls"
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_left = SPINE + 12.0
	strip.offset_right = -12.0
	strip.offset_bottom = -10.0
	strip.offset_top = -10.0 - STRIP
	add_child(strip)
	# the cover's strap line across the picture's foot, between two orange rules
	var strap := HBoxContainer.new()
	strap.name = "Strap"
	strap.alignment = BoxContainer.ALIGNMENT_CENTER
	strap.add_theme_constant_override("separation", 22)
	strap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strap.offset_left = SPINE + 12.0
	strap.offset_right = -12.0
	strap.offset_bottom = -10.0 - STRIP - 10.0
	strap.offset_top = strap.offset_bottom - 34.0
	add_child(strap)
	var words := UI.label(Title.STRAP, 21, Title.Letters.CREAM)
	words.add_theme_font_override("font", Title.strap_font(7))
	words.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	words.add_theme_constant_override("shadow_offset_x", 2)
	words.add_theme_constant_override("shadow_offset_y", 2)
	for k in 2:
		var rule := ColorRect.new()
		rule.color = Title.Letters.STROKE
		rule.custom_minimum_size = Vector2(150, 3)
		rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		strap.add_child(rule)
		if k == 0:
			# the words lean as the cover's do: their own holder shears them (a font cannot be asked to)
			var holder := Control.new()
			strap.add_child(holder)
			var lean := Node2D.new()
			holder.add_child(lean)
			lean.add_child(words)
			var room := words.get_minimum_size()
			words.size = room
			words.position = -room / 2.0
			holder.custom_minimum_size = room
			lean.transform = Transform2D(Vector2.RIGHT, Vector2(-Title.STRAP_LEAN, 1.0), room / 2.0)
	resized.connect(_frame_title)
	_frame_title()
	sprint.grab_focus()


## Aim the title's camera at what the panels leave of the window.
func _frame_title() -> void:
	if stage == null:
		return
	art = Rect2(SPINE, 0.0, size.x - SPINE, size.y - STRIP - 20.0)
	stage.frame(art, size)


## Put the chosen pilot craft on the title's turntable, in the paint its flight will wear.
func _showcase_changed() -> void:
	if stage != null:
		stage.show_craft(craft_selector.selected)


## The title's camera turns to the turntable while a button that changes its craft has the pointer or the
## keyboard (a moment, so the pointer passing over one does not swing it), and back to the cover's view after.
func _process(delta: float) -> void:
	if stage == null:
		return
	var on := false
	for look in look_buttons:
		on = on or look.is_hovered() or look.has_focus()
	_look_for = _look_for + delta if on else 0.0
	stage.attend(_look_for >= LOOK_DWELL)

func start_course(course: String) -> void:
	if UI.course_index(course) < 0:
		return
	var overrides := UI.course_overrides(course)
	View.vehicle_override = craft_selector.selected
	View.track_override = overrides[0]
	View.job_override = overrides[1]
	View.spot_override = overrides[2]
	View.pad_start = true      # (the Network: on its starting pad at the roadside)
	get_tree().change_scene_to_file(UI.GAME_SCENE)
