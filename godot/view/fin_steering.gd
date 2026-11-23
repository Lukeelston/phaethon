## How the engines' fins answer a turn (Luke: "The engine fins should rotate left/right as well as up/down
## with turning"), and the Phaethon's two moving surfaces. Looks only: the sim is not touched, and nothing
## here runs in its steps. view/craft_model.gd reads the turn once a frame and poses the parts.
##
## What they answer. Two things the model already has each frame, as one number in g toward the right:
##   the turn's own load   the engines' cornering load, smoothed (craft_model's _lat: what the lean and the
##                         jets' vanes use). It is the turn itself, however it came about, and it is what
##                         the pilot's flying shows up in: his lever split is a few hundredths (median 0.03,
##                         nine tenths under 0.17) while the load that split brings is 4 to 21 g.
##   the levers' split     at once, ahead of the load, as a control surface goes before the craft answers:
##                         SPLIT_G of it for each unit of split (what a split brings at speed, measured:
##                         tests/probe_slide.gd), less SPLIT_SLACK either way so that a parked craft's
##                         idling engines and a resting hand's tremor move nothing. Standing still it is
##                         all there is: squeeze a grip on the pad and the fins go over.
## LEAD of the first and the rest of the second: in a steady turn the two agree, so the fins hold what the
## turn's load alone would give. That is eased (TAU), turned into a share of full travel (TURN_G: his median
## turn a fifth of it, his hardest tenth nine tenths), and each surface goes to its share of its own travel
## no faster than its actuator strokes. Yaw rate was the other thing on offer. It is the load over the speed,
## so the same squeeze of a grip would move the fins less the faster he flew, and his hands bring the same
## load at any speed; and up a shaft the road's own bend turns the craft with no turn made (the load has
## that taken out of it already).
##
## What moves:
##   the Shrike     view/shrike_airframe.gd: each fin's outer panel swings on its spindle; the ram lays the
##                  inside engine's fin out and stands the outside engine's up.
##   the Phaethon   its fins were part of the engine's one fixed mesh. Now, on each engine:
##     the rudder       the dorsal fin's aft two thirds, on a post through its nose: stepped in a collar on
##                      the deck (the rotary actuator that turns it) and held at its head by a bearing block
##                      on the fixed strake ahead of it. Trailing edge into the turn.
##     the stabiliser   the outboard fin's outer four fifths, all-moving on a spindle from the fixed root
##                      glove (the boss on the glove is its actuator) out to the nav lamp at its tip:
##                      the lamp is on the spindle's own line, so it stays where it is. The inside engine's
##                      goes trailing edge up and the outside engine's down, as ailerons do.
##   The split-off parts leave the engine's fixed mesh (craft_model._engine_body(out, false)); the racers',
##   the partner's and the patrol's engines are that mesh with its fins whole and fixed, as they were.
##   Both engines' rudders are one mesh drawn as one batch, and both stabiliser panels another (the port
##   engine's panel is the starboard's turned half round: it is the same top and bottom), so the two pairs
##   are two things to draw: craft_model.fin_batches, put where the engines are each frame.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Fairings := preload("res://view/craft_fairings.gd")

# --- what the fins answer
const SPLIT_G := 120.0                 # g of cornering a unit of lever split brings at speed (0.03: 4 g, 0.17: 21 g, 0.40: 53 g)
const SPLIT_SLACK := 0.02              # split that asks nothing
const ASK_MAX := 40.0                  # g: the most the levers alone ask
const LEAD := 0.5                      # the levers' share of what the fins answer; the rest is the turn's own load
const TAU := 0.12                      # s: the answer is eased
const TURN_G := 13.0                   # g that brings 76 % of full travel
# --- how far and how fast (the Shrike's own are view/shrike_airframe.gd's PANEL_* and FIN_LEAN)
const SWING_MAX := deg_to_rad(20.0)    # the rudders, either way
const SWING_SLEW := deg_to_rad(60.0)   # ... a second
const PITCH_MAX := deg_to_rad(14.0)    # the Phaethon's stabilisers, either way
const PITCH_SLEW := deg_to_rad(45.0)
# --- the Phaethon's surfaces, engine-local metres (forward is -Z, the deck at `deck`)
const RUDDER_Z := 0.45                 # the rudder's post
const RUDDER_LIFT := 0.03              # its foot clears the deck (and the band round the engine there) by this
const POST := 0.045                    # the post's radius: a little thicker than the fin
const FIN_THICK := 0.07
const STAB_Y := -0.1                   # the stabiliser's plane
const STAB_THICK := 0.065
const GLOVE := 0.22                    # the fixed root glove's span: clear of the pipes and covers on the flank
const STAB_FROM := 0.235               # where the moving panel begins, from the flank
const STAB_AXIS_Z := 0.5               # the spindle's station there ...
const LAMP := Vector2(1.02, 1.1)       # ... and it runs out to the nav lamp at the tip: (from the flank, station)
const BOSS := 0.046                    # the spindle's bosses: proud of the stabiliser's faces


## What the fins answer, g toward the right: the levers' split and the turn's own load.
static func ask(split: float, turn_g: float) -> float:
	var lever := clampf(signf(split) * maxf(absf(split) - SPLIT_SLACK, 0.0) * SPLIT_G, -ASK_MAX, ASK_MAX)
	return LEAD * lever + (1.0 - LEAD) * turn_g


## That, eased over a frame (and let go of altogether once it has died away).
static func ease(now: float, want: float, dt: float) -> float:
	var next := lerpf(now, want, 1.0 - exp(-dt / TAU))
	return 0.0 if want == 0.0 and absf(next) < 1e-4 else next


## The share of its travel each surface goes to: -1 .. 1, + = a right turn.
static func share(drive: float) -> float:
	return tanh(drive / TURN_G)


## The dorsal fin's leading edge: how high it stands over the deck at a station.
static func _fin_rise(z: float) -> float:
	return 0.64 * (z + 0.65) / 1.6


## The Phaethon's rudder about the foot of its post (y up, z aft): the fin's aft part, its painted tip,
## and the post through its nose. One mesh for both engines.
static func rudder_mesh(steel: Color, paint: Color, dark: Color) -> ArrayMesh:
	var top := _fin_rise(RUDDER_Z)
	var heel := 1.15 + 0.3 * RUDDER_LIFT / 0.59 - RUDDER_Z      # where the lifted foot meets the trailing edge
	return Kit.compound([
		[Fairings.fin(PackedVector2Array([Vector2(RUDDER_LIFT, 0.0), Vector2(top, 0.0), Vector2(0.64, 0.95 - RUDDER_Z), Vector2(0.59, 1.45 - RUDDER_Z), Vector2(RUDDER_LIFT, heel)]), FIN_THICK), Transform3D.IDENTITY, steel],
		[Fairings.fin(PackedVector2Array([Vector2(0.49, 0.65 - RUDDER_Z), Vector2(0.64, 0.95 - RUDDER_Z), Vector2(0.59, 1.45 - RUDDER_Z), Vector2(0.49, 1.35 - RUDDER_Z)]), FIN_THICK + 0.005), Transform3D.IDENTITY, paint],
		[Kit.cyl(POST, POST, top + 0.04, 14), Kit.at(Vector3(0.0, (top + 0.04) / 2.0 - 0.015, 0.0)), dark.lightened(0.38)],
	])


## What the rudder stands on, fixed to the engine: the strake ahead of it (the fin's fore part, as it
## was), the bearing block at its head that holds the post's top, and the actuator's collar on the deck.
## Parts for craft_model._engine_body's compound.
static func rudder_fittings(deck: float, steel: Color, dark: Color, bright: Color) -> Array:
	var cut := RUDDER_Z - POST + 0.012      # the strake runs into the post's fore side
	var top := _fin_rise(RUDDER_Z)
	return [
		[Fairings.fin(PackedVector2Array([Vector2(0.0, -0.65), Vector2(_fin_rise(cut), cut), Vector2(0.0, cut)]), FIN_THICK), Kit.at(Vector3(0.0, deck, 0.0)), steel],
		[Kit.rounded_box(Vector3(0.085, 0.085, 0.11), 5.0, 8), Kit.at(Vector3(0.0, deck + top - 0.025, RUDDER_Z - POST - 0.035)), dark.lightened(0.25)],
		[Kit.cyl(POST + 0.016, POST + 0.016, 0.03, 16), Kit.at(Vector3(0.0, deck + top + 0.02, RUDDER_Z)), dark.lightened(0.25)],
		[Kit.cyl(POST + 0.045, POST + 0.06, RUDDER_LIFT - 0.006, 20), Kit.at(Vector3(0.0, deck + (RUDDER_LIFT - 0.006) / 2.0, RUDDER_Z)), dark.lightened(0.25)],
		[Kit.cyl(POST + 0.022, POST + 0.022, 0.008, 20), Kit.at(Vector3(0.0, deck + RUDDER_LIFT - 0.008, RUDDER_Z)), bright],
	]


## The stabiliser's edges at `h` m out from the flank: Vector2(leading, trailing) stations.
static func _stab_edges(h: float) -> Vector2:
	return Vector2(-0.3 + 1.25 * h / 1.05, 1.05 + 0.33 * h / 0.99)


## The spindle's line in the panel's own frame (x out from the flank, z aft): from its foot toward the lamp.
static func stab_axis() -> Vector3:
	return Vector3(LAMP.x - STAB_FROM, 0.0, LAMP.y - STAB_AXIS_Z).normalized()


## The Phaethon's stabiliser panel about the foot of its spindle (x out from the flank, y up, z aft), and
## the boss that rides the spindle. The same top and bottom, so one mesh serves both engines: the port
## engine's is this one turned half round about the engine's own line.
static func stabiliser_mesh(steel: Color, dark: Color) -> ArrayMesh:
	var inner := _stab_edges(STAB_FROM)
	var foot := Vector2(STAB_FROM, STAB_AXIS_Z)
	var profile := PackedVector2Array()
	for p in [Vector2(STAB_FROM, inner.x), Vector2(1.05, 0.95), Vector2(0.99, 1.38), Vector2(STAB_FROM, inner.y)]:
		profile.append(p - foot)
	var axis := stab_axis()
	var along := Basis(Vector3.UP.cross(axis).normalized(), axis, Vector3.UP.cross(axis).normalized().cross(axis))      # a cylinder's own line laid along the spindle
	return Kit.compound([
		[Fairings.fin(profile, STAB_THICK), Kit.at(Vector3.ZERO, Vector3(0.0, 0.0, -PI / 2.0)), steel],
		[Kit.cyl(BOSS, BOSS, 0.075, 14), Transform3D(along, axis * 0.0745), dark.lightened(0.38)],      # (clear of the glove's edge: it begins 37 mm up the spindle)
	])


## What it turns on, fixed to the engine: the root glove (the fin's root, as it was) and the actuator's
## boss on it, round the spindle. `out`: -1 the port engine, 1 the starboard.
static func stabiliser_fittings(out: float, side: float, steel: Color, dark: Color) -> Array:
	var edge := _stab_edges(GLOVE)
	var axis := stab_axis()
	var line := Vector3(out * axis.x, 0.0, axis.z)
	var across := Vector3.UP.cross(line).normalized()
	var foot := Vector3(out * (side + STAB_FROM), STAB_Y, STAB_AXIS_Z)
	return [
		[Fairings.fin(PackedVector2Array([Vector2(0.0, -0.3), Vector2(GLOVE, edge.x), Vector2(GLOVE, edge.y), Vector2(0.0, 1.05)]), STAB_THICK), Kit.at(Vector3(out * side, STAB_Y, 0.0), Vector3(0.0, 0.0, -out * PI / 2.0)), steel],
		[Kit.cyl(BOSS + 0.008, BOSS + 0.008, 0.10, 14), Transform3D(Basis(across, line, across.cross(line)), foot - line * 0.112), dark.lightened(0.25)],      # (and this one clear of the panel's edge: it ends 62 mm short of the foot)
	]


## The stabiliser panel on its spindle, engine-local: `pitch` rad, + = a right turn's (the starboard
## engine's trailing edge up, the port engine's down).
static func stabiliser_place(out: float, side: float, pitch: float) -> Transform3D:
	var stand := Basis.IDENTITY if out > 0.0 else Basis(Vector3.BACK, PI)
	return Transform3D(stand * Basis(stab_axis(), -pitch), Vector3(out * (side + STAB_FROM), STAB_Y, STAB_AXIS_Z))
