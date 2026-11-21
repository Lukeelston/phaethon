## Player airframes. Handling modes remain independently switchable on either craft.
extends RefCounted

const STANDARD := "phaethon"
const SHRIKE := "shrike"
const SHR_TUNING := {"engineMass": 1000.0, "podMass": 410.0, "engineGap": 7.2, "cableLen": 12.5}


static func known(id: Variant) -> String:
	return SHRIKE if id is String and id == SHRIKE else STANDARD


static func tuning(id: String) -> Dictionary:
	return SHR_TUNING.duplicate() if id == SHRIKE else {}


## The short, wide craft needs less yaw damping to follow a corner on the GP.
## Keep the high-speed setting for the Sprint and blend normally on a mode change.
static func starfighter_profile(id: String, base: Dictionary) -> Dictionary:
	return base.merged({"yawDamp": 68000.0}, true) if id == SHRIKE else base


static func resolve(args: PackedStringArray, menu_choice: String) -> String:
	for arg in args:
		if arg.begins_with("--vehicle="):
			return known(arg.trim_prefix("--vehicle="))
	return known(menu_choice)
