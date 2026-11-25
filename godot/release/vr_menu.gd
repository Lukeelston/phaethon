## Stationary, headset-visible course menu. No flight and no flight audio is loaded: the title's two
## craft (release/title_stage.gd) stand round it, silent, and go when a flight starts. The craft Fly will
## use turns on a turntable behind the board, which swings aside while Role has the highlight.
## Luke, 2026-11-25: "the main menu should hold the map/game mode, but then any vehicle or additional adjustments
## should be made in codex's new garage", and "Keep quick Fly". So, as on the desktop: choose a map, then Fly (at
## once, in the craft last used) or Pilot garage (Codex's workshop, bound for that map). The craft and its paint are
## chosen in the garage.
extends Node3D

const Garage := preload("res://release/garage_route.gd")
const UI := preload("res://release/release_config.gd")
const Title := preload("res://release/title_stage.gd")
const BOARD_DROP := 0.40      # in the title, the board's middle is this far under the eye and leaned back to face it: the word stands over its top edge
# In the title the turntable stands straight ahead behind the board (release/title_stage.gd). While a row
# that changes what is on it (Role: the patrol's own paint) has had the highlight a moment, it is
# brought up and the board swings this far to the left about the pilot, and shrinks, clear of the longest
# craft's sweep (36 degrees either side of ahead, the turntable 26.5 m out); it swings back, and the
# turntable is put away, when the highlight leaves.
const BOARD_SWING := 57.0
const BOARD_SWING_SCALE := 0.62
const SWING_DWELL := 0.25     # s on such a row before it goes (the stick passing over one does not move it)
const SWING_S := 0.5          # s to swing either way
static var remembered_course := "range"

var selected_course := "range"
var focus_index := 0
var launching := false
var camera: XRCamera3D
var hands: Array[XRController3D] = []
var panel_view: SubViewport
var screen: Control
var board: MeshInstance3D
var stage: Node3D             # the title: the place the board stands in (null with Title.enabled off: the board in the dark, as it was)
var strap: Node3D             # ... and its strap line, hung under the board
var buttons: Array[Button] = []
var title: Label
var description: Label
var start_button: Button      # Fly, named for the chosen map
var fly_craft: Label          # ... and the craft it will use, named over the hint above it (_showcase_changed)
var collision_checkbox: CheckBox
var partner_checkbox: CheckBox
var option_buttons: Array[Button] = []   # the rows that step through choices: where the Network begins, ...
var look_buttons: Array[Button] = []     # the rows that change the craft on the turntable: Role (the patrol's own paint)
var swing := 0.0              # 0 the board in front of the pilot, 1 swung aside to show the turntable
var start_index := 0
var _dwell := 0.0
var _home_eye := Vector3.ZERO
var _home_forward := Vector3.FORWARD
var _confirm_down := true
var _stick_down := true
var _armed := false
var _focused := false
var _recenter_down := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var xr := XRServer.find_interface("OpenXR")
	if xr != null and xr.is_initialized():
		get_viewport().use_xr = true
		get_viewport().msaa_3d = Viewport.MSAA_4X
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	stage = Title.make("vr")      # (it brings its own sky and light)
	if stage != null:
		add_child(stage)
	else:
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("090e13")
		add_child(environment)
	var origin := XROrigin3D.new()
	add_child(origin)
	camera = XRCamera3D.new()
	if stage != null:
		camera.far = 200000.0      # (the cloud deck and the far city: a camera's own reach is 4 km)
	origin.add_child(camera)
	for side in ["left_hand", "right_hand"]:
		var hand := XRController3D.new()
		hand.tracker = side
		origin.add_child(hand)
		hands.append(hand)
	panel_view = SubViewport.new()
	panel_view.size = Vector2i(1440, 900)
	panel_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	panel_view.gui_disable_input = true
	add_child(panel_view)
	_build_screen()
	board = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.2, 2.0)
	board.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = panel_view.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	board.material_override = material
	add_child(board)
	if stage != null:
		strap = Title.strap_3d(quad.size.x)
		strap.position = Vector3(0.0, -quad.size.y / 2.0 - 0.10, 0.0)
		board.add_child(strap)
	choose_course(remembered_course if UI.course_index(remembered_course) >= 0 else "range")
	focus_row(maxi(0, UI.course_index(selected_course)))
	_showcase_changed()
	recenter_panel()
	print("VR MENU: ready; select a map, then Fly or Pilot garage")


## Name the craft Fly will use on the board, and put it on the title's turntable in the paint its flight will wear.
func _showcase_changed() -> void:
	var craft := UI.Settings.selected_craft()
	if fly_craft != null:
		fly_craft.text = UI.fly_craft_text(craft)
	if stage != null:
		stage.show_craft(craft)

func _build_screen() -> void:
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.theme = UI.make_theme()
	panel_view.add_child(screen)
	var background := ColorRect.new()
	background.color = UI.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 32)
	screen.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	layout.add_child(UI.label("PHAETHON", 56))
	layout.add_child(UI.label("Two engines. One cockpit. We know it’s a little fucky.", 24, UI.MUTED))
	layout.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 580
	columns.add_child(choices)
	choices.add_child(UI.label("Choose a map", 32, UI.AMBER))
	var crowded: bool = UI.COURSES.size() > 6   # eight rows fit the board at this height and spacing
	if crowded:
		choices.add_theme_constant_override("separation", 6)
	for course in UI.COURSES:
		var button := UI.button(course.name, choose_course.bind(course.id), 46 if crowded else 64)
		button.add_theme_font_size_override("font_size", (22 if UI.COURSES.size() > 8 else 24) if crowded else 28)      # (nine courses: a size down, or the board's last line sat on its edge)
		choices.add_child(button)
		buttons.append(button)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 7)
	columns.add_child(details)
	title = UI.label("", 32, UI.AMBER)
	details.add_child(title)
	description = UI.label("", 24)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(description)
	# The two switches side by side, then the rows that step through choices (they need the room the
	# switches' own lines took: with a row each the column ran off the board).
	var switches := HBoxContainer.new()
	switches.add_theme_constant_override("separation", 20)
	details.add_child(switches)
	collision_checkbox = UI.collision_checkbox(26)
	collision_checkbox.custom_minimum_size.y = 52
	collision_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switches.add_child(collision_checkbox)
	buttons.append(collision_checkbox)
	partner_checkbox = UI.partner_checkbox(26)
	partner_checkbox.custom_minimum_size.y = 52
	partner_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	switches.add_child(partner_checkbox)
	buttons.append(partner_checkbox)
	details.add_child(UI.label("Collisions: pillars and traffic. Guardrails stay on.", 20, UI.MUTED))
	var role := UI.craft_button(22)
	look_buttons = [role]
	for look in look_buttons:
		look.pressed.connect(_showcase_changed)      # (after the row's own handler: the choice is saved by then)
	# A or the trigger takes the next choice. Two abreast, as over the desktop's title: where on the Network and its
	# Raids, the sky, and the chase with its Role (pursuit or getaway is a chase choice).
	var rows: Array = [[UI.insertion_button(22), UI.raids_button(22)], [UI.time_button(22), UI.weather_button(22)], [UI.chase_button(22), role]]
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		details.add_child(line)
		for option: Button in row:
			option.custom_minimum_size.y = 46
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(option)
			buttons.append(option)
			option_buttons.append(option)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	# the craft Fly will use, in words (the turntable shows it only while Role has the highlight), in the band the
	# craft and paint rows left over the hint
	fly_craft = UI.label("", 22, UI.MUTED)
	fly_craft.name = "FlyCraft"
	details.add_child(fly_craft)
	details.add_child(UI.label("Release controls after Fly.  In flight, tap Menu: options.\nHold Menu: back to this board; ends the run.", 20, UI.MUTED))
	start_button = UI.button("Fly", start_selected, 72)
	start_button.name = "Fly"
	start_button.add_theme_font_size_override("font_size", 30)
	layout.add_child(start_button)
	start_index = buttons.size()
	buttons.append(start_button)
	var exits := HBoxContainer.new()
	layout.add_child(exits)
	var garage := UI.button("Pilot garage", _open_garage, 60)
	garage.name = "Garage"
	for button: Button in [garage, UI.button("Quit to desktop", get_tree().quit, 60)]:
		button.add_theme_font_size_override("font_size", 26)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exits.add_child(button)
		buttons.append(button)
	layout.add_child(UI.label("Stick up/down: highlight    A or trigger: select    Stick click: recenter", 25, UI.MUTED))

func choose_course(course: String) -> void:
	var index := UI.course_index(course)
	if index < 0 or launching:
		return
	selected_course = course
	remembered_course = course
	title.text = UI.COURSES[index].name
	description.text = UI.COURSES[index].detail
	start_button.text = UI.fly_text(UI.COURSES[index].name)
	for i in UI.COURSES.size():
		buttons[i].text = UI.course_text(UI.COURSES[i].name, i == index)

func focus_row(index: int) -> void:
	focus_index = posmod(index, buttons.size())
	for i in buttons.size():
		buttons[i].add_theme_stylebox_override("normal", UI.box(Color("344350"), UI.AMBER) if i == focus_index else UI.box(UI.PANEL, Color("34414b")))

func activate() -> void:
	if launching:
		return
	if buttons[focus_index] is CheckBox:
		buttons[focus_index].button_pressed = not buttons[focus_index].button_pressed
	else:
		buttons[focus_index].pressed.emit()
	if focus_index < UI.COURSES.size():
		focus_row(start_index)

## Fly: at once, the chosen map in the craft last used, with its saved switches and paint (release/garage_route.gd
## fly), from cold as any start from this board. Once: a second press, or Pilot garage, before the scene changes does
## nothing.
func start_selected() -> void:
	if launching or UI.course_index(selected_course) < 0:
		return
	launching = true
	start_button.text = "Loading " + title.text + "."
	print("VR MENU: starting ", selected_course)
	Garage.fly(get_tree(), true, selected_course)


## Codex's Pilot garage, bound for the chosen map: departing it starts the flight there.
func _open_garage() -> void:
	if launching:
		return
	launching = true
	Garage.enter(get_tree(), true, selected_course)


func consume_controller(axis: float, confirm: bool, focused: bool) -> void:
	if not focused:
		_armed = false
		return
	# A squeezed flight trigger must never immediately restart from this menu.
	if not _armed:
		if not confirm and absf(axis) < 0.3:
			_armed = true
			_confirm_down = false
			_stick_down = false
		return
	if absf(axis) < 0.3:
		_stick_down = false
	elif absf(axis) > 0.65 and not _stick_down:
		_stick_down = true
		focus_row(focus_index + (-1 if axis > 0 else 1))
	if confirm and not _confirm_down:
		activate()
	_confirm_down = confirm

func _process(delta: float) -> void:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	var focused := xr != null and xr.is_initialized() and xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	if focused and not _focused:
		recenter_panel()
	_focused = focused
	var axis := 0.0
	var confirm := false
	var center := false
	for hand in hands:
		if not hand.get_has_tracking_data():
			continue
		var stick := hand.get_vector2("primary")
		if absf(stick.y) > absf(axis):
			axis = stick.y
		confirm = confirm or hand.get_float("trigger") > 0.65 or hand.is_button_pressed("ax_button")
		center = center or hand.is_button_pressed("primary_click")
	if center and not _recenter_down and focused:
		recenter_panel()
	_recenter_down = center
	consume_controller(axis, confirm, focused)
	update_swing(delta)

## In the title: swing the board aside while a row that changes the turntable's craft has had the
## highlight SWING_DWELL, and back when the highlight leaves it.
func update_swing(delta: float) -> void:
	if stage == null:
		return
	var on_look := focus_index < buttons.size() and look_buttons.has(buttons[focus_index]) and not launching
	_dwell = _dwell + delta if on_look else 0.0
	stage.attend(_dwell >= SWING_DWELL)
	var was := swing
	swing = move_toward(swing, 1.0 if _dwell >= SWING_DWELL else 0.0, delta / SWING_S)
	if swing != was:
		_place_board()

func recenter_panel() -> void:
	var forward := -camera.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	if stage == null:
		board.global_position = camera.global_position + forward * 3.0
		board.global_basis = Basis.looking_at(forward, Vector3.UP)
		return
	# In the title the board stands a little under the eye, leaned back to face it, and the scene is stood
	# round the pilot the same way: both move only here (the session's start, a recentre), never the camera.
	_home_eye = camera.global_position
	_home_forward = forward
	_place_board()
	stage.place(camera.global_position, forward)

## The board where the last recentre stood it, swung aside as far as `swing` says (eased at both ends).
func _place_board() -> void:
	var e := smoothstep(0.0, 1.0, swing)
	var forward := _home_forward.rotated(Vector3.UP, deg_to_rad(BOARD_SWING) * e)      # (+ about up: to the pilot's left)
	board.global_position = _home_eye + forward * 3.0 + Vector3.DOWN * BOARD_DROP
	board.global_basis = Basis.looking_at(forward, Vector3.UP) * Basis(Vector3.RIGHT, -atan2(BOARD_DROP, 3.0)) * Basis.from_scale(Vector3.ONE * lerpf(1.0, BOARD_SWING_SCALE, e))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP: focus_row(focus_index - 1)
			KEY_DOWN, KEY_TAB: focus_row(focus_index + 1)
			KEY_ENTER, KEY_SPACE: activate()
			_: return
		get_viewport().set_input_as_handled()
