extends Control

const UI := preload("res://release/release_config.gd")
const Garage := preload("res://release/garage_route.gd")
const Title := preload("res://release/title_stage.gd")
const SPINE := 500.0          # in the title, the menu's column down the left edge is this wide (of the window's 1280) ...
const STRIP := 150.0          # ... and the controls' strip along the bottom of the rest this high: the picture has what is left
const LOOK_DWELL := 0.2       # s a button that changes the turntable's craft has the pointer or the keyboard before the camera turns to it
# The course chosen last: the menu chooses it again when it is built (release/garage_route.gd hands it back after a
# garage visit, as it does the headset's).
static var remembered_course := "range"

# Luke, 2026-11-25: "the main menu should hold the map/game mode, but then any vehicle or additional adjustments should
# be made in codex's new garage", and "Keep quick Fly". So: choose a map, then Fly (at once, in the craft last used) or
# Pilot garage (Codex's workshop, bound for that map). The craft and its paint are chosen in the garage.
var selected_course := "range"
var launching := false        # Fly or Pilot garage pressed: the scene is changing, and nothing else starts
var course_buttons: Array[Button] = []   # in UI.COURSES' order
var fly_button: Button
var fly_craft: Label          # the craft Fly will use, named over it (_showcase_changed)
var collision_checkbox: CheckBox
var partner_checkbox: CheckBox
var stage: Node3D             # the title: the scene the menu lies over (release/title_stage.gd; null with Title.enabled off)
var art := Rect2()            # ... and the part of the window its picture is composed in
var look_buttons: Array[Button] = []     # the buttons that change the craft on the title's turntable: Role (the patrol's own paint)
var _look_for := 0.0

func _ready() -> void:
	if "--benchmark" in OS.get_cmdline_user_args():
		var runner = preload("res://release/flight_benchmark.gd").new()
		add_child(runner)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = UI.make_theme()
	stage = Title.make("flat")
	if stage != null:
		add_child(stage)
		_over_title()
	else:
		_plain()
	_showcase_changed()
	choose_course(remembered_course if UI.course_index(remembered_course) >= 0 else "range")
	course_buttons[UI.course_index(selected_course)].grab_focus()      # (the keyboard starts on the chosen map, as the headset's highlight does: Enter, Enter flies it)


func _plain() -> void:
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
	# (6 until Fly came: with it the column ran 13 px past the window's foot margin; 5 until the label naming the craft
	# came over Fly, which took the 6 px of breathing room under the tagline as well)
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(UI.label("EXPERIMENTAL DESKTOP BUILD", 15, UI.AMBER))
	left.add_child(UI.label("PHAETHON", 50))
	left.add_child(UI.label("Two engines. One cockpit.\nWe know it’s a little fucky.", 25))
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 14, UI.MUTED))
	var course_list: Container = left
	if UI.COURSES.size() > 6:   # eight and more: two abreast, or the list runs off the window
		course_list = GridContainer.new()
		(course_list as GridContainer).columns = 3 if UI.COURSES.size() > 8 else 2      # (nine: a fifth row of two pushed Quit out of a 720-line window)
		course_list.add_theme_constant_override("h_separation", 8)
		course_list.add_theme_constant_override("v_separation", 6)
		left.add_child(course_list)
	for course in UI.COURSES:
		var button := _course_button(course, 40)
		button.add_theme_font_size_override("font_size", 17)      # (at 18, "●  Aurora Pressure Line" outgrew its third of the row)
		course_list.add_child(button)
	collision_checkbox = UI.collision_checkbox()
	partner_checkbox = UI.partner_checkbox()
	var flight_options := HBoxContainer.new()
	flight_options.add_theme_constant_override("separation", 24)
	flight_options.add_child(collision_checkbox)
	flight_options.add_child(partner_checkbox)
	left.add_child(flight_options)
	left.add_child(UI.label("Collisions: pillars and traffic. Guardrails stay on.", 14, UI.MUTED))
	# Rows that step through choices (after the courses: the release check counts buttons from the top). Three
	# abreast each, the start point's widest for its long names; a third row would push Quit out of a 720-line window.
	var start := UI.insertion_button(15)
	for row: Array in [[start, UI.time_button(15), UI.weather_button(15)], [UI.chase_button(15), UI.craft_button(15), UI.raids_button(15)]]:
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		left.add_child(options)
		for option: Button in row:
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.size_flags_stretch_ratio = 1.5 if option == start else 1.0
			options.add_child(option)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UI.label("A rough, playable physics experiment.\nExpect odd handling, rough edges and spectacular mistakes.", 16, UI.MUTED))
	left.add_child(_fly_craft_label(15))
	left.add_child(_fly_button(48, 22))
	var exits := HBoxContainer.new()
	left.add_child(exits)
	for button: Button in [_garage_button(42), UI.button("Quit to desktop", get_tree().quit, 42)]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exits.add_child(button)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	columns.add_child(right)
	right.add_child(UI.controls_panel())


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
	backing.content_margin_top = 12      # (16, and the column's gaps 5, until the label naming the craft came over Fly: Quit was pushed off the window)
	backing.content_margin_bottom = 14
	spine.add_theme_stylebox_override("panel", backing)
	spine.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	spine.offset_right = SPINE
	add_child(spine)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	spine.add_child(left)
	left.add_child(UI.label("EXPERIMENTAL DESKTOP BUILD", 14, UI.AMBER))
	left.add_child(UI.label("PHAETHON", 36))
	left.add_child(UI.label("Two engines. One cockpit. We know it’s a little fucky.", 15))
	left.add_child(UI.label("CHOOSE YOUR BAD IDEA", 13, UI.MUTED))
	var course_list := GridContainer.new()
	course_list.columns = 2
	course_list.add_theme_constant_override("h_separation", 8)
	course_list.add_theme_constant_override("v_separation", 4)
	left.add_child(course_list)
	for course in UI.COURSES:
		var button := _course_button(course, 36)
		button.add_theme_font_size_override("font_size", 15)      # (at 17, the marks' indent cut "Aurora Pressure Line")
		button.clip_text = true
		course_list.add_child(button)
	collision_checkbox = UI.collision_checkbox(16)
	partner_checkbox = UI.partner_checkbox(16)
	var flight_options := HBoxContainer.new()
	flight_options.add_theme_constant_override("separation", 18)
	flight_options.add_child(collision_checkbox)
	flight_options.add_child(partner_checkbox)
	left.add_child(flight_options)
	left.add_child(UI.label("Collisions: pillars and traffic. Guardrails stay on.", 13, UI.MUTED))
	# the rows that step through choices, after the courses (the release check counts buttons from the top), two abreast:
	# where on the Network and its Raids (the start point the wider, for its long names), the sky, and the chase with
	# its Role (pursuit or getaway is a chase choice)
	var role := UI.craft_button(14)
	look_buttons = [role]
	role.pressed.connect(_showcase_changed)      # (after the button's own handler: the choice is saved by then)
	var start := UI.insertion_button(14)
	for row: Array in [[start, UI.raids_button(14)], [UI.time_button(14), UI.weather_button(14)], [UI.chase_button(14), role]]:
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		left.add_child(options)
		for option: Button in row:
			option.custom_minimum_size.y = 34
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.size_flags_stretch_ratio = 1.6 if option == start else 1.0
			options.add_child(option)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(UI.label("A rough, playable physics experiment. Expect odd\nhandling, rough edges and spectacular mistakes.", 14, UI.MUTED))
	left.add_child(_fly_craft_label(14))
	left.add_child(_fly_button(48, 22))
	# Codex's Pilot garage beside Quit, as on the plain menu and the headset's
	var exits := HBoxContainer.new()
	exits.add_theme_constant_override("separation", 8)
	left.add_child(exits)
	for button: Button in [_garage_button(38), UI.button("Quit to desktop", get_tree().quit, 38)]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exits.add_child(button)
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


## Aim the title's camera at what the panels leave of the window.
func _frame_title() -> void:
	if stage == null:
		return
	art = Rect2(SPINE, 0.0, size.x - SPINE, size.y - STRIP - 20.0)
	stage.frame(art, size)


## Name the craft Fly will use over Fly, and put it on the title's turntable in the paint its flight will wear.
func _showcase_changed() -> void:
	var craft := UI.Settings.selected_craft()
	if fly_craft != null:
		fly_craft.text = UI.fly_craft_text(craft)
	if stage != null:
		stage.show_craft(craft)


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


## A map's button: it chooses the map (no flight starts: Fly does that).
func _course_button(course: Dictionary, height: int) -> Button:
	var button := UI.button(course.name, choose_course.bind(course.id), height)
	button.name = "Course_" + course.id
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_buttons.append(button)
	return button


## The craft Fly will use, in words directly over Fly (the turntable shows it only while Role has the pointer, and the
## plain menu has none): muted, and where to change it.
func _fly_craft_label(font_size: int) -> Label:
	fly_craft = UI.label("", font_size, UI.MUTED)
	fly_craft.name = "FlyCraft"
	return fly_craft


## Fly: the widest and tallest button on the menu, named for the chosen map (choose_course).
func _fly_button(height: int, font_size: int) -> Button:
	fly_button = UI.button("Fly", fly, height)
	fly_button.name = "Fly"
	fly_button.add_theme_font_size_override("font_size", font_size)
	fly_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return fly_button


func _garage_button(height: int) -> Button:
	var button := UI.button("Pilot garage", _open_garage, height)
	button.name = "Garage"
	return button


## Choose a map: marked as the headset's board marks its choice, named on Fly, remembered for the next menu, and the
## keyboard to Fly (so Enter on a map, then Enter again, flies it).
func choose_course(course: String) -> void:
	var index := UI.course_index(course)
	if index < 0 or launching:
		return
	selected_course = course
	remembered_course = course
	fly_button.text = UI.fly_text(UI.COURSES[index].name)
	for i in UI.COURSES.size():
		course_buttons[i].text = UI.course_text(UI.COURSES[i].name, i == index)
	fly_button.grab_focus()


## Fly: at once, the chosen map in the craft last used, with its saved switches and paint (release/garage_route.gd
## fly). Once: a second press, or Pilot garage, before the scene changes does nothing.
func fly() -> void:
	if launching or UI.course_index(selected_course) < 0:
		return
	launching = true
	Garage.fly(get_tree(), false, selected_course)


## Codex's Pilot garage, bound for the chosen map: departing it starts the flight there.
func _open_garage() -> void:
	if launching:
		return
	launching = true
	Garage.enter(get_tree(), false, selected_course)


## A course started in one call (tests and tools): choose it, then Fly. An unknown course does nothing.
func start_course(course: String) -> void:
	if UI.course_index(course) < 0:
		return
	choose_course(course)
	fly()
