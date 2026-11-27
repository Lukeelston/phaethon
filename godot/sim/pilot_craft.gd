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
# The pilot garage's bays (Codex's, garage/garage_environment.gd), in their order: its hall, stands, shutter numbers
# and fleet board were built for these six. The Talon came in after: a Phaethon in another body, it stands in the
# Phaethon's bay, which holds either body (the garage swaps them there: bay_of, has_bay).
const GARAGE_BAYS := [STANDARD, SHRIKE, ORRERY, KILN, VESPER, BASILISK]
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
# The weapon (`weapon`: Raids, 2026-11-24, Luke: "every vehicle should have their own weapon system like the basilisk's
# hidden cannon"): the view's figures alone (view/gunnery.gd and the craft's mount; the sim never reads them, and
# sim-core.js has none), {} for a craft whose weapon is not built yet. Which weapon a craft carries is WEAPONS.
#   rate         shots a second, the barrels taking turns
#   boltV        m/s: a bolt's speed
#   hits         hits a bolt does (missiles: a missile)
#   reach        m: how far the aim is looked for
#   fireS        s of fire on end that overheat it; it is dead till it has cooled `coolS` s
#   assistDeg    how far off its bore (degrees) the fire control may take a target for it (fixed guns)
# The Basilisk's repeats its power's fireS/coolS: its gun is its power.
# Missiles (the Shrike's, view/weapons/missile_mount.gd), look-to-lock:
#   locks        targets a volley may take, one missile each (and the rounds its rack holds)
#   lockS        s a hostile holds under the gaze sight to be locked (the fire control's lock, view/gunnery.gd)
#   missileV     m/s: a missile's own speed; the craft's own along its line is added at its launch, and kept
#   turnDeg      degrees a second a missile turns toward its target's lead, at the most
#   reloadS      s the rack takes to reload after a volley, all of it together
#   lifeS        s a missile flies before it fizzes out
# The lance (the Kiln's, view/weapons/lance_mount.gd), a beam along the gaze:
#   reach        m: how long the beam is, at the most (it stops at the ground or the first hostile on it)
#   coneDeg      degrees off the craft's forward the beam may go; a gaze further off leaves it at that edge
#   dps          hits a second on the hostile the beam is on (whole hits, the remainder carried)
#   fireS        s of burn that overheat it; it is dead till it has cooled `coolS` s
# The pulse (the Vesper's, view/weapons/pulse_mount.gd), a ring released round the craft:
#   radius       m: how far the ring reaches from where it was released (a flyer in the round, a raider over the ground)
#   rechargeS    s from a release before the next may leave
#   gunshipFrac  of the gunship's full HP the ring takes (a drone or a raider it destroys): under 1, so never a fresh one
#   spreadS      s the ring takes to reach its radius
# The orbs (the Orrery's, view/weapons/orb_mount.gd), three that circle the craft and strike:
#   orbs         how many (Codex's arms have three)
#   reach        m from the craft: an orb rested in its orbit takes the nearest threat this near on its own
#   sendReach    m from the craft: the trigger sends every orb in orbit at the hostile under the gaze this near (the
#                fire control's gaze search reaches as far)
#   orbV         m/s: an orb's speed out and back, the craft's own speed added
#   hits         hits a strike does
#   restS        s an orb rests in its orbit after a sortie before it takes a threat on its own again
#   orbitR       m from the craft's up axis the orbs circle at
#   orbitS       s a turn of the orbit takes
const TRAITS := {
	STANDARD: {"power": {"id": "slipstream", "name": "Slipstream", "lcd": "SLIPSTREAM",
		"thrust": 1.15, "last": 4.0, "fill": 6.0, "reach": 120.0, "lane": 22.0},
		"weapon": {"rate": 10.0, "boltV": 1300.0, "hits": 1, "reach": 2600.0, "fireS": 5.0, "coolS": 3.0, "assistDeg": 3.0}},
	"talon": {"gripCapG": 0.93, "engineCd": 0.98, "lift": 0.1,
		"power": {"id": "glide", "name": "Glide", "lcd": "GLIDE", "hang": 1.4, "airGrip": 0.3},
		"weapon": {"rate": 18.0, "boltV": 1400.0, "hits": 1, "reach": 2200.0, "fireS": 4.0, "coolS": 2.5, "assistDeg": 3.0}},
	SHRIKE: {"engineCd": 1.04, "gripCapG": 1.07, "brakes": 1.15,
		"power": {"id": "kickdown", "name": "Kickdown", "lcd": "KICKDOWN",
			"thrust": 1.35, "last": 1.5, "recharge": 12.0, "low": 0.3, "full": 0.85, "within": 0.3},
		"weapon": {"locks": 4, "lockS": 0.35, "missileV": 900.0, "turnDeg": 120.0, "hits": 40, "reach": 3000.0, "reloadS": 5.0, "lifeS": 6.0}},
	ORRERY: {"gripCapG": 1.13, "driftReach": 0.8,
		"power": {"id": "gyro", "name": "Gyro Lock", "lcd": "GYRO LOCK", "grip": 1.2, "last": 4.0, "recharge": 15.0},
		"weapon": {"orbs": 3, "reach": 900.0, "sendReach": 2200.0, "orbV": 700.0, "hits": 3, "restS": 1.2, "orbitR": 4.0, "orbitS": 3.0}},
	KILN: {"thrustMax": 0.95, "brakes": 1.3, "wallShove": 0.75, "driftReach": 0.7,
		"power": {"id": "ram", "name": "Ram Plate", "lcd": "RAM PLATE", "wallShove": 0.5, "last": 5.0, "recharge": 20.0},
		"weapon": {"reach": 600.0, "coneDeg": 25.0, "dps": 30.0, "fireS": 2.5, "coolS": 3.0}},
	VESPER: {"engineCd": 0.88, "gripCapG": 0.9, "driftReach": 1.2,
		"power": {"id": "ground", "name": "Ground Effect", "lcd": "GROUND EFFECT", "drag": 0.85,
			"minV": 894.08, "climb": 0.03, "split": 0.08, "hardSplit": 0.12, "settle": 0.5},
		"weapon": {"radius": 450.0, "rechargeS": 12.0, "gunshipFrac": 0.6, "spreadS": 0.5}},
	BASILISK: {"engineCd": 1.02, "driftReach": 0.85,
		"power": {"id": "turret", "name": "Gaze Turret", "lcd": "GUN", "drag": 1.04, "fireS": 4.0, "coolS": 3.0},
		"weapon": {"fireS": 4.0, "coolS": 3.0}},
}
const TRAIT_DEFAULTS := {"thrustMax": 1.0, "engineCd": 1.0, "gripCapG": 1.0, "brakes": 1.0, "wallShove": 1.0, "lift": 0.0, "driftReach": 1.0}


static func known(id: Variant) -> String:
	return id if id is String and NAMES.has(id) else STANDARD


## A craft's attributes, every one (1 where it has none: TRAIT_DEFAULTS), its power (`power`: {} for none) and its
## weapon's figures (`weapon`: {} for none).
## By its id string as given: a row this file's NAMES does not know yet (the Talon's, before it is merged) is read too.
static func traits(id: Variant) -> Dictionary:
	var out := TRAIT_DEFAULTS.duplicate()
	var row: Dictionary = TRAITS.get(id if id is String and TRAITS.has(id) else known(id), {})
	for k in row:
		out[k] = row[k]
	out["power"] = (out.get("power", {}) as Dictionary).duplicate()   # (a copy: the table is a constant)
	out["weapon"] = (out.get("weapon", {}) as Dictionary).duplicate()
	return out


## ... and its power alone ({} for none).
static func power_of(id: Variant) -> Dictionary:
	return traits(id).power


## Does this airframe carry a weapon (WEAPONS)? Its cockpit then has a GUN switch (vr/vr_cockpit.gd), and X, and the
## flat view's K and F, work its gun. Stage 1 of the Raids: the Phaethon, the Talon and the Basilisk; stage 2: the Shrike,
## the Kiln, the Vesper and the Orrery. Every pilot craft is armed.
static func armed(id: Variant) -> bool:
	return WEAPONS.has(known(id))


## Each craft's weapon, hidden in its hull until its GUN switch is armed (Raids; Luke: "Modelled and hidden - have codex
## work on the art"): its hardware is view/arms/<craft>_arms.gd (the Basilisk's, its turret: view/turret.gd), built with
## its model (view/craft_model.gd `arms`), and its figures are TRAITS[..].weapon.
##   cannons     the Phaethon's: one in the nose of each engine, fixed along the engine's heading
##   wing_guns   the Talon's: one at each wing root, fixed forward; faster and lighter than the Phaethon's
##   turret      the Basilisk's gaze-slaved turret
##   missiles    the Shrike's: four darts on two cassettes that rise over its cheeks (view/arms/shrike_arms.gd), locked by
##               the gaze and fired together (view/weapons/missile_mount.gd); its arms are fitted at the first arming
##               (with Raids on, at load, stowed)
##   lance       the Kiln's: a plasma beam from an emitter that rises out of its starboard foredeck (view/arms/kiln_arms.gd),
##               along the gaze and held on (view/weapons/lance_mount.gd); its arms are fitted as the Shrike's are
##   pulse       the Vesper's: a shock ring released round the craft from a wheel that rises out of its forward starboard
##               sill (view/arms/vesper_arms.gd), on a long recharge (view/weapons/pulse_mount.gd); its arms are fitted as
##               the Kiln's are
##   orbs        the Orrery's: three survey orbs that rise out of cradles in its bonnet (view/arms/orrery_arms.gd), circle
##               the craft, strike the nearest threat on their own and go where the pilot looks on the trigger
##               (view/weapons/orb_mount.gd); its arms are fitted as the Kiln's are
const WEAPONS := {STANDARD: "cannons", TALON: "wing_guns", BASILISK: "turret", SHRIKE: "missiles", KILN: "lance", VESPER: "pulse", ORRERY: "orbs"}


## A craft's weapon (WEAPONS), "" for none.
static func weapon_of(id: Variant) -> String:
	return WEAPONS.get(known(id), "")


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


## The garage bay a craft stands in: its own, or for the Talon (a Phaethon in another body) the Phaethon's; "" for a
## craft with none.
static func bay_of(id: Variant) -> String:
	if id is String and id == TALON:
		return STANDARD
	return id if id is String and GARAGE_BAYS.has(id) else ""


## Has a craft a bay in the garage (bay_of)? Its parked flight is then offered the garage (view/craft_view.gd).
static func has_bay(id: Variant) -> bool:
	return bay_of(id) != ""


## The name a craft goes by on a placard: the garage's aisle sign and its row on the fleet board, both made for the six
## bays' short names (the longest, "03   ORRERY IX", is 1.1 m of a 1.65 m sign; "01   PHAETHON TALON" would be 1.55 m).
## Its own name, or for the Talon, which stands in the Phaethon's bay, "Talon".
const PLACARD_NAMES := {TALON: "Talon"}


static func placard_name(id: Variant) -> String:
	var craft := known(id)
	return PLACARD_NAMES.get(craft, NAMES[craft])


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
