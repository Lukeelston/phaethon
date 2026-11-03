extends RefCounted

const BACKGROUND := Color("10151b")
const PANEL := Color("192129")
const INK := Color("ecede9")
const MUTED := Color("a3adb5")
const AMBER := Color("efb15d")
const MENU_SCENE := "res://release/menu.tscn"
const GAME_SCENE := "res://main.tscn"
const VR_MENU_SCENE := "res://release/vr_menu.tscn"
const COURSES := [
	{"id": "range", "name": "100-mile Sprint", "detail": "A straight run into absurd speed.\nStop inside the finish box. Brake early."},
	{"id": "gp", "name": "Grand Prix", "detail": "A tighter 29 km circuit.\nStarts in Starfighter handling."},
	{"id": "eridanus", "name": "Eridanus", "detail": "A 199 km course with a fast loop\nand two Starfighter towns."},
	{"id": "emergency", "name": "Emergency Run", "detail": "An emergency delivery on Eridanus.\nAn additional experimental mode."},
	{"id": "network", "name": "The Network", "detail": "Explore linked roads and cities.\nAn additional experimental map."},
]

static func course_index(id: String) -> int:
	for i in COURSES.size():
		if COURSES[i].id == id:
			return i
	return -1

static func course_overrides(id: String) -> Array:
	return ["eridanus", "emergency"] if id == "emergency" else [id, "none"]

static func box(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	return style

static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", BACKGROUND)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_stylebox("normal", "Button", box(PANEL, Color("34414b")))
	theme.set_stylebox("hover", "Button", box(Color("27313a"), AMBER))
	theme.set_stylebox("pressed", "Button", box(AMBER))
	var focus := box(Color.TRANSPARENT, AMBER)
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_constant("separation", "VBoxContainer", 12)
	return theme

static func label(text: String, font_size: int, color: Color = INK) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	return item

static func button(text: String, action: Callable, height: float = 58) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = height
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.pressed.connect(action)
	return item

static func controls_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(PANEL))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)
	content.add_child(label("FLIGHT CONTROLS", 17, AMBER))
	var intro := label("Steer with unequal engine thrust.\nThrottle stays where you leave it.", 17, MUTED)
	content.add_child(intro)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for row in [
		["E / D", "Both throttles up / down"],
		["W / S", "Left throttle up / down"],
		["↑ / ↓", "Right throttle up / down"],
		["A / →", "Left / right air brake"],
		["X", "Cut both throttles"],
		["Space", "Reignite engines"],
		["H", "Hold to repair"],
		["R", "Arm ramjet"],
		["M", "Switch handling mode"],
		["Backspace", "Reset to track; keeps throttle"],
		["Esc", "Pause / resume"]
	]:
		grid.add_child(label(row[0], 17, AMBER))
		grid.add_child(label(row[1], 17))
	content.add_child(HSeparator.new())
	content.add_child(label("Start gently: hold E, then release.\nHold D to ease off; X cuts thrust.", 17, MUTED))
	content.add_child(label("Keyboard first. Gamepad support is experimental.", 14, MUTED))
	return panel
