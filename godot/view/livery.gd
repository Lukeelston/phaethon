## The craft's paint (Luke: "What about color settings for the vehicle?", and "a police variant of
## the vehicle"; then "Will you make it so that all vehicles can have a color option?"). A livery names
## the colours a craft is built in:
##   paint    the pod's top decks, nose and fin, and the piping on the cockpit's lip (clear-coated)
##   stripe   the racing stripe along the pod's flanks
##   pin      the pinstripes where the paint meets the metal
##   engine   the band, ring and fin tips on each engine, a fan blade, the binder's ring
##   skin     the polished metal under it all
##   accent   what the authored fittings' orange turns to: the coaming's enamel, the stitching, the
##            grips' anodised bands, the engines' armour plates (view/accent.gd); none for Ember,
##            whose fittings are drawn exactly as they were made
## "ember" is the Phaethon as it always was. A craft's colours are in its meshes' vertices, so the
## livery is chosen before the craft is built (CraftView reads the menus' choice) and each has its
## own hull (CraftModel.pod_hull()).
## Every pilot craft takes a paint, and each keeps its own choice (saved under key_for(craft); the
## Phaethon's is the "paint" it always had). The first on the row is "factory": each craft as it was
## designed. The Phaethon's factory paint is Ember orange, so its row has no second Ember. The others
## wear a livery over their painted atlases (view/fleet_airframe.gd, view/shrike_airframe.gd): its paint
## on their enamel, its accent on their accent, its pin on their trim lines, and nothing else touched.
## One livery is a craft's own: the Vesper's Star Command (Codex's), a white, green and red racing atlas of
## its own (art/pilot_fleet/vesper_star_command.webp) worn instead of a repaint. It is on the Vesper's row only,
## after Factory, and saved as its paint like any other.
##   Livery.current = "cobalt"            before a craft is built (and `pinned`, so a saved choice is left alone)
##   Livery.coat("paint")                 the colour of a part in the current livery (Factory's: Ember's)
##   Livery.built(vehicle)                the livery the menus' choice builds that craft in
extends RefCounted

const Settings := preload("res://release/game_settings.gd")
const Pilot := preload("res://sim/pilot_craft.gd")

const FACTORY := "factory"      # each craft as it was designed (the Phaethon: Ember orange)
const STAR_COMMAND := "star_command"      # the Vesper's own racing livery (view/fleet_airframe.gd wears its atlas)
const OWN := {Pilot.VESPER: [[STAR_COMMAND, "Star Command"]]}      # a craft's own liveries: on its row after Factory
const TABLE := {
	"ember": {"name": "Ember orange", "paint": Color(0.95, 0.42, 0.08), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.96, 0.95, 0.9),
		"engine": Color(0.86, 0.27, 0.09), "skin": Color(0.80, 0.82, 0.86)},
	"cobalt": {"name": "Cobalt blue", "paint": Color(0.04, 0.20, 0.70), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.96, 0.95, 0.9),
		"engine": Color(0.05, 0.24, 0.74), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.07, 0.30, 0.86)},
	"viridian": {"name": "Racing green", "paint": Color(0.02, 0.27, 0.14), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.86, 0.72, 0.36),
		"engine": Color(0.03, 0.32, 0.17), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.04, 0.42, 0.22)},
	"crimson": {"name": "Crimson", "paint": Color(0.68, 0.03, 0.05), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.96, 0.95, 0.9),
		"engine": Color(0.64, 0.04, 0.05), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.76, 0.05, 0.07)},
	"sunflower": {"name": "Sunflower yellow", "paint": Color(0.96, 0.72, 0.04), "stripe": Color(0.06, 0.06, 0.07), "pin": Color(0.06, 0.06, 0.07),
		"engine": Color(0.92, 0.66, 0.04), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.93, 0.68, 0.05)},
	"violet": {"name": "Violet", "paint": Color(0.34, 0.08, 0.60), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.85, 0.86, 0.90),
		"engine": Color(0.36, 0.10, 0.62), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.47, 0.16, 0.82)},
	"bone": {"name": "Bone white", "paint": Color(0.90, 0.88, 0.82), "stripe": Color(0.11, 0.12, 0.14), "pin": Color(0.70, 0.09, 0.06),
		"engine": Color(0.88, 0.86, 0.80), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.84, 0.81, 0.73)},
	"obsidian": {"name": "Obsidian black", "paint": Color(0.035, 0.035, 0.04), "stripe": Color(0.20, 0.21, 0.23), "pin": Color(0.90, 0.30, 0.06),
		"engine": Color(0.05, 0.05, 0.06), "skin": Color(0.34, 0.35, 0.38), "accent": Color(0.10, 0.10, 0.11)},
	# the Vesper's own (on its row only: OWN); its colours are its atlas's, for what is drawn in a livery's colours
	STAR_COMMAND: {"name": "Star Command", "paint": Color("#f4f4eb"), "stripe": Color("#95e139"), "pin": Color("#d33948"),
		"engine": Color("#95e139"), "skin": Color("#f4f4eb"), "accent": Color("#7238bd")},
	# the patrol's black and white (not on the paint row: it comes with the patrol craft)
	"police": {"name": "Patrol black and white", "paint": Color(0.93, 0.93, 0.92), "stripe": Color(0.035, 0.035, 0.04), "pin": Color(0.05, 0.22, 0.78),
		"engine": Color(0.93, 0.93, 0.92), "skin": Color(0.05, 0.05, 0.06), "accent": Color(0.06, 0.24, 0.80)},
	# the box cover's navy, white and orange-red (not on the paint row: the title's craft wears it, release/title_stage.gd)
	"boxcover": {"name": "Box-cover navy", "paint": Color(0.045, 0.085, 0.30), "stripe": Color(0.86, 0.21, 0.07), "pin": Color(0.96, 0.93, 0.84),
		"engine": Color(0.88, 0.23, 0.07), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.06, 0.13, 0.46)},
}
const CHOICES := [["factory", "Factory"], ["ember", "Ember orange"], ["cobalt", "Cobalt blue"], ["viridian", "Racing green"], ["crimson", "Crimson"],
	["sunflower", "Sunflower yellow"], ["violet", "Violet"], ["bone", "Bone white"], ["obsidian", "Obsidian black"]]   # the menus' paint row: [id, name]

static var current := FACTORY   # the livery crafts are built in
static var pinned := false      # a test or a render chose it: the saved choice does not replace it


static func ids() -> Array:
	return CHOICES.map(func(entry): return entry[0])


## The paint row for a pilot craft: [id, name], Factory first. The Phaethon's Factory is Ember orange, so
## Ember is not on its row twice. A craft's own liveries (OWN: the Vesper's Star Command) come next.
static func choices_for(vehicle: String) -> Array:
	var craft := Pilot.known(vehicle)
	if craft == Pilot.STANDARD:
		return CHOICES.filter(func(entry): return entry[0] != "ember")
	if OWN.has(craft):
		return CHOICES.slice(0, 1) + OWN[craft] + CHOICES.slice(1)
	return CHOICES


static func ids_for(vehicle: String) -> Array:
	return choices_for(vehicle).map(func(entry): return entry[0])


## Where a craft's paint is saved (release/game_settings.gd's "flight" section): the Phaethon's is the
## "paint" it always had (a choice saved before every craft had one is its), each other craft its own.
static func key_for(vehicle: String) -> String:
	var craft := Pilot.known(vehicle)
	return "paint" if craft == Pilot.STANDARD else "paint_" + craft


## The paint the menus have chosen for a craft (Factory until one is chosen).
static func saved_for(vehicle: String) -> String:
	return Settings.choice(key_for(vehicle), ids_for(vehicle))


## The livery a craft is built in for a choice from its row: the Phaethon's Factory is Ember.
static func for_craft(vehicle: String, choice: String) -> String:
	return "ember" if choice == FACTORY and Pilot.known(vehicle) == Pilot.STANDARD else choice


## ... and for the menus' saved choice.
static func built(vehicle: String) -> String:
	return for_craft(vehicle, saved_for(vehicle))


static func known(which: String) -> bool:
	return which == FACTORY or TABLE.has(which)


## Is a livery (the current one by default) a craft's factory finish?
static func is_factory(which := "") -> bool:
	return (which if known(which) else current) == FACTORY


## The table entry a livery's colours come from: Factory's are Ember's (the parts every craft shares, such
## as the binder's ring, are drawn as they were).
static func table_id(which := "") -> String:
	var id: String = which if known(which) else current
	return id if TABLE.has(id) else "ember"
## Build one synchronous piece in its owner's paint. Restore the previous colour
## before returning so multiple displayed craft and frame-sliced cabins can coexist.
static func build_in(which: String, build_piece: Callable) -> Variant:
	var previous := current
	current = which
	var piece: Variant = build_piece.call()
	current = previous
	return piece


## The colour of a part ("paint", "stripe", "pin", "engine", "skin") in a livery (the current one by default).
static func coat(part: String, which := "") -> Color:
	return TABLE[table_id(which)][part]


## The colour the authored fittings' orange takes, or null to leave them as they were made.
static func accent(which := ""):
	return TABLE[table_id(which)].get("accent")
