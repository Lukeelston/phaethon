## Player airframes, in selector order. Both handling modes are available to every pilot.
extends RefCounted

const STANDARD := "phaethon"
const SHRIKE := "shrike"
const ORRERY := "orrery"
const KILN := "kiln"
const VESPER := "vesper"
const BASILISK := "basilisk"   # the gunship: a turret slaved to the pilot's gaze (view/turret.gd, view/gunnery.gd)
const ORDER := [STANDARD, SHRIKE, ORRERY, KILN, VESPER, BASILISK]
const NAMES := {STANDARD: "Phaethon", SHRIKE: "Shrike RS", ORRERY: "Orrery IX", KILN: "Kiln Six", VESPER: "Vesper", BASILISK: "Basilisk"}
const DETAILS := {
	STANDARD: "Original twin-engine chassis  ·  16 m tow",
	SHRIKE: "Lightweight sprint chassis  ·  12.5 m tow",
	ORRERY: "Annular induction surveyor  ·  17 m tow",
	KILN: "Six-bank recovery tractor  ·  15 m tow",
	VESPER: "Split-inlet racing hydrofoil  ·  13.5 m tow",
	BASILISK: "Gaze-slaved gunship  ·  14.5 m tow",
}
const SHR_TUNING := {"engineMass": 1000.0, "podMass": 410.0, "engineGap": 7.2, "cableLen": 12.5}
const TUNING := {
	STANDARD: {}, SHRIKE: SHR_TUNING,
	ORRERY: {"engineMass": 1140.0, "podMass": 475.0, "engineGap": 7.6, "cableLen": 17.0},
	KILN: {"engineMass": 1300.0, "podMass": 540.0, "engineGap": 6.8, "cableLen": 15.0},
	VESPER: {"engineMass": 960.0, "podMass": 410.0, "engineGap": 7.8, "cableLen": 13.5},
	BASILISK: {"engineMass": 1240.0, "podMass": 560.0, "engineGap": 7.2, "cableLen": 14.5},
}


# Each craft's attributes and power (Luke, 2026-11-24: "build the attributes and powers into the game": the fleet
# sheet's ratings and powers, made real). One row a craft, keyed by its id string (the Talon's "talon" too: its row
# applies once that craft is known here). Mirrors sim-core.js PILOT_TRAITS: change one, change both.
# The attributes are always on: multipliers on whatever the handling mode sets (SPEEDCRAFT and STARFIGHTER alike),
# 1 where a craft has none. The Phaethon has none, so it flies, and every replay plays, exactly as before.
#   thrustMax    the engines' thrust
#   engineCd     the craft's cruise drag: the engines' and the pod's (the sheet's top speeds are the whole craft's:
#                x0.88 is +6.6%, the square root of 1 / 0.88); the brakes' drag is not in it
#   gripCapG     the engines' grip limit
#   brakes       the air brakes, all of them: brakeCd, the linear and constant terms, and the front flaps (their g
#                cap with them), on the engines and the pod
#   wallShove    a wall's spring, the shove that throws a craft back off it (its damper, which soaks a hit up, is
#                kept): less of it, and a craft that meets a wall leans on it and comes off slower
#   lift         g of lift in the air: none on the ground; it comes in as the repulsors' grip goes, 0.5 to 2 m up
#   driftReach   how far the cockpit steps out in a slide (vr_cockpit.gd _ease_slide). The view's: the slide is
#                the cockpit's, and the sim never reads this
# The power (one a craft): its name, the LCD's word for it, and its own figures (craft_sim.gd _power_step):
#   slipstream   inp.draft (the view: a traffic vehicle within `reach` m ahead, in the craft's lane, its own way)
#                fills the gauge in `fill` s of drafting (it keeps what it has); fired full: `last` s of thrust x`thrust`
#   glide        while armed and in the air: hang time x`hang` (lift against gravity, on top of the craft's own
#                `lift`), and grip of at least `airGrip` in the air, so the levers steer it. Every jump
#   kickdown     both levers from under `low` to `full` (0.85: the trigger throttles' top is 0.87) inside `within`
#                s: `last` s of thrust x`thrust`, automatic when armed; `recharge` s after it ends
#   gyro         fired: `last` s of the grip limit x`grip`; `recharge` s after it ends
#   ram          fired: `last` s in which traffic is shoved aside (the vehicle gives way, shoved by the view: its
#                field does not push the craft, and a closing speed that would smash is a bump; a pillar is still a
#                pillar), and the walls' shove x`wallShove`
#   ground       automatic when armed: faster than `minV` m/s (2,000 mph), every body on the ground, the climb under
#                `climb` of the speed, the levers' split (thrust and brakes, either way) under `split` for `settle`
#                s: the cruise drag x`drag`, until the split passes `hardSplit` (turning hard) or the rest fails
#   turret       the Basilisk's gun (view/gunnery.gd; the GUN switch and X: the POWER switch and button do nothing):
#                out, the cruise drag x`drag`; `fireS` s of fire on end overheats it, and it is dead till `coolS` s cool
const TRAITS := {
	STANDARD: {"power": {"id": "slipstream", "name": "Slipstream", "lcd": "SLIPSTREAM",
		"thrust": 1.15, "last": 4.0, "fill": 6.0, "reach": 120.0, "lane": 22.0}},
	"talon": {"gripCapG": 0.93, "engineCd": 0.98, "lift": 0.1,
		"power": {"id": "glide", "name": "Glide", "lcd": "GLIDE", "hang": 1.4, "airGrip": 0.3}},
	SHRIKE: {"engineCd": 1.04, "gripCapG": 1.07, "brakes": 1.15,
		"power": {"id": "kickdown", "name": "Kickdown", "lcd": "KICKDOWN",
			"thrust": 1.35, "last": 1.5, "recharge": 12.0, "low": 0.3, "full": 0.85, "within": 0.3}},
	ORRERY: {"gripCapG": 1.13, "driftReach": 0.8,
		"power": {"id": "gyro", "name": "Gyro Lock", "lcd": "GYRO LOCK", "grip": 1.2, "last": 4.0, "recharge": 15.0}},
	KILN: {"thrustMax": 0.95, "brakes": 1.3, "wallShove": 0.75, "driftReach": 0.7,
		"power": {"id": "ram", "name": "Ram Plate", "lcd": "RAM PLATE", "wallShove": 0.5, "last": 5.0, "recharge": 20.0}},
	VESPER: {"engineCd": 0.88, "gripCapG": 0.9, "driftReach": 1.2,
		"power": {"id": "ground", "name": "Ground Effect", "lcd": "GROUND EFFECT", "drag": 0.85,
			"minV": 894.08, "climb": 0.03, "split": 0.08, "hardSplit": 0.12, "settle": 0.5}},
	BASILISK: {"engineCd": 1.02, "driftReach": 0.85,
		"power": {"id": "turret", "name": "Gaze Turret", "lcd": "GUN", "drag": 1.04, "fireS": 4.0, "coolS": 3.0}},
}
const TRAIT_DEFAULTS := {"thrustMax": 1.0, "engineCd": 1.0, "gripCapG": 1.0, "brakes": 1.0, "wallShove": 1.0, "lift": 0.0, "driftReach": 1.0}


static func known(id: Variant) -> String:
	return id if id is String and NAMES.has(id) else STANDARD


## A craft's attributes, every one (1 where it has none: TRAIT_DEFAULTS), and its power (`power`: {} for none).
## By its id string as given: a row this file's NAMES does not know yet (the Talon's, before it is merged) is read too.
static func traits(id: Variant) -> Dictionary:
	var out := TRAIT_DEFAULTS.duplicate()
	var row: Dictionary = TRAITS.get(id if id is String and TRAITS.has(id) else known(id), {})
	for k in row:
		out[k] = row[k]
	out["power"] = (out.get("power", {}) as Dictionary).duplicate()   # (a copy: the table is a constant)
	return out


## ... and its power alone ({} for none).
static func power_of(id: Variant) -> Dictionary:
	return traits(id).power


## Does this airframe carry a gun (the Basilisk's turret)?
static func armed(id: Variant) -> bool:
	return known(id) == BASILISK


## The airframe a craft was drawn from, where it has no part of its own. The Basilisk came in (2026-11-23) after
## Codex's fleet sound banks and the fleet flight decks, and has neither: its cab is the Kiln's (the same sills, seat
## and shell in tools/art_pilot_fleet.py), so it takes the Kiln's instrument deck (in its own finishes,
## vr/fleet_flight_deck.gd) and the Kiln's engine and start-up bank, voiced by its own FLEET_VOICES balance.
const DRAWN_FROM := {BASILISK: KILN}


static func drawn_from(id: Variant) -> String:
	var craft := known(id)
	return DRAWN_FROM.get(craft, craft)


## Whose recorded engine and start-up bank (res://audio/fleet/<id>/) an airframe plays.
static func sound_bank(id: Variant) -> String:
	return drawn_from(id)


## Whose fleet flight deck (dial stations, fittings, auxiliary meter) an airframe's cockpit is built with.
static func deck_of(id: Variant) -> String:
	return drawn_from(id)


static func tuning(id: String) -> Dictionary:
	return TUNING[known(id)].duplicate()


static func next(id: String) -> String:
	return ORDER[(ORDER.find(known(id)) + 1) % ORDER.size()]


static func starfighter_profile(id: String, base: Dictionary) -> Dictionary:
	if id == SHRIKE or id == VESPER:
		return base.merged({"yawDamp": 68000.0 if id == SHRIKE else 71000.0}, true)
	return base


static func resolve(args: PackedStringArray, menu_choice: String) -> String:
	for arg in args:
		if arg.begins_with("--vehicle="):
			return known(arg.trim_prefix("--vehicle="))
	return known(menu_choice)
