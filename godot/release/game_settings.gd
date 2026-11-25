## Shared desktop/VR flight preference. Each export uses its own user-data folder.
extends RefCounted

const PREFS := "user://game_settings.cfg"
static var prefs_path := PREFS
const Craft := preload("res://sim/pilot_craft.gd")

static func selected_craft() -> String:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return Craft.STANDARD
	return Craft.known(config.get_value("flight", "vehicle", Craft.STANDARD))

static func set_selected_craft(id: String) -> void:
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("flight", "vehicle", Craft.known(id))
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save pilot craft: %s" % error_string(error))

static func driving_partner_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return false
	var saved = config.get_value("flight", "driving_partner", false)
	return saved if saved is bool else false

static func set_driving_partner(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("flight", "driving_partner", enabled)
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save driving partner preference: %s" % error_string(error))

## Launch flags override this flight; only a menu choice changes the saved preference.
static func resolve_driving_partner(args: PackedStringArray) -> bool:
	if "--no-partner" in args:
		return false
	return "--partner" in args or driving_partner_enabled()

static func obstacle_collisions_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return false # preserve the release's existing pass-through traffic
	var saved = config.get_value("flight", "obstacle_collisions", false)
	return saved if saved is bool else false

static func set_obstacle_collisions(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("flight", "obstacle_collisions", enabled)
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save obstacle collision preference: %s" % error_string(error))


## A named choice from one of the menus' option rows ("flight" section, like the two switches above):
## where a Network flight begins, the time of day, the weather, the craft's paint. `allowed` guards
## against a stale or hand-edited value; the first entry is the default.
static func choice(key: String, allowed: Array) -> String:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return allowed[0]
	var saved = config.get_value("flight", key, allowed[0])
	return saved if saved is String and allowed.has(saved) else allowed[0]

static func set_choice(key: String, value: String) -> void:
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("flight", key, value)
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save the %s preference: %s" % [key, error_string(error)])


## The switch set-up a craft was last flown with ("garage" section, one entry a craft): "handling" ("speed" or
## "starfighter") and "slide" (bool), each present only when saved and valid. Anything else stored is dropped (a
## stale or hand-edited file); the engine state is never saved, a flight always begins on a cold pad.
static func craft_setup(id: String) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return {}
	return _valid_setup(config.get_value("garage", Craft.known(id), {}))

## Merges the valid keys of `moved` over the craft's saved set-up. Nothing valid, nothing saved; nor for an id that is not
## a craft's (Craft.known would make it the default craft's).
static func set_craft_setup(id: String, moved: Dictionary) -> void:
	if id not in Craft.ORDER:
		return
	var valid := _valid_setup(moved)
	if valid.is_empty():
		return
	var setup := craft_setup(id)
	setup.merge(valid, true)
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("garage", Craft.known(id), setup)
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save the %s set-up: %s" % [id, error_string(error)])

## Which body stands in the Phaethon's garage bay ("garage" section, "phaethon_body"): the Phaethon or the Talon, the
## Phaethon until one is saved (a hand-edited value is the Phaethon too).
static func phaethon_body() -> String:
	var config := ConfigFile.new()
	if config.load(prefs_path) != OK:
		return Craft.STANDARD
	var saved = config.get_value("garage", "phaethon_body", Craft.STANDARD)
	return saved if saved is String and saved in [Craft.STANDARD, Craft.TALON] else Craft.STANDARD

static func set_phaethon_body(id: String) -> void:
	if id not in [Craft.STANDARD, Craft.TALON]:
		return
	var config := ConfigFile.new()
	config.load(prefs_path)
	config.set_value("garage", "phaethon_body", id)
	var error := config.save(prefs_path)
	if error != OK:
		push_warning("Could not save the Phaethon's bay's body: %s" % error_string(error))

static func _valid_setup(raw: Variant) -> Dictionary:
	var valid := {}
	if not raw is Dictionary:
		return valid
	var handling = raw.get("handling")
	if handling is String and handling in ["speed", "starfighter"]:
		valid["handling"] = handling
	var slide = raw.get("slide")
	if slide is bool:
		valid["slide"] = slide
	return valid
