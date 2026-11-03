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
