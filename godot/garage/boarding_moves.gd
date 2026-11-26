## The pilot's climb into and out of each craft (Luke, 2026-11-25: "the character should put his hand on the craft,
## jump up, and sit down in the seat. Getting out, the pilot should hop up, climb over the side and slide or hop down.
## Each craft will need a different animation"). Key poses for garage/pose_track.gd, written in the bay's frame as if
## the pilot boards from its +X side ("canonical"); garage/boarding.gd mirrors them for a bay boarded from -X.
## A key holds every channel; each key written here inherits the one before and changes what moves:
##   pelvis   the Pelvis joint (bay frame)            hip       the Pelvis joint from the pilot's own origin
##   yaw      heading (0 the craft's forward, +90 facing -X: in toward the cockpit from a +X gate)
##   pelvis_q, torso_q, stretch, torso_at, head_q     the body's turns (heading frame; the torso's from the pelvis)
##   ankle_l/r, foot_l/r, knee_l/r                    each ankle (bay frame), its boot's turn (bay frame; written in k()
##                                                    as from the key's heading), its knee's hint
##   grip_l/r, elbow_l/r                              each glove's grip (bay frame), its elbow's hint
## The first and last keys are the rig's own poses (pilot_model.gd snapshot()), so a climb starts and ends without a pop.
## Sill and hull figures are measured off the airframes (tests/probe_canopy_geometry.gd).
extends RefCounted

const Pilot := preload("res://sim/pilot_craft.gd")
const Suit := preload("res://garage/pilot_model.gd")

const FLOOR := -0.72        # the hall's floor in a bay's frame (garage/parked_airframe.gd SHELL_HEIGHT)
const SOLE := 0.095         # an ankle above its sole
# Each cab as the climb meets it, measured by rays with its canopy open (tests/probe_climb_clipping.gd --profile),
# canonical (boarded from +X), in the bay's frame:
#   rim      where a hand takes the rim (x out from the centreline) and the rim's top there
#   inner    the rim's inside edge: the cockpit's opening runs to here
#   wall     the hull's widest point on that side (x) and its height: hanging legs and a body sliding down keep outside it
#   floor    the footwell's floor; step   how far along the craft a foot steps down into it (on the flat, ahead of the
#            seat's front)
#   z        where along the craft he climbs: clear of the air brakes behind (fleet from 0.70), and the Basilisk's gun
#            mount (rim, z -0.9 to -0.1) and GUN switch (rim, 0.30); spread: how far apart his hands go on the rim
#   cushion  the seat pan's top
#   Talon:   fairing (the wing root's hump: x, top), wing (a point on its flat deck, its top), edge (its swept leading
#            edge: x at z 0.3, and how far out it runs for each metre aft)
#   Shrike:  strake (a point on the strake beside the rim, its top)
#   Basilisk: roof (the raised hatch's underside over the rim)
const HULLS := {
	Pilot.STANDARD: {"rim": Vector2(0.66, 0.60), "inner": 0.58, "wall": Vector2(1.16, 0.28), "floor": 0.12, "step": 0.40, "cushion": 0.22, "z": 0.46},
	Pilot.TALON: {"rim": Vector2(0.66, 0.60), "inner": 0.58, "wall": Vector2(1.16, 0.28), "floor": 0.12, "step": 0.40, "cushion": 0.22, "z": 0.46,
			"fairing": Vector2(0.98, 0.74), "wing": Vector2(1.55, 0.545), "edge": Vector2(1.95, 1.15)},
	Pilot.SHRIKE: {"rim": Vector2(0.66, 0.60), "inner": 0.58, "wall": Vector2(1.62, 0.68), "floor": 0.12, "step": 0.40, "cushion": 0.22, "z": 0.40,
			"strake": Vector2(1.46, 0.70)},
	Pilot.ORRERY: {"rim": Vector2(1.00, 0.72), "inner": 0.86, "wall": Vector2(1.29, 0.30), "floor": 0.12, "step": 0.20, "cushion": 0.265, "z": 0.30},
	Pilot.KILN: {"rim": Vector2(1.08, 0.77), "inner": 0.90, "wall": Vector2(1.40, 0.45), "floor": 0.12, "step": 0.20, "cushion": 0.265, "z": 0.24},
	Pilot.VESPER: {"rim": Vector2(1.00, 0.72), "inner": 0.86, "wall": Vector2(1.24, 0.50), "floor": 0.12, "step": 0.20, "cushion": 0.265, "z": 0.30,
			"spread": 0.20},
	Pilot.BASILISK: {"rim": Vector2(1.12, 0.75), "inner": 0.95, "wall": Vector2(1.36, 0.50), "floor": 0.12, "step": 0.20, "cushion": 0.265, "z": 0.46,
			"spread": 0.12,
			"low": true},
}
const SEAT_Z := 0.915       # the seated pilot's origin, along the craft
const PALM := 0.075         # a hand resting on a surface: its grip point (inside the fist) this far above it, the fingers to it
const CLEAR := 0.30         # hanging feet this far outside the hull's widest point
const CONSOLE := Vector2(0.615, 0.446)    # the side console's top beside the seat (every cab's interior: vr/cockpit_interior.gd)

var keys: Array[Dictionary] = []
var craft := ""
var hull := {}
var rim := Vector2.ZERO
var inner := 0.0
var wall := Vector2.ZERO
var floor_y := 0.0
var step_z := 0.0
var cushion := 0.0
var board_z := 0.0
var low := false            # (the Basilisk: under its raised hatch he keeps low)
var gate := Vector3.ZERO
var lead := 0.0             # seconds the canopy needs before the pilot's hands go to the sill
var seated := {}            # the seated pose (canonical)
var _cur := {}


## A boarding: from `start` (canonical channels of the pilot as he stands) to the seated pose given at _init.
func board(start: Dictionary) -> Array[Dictionary]:
	keys.clear()
	_first(start)
	_board()
	_last(seated)
	return keys


## An exit: from the seated pose to `end` (standing at the gate, facing out).
func leave(end: Dictionary) -> Array[Dictionary]:
	keys.clear()
	_first(seated)
	_leave()
	_last(end)
	return keys


## `gate_point`: the bay's gate (canonical); `canopy_lead`: seconds the canopy needs open before hands go to the sill.
func _init(id: String, gate_point: Vector3, seated_pose: Dictionary, canopy_lead := 1.0) -> void:
	craft = id
	hull = HULLS.get(id, HULLS[Pilot.STANDARD])
	rim = hull.rim
	inner = hull.inner
	wall = hull.wall
	floor_y = hull.floor
	step_z = hull.step
	cushion = hull.cushion
	board_z = hull.z
	low = hull.get("low", false)
	gate = gate_point
	seated = seated_pose
	lead = canopy_lead


func _first(pose: Dictionary) -> void:
	_cur = pose.duplicate()
	_cur.t = 0.0
	keys.append(_cur)


func _last(pose: Dictionary) -> void:
	var at: float = _cur.t + 0.42
	_cur = pose.duplicate()
	_cur.t = at
	keys.append(_cur)


func _board() -> void:
	match craft:
		Pilot.TALON: _board_wing()
		Pilot.SHRIKE: _board_vault()
		Pilot.ORRERY: _board_perch()
		Pilot.KILN: _board_haul()
		Pilot.VESPER: _board_f1()
		Pilot.BASILISK: _board_crawl()
		_: _board_mantle()


func _leave() -> void:
	match craft:
		Pilot.TALON: _leave_wing()
		Pilot.SHRIKE: _leave_hop()
		Pilot.ORRERY: _leave_pushoff()
		Pilot.KILN: _leave_climb_down()
		Pilot.VESPER: _leave_f1()
		Pilot.BASILISK: _leave_hang()
		_: _leave_slide()


# --- the language the moves are written in ---------------------------------------------------------------------------

## A key `dt` seconds after the last, changing `set`.
func k(dt: float, set: Dictionary) -> void:
	_cur = _cur.duplicate()
	_cur.merge(set, true)
	_cur.t = float(_cur.t) + dt
	# a boot's turn is written as from that key's heading, and held in the bay's frame: a planted boot stays put as he turns
	for foot in ["foot_l", "foot_r"]:
		if set.has(foot):
			_cur[foot] = Quaternion(Vector3.UP, float(_cur.yaw)) * (set[foot] as Quaternion)
	keys.append(_cur)


static func body(pelvis: Vector3, yaw_deg: float, hip_y := 0.941) -> Dictionary:
	return {"pelvis": pelvis, "yaw": deg_to_rad(yaw_deg), "hip": Vector3(0.0, hip_y, 0.0)}


## The torso's lean from the pelvis: forward, to the pilot's right, twisted to his left (degrees).
static func spine(forward: float, side := 0.0, twist := 0.0, stretch := 1.0) -> Dictionary:
	var q := Quaternion(Vector3.UP, deg_to_rad(twist)) * Quaternion(Vector3.RIGHT, -deg_to_rad(forward)) * Quaternion(Vector3.BACK, -deg_to_rad(side))
	return {"torso_q": q, "stretch": stretch, "torso_at": Vector3(0.0, 0.036, 0.0)}


## The pelvis's own tilt: forward, to the right (degrees).
static func tilt(forward: float, side := 0.0) -> Dictionary:
	return {"pelvis_q": Quaternion(Vector3.RIGHT, -deg_to_rad(forward)) * Quaternion(Vector3.BACK, -deg_to_rad(side))}


## Where the eye looks, from the heading: down, and turned to the left (degrees).
static func gaze(down: float, turn := 0.0) -> Dictionary:
	return {"head_q": Quaternion(Vector3.UP, deg_to_rad(turn)) * Quaternion(Vector3.RIGHT, -deg_to_rad(down))}


## Ankles (bay frame) and each sole's pitch, toes up positive (degrees).
static func feet(left: Vector3, right: Vector3, toe_left := 0.0, toe_right := 0.0) -> Dictionary:
	return {"ankle_l": left, "ankle_r": right,
			"foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(toe_left)), "foot_r": Quaternion(Vector3.RIGHT, deg_to_rad(toe_right))}


## Which way each knee points (heading frame: -Z ahead, +X his right).
static func knees(left: Vector3, right: Vector3) -> Dictionary:
	return {"knee_l": left, "knee_r": right}


static func hands(left: Vector3, right: Vector3) -> Dictionary:
	return {"grip_l": left, "grip_r": right}


static func elbows(left: Vector3, right: Vector3) -> Dictionary:
	return {"elbow_l": left, "elbow_r": right}


static func merged(parts: Array) -> Dictionary:
	var all := {}
	for part: Dictionary in parts:
		all.merge(part, true)
	return all


## A point `local` in the pilot's own frame (+X his right, -Z ahead) for a pilot whose origin is `root`, heading `yaw`.
static func near(root: Vector3, yaw_deg: float, local: Vector3) -> Vector3:
	return root + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * local


## Both hands hanging at his sides, for a pilot with his pelvis at `pelvis`, heading `yaw`.
static func hang(pelvis: Vector3, yaw_deg: float) -> Dictionary:
	return hands(near(pelvis, yaw_deg, Vector3(-0.235, -0.10, -0.03)), near(pelvis, yaw_deg, Vector3(0.235, -0.10, -0.03)))


## Standing upright at `x, z` heading `yaw`, feet under the hips, arms at the sides.
static func standing(x: float, z: float, yaw_deg: float) -> Dictionary:
	var pelvis := Vector3(x, FLOOR + 0.941, z)
	var root := Vector3(x, FLOOR, z)
	return merged([body(pelvis, yaw_deg), tilt(0.0), spine(0.0), gaze(0.0),
			feet(near(root, yaw_deg, Vector3(-0.1, SOLE, 0.0)), near(root, yaw_deg, Vector3(0.1, SOLE, 0.0))),
			knees(Vector3(-0.15, 0.0, -1.0), Vector3(0.15, 0.0, -1.0)), hang(pelvis, yaw_deg),
			elbows(Vector3(-0.8, -1.0, 0.5), Vector3(0.8, -1.0, 0.5))])


## Walk from where the last key stands to `x, z`, ending heading `yaw`: a step every STEP seconds, the feet planted
## between steps and lifted on the way.
const STEP := 0.34
func walk_to(x: float, z: float, yaw_deg: float) -> void:
	var from: Vector3 = _cur.pelvis
	var from_yaw: float = rad_to_deg(float(_cur.yaw))
	var to := Vector3(x, FLOOR + 0.941, z)
	var flat := Vector2(to.x - from.x, to.z - from.z)
	var turn := absf(wrapf(yaw_deg - from_yaw, -180.0, 180.0))
	var steps := clampi(ceili(flat.length() / 0.55), 0, 6)
	if steps == 0 and turn > 25.0:
		steps = 1
	if steps == 0:
		k(0.25, standing(x, z, yaw_deg))
		return
	for j in steps:
		var right := j % 2 == 0
		var f := float(j + 1) / steps
		var at := from.lerp(to, f)
		var yaw: float = lerpf(from_yaw, from_yaw + wrapf(yaw_deg - from_yaw, -180.0, 180.0), f)
		var plant := standing(at.x, at.z, yaw)
		var mid := from.lerp(to, (j + 0.5) / steps)
		var swing: Vector3 = (plant.ankle_r if right else plant.ankle_l)
		var lifted := (Vector3((swing.x + float((_cur.ankle_r if right else _cur.ankle_l).x)) * 0.5, swing.y + 0.10,
				(swing.z + float((_cur.ankle_r if right else _cur.ankle_l).z)) * 0.5))
		k(STEP * 0.5, merged([body(Vector3(mid.x, FLOOR + 0.941 + 0.012, mid.z), lerpf(from_yaw, yaw, 0.5 + 0.5 * f)),
				{"ankle_r": lifted} if right else {"ankle_l": lifted}, {"foot_r" if right else "foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(-12.0))},
				hang(mid, yaw)]))
		k(STEP * 0.5, plant)


# --- shared pieces, routed round each cab's measured shape -------------------------------------------------------

## A hand on the rim on his side, or the far rim, `z` along the craft.
func near_rim(z: float, up := 0.03) -> Vector3:
	return Vector3(rim.x + 0.02, rim.y + up + PALM, z)


func far_rim(z: float, up := 0.03) -> Vector3:
	return Vector3(-inner - 0.04, rim.y + up + PALM, z)


## Where he stands to climb: clear of the hull's widest point.
func stand_x() -> float:
	return wall.x + 0.40


## Legs hanging near-straight below hips at `pelvis`, outboard of the hull's widest point, toes down (a bent knee
## would fold into the hull's side).
func dangling(pelvis: Vector3, toe := -35.0) -> Dictionary:
	var x := maxf(pelvis.x + 0.16, wall.x + 0.24)
	return merged([feet(Vector3(x, pelvis.y - 0.80, pelvis.z + 0.11), Vector3(x - 0.03, pelvis.y - 0.78, pelvis.z - 0.11), toe, toe),
			knees(Vector3(-0.3, -0.4, -1.0), Vector3(0.3, -0.4, -1.0))])


## Both feet in the footwell ahead of the seat.
func in_well(dz := 0.0) -> Dictionary:
	return feet(Vector3(-0.13, floor_y + SOLE, step_z + 0.04 + dz), Vector3(0.13, floor_y + SOLE, step_z - 0.04 + dz))


## The feet `f` of the way from the footwell toward the seated pose's, along the floor (flat, at the floor's height: the
## seated pose itself sets them down where it has them).
func feet_toward_seat(f: float) -> Dictionary:
	var well := in_well()
	var l: Vector3 = (well.ankle_l as Vector3).lerp(seated.ankle_l, f)
	var r: Vector3 = (well.ankle_r as Vector3).lerp(seated.ankle_r, f)
	l.y = floor_y + SOLE + 0.01
	r.y = floor_y + SOLE + 0.01
	return {"ankle_l": l, "ankle_r": r, "foot_l": Quaternion.IDENTITY, "foot_r": Quaternion.IDENTITY,
			"knee_l": Vector3(-0.2, 0.3, -1.0).lerp(seated.knee_l, f), "knee_r": Vector3(0.2, 0.3, -1.0).lerp(seated.knee_r, f)}


## Walk up beside the cockpit at `z`, bring both hands up outside the hull, then down onto the rim; wait there for the
## canopy (`lead` seconds in).
func up_to_rim(z: float, spread := 0.22) -> void:
	spread = hull.get("spread", spread)
	var x := stand_x()
	walk_to(x, z, 90.0)
	k(0.24, merged([body(Vector3(x - 0.02, FLOOR + 0.941 - 0.02, z), 90.0), spine(10.0), gaze(22.0),
			hands(Vector3(wall.x + 0.10, rim.y + 0.34, z + spread), Vector3(wall.x + 0.10, rim.y + 0.34, z - spread)),
			elbows(Vector3(-1.0, -0.6, 0.4), Vector3(1.0, -0.6, 0.4))]))
	k(maxf(0.24, lead - float(_cur.t)), merged([body(Vector3(x - 0.05, FLOOR + 0.941 - 0.04, z), 90.0), spine(24.0), tilt(4.0), gaze(28.0),
			hands(near_rim(z + spread), near_rim(z - spread)), elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))


## Sink at the knees, arms bent on the rim, ready to jump.
func crouch(z: float, dt := 0.30) -> void:
	k(dt, merged([body(Vector3(stand_x() + 0.04, FLOOR + 0.941 - 0.21, z), 90.0), spine(20.0), tilt(10.0), gaze(16.0),
			knees(Vector3(-0.25, 0.0, -1.0), Vector3(0.25, 0.0, -1.0))]))


## Jump: legs straighten under him, hips rising beside the hull.
func spring(z: float, dt := 0.18) -> void:
	var pelvis := Vector3(wall.x + 0.12, rim.y - 0.10, z)
	k(dt, merged([body(pelvis, 90.0), spine(34.0), tilt(10.0), gaze(14.0), dangling(pelvis, -40.0)]))


## Up on straight arms, hips over the rim's outside, shoulders over the hands, legs hanging clear of the hull.
func press(z: float, dt := 0.22) -> void:
	var pelvis := Vector3(rim.x + 0.40, rim.y + 0.30, z)
	k(dt, merged([body(pelvis, 90.0), spine(40.0), tilt(14.0), gaze(30.0), dangling(pelvis)]))


## One knee down on the deck by the rim, its shin lying back along it; the other leg hanging outside.
func knee_on_rim(z: float, right := true, dt := 0.30) -> void:
	var s := "_r" if right else "_l"
	var o := "_l" if right else "_r"
	var dz := -0.12 if right else 0.12
	var lip := wall.x + 0.02 if rim.x > 0.9 else rim.x + 0.34      # (the deck's outer edge; the Phaethon's rim rounds off at once)
	k(dt, merged([body(Vector3(rim.x + 0.24, rim.y + 0.44, z + 0.02), 90.0), spine(44.0), tilt(24.0), gaze(36.0),
			{"ankle" + s: Vector3(minf(rim.x + 0.42, lip - 0.04), rim.y + 0.10, z + dz), "foot" + s: Quaternion(Vector3.RIGHT, deg_to_rad(-60.0)),
			"knee" + s: Vector3(0.0, -0.7, -1.0),
			"ankle" + o: Vector3(lip + 0.12, rim.y - 0.34, z - dz), "foot" + o: Quaternion(Vector3.RIGHT, deg_to_rad(-30.0)),
			"knee" + o: Vector3(0.0, 0.5, 1.0)}]))


## The kneeling leg's foot comes up over the rim and down into the footwell; the other knee comes onto the deck; then
## that leg over too, and he stands in the cockpit facing forward.
func step_down_in(z: float, right := true) -> void:
	var s := "_r" if right else "_l"
	var o := "_l" if right else "_r"
	var side := 1.0 if right else -1.0
	var dip := 0.16 if low else 0.0
	var bend := 16.0 if low else 0.0
	k(0.26, merged([body(Vector3(rim.x + 0.04, rim.y + 0.54 - dip, z + 0.06), 74.0), spine(36.0 + bend), tilt(14.0), gaze(34.0, -8.0),
			{"ankle" + s: Vector3(inner - 0.08, rim.y + 0.30, z - 0.10 * side), "foot" + s: Quaternion(Vector3.RIGHT, deg_to_rad(-20.0)),
			"knee" + s: Vector3(0.0, 0.8, -1.0),
			"ankle" + o: Vector3(wall.x + 0.26, rim.y + 0.14, z + 0.14 * side), "knee" + o: Vector3(0.3 * side, -0.2, -1.0)}]))
	k(0.30, merged([body(Vector3(inner - 0.10, rim.y + 0.46 - dip, (z + step_z) * 0.5), 58.0), spine(30.0 + bend), tilt(10.0), gaze(30.0, -12.0),
			{"ankle" + s: Vector3(0.14 * side, floor_y + SOLE, step_z - 0.06 * side), "foot" + s: Quaternion.IDENTITY,
			"knee" + s: Vector3(0.2 * side, 0.2, -1.0),
			"ankle" + o: Vector3(minf(rim.x + 0.30, (wall.x - 0.04) if rim.x > 0.9 else rim.x + 0.30), rim.y + 0.10, z + 0.14 * side),
			"foot" + o: Quaternion(Vector3.RIGHT, deg_to_rad(-55.0)),
			"knee" + o: Vector3(0.0, -0.7, -1.0)}]))
	# the other leg: knee high, over the rim, down beside the first
	k(0.28, merged([body(Vector3(inner - 0.30, floor_y + 0.96 - dip * 0.5, step_z + 0.10), 38.0), spine(18.0 + bend * 0.5), tilt(4.0), gaze(24.0, -6.0),
			{"ankle" + o: Vector3(inner - 0.02, rim.y + 0.30, step_z + 0.22), "knee" + o: Vector3(0.0, 0.8, -1.0),
			"foot" + o: Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))}]))
	k(0.28, merged([body(Vector3(0.02, floor_y + 0.941 - 0.04, step_z + 0.02), 0.0), spine(8.0), tilt(0.0), gaze(18.0), in_well(),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0))]))


## The seated pose's feet, turned as it has them, but standing on the floor: the last step into the seat only lets them
## down into its place (turning and dropping together dug a toe through the floor: tests/probe_climb_clipping.gd).
func feet_seated_on_floor() -> Dictionary:
	var l: Vector3 = seated.ankle_l
	var r: Vector3 = seated.ankle_r
	l.y = maxf(l.y, floor_y + SOLE + 0.01)
	r.y = maxf(r.y, floor_y + SOLE + 0.01)
	return {"ankle_l": l, "ankle_r": r, "foot_l": seated.foot_l, "foot_r": seated.foot_r, "knee_l": seated.knee_l, "knee_r": seated.knee_r}


## From standing in the footwell: hands to the rims, sit back into the seat, the feet sliding forward along the floor.
## (The seated pose follows: _last.)
func sit_back(dt := 0.44) -> void:
	k(0.22, merged([body(Vector3(0.0, floor_y + 0.941 - 0.14, step_z + 0.12), 0.0), spine(22.0), tilt(8.0), gaze(14.0),
			hands(far_rim(step_z + 0.30, 0.0), near_rim(step_z + 0.30, 0.0)), elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	k(dt, merged([body(Vector3(0.0, cushion + 0.36, SEAT_Z - 0.10), 0.0), spine(24.0), tilt(8.0), gaze(12.0), feet_toward_seat(0.45),
			hands(far_rim(0.66, 0.0), near_rim(0.66, 0.0))]))
	k(0.22, merged([body(Vector3(0.0, cushion + 0.30, SEAT_Z - 0.04), 0.0), spine(22.0), tilt(6.0), gaze(10.0)]))
	_cur.merge(feet_seated_on_floor(), true)      # (in the bay's frame already: not through k()'s heading)


## Out of the seat: hands to the rims as the canopy goes, feet drawn back along the floor, and up to stand in the
## footwell facing forward.
func stand_in_well() -> void:
	k(maxf(0.25, lead * 0.4), merged([spine(26.0), gaze(10.0), hands(far_rim(0.66, 0.0), near_rim(0.66, 0.0)),
			elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	_cur.merge(feet_seated_on_floor(), true)
	k(maxf(0.22, lead * 0.25), merged([spine(30.0), gaze(10.0), feet_toward_seat(0.5)]))
	k(0.40, merged([body(Vector3(0.0, floor_y + 0.941 - 0.14, step_z + 0.14), 0.0), spine(24.0), tilt(8.0), gaze(14.0), in_well(),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)), hands(far_rim(step_z + 0.30, 0.0), near_rim(step_z + 0.30, 0.0))]))
	k(0.26, merged([body(Vector3(0.02, floor_y + 0.941 - 0.04, step_z + 0.04), 0.0), spine(8.0), tilt(0.0), gaze(18.0),
			hang(Vector3(0.02, floor_y + 0.90, step_z + 0.04), 0.0)]))


## Sitting on the rim's deck facing out, legs hanging outside, hands on the deck beside his hips.
func perched(z := 0.50) -> Dictionary:
	var lip := wall.x + 0.02 if rim.x > 0.9 else rim.x + 0.34
	return merged([body(Vector3(maxf(rim.x + 0.12, lip - 0.14), rim.y + 0.15, z), -90.0, 0.30), spine(6.0), tilt(-4.0), gaze(24.0),
			feet(Vector3(wall.x + CLEAR, rim.y - 0.42, z - 0.12), Vector3(wall.x + CLEAR, rim.y - 0.42, z + 0.12), -15.0, -15.0),
			knees(Vector3(-0.1, 0.0, -1.0), Vector3(0.1, 0.0, -1.0)),
			hands(near_rim(z + 0.30, 0.0), near_rim(z - 0.30, 0.0)), elbows(Vector3(-0.6, -0.2, 1.0), Vector3(0.6, -0.2, 1.0))])


## From standing in the footwell: sit on the rim beside him, then swing both legs up over it and out, turning to face
## out. Beside a narrow rim (the Phaethon's three) he sits facing forward with his feet on the floor; onto a wide deck (the
## fleet's) he sits up from the footwell facing out, knees drawn up over the rim's inner lip.
func sit_and_swing_out(z := 0.50) -> void:
	var wide := rim.x > 0.9
	if not wide:
		# a narrow rim: sat on it facing forward, feet on the floor, then the legs up high over the map panel and out
		k(0.40, merged([body(Vector3(rim.x - 0.02, rim.y + 0.14, z + 0.04), -20.0, 0.30), spine(6.0), tilt(-6.0, 6.0), gaze(18.0, -20.0),
				feet(Vector3(inner - 0.30, floor_y + SOLE, z - 0.02), Vector3(inner - 0.12, floor_y + SOLE, z + 0.10)),
				knees(Vector3(0.0, 0.2, -1.0), Vector3(0.0, 0.2, -1.0)), hands(near_rim(z - 0.30, 0.0), near_rim(z + 0.36, 0.0))]))
		k(0.36, merged([body(Vector3(rim.x + 0.02, rim.y + 0.15, z), -55.0, 0.30), spine(-16.0), tilt(-16.0), gaze(20.0, -10.0),
				feet(Vector3(rim.x + 0.10, rim.y + 0.46, z - 0.22), Vector3(rim.x + 0.20, rim.y + 0.48, z - 0.04), 10.0, 10.0),
				knees(Vector3(0.0, 1.0, -0.5), Vector3(0.0, 1.0, -0.5))]))
		k(0.30, perched(z))
		return
	# a wide deck: up from the footwell to sit on the deck facing out, knees drawn up high over the rim's raised inner lip
	# (sat with his feet on the side console, his shins lay across it), then the legs out over the edge
	var by := minf(inner - 0.12, 0.34)      # (standing on the floor, clear of the side console)
	k(0.30, merged([body(Vector3(by, floor_y + 0.90, z), -90.0), spine(14.0), gaze(26.0),
			feet(Vector3(by - 0.04, floor_y + SOLE, z - 0.13), Vector3(by - 0.04, floor_y + SOLE, z + 0.13)),
			hands(near_rim(z - 0.24, 0.0), near_rim(z + 0.24, 0.0)), elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	k(0.40, merged([body(Vector3(rim.x - 0.08, rim.y + 0.26, z), -90.0, 0.30), spine(20.0), tilt(-4.0), gaze(30.0),
			feet(Vector3(CONSOLE.x + 0.02, rim.y + 0.12, z - 0.12), Vector3(CONSOLE.x + 0.02, rim.y + 0.12, z + 0.12), 20.0, 20.0),
			knees(Vector3(0.0, 1.0, -0.6), Vector3(0.0, 1.0, -0.6)), hands(near_rim(z - 0.28, 0.0), near_rim(z + 0.28, 0.0))]))
	k(0.34, merged([body(Vector3(rim.x + 0.04, rim.y + 0.18, z), -90.0, 0.30), spine(-10.0), tilt(-12.0), gaze(26.0),
			feet(Vector3(rim.x + 0.16, rim.y + 0.36, z - 0.12), Vector3(rim.x + 0.16, rim.y + 0.36, z + 0.12), 10.0, 10.0),
			knees(Vector3(0.0, 1.0, -0.5), Vector3(0.0, 1.0, -0.5))]))
	k(0.30, perched(z))


## From sitting on the rim: slide down the hull's side and round its widest point, hands trailing on the rim, to land.
func slide_down(z := 0.50) -> void:
	k(0.26, merged([body(Vector3(wall.x + 0.16, rim.y - 0.08, z), -90.0), spine(-2.0), tilt(-2.0), gaze(28.0),
			feet(Vector3(wall.x + 0.40, rim.y - 0.66, z - 0.12), Vector3(wall.x + 0.40, rim.y - 0.66, z + 0.12), -20.0, -20.0),
			hands(near_rim(z + 0.32, 0.0), near_rim(z - 0.32, 0.0))]))
	k(0.30, merged([body(Vector3(wall.x + 0.24, FLOOR + 0.941 - 0.22, z), -90.0), spine(-2.0), tilt(6.0), gaze(30.0),
			feet(Vector3(wall.x + 0.46, FLOOR + SOLE, z - 0.12), Vector3(wall.x + 0.46, FLOOR + SOLE, z + 0.12)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)),
			hands(Vector3(wall.x + 0.10, rim.y + 0.10, z + 0.36), Vector3(wall.x + 0.10, rim.y + 0.10, z - 0.36)),
			elbows(Vector3(-0.6, -0.2, 1.0), Vector3(0.6, -0.2, 1.0))]))


## Down on the floor at `x, z` heading `yaw` (out: -90), knees taking it, arms forward; up; and out to the gate.
func land_and_walk(x: float, z := 0.50, deep := 0.30, dt := 0.24, yaw := -90.0) -> void:
	var root := Vector3(x, FLOOR, z)
	k(dt, merged([body(near(root, yaw, Vector3(0.0, 0.941 - deep, 0.04)), yaw), spine(26.0), tilt(12.0), gaze(30.0),
			feet(near(root, yaw, Vector3(-0.13, SOLE, 0.0)), near(root, yaw, Vector3(0.13, SOLE, -0.06))),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)),
			hands(near(root, yaw, Vector3(-0.26, 0.95, -0.30)), near(root, yaw, Vector3(0.26, 0.95, -0.30))),
			elbows(Vector3(-1, -0.6, 0.2), Vector3(1, -0.6, 0.2))]))
	k(0.40, standing(x, z, yaw))
	walk_to(gate.x, gate.z, -90.0)


# --- each craft's climbs ---------------------------------------------------------------------------------------------

## Phaethon: the mantle in (both hands, a knee on the rim, a foot down into the well); out, sat on the rim, legs over,
## and slid down the side.
func _board_mantle() -> void:
	var z := board_z
	up_to_rim(z)
	crouch(z)
	spring(z)
	press(z)
	knee_on_rim(z, true)
	step_down_in(z, true)
	sit_back()


func _leave_slide() -> void:
	var z := board_z
	stand_in_well()
	sit_and_swing_out(z)
	slide_down(z)
	land_and_walk(wall.x + 0.50, z, 0.24, 0.22)


## Talon: hands on the wing, up onto it, stood, over the fairing and the rim; out the same way, off the wing's edge.
func wing_edge(z: float) -> float:
	return hull.edge.x + (z - 0.3) * hull.edge.y


## A point on the Talon's wing: from where its edge is at `z0`, `inward` square to the edge (in and aft), `along` it
## (out and aft), at height `y`.
func on_wing(z0: float, inward: float, along: float, y: float) -> Vector3:
	var normal := Vector3(-1.0, 0.0, hull.edge.y).normalized()
	var line := Vector3(hull.edge.y, 0.0, 1.0).normalized()
	return Vector3(wing_edge(z0), y, z0) + normal * inward + line * along


## The heading that faces square into the wing's edge.
func into_wing() -> float:
	var normal := Vector3(-1.0, 0.0, hull.edge.y).normalized()
	return rad_to_deg(atan2(-normal.x, -normal.z))


func _board_wing() -> void:
	var wing: Vector2 = hull.wing
	var fairing: Vector2 = hull.fairing
	var z0 := 0.26
	var yaw := into_wing()
	var stand := on_wing(z0, -0.34, 0.0, 0.0)
	walk_to(stand.x, stand.z, yaw)
	k(0.24, merged([body(on_wing(z0, -0.36, 0.0, FLOOR + 0.92), yaw), spine(10.0), gaze(24.0),
			hands(on_wing(z0, -0.08, 0.22, wing.y + 0.30), on_wing(z0, -0.08, -0.22, wing.y + 0.30)),
			elbows(Vector3(-1.0, -0.6, 0.4), Vector3(1.0, -0.6, 0.4))]))
	k(maxf(0.24, lead - float(_cur.t)), merged([body(on_wing(z0, -0.32, 0.0, FLOOR + 0.90), yaw), spine(24.0), tilt(4.0), gaze(30.0),
			hands(on_wing(z0, 0.16, 0.22, wing.y + 0.03 + PALM), on_wing(z0, 0.16, -0.22, wing.y + 0.03 + PALM)),
			elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	k(0.30, merged([body(on_wing(z0, -0.46, 0.0, FLOOR + 0.75), yaw), spine(18.0), tilt(8.0), gaze(16.0),
			knees(Vector3(-0.25, 0.0, -1.0), Vector3(0.25, 0.0, -1.0))]))
	var up := on_wing(z0, -0.22, 0.0, wing.y + 0.04)
	k(0.18, merged([body(up, yaw), spine(34.0), tilt(10.0), gaze(14.0),
			feet(on_wing(z0, -0.30, 0.10, FLOOR + 0.28), on_wing(z0, -0.28, -0.10, FLOOR + 0.34), -40.0, -40.0)]))
	# a knee onto the wing, then both feet under him, then up
	k(0.30, merged([body(on_wing(z0, 0.26, 0.0, wing.y + 0.44), yaw), spine(40.0), tilt(20.0), gaze(34.0),
			{"ankle_r": on_wing(z0, 0.10, -0.12, wing.y + 0.10), "foot_r": Quaternion(Vector3.RIGHT, deg_to_rad(-60.0)),
			"knee_r": Vector3(0.0, -0.7, -1.0), "ankle_l": on_wing(z0, -0.12, 0.12, wing.y - 0.36), "knee_l": Vector3(0.0, 0.5, 1.0),
			"foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(-30.0))}]))
	k(0.32, merged([body(on_wing(z0, 0.40, 0.0, wing.y + SOLE + 0.66), yaw), spine(24.0), tilt(18.0), gaze(28.0),
			feet(on_wing(z0, 0.36, 0.13, wing.y + SOLE), on_wing(z0, 0.42, -0.13, wing.y + SOLE)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0))]))
	k(0.32, merged([body(on_wing(z0, 0.42, 0.0, wing.y + SOLE + 0.86), yaw), spine(4.0), tilt(0.0), gaze(24.0),
			hands(on_wing(z0, 0.40, 0.42, wing.y + 0.98), on_wing(z0, 0.40, -0.42, wing.y + 0.98)),
			elbows(Vector3(-1, -0.3, 0.3), Vector3(1, -0.3, 0.3))]))
	var z := board_z
	# a step in along the wing, then the right foot up onto the fairing
	k(0.40, merged([body(Vector3(wing.x - 0.10, wing.y + SOLE + 0.86, z), 90.0),
			feet(Vector3(wing.x - 0.02, wing.y + SOLE, z + 0.14), Vector3(wing.x - 0.12, wing.y + SOLE, z - 0.12))]))
	k(0.30, merged([body(Vector3(fairing.x + 0.30, fairing.y + 0.72, z + 0.02), 80.0), spine(14.0), gaze(30.0),
			{"ankle_r": Vector3(fairing.x + 0.02, fairing.y + SOLE, z - 0.10), "knee_r": Vector3(0.0, 0.5, -1.0)}]))
	# over the rim: the left leg high and down into the well, then the right after it
	k(0.30, merged([body(Vector3(fairing.x - 0.12, fairing.y + 0.70, z + 0.04), 64.0), spine(20.0), gaze(34.0, -10.0),
			{"ankle_l": Vector3(inner - 0.06, rim.y + 0.32, z + 0.10), "knee_l": Vector3(0.0, 0.8, -1.0),
			"foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))},
			hands(Vector3(fairing.x - 0.02, fairing.y + 0.03 + PALM, z + 0.34), near_rim(z - 0.30, 0.02))]))
	k(0.30, merged([body(Vector3(inner - 0.20, floor_y + 1.02, (z + step_z) * 0.5), 40.0), spine(24.0), gaze(28.0, -8.0),
			{"ankle_l": Vector3(-0.12, floor_y + SOLE, step_z + 0.04), "foot_l": Quaternion.IDENTITY, "knee_l": Vector3(-0.2, 0.2, -1.0),
			"ankle_r": Vector3(inner - 0.04, rim.y + 0.32, step_z - 0.02), "knee_r": Vector3(0.0, 0.8, -1.0),
			"foot_r": Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))}]))
	k(0.28, merged([body(Vector3(0.02, floor_y + 0.90, step_z + 0.02), 0.0), spine(8.0), tilt(0.0), gaze(18.0), in_well(),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)), hang(Vector3(0.02, floor_y + 0.90, step_z), 0.0)]))
	sit_back()


func _leave_wing() -> void:
	var wing: Vector2 = hull.wing
	var fairing: Vector2 = hull.fairing
	var z := board_z
	stand_in_well()
	# the right foot high over the rim onto the fairing, up onto it, the left after
	k(0.30, merged([body(Vector3(inner - 0.24, floor_y + 1.00, step_z + 0.06), -40.0), spine(16.0), gaze(30.0, -12.0),
			{"ankle_r": Vector3(inner - 0.04, rim.y + 0.32, step_z + 0.10), "knee_r": Vector3(0.0, 0.8, -1.0)},
			hands(near_rim(step_z - 0.10, 0.02), near_rim(step_z + 0.40, 0.02))]))
	k(0.32, merged([body(Vector3(fairing.x - 0.10, fairing.y + 0.70, z - 0.02), -70.0), spine(20.0), gaze(30.0),
			{"ankle_r": Vector3(fairing.x + 0.02, fairing.y + SOLE, z - 0.04), "foot_r": Quaternion.IDENTITY, "knee_r": Vector3(0.0, 0.4, -1.0),
			"ankle_l": Vector3(inner - 0.04, rim.y + 0.32, z + 0.06), "knee_l": Vector3(0.0, 0.8, -1.0)},
			hands(Vector3(fairing.x - 0.02, fairing.y + 0.03 + PALM, z - 0.34), Vector3(fairing.x - 0.02, fairing.y + 0.03 + PALM, z + 0.34))]))
	k(0.32, merged([body(Vector3(wing.x - 0.06, wing.y + SOLE + 0.84, z), -90.0), spine(6.0), tilt(0.0), gaze(30.0),
			feet(Vector3(wing.x - 0.10, wing.y + SOLE, z - 0.12), Vector3(wing.x + 0.02, wing.y + SOLE, z + 0.12)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)),
			hands(Vector3(wing.x - 0.08, wing.y + 0.96, z - 0.42), Vector3(wing.x - 0.08, wing.y + 0.96, z + 0.42)),
			elbows(Vector3(-1, -0.3, 0.3), Vector3(1, -0.3, 0.3))]))
	# out along the wing, turned square to its edge; down into a crouch, and off
	var z0 := 0.42
	var out := into_wing() - 180.0
	k(0.36, merged([body(on_wing(z0, 0.30, 0.0, wing.y + SOLE + 0.84), out), spine(6.0), gaze(30.0),
			feet(on_wing(z0, 0.30, -0.13, wing.y + SOLE), on_wing(z0, 0.34, 0.13, wing.y + SOLE))]))
	k(0.30, merged([body(on_wing(z0, 0.24, 0.0, wing.y + SOLE + 0.62), out), spine(22.0), tilt(14.0), gaze(40.0),
			feet(on_wing(z0, 0.18, -0.13, wing.y + SOLE), on_wing(z0, 0.16, 0.13, wing.y + SOLE)),
			hands(on_wing(z0, 0.02, -0.30, wing.y + 0.55), on_wing(z0, 0.02, 0.30, wing.y + 0.55))]))
	k(0.32, merged([body(on_wing(z0, -0.40, 0.0, wing.y + 0.30), out), spine(10.0), tilt(4.0), gaze(34.0),
			feet(on_wing(z0, -0.28, -0.12, wing.y - 0.20), on_wing(z0, -0.32, 0.12, wing.y - 0.24), -25.0, -25.0),
			hands(on_wing(z0, -0.60, -0.30, wing.y + 0.75), on_wing(z0, -0.60, 0.30, wing.y + 0.75))]))
	var land := on_wing(z0, -0.62, 0.0, 0.0)
	land_and_walk(land.x, land.z, 0.34, 0.30, out)


## Shrike: a one-hand vault over the strake and the rim, landing in the well; out, up onto the strake and a hop off.
func _board_vault() -> void:
	var strake: Vector2 = hull.strake
	var z := board_z
	var x := stand_x()
	walk_to(x, z, 90.0)
	k(0.22, merged([body(Vector3(x - 0.02, FLOOR + 0.92, z), 90.0), spine(10.0), gaze(22.0),
			{"grip_r": Vector3(wall.x + 0.06, wall.y + 0.30, z - 0.08), "elbow_r": Vector3(1.0, -0.6, 0.4)}]))
	k(maxf(0.22, lead - float(_cur.t)), merged([body(Vector3(x - 0.04, FLOOR + 0.90, z), 90.0), spine(22.0), tilt(4.0), gaze(28.0),
			{"grip_r": Vector3(strake.x, strake.y + 0.03 + PALM, z - 0.08), "elbow_r": Vector3(0.9, -0.6, 0.5),
			"grip_l": Vector3(x + 0.30, FLOOR + 0.80, z + 0.30)}]))
	k(0.22, merged([body(Vector3(x + 0.02, FLOOR + 0.72, z), 90.0), spine(26.0), tilt(12.0), gaze(18.0),
			knees(Vector3(-0.25, 0.0, -1.0), Vector3(0.25, 0.0, -1.0)), {"grip_l": Vector3(x + 0.36, FLOOR + 0.62, z + 0.34)}]))
	# up, pivoting round the planted arm, knees tucked and swinging round together, high over the strake
	k(0.24, merged([body(Vector3(wall.x + 0.02, wall.y + 0.16, z + 0.02), 72.0), spine(28.0, 10.0), tilt(8.0), gaze(16.0),
			feet(Vector3(wall.x + 0.24, wall.y - 0.06, z + 0.14), Vector3(wall.x + 0.20, wall.y - 0.02, z - 0.02), -45.0, -45.0),
			knees(Vector3(0.2, 0.4, -1.0), Vector3(0.3, 0.4, -1.0)), {"grip_l": Vector3(wall.x + 0.10, wall.y + 0.55, z + 0.30)}]))
	k(0.27, merged([body(Vector3(strake.x - 0.10, strake.y + 0.62, z + 0.10), 40.0, 0.70), spine(18.0, 18.0), tilt(4.0, 10.0), gaze(26.0, -14.0),
			feet(Vector3(strake.x + 0.04, strake.y + 0.34, z + 0.28), Vector3(strake.x - 0.02, strake.y + 0.36, z + 0.08), -20.0, -20.0),
			knees(Vector3(-0.4, 0.5, -1.0), Vector3(-0.2, 0.5, -1.0)), {"grip_l": Vector3(strake.x + 0.10, strake.y + 0.80, z + 0.40)}]))
	k(0.25, merged([body(Vector3(inner - 0.20, rim.y + 0.40, (z + step_z) * 0.5 + 0.04), 20.0, 0.70), spine(14.0, 8.0), gaze(24.0, -8.0),
			feet(Vector3(inner - 0.10, rim.y + 0.26, step_z + 0.14), Vector3(inner - 0.16, rim.y + 0.28, step_z - 0.02), -10.0, -10.0)]))
	# down into the well, knees taking it
	k(0.22, merged([body(Vector3(0.04, floor_y + 0.72, step_z + 0.04), 4.0), spine(18.0), tilt(10.0), gaze(18.0), in_well(),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)),
			hands(far_rim(step_z + 0.24, 0.10), near_rim(step_z + 0.20, 0.06)), elbows(Vector3(-1, -0.4, 0.4), Vector3(1, -0.4, 0.4))]))
	sit_back(0.40)


func _leave_hop() -> void:
	var strake: Vector2 = hull.strake
	var z := board_z
	stand_in_well()
	# a foot high over the rim onto the strake, then up to crouch on it, facing out
	k(0.32, merged([body(Vector3(inner - 0.20, floor_y + 1.00, step_z + 0.06), -40.0), spine(16.0), gaze(30.0, -10.0),
			{"ankle_r": Vector3(inner - 0.02, rim.y + 0.32, step_z + 0.04), "knee_r": Vector3(0.0, 0.8, -1.0)},
			hands(near_rim(step_z - 0.16, 0.02), near_rim(step_z + 0.40, 0.02))]))
	k(0.30, merged([body(Vector3(rim.x + 0.10, strake.y + 0.66, z), -70.0), spine(20.0), gaze(32.0),
			{"ankle_r": Vector3(strake.x - 0.04, strake.y + SOLE, z - 0.10), "foot_r": Quaternion.IDENTITY, "knee_r": Vector3(0.0, 0.5, -1.0),
			"ankle_l": Vector3(inner - 0.02, rim.y + 0.32, z + 0.08), "knee_l": Vector3(0.0, 0.8, -1.0)}]))
	k(0.30, merged([body(Vector3(strake.x + 0.02, strake.y + SOLE + 0.52, z), -90.0), spine(30.0), tilt(18.0), gaze(40.0),
			feet(Vector3(strake.x - 0.02, strake.y + SOLE, z - 0.12), Vector3(strake.x + 0.06, strake.y + SOLE + 0.01, z + 0.12)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)),
			hands(Vector3(strake.x + 0.16, strake.y + 0.03 + PALM, z - 0.28), Vector3(strake.x + 0.16, strake.y + 0.03 + PALM, z + 0.28)),
			elbows(Vector3(-1, -0.4, 0.4), Vector3(1, -0.4, 0.4))]))
	# the hop: out past the strake's edge and down
	k(0.34, merged([body(Vector3(wall.x + 0.34, wall.y + 0.20, z), -90.0), spine(8.0), tilt(4.0), gaze(36.0),
			feet(Vector3(wall.x + 0.22, wall.y - 0.32, z - 0.12), Vector3(wall.x + 0.28, wall.y - 0.36, z + 0.12), -25.0, -25.0),
			hands(Vector3(wall.x + 0.50, wall.y + 0.65, z - 0.30), Vector3(wall.x + 0.50, wall.y + 0.65, z + 0.30))]))
	land_and_walk(wall.x + 0.60, z, 0.36, 0.30)


## Orrery: up to sit on the rim facing out, legs swung up over it and in, off the rim into the well; out, sat on the rim,
## legs swung out, and a push off.
func _board_perch() -> void:
	var z := board_z
	up_to_rim(z, 0.30)
	crouch(z)
	k(0.20, merged([body(Vector3(wall.x + 0.12, rim.y - 0.08, z), 40.0), spine(24.0, 0.0, 30.0), tilt(8.0), gaze(16.0, 20.0),
			feet(Vector3(wall.x + CLEAR + 0.04, FLOOR + 0.30, z + 0.10), Vector3(wall.x + CLEAR, FLOOR + 0.34, z - 0.10), -40.0, -40.0)]))
	k(0.26, perched(z))
	# lean back on his hands, both legs up over the rim and round to the front
	k(0.34, merged([body(Vector3(rim.x + 0.04, rim.y + 0.13, z + 0.04), -50.0, 0.30), spine(-22.0), tilt(-14.0), gaze(16.0, 30.0),
			feet(Vector3(rim.x + 0.20, rim.y + 0.44, z - 0.40), Vector3(rim.x + 0.12, rim.y + 0.48, z - 0.20), 10.0, 10.0),
			knees(Vector3(0.0, 1.0, -0.4), Vector3(0.0, 1.0, -0.4)),
			hands(near_rim(z + 0.30, 0.0), near_rim(z - 0.20, 0.0))]))
	k(0.30, merged([body(Vector3(inner + 0.02, rim.y + 0.14, z + 0.06), -10.0, 0.30), spine(-6.0), tilt(-6.0), gaze(14.0),
			feet(Vector3(inner - 0.36, rim.y + 0.20, z - 0.30), Vector3(inner - 0.30, rim.y + 0.22, z - 0.14), 0.0, 0.0),
			knees(Vector3(0.0, 0.8, -1.0), Vector3(0.0, 0.8, -1.0))]))
	# off the rim, down into the well
	k(0.32, merged([body(Vector3(inner - 0.40, floor_y + 0.80, step_z + 0.10), 0.0, 0.60), spine(14.0), tilt(4.0), gaze(16.0),
			feet(Vector3(-0.06, floor_y + SOLE, step_z + 0.02), Vector3(0.20, floor_y + SOLE, step_z - 0.04)),
			knees(Vector3(-0.2, 0.2, -1.0), Vector3(0.2, 0.2, -1.0)),
			hands(near_rim(z + 0.30, 0.0), near_rim(z - 0.20, 0.0))]))
	k(0.24, merged([body(Vector3(0.02, floor_y + 0.88, step_z + 0.04), 0.0, 0.941), spine(10.0), tilt(0.0), gaze(16.0), in_well()]))
	sit_back()


func _leave_pushoff() -> void:
	var z := board_z
	stand_in_well()
	sit_and_swing_out(z)
	# push off with both hands and drop
	k(0.28, merged([body(Vector3(wall.x + 0.26, rim.y - 0.32, z), -90.0), spine(6.0), tilt(4.0), gaze(34.0),
			feet(Vector3(wall.x + 0.36, FLOOR + 0.30, z - 0.13), Vector3(wall.x + 0.40, FLOOR + 0.30, z + 0.13), -20.0, -20.0),
			hands(near_rim(z + 0.30, 0.10) + Vector3(0.24, 0.0, 0.0), near_rim(z - 0.30, 0.10) + Vector3(0.24, 0.0, 0.0))]))
	land_and_walk(wall.x + 0.46, z, 0.34, 0.24)


## Kiln: a foot walked up the hull's wall and a haul onto the deck, a knee, a step down; out, sat on the deck, turned to
## face the hull and climbed down it.
func _board_haul() -> void:
	var z := board_z
	up_to_rim(z, 0.26)
	# the trailing foot planted on the hull's wall, the body hanging back off the arms
	k(0.36, merged([body(Vector3(stand_x() + 0.06, FLOOR + 0.84, z), 90.0), spine(10.0), tilt(-4.0), gaze(30.0),
			{"ankle_l": Vector3(wall.x + 0.13, FLOOR + 0.80, z + 0.10), "foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(50.0)),
			"knee_l": Vector3(0.0, 0.4, -1.0)}]))
	# haul: up off that foot, hips over the deck's edge
	k(0.42, merged([body(Vector3(rim.x + 0.42, rim.y + 0.26, z), 90.0), spine(42.0), tilt(16.0), gaze(30.0),
			{"ankle_l": Vector3(wall.x + 0.16, rim.y + 0.14, z + 0.12), "foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(10.0)),
			"ankle_r": Vector3(wall.x + CLEAR, rim.y - 0.50, z - 0.12), "foot_r": Quaternion(Vector3.RIGHT, deg_to_rad(-35.0))}]))
	knee_on_rim(z, false, 0.34)
	step_down_in(z, false)
	sit_back(0.48)


func _leave_climb_down() -> void:
	var z := board_z
	stand_in_well()
	sit_and_swing_out(z)
	# roll over onto the belly to face the hull, legs going down outside
	k(0.52, merged([body(Vector3(wall.x + 0.14, rim.y + 0.12, z), 90.0), spine(58.0), tilt(22.0), gaze(40.0),
			dangling(Vector3(wall.x + 0.14, rim.y + 0.12, z), -30.0), hands(near_rim(z + 0.28, 0.0), near_rim(z - 0.28, 0.0)),
			elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	# lower away on the arms, a foot finding a hold high on the wall, the other hanging
	k(0.42, merged([body(Vector3(wall.x + 0.32, rim.y - 0.28, z), 90.0), spine(14.0), tilt(4.0), gaze(30.0),
			{"ankle_l": Vector3(wall.x + 0.15, wall.y - 0.18, z + 0.12), "foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(50.0)),
			"knee_l": Vector3(-0.3, -1.0, 0.3), "ankle_r": Vector3(wall.x + 0.34, rim.y - 1.04, z - 0.12), "knee_r": Vector3(0.3, -0.4, -1.0)}]))
	# down off the hold onto the floor, arms long
	k(0.36, merged([body(Vector3(wall.x + 0.36, FLOOR + 0.82, z), 90.0), spine(16.0), gaze(24.0),
			feet(Vector3(wall.x + 0.40, FLOOR + SOLE, z + 0.13), Vector3(wall.x + 0.38, FLOOR + SOLE, z - 0.13)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0))]))
	k(0.34, merged([standing(stand_x(), z, 90.0), spine(10.0), gaze(16.0), hands(near_rim(z + 0.28, 0.0), near_rim(z - 0.28, 0.0))]))
	k(0.30, standing(stand_x() + 0.06, z, 90.0))
	walk_to(gate.x, gate.z, -90.0)


## Vesper: a foot up onto the deck, up to stand on it, down into the well and slid in; out, side-saddle off the rim.
func _board_f1() -> void:
	var z := board_z
	up_to_rim(z, 0.28)
	crouch(z, 0.26)
	spring(z)
	# up on his arms, the right foot swung up onto the deck, knee to the chest
	k(0.30, merged([body(Vector3(rim.x + 0.34, rim.y + 0.20, z), 90.0), spine(34.0), tilt(18.0), gaze(30.0),
			{"ankle_r": Vector3(rim.x + 0.10, rim.y + SOLE, z - 0.12), "foot_r": Quaternion.IDENTITY, "knee_r": Vector3(0.2, 0.6, -1.0)}]))
	# step up onto it, the other foot beside it: crouched on the deck
	k(0.36, merged([body(Vector3(rim.x + 0.26, rim.y + 0.42, z), 90.0), spine(34.0), tilt(16.0), gaze(34.0),
			{"ankle_l": Vector3(wall.x + CLEAR, rim.y - 0.24, z + 0.14), "foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(-30.0))}]))
	k(0.30, merged([body(Vector3(rim.x + 0.10, rim.y + SOLE + 0.56, z + 0.02), 80.0), spine(26.0), tilt(16.0), gaze(32.0),
			feet(Vector3(rim.x + 0.14, rim.y + SOLE, z + 0.14), Vector3(rim.x + 0.12, rim.y + SOLE, z - 0.12)),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0))]))
	# stand up on the deck, arms out; then down into the well, the left leg first
	k(0.30, merged([body(Vector3(rim.x + 0.08, rim.y + SOLE + 0.84, z + 0.04), 66.0), spine(6.0), tilt(0.0), gaze(30.0, -10.0),
			hands(Vector3(rim.x - 0.06, rim.y + 1.02, z + 0.46), Vector3(rim.x + 0.12, rim.y + 1.02, z - 0.40)),
			elbows(Vector3(-1, -0.3, 0.3), Vector3(1, -0.3, 0.3))]))
	k(0.30, merged([body(Vector3(inner - 0.02, rim.y + 0.70, (z + step_z) * 0.5), 40.0), spine(16.0), gaze(30.0, -8.0),
			{"ankle_l": Vector3(inner - 0.12, rim.y + 0.26, step_z + 0.10), "knee_l": Vector3(0.0, 0.8, -1.0),
			"foot_l": Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))}]))
	k(0.30, merged([body(Vector3(inner - 0.40, floor_y + 1.00, step_z + 0.06), 18.0), spine(14.0), gaze(24.0),
			{"ankle_l": Vector3(-0.12, floor_y + SOLE, step_z + 0.04), "foot_l": Quaternion.IDENTITY, "knee_l": Vector3(-0.2, 0.2, -1.0),
			"ankle_r": Vector3(inner - 0.06, rim.y + 0.28, step_z), "knee_r": Vector3(0.0, 0.8, -1.0)}]))
	k(0.26, merged([body(Vector3(0.02, floor_y + 0.90, step_z + 0.02), 0.0), spine(8.0), tilt(0.0), gaze(18.0), in_well(),
			knees(Vector3(-0.2, 0.0, -1.0), Vector3(0.2, 0.0, -1.0)), hang(Vector3(0.02, floor_y + 0.90, step_z), 0.0)]))
	# the racing driver's slide: hands on the rims, down, legs straight out along the floor
	sit_back(0.50)


func _leave_f1() -> void:
	var z := board_z
	stand_in_well()
	sit_and_swing_out(z)
	# off it side-saddle, out and down, one hand on the rim
	k(0.30, merged([body(Vector3(wall.x + 0.24, rim.y - 0.30, z - 0.06), -76.0), spine(6.0), tilt(4.0), gaze(34.0),
			feet(Vector3(wall.x + 0.34, FLOOR + 0.28, z - 0.18), Vector3(wall.x + 0.40, FLOOR + 0.26, z + 0.06), -20.0, -20.0),
			hands(near_rim(z + 0.20, 0.10) + Vector3(0.22, 0, 0), Vector3(wall.x + 0.60, rim.y + 0.30, z - 0.40))]))
	land_and_walk(wall.x + 0.48, z - 0.04, 0.32, 0.24)


## Basilisk: belly over the deck under the raised hatch, a knee, down into the well; out, sat on the deck, turned to the
## hull, hung off straight arms and dropped.
func _board_crawl() -> void:
	var z := board_z
	up_to_rim(z, 0.26)
	crouch(z)
	spring(z)
	# belly over the deck, low under the hatch, hands walking in to its inside edge
	k(0.30, merged([body(Vector3(rim.x + 0.40, rim.y + 0.24, z), 90.0), spine(58.0), tilt(26.0), gaze(50.0),
			dangling(Vector3(rim.x + 0.40, rim.y + 0.24, z))]))
	k(0.34, merged([body(Vector3(rim.x + 0.26, rim.y + 0.30, z + 0.04), 90.0), spine(64.0), tilt(28.0), gaze(56.0),
			hands(Vector3(inner + 0.02, rim.y + 0.03 + PALM, z + 0.28), Vector3(inner + 0.02, rim.y + 0.03 + PALM, z - 0.16)),
			elbows(Vector3(-0.8, -0.3, 0.6), Vector3(0.8, -0.3, 0.6))]))
	knee_on_rim(z, false, 0.34)
	step_down_in(z, false)
	sit_back()


func _leave_hang() -> void:
	var z := board_z
	stand_in_well()
	sit_and_swing_out(z)
	# turn over onto the belly to face the hull
	k(0.58, merged([body(Vector3(wall.x + 0.16, rim.y + 0.12, z), 90.0), spine(58.0), tilt(22.0), gaze(44.0),
			dangling(Vector3(wall.x + 0.16, rim.y + 0.12, z), -30.0), hands(near_rim(z + 0.18, 0.0), near_rim(z - 0.18, 0.0)),
			elbows(Vector3(-1.0, 0.1, 0.4), Vector3(1.0, 0.1, 0.4))]))
	# a full hang off straight arms, then let go
	k(0.42, merged([body(Vector3(wall.x + 0.22, rim.y - 0.66, z), 90.0), spine(4.0), tilt(0.0), gaze(30.0),
			feet(Vector3(wall.x + CLEAR, FLOOR + 0.30, z + 0.12), Vector3(wall.x + CLEAR, FLOOR + 0.30, z - 0.12), -35.0, -35.0),
			knees(Vector3(-0.1, 0.0, -1.0), Vector3(0.1, 0.0, -1.0))]))
	k(0.26, merged([body(Vector3(wall.x + 0.30, FLOOR + 0.941 - 0.30, z), 90.0), spine(16.0), tilt(10.0), gaze(30.0),
			feet(Vector3(wall.x + 0.34, FLOOR + SOLE, z + 0.13), Vector3(wall.x + 0.34, FLOOR + SOLE, z - 0.13)),
			hands(Vector3(wall.x + 0.12, FLOOR + 1.05, z + 0.30), Vector3(wall.x + 0.12, FLOOR + 1.05, z - 0.30))]))
	k(0.36, standing(wall.x + 0.40, z, 90.0))
	walk_to(gate.x, gate.z, -90.0)
