extends VBoxContainer

const UI := preload("res://release/release_config.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")

var selected := Craft.STANDARD
var button: Button
var detail: Label


func build(vr: bool) -> void:
	selected = Settings.selected_craft()
	add_theme_constant_override("separation", 2)
	button = UI.button("", cycle, 52 if vr else 42)
	button.add_theme_font_size_override("font_size", 25 if vr else 20)
	button.tooltip_text = "Change pilot craft"
	add_child(button)
	detail = UI.label("", 20 if vr else 15, UI.MUTED)
	add_child(detail)
	_refresh()


func cycle() -> void:
	selected = Craft.next(selected)
	Settings.set_selected_craft(selected)
	_refresh()


func _refresh() -> void:
	button.text = "Pilot craft   ·   %s   ›" % Craft.NAMES[selected]
	detail.text = Craft.DETAILS[selected]
