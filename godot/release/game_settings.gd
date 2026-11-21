## Shared desktop/VR flight preference. Each export uses its own user-data folder.
extends RefCounted

const PREFS := "user://game_settings.cfg"

static func driving_partner_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(PREFS) != OK:
		return false
	var saved = config.get_value("flight", "driving_partner", false)
	return saved if saved is bool else false

static func set_driving_partner(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(PREFS)
	config.set_value("flight", "driving_partner", enabled)
	var error := config.save(PREFS)
	if error != OK:
		push_warning("Could not save driving partner preference: %s" % error_string(error))

## Launch flags override this flight; only a menu choice changes the saved preference.
static func resolve_driving_partner(args: PackedStringArray) -> bool:
	if "--no-partner" in args:
		return false
	return "--partner" in args or driving_partner_enabled()

static func obstacle_collisions_enabled() -> bool:
	var config := ConfigFile.new()
	if config.load(PREFS) != OK:
		return false # preserve the release's existing pass-through traffic
	var saved = config.get_value("flight", "obstacle_collisions", false)
	return saved if saved is bool else false

static func set_obstacle_collisions(enabled: bool) -> void:
	var config := ConfigFile.new()
	config.load(PREFS)
	config.set_value("flight", "obstacle_collisions", enabled)
	var error := config.save(PREFS)
	if error != OK:
		push_warning("Could not save obstacle collision preference: %s" % error_string(error))


## A named choice from one of the menus' option rows ("flight" section, like the two switches above):
## where a Network flight begins, the time of day, the weather, the craft's paint. `allowed` guards
## against a stale or hand-edited value; the first entry is the default.
static func choice(key: String, allowed: Array) -> String:
	var config := ConfigFile.new()
	if config.load(PREFS) != OK:
		return allowed[0]
	var saved = config.get_value("flight", key, allowed[0])
	return saved if saved is String and allowed.has(saved) else allowed[0]

static func set_choice(key: String, value: String) -> void:
	var config := ConfigFile.new()
	config.load(PREFS)
	config.set_value("flight", key, value)
	var error := config.save(PREFS)
	if error != OK:
		push_warning("Could not save the %s preference: %s" % [key, error_string(error)])
