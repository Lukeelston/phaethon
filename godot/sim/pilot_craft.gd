## Player airframes, in selector order. Both handling modes are available to every pilot.
extends RefCounted

const STANDARD := "phaethon"
const TALON := "talon"         # the Phaethon in Codex's swept twin-tail starfighter body (view/talon_airframe.gd): a Phaethon underneath
const SHRIKE := "shrike"
const ORRERY := "orrery"
const KILN := "kiln"
const VESPER := "vesper"
const BASILISK := "basilisk"   # the gunship: a turret slaved to the pilot's gaze (view/turret.gd, view/gunnery.gd)
const ORDER := [STANDARD, TALON, SHRIKE, ORRERY, KILN, VESPER, BASILISK]
const NAMES := {STANDARD: "Phaethon", TALON: "Phaethon Talon", SHRIKE: "Shrike RS", ORRERY: "Orrery IX", KILN: "Kiln Six", VESPER: "Vesper", BASILISK: "Basilisk"}
const DETAILS := {
	STANDARD: "Original twin-engine chassis  ·  16 m tow",
	TALON: "Swept twin-tail starfighter body  ·  16 m tow",
	SHRIKE: "Lightweight sprint chassis  ·  12.5 m tow",
	ORRERY: "Annular induction surveyor  ·  17 m tow",
	KILN: "Six-bank recovery tractor  ·  15 m tow",
	VESPER: "Split-inlet racing hydrofoil  ·  13.5 m tow",
	BASILISK: "Gaze-slaved gunship  ·  14.5 m tow",
}
const SHR_TUNING := {"engineMass": 1000.0, "podMass": 410.0, "engineGap": 7.2, "cableLen": 12.5}
const TUNING := {
	STANDARD: {}, TALON: {}, SHRIKE: SHR_TUNING,
	ORRERY: {"engineMass": 1140.0, "podMass": 475.0, "engineGap": 7.6, "cableLen": 17.0},
	KILN: {"engineMass": 1300.0, "podMass": 540.0, "engineGap": 6.8, "cableLen": 15.0},
	VESPER: {"engineMass": 960.0, "podMass": 410.0, "engineGap": 7.8, "cableLen": 13.5},
	BASILISK: {"engineMass": 1240.0, "podMass": 560.0, "engineGap": 7.2, "cableLen": 14.5},
}


static func known(id: Variant) -> String:
	return id if id is String and NAMES.has(id) else STANDARD


## Does this airframe carry a gun (the Basilisk's turret)?
static func armed(id: Variant) -> bool:
	return known(id) == BASILISK


## The airframe a craft was drawn from, where it has no part of its own. The Basilisk came in (2026-11-23) after
## Codex's fleet sound banks and the fleet flight decks, and has neither: its cab is the Kiln's (the same sills, seat
## and shell in tools/art_pilot_fleet.py), so it takes the Kiln's instrument deck (in its own finishes,
## vr/fleet_flight_deck.gd) and the Kiln's engine and start-up bank, voiced by its own FLEET_VOICES balance.
## The Talon (2026-11-24: Codex's starfighter reshape of the Phaethon, e2675a1, which Luke chose to "Add as its
## own craft") is a Phaethon in another body: the Phaethon's tuning, engines, cockpit, sounds, links and hardpoints.
const DRAWN_FROM := {BASILISK: KILN, TALON: STANDARD}


static func drawn_from(id: Variant) -> String:
	var craft := known(id)
	return DRAWN_FROM.get(craft, craft)


## Whose recorded engine and start-up bank an airframe plays: res://audio/fleet/<id>/, or for STANDARD the
## Phaethon's own (res://audio/engines/, res://audio/startup/).
static func sound_bank(id: Variant) -> String:
	return drawn_from(id)


## Is this airframe a Phaethon underneath (the Phaethon itself, or the Talon)? Where the game asks for the
## standard craft's own parts (its sounds, its cockpit), it asks this, not whether the craft is STANDARD.
static func phaethon_based(id: Variant) -> bool:
	return drawn_from(id) == STANDARD


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
