## The craft's paint (Luke: "What about color settings for the vehicle?", and "a police variant of
## the vehicle"). A livery names the colours a craft is built in:
##   paint    the pod's top decks, nose and fin, and the piping on the cockpit's lip (clear-coated)
##   stripe   the racing stripe along the pod's flanks
##   pin      the pinstripes where the paint meets the metal
##   engine   the band, ring and fin tips on each engine, a fan blade, the binder's ring
##   skin     the polished metal under it all
##   accent   what the authored fittings' orange turns to: the coaming's enamel, the stitching, the
##            grips' anodised bands, the engines' armour plates (view/accent.gd); none for Ember,
##            whose fittings are drawn exactly as they were made
## "ember" is the craft as it always was. A craft's colours are in its meshes' vertices, so the
## livery is chosen before the craft is built (CraftView reads the menus' choice) and each has its
## own hull (CraftModel.pod_hull()).
##   Livery.current = "cobalt"            before a craft is built (and `pinned`, so a saved choice is left alone)
##   Livery.coat("paint")                 the colour of a part in the current livery
extends RefCounted

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
	# the patrol's black and white (not on the paint row: it comes with the patrol craft)
	"police": {"name": "Patrol black and white", "paint": Color(0.93, 0.93, 0.92), "stripe": Color(0.035, 0.035, 0.04), "pin": Color(0.05, 0.22, 0.78),
		"engine": Color(0.93, 0.93, 0.92), "skin": Color(0.05, 0.05, 0.06), "accent": Color(0.06, 0.24, 0.80)},
	# the box cover's navy, white and orange-red (not on the paint row: the title's craft wears it, release/title_stage.gd)
	"boxcover": {"name": "Box-cover navy", "paint": Color(0.045, 0.085, 0.30), "stripe": Color(0.86, 0.21, 0.07), "pin": Color(0.96, 0.93, 0.84),
		"engine": Color(0.88, 0.23, 0.07), "skin": Color(0.80, 0.82, 0.86), "accent": Color(0.06, 0.13, 0.46)},
}
const CHOICES := [["ember", "Ember orange"], ["cobalt", "Cobalt blue"], ["viridian", "Racing green"], ["crimson", "Crimson"],
	["sunflower", "Sunflower yellow"], ["violet", "Violet"], ["bone", "Bone white"], ["obsidian", "Obsidian black"]]   # the menus' paint row: [id, name]

static var current := "ember"     # the livery crafts are built in
static var pinned := false        # a test or a render chose it: the saved choice does not replace it


static func ids() -> Array:
	return CHOICES.map(func(entry): return entry[0])


## The colour of a part ("paint", "stripe", "pin", "engine", "skin") in a livery (the current one by default).
static func coat(part: String, which := "") -> Color:
	return TABLE[which if TABLE.has(which) else current][part]


## The colour the authored fittings' orange takes, or null to leave them as they were made.
static func accent(which := ""):
	return TABLE[which if TABLE.has(which) else current].get("accent")
