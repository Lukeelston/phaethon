extends RefCounted

const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const Raids := preload("res://view/network_raids.gd")

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
	{"id": "carving", "name": "S5 Carving Circuit", "detail": "S5's sweeping rhythm, built for racing.\nSpeedcraft, ramjet, and your cleanest lap."},
	{"id": "coast", "name": "Coast Road", "detail": "The Network's west edge: 250 km.\nThe sea on your left, a mountain on your right."},
	{"id": "drop", "name": "The Drop", "detail": "The Network's east edge: up a mountainside,\nthen 2 km down off its rim into the valley."},
	{"id": "aurora", "name": "Aurora Pressure Line", "detail": "A glass crossing from corner to corner.\nSteer up either wall and across the ceiling."},
]
# A course that is a place on the Network: its road there (the flight starts at the foot of it).
const SPOTS := {"coast": "SCoast", "drop": "SDrop", "aurora": "SAurora"}
# Where a flight on the Network itself begins (Luke: "would also love to be able to choose insertion
# point on the network"): [id, the menus' name for it, the spot]. A spot is "" (the city last
# reached, as it always was), "city:NAME" (that city's terminal), or a road's name, with "@sample"
# to start that far up it and a second "@-1" to face down it. A scenic road named alone starts at
# the foot of its scenery (view/craft_view.gd start_spot). The id is what is saved.
const INSERTIONS := [
	["last", "Last city reached", ""],
	["eridanus", "Eridanus", "city:ERIDANUS"], ["dunes", "Dunes", "city:DUNES"], ["glacier", "Glacier", "city:GLACIER"],
	["basalt", "Basalt", "city:BASALT"], ["mesa", "Mesa", "city:MESA"],
	["coast", "Coast Road", "SCoast"], ["drop", "The Drop", "SDrop"],
	["wash", "Sirocco Wash", "SWash@130"], ["frost", "Frostline Pass", "SFrost@140"],
	["reed", "Reedwater Causeway", "SReed@135"], ["red", "Red Table Cut", "SRed@130"],
	["needle", "Needle Roll", "SNeedle@96"], ["hammer", "Hammerfall", "SHammer@92"],
	["gap", "Mesa Gap run-up", "N3@300"],     # N3 northbound, 55 km short of the ramp the launch forks from
	["helios", "Helios, the foot", "SHelios@1540"],     # 2 km short of where the road meets the mountain
	["summit", "Helios summit", "SHelios@7244"],   # the centre of the spire's plateau, 16 km up, facing the far rim 3 km on (the designer's Face "centre")
	["hyperion", "Hyperion, the foot", "SHyperion@1790"],     # 2 km short of the ramp's foot, the mountain dead ahead
	["hyperion_summit", "Hyperion summit", "SHyperion@5200"],   # 48 km up, 96 m short of the summit's stop line and 384 m short of the lip (the designer's "lip" less 16)
	# (the Caucasus, 2026-11-22: start points only. A tenth course would not fit the VR board, which is full at nine)
	["caucasus", "The Caucasus", "SCaucasus"],     # the foot of the range (its scenic stretch's start: the climb comes to you)
	["crest", "Caucasus crest", "SCaucasus@4534"],   # 3,260 m up, on the level top of the Crest (its height key's own sample): the land gone on both sides, the ridge road ahead
]

static func course_index(id: String) -> int:
	for i in COURSES.size():
		if COURSES[i].id == id:
			return i
	return -1

static func insertion_ids() -> Array:
	return INSERTIONS.map(func(entry): return entry[0])


## The saved insertion point's [id, name, spot].
static func insertion() -> Array:
	var id := Settings.choice("network_start", insertion_ids())
	return INSERTIONS[insertion_ids().find(id)]


## [track, job, the Network spot to start at ("" for none: a city, the last one reached)].
static func course_overrides(id: String) -> Array:
	if SPOTS.has(id):
		return ["network", "none", SPOTS[id]]
	if id == "network":
		return ["network", "none", insertion()[2]]
	return ["eridanus", "emergency", ""] if id == "emergency" else [id, "none", ""]


## The menu's course for a flight: a scenic road's own entry if it started on one.
static func course_for(track: String, spot: String) -> String:
	for id in SPOTS:
		if SPOTS[id] == spot and track == "network":
			return id
	return track

static func box(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(4)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 8
	style.content_margin_bottom = 8
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

static func collision_checkbox(font_size: int = 18) -> CheckBox:
	var item := CheckBox.new()
	item.text = "Obstacle collisions"
	item.custom_minimum_size.y = 38
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_icon_override("unchecked", preload("res://release/checkbox_off.svg"))
	item.add_theme_icon_override("checked", preload("res://release/checkbox_on.svg"))
	item.add_theme_color_override("checkbox_unchecked_color", Color.WHITE)
	item.add_theme_color_override("checkbox_checked_color", Color.WHITE)
	item.button_pressed = Settings.obstacle_collisions_enabled()
	item.toggled.connect(Settings.set_obstacle_collisions)
	return item

static func partner_checkbox(font_size: int = 18) -> CheckBox:
	var item := CheckBox.new()
	item.text = "Driving partner"
	item.custom_minimum_size.y = 38
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_icon_override("unchecked", preload("res://release/checkbox_off.svg"))
	item.add_theme_icon_override("checked", preload("res://release/checkbox_on.svg"))
	item.add_theme_color_override("checkbox_unchecked_color", Color.WHITE)
	item.add_theme_color_override("checkbox_checked_color", Color.WHITE)
	item.button_pressed = Settings.driving_partner_enabled()
	item.toggled.connect(Settings.set_driving_partner)
	return item

## A row that steps through named choices: each press takes the next and saves it. `choices` is
## [[id, name], ...]; `changed` (optional) hears the new id.
static func option_button(title: String, key: String, choices: Array, font_size: int = 18, changed: Callable = Callable()) -> Button:
	var ids := choices.map(func(entry): return entry[0])
	var item := _option_row(font_size)
	var show := func() -> void:
		item.text = "%s:  %s" % [title, choices[ids.find(Settings.choice(key, ids))][1]]
	item.pressed.connect(func() -> void:
		var next: String = ids[(ids.find(Settings.choice(key, ids)) + 1) % ids.size()]
		Settings.set_choice(key, next)
		show.call()
		if changed.is_valid():
			changed.call(next))
	show.call()
	return item


static func _option_row(font_size: int) -> Button:
	var item := Button.new()
	item.custom_minimum_size.y = 38
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.clip_text = true
	item.add_theme_font_size_override("font_size", font_size)
	return item


static func insertion_button(font_size: int = 18) -> Button:
	return option_button("Start", "network_start", INSERTIONS, font_size)


## The paint row (Luke: "Will you make it so that all vehicles can have a color option?"): the chosen pilot
## craft's own paint, Factory first (view/livery.gd). Each press takes that craft's next and saves it as
## that craft's; the other craft keep theirs. When the menus change the pilot craft, refresh_paint() shows
## the new one's.
static func paint_button(font_size: int = 18) -> Button:
	var item := _option_row(font_size)
	item.pressed.connect(func() -> void:
		var craft := Settings.selected_craft()
		var ids := Livery.ids_for(craft)
		Settings.set_choice(Livery.key_for(craft), ids[(ids.find(Livery.saved_for(craft)) + 1) % ids.size()])
		refresh_paint(item))
	refresh_paint(item)
	return item


## Show the chosen pilot craft's paint on the paint row.
static func refresh_paint(item: Button) -> void:
	var craft := Settings.selected_craft()
	var choices := Livery.choices_for(craft)
	item.text = "Paint:  %s" % choices[Livery.ids_for(craft).find(Livery.saved_for(craft))][1]


static func craft_button(font_size: int = 18) -> Button:
	return option_button("Role", "craft", Chase.CRAFTS, font_size)


static func chase_button(font_size: int = 18) -> Button:
	return option_button("Chase", "chase", Chase.MODES, font_size)


static func raids_button(font_size: int = 18) -> Button:
	return option_button("Raids", "raids", Raids.MODES, font_size)


static func time_button(font_size: int = 18) -> Button:
	return option_button("Time", "time", Outlook.TIMES, font_size)


static func weather_button(font_size: int = 18) -> Button:
	return option_button("Weather", "weather", Outlook.WEATHERS, font_size)


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
		["R / Pad Y", "Tap to arm ramjet\nHold for 1.3× boost"],
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


## The flight controls as a strip, three keys abreast: the same keys as controls_panel(), for the desktop
## menu over the title (release/menu.gd lays it along the bottom of the picture).
static func controls_strip() -> PanelContainer:
	var panel := PanelContainer.new()
	var backing := box(Color(0.030, 0.043, 0.075, 0.88), Color("34414b"))
	backing.content_margin_left = 18
	backing.content_margin_right = 18
	backing.content_margin_top = 8
	backing.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", backing)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	content.add_child(head)
	head.add_child(label("FLIGHT CONTROLS", 14, AMBER))
	head.add_child(label("Steer with unequal thrust; throttle stays where you leave it. Start gently: hold E.", 13, MUTED))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	content.add_child(grid)
	for row in [
		["E / D", "Both throttles up / down"], ["W / S", "Left throttle up / down"], ["↑ / ↓", "Right throttle up / down"],
		["A / →", "Left / right air brake"], ["X", "Cut both throttles"], ["Space", "Reignite engines"],
		["H", "Hold to repair"], ["R / Pad Y", "Tap to arm ramjet\nHold for 1.3× boost"], ["M", "Switch handling mode"],
		["Backspace", "Reset to track; keeps throttle"], ["Esc", "Pause / resume"], ["Pad", "Gamepad: experimental"]
	]:
		grid.add_child(label(row[0], 13, AMBER))
		var what := label(row[1], 13)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(what)
	return panel
