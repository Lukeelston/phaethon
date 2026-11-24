## The Basilisk's gun (Luke: "design a new craft that has a switch that deploys a turret that fires at a
## reticle that points at where the headset is looking"): a twin-emitter turret in a sponson on the
## starboard shoulder of the cab, and a sight ball at that sponson's nose. Both are slaved to the pilot's
## gaze; view/gunnery.gd finds what the gaze is on, lays the gun and fires it. This is the mount itself.
##
## Its parts are authored about their own pivots (tools/art_pilot_fleet.py: GunHatch, GunRing, GunCradle,
## GunCoils, SightBall, SightLens), in the cab's frame (+X starboard, +Y up, +Z aft). This node stands at
## the cab's origin, a child of whichever hull is drawn (the flat view's pod, or the cockpit's own hull).
##
## Deploying, from stowed (the gun lying forward in its bed, the hatch shut):
##   0.00 .. 0.55 s   the hatch swings open outboard on its knuckles
##   0.35 .. 1.05 s   the ring rises on its post, out of the bed
##   1.05 s ..        it is free: it traverses and elevates after the aim at its own rates
## Stowing runs that back, once the gun has come home (laid forward, level) to fit its bed.
##   var t := Turret.new(); hull.add_child(t); t.build(fleet)
##   t.step(delta, want_out, aim_local)     aim_local: where to point, cab frame (null: hold / go home)
##   t.ready_to_fire(), t.muzzles(), t.bore()  (global)
class_name Turret
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")

# The mount, as tools/art_pilot_fleet.py builds it (cab frame).
const SPONSON_X := 1.13
const SPONSON_TOP := 0.19
const HATCH_HINGE := Vector3(SPONSON_X + 0.215, SPONSON_TOP, 0.0)   # its axis runs fore and aft (Z)
const GUN_PIVOT := Vector3(SPONSON_X, SPONSON_TOP - 0.035, -0.45)    # the ring's top centre, stowed (sunk in its socket)
const TRUNNION_UP := 0.07
const MUZZLES := [Vector3(-0.065, 0.0, -0.93), Vector3(0.065, 0.0, -0.93)]   # cradle-local
const SIGHT := Vector3(SPONSON_X, SPONSON_TOP + 0.065, -1.63)
const SIGHT_R := 0.08
# How it moves.
const LIFT := 0.30                         # m the ring rises on its post
const HATCH_OPEN := deg_to_rad(150.0)      # the hatch's swing, outboard and down
const T_HATCH := Vector2(0.0, 0.55)        # s of the deploy: the hatch opens over this ...
const T_LIFT := Vector2(0.35, 1.05)        # ... the ring rises over this
const T_FREE := 1.05                       # ... and from here it lays itself
const TRAVERSE := Vector2(deg_to_rad(-75.0), deg_to_rad(175.0))   # yaw from dead ahead, + to starboard (over the cab's port side it would sweep the canopy)
const ELEVATE := Vector2(deg_to_rad(-12.0), deg_to_rad(40.0))     # pitch, + up (higher, the receiver's tail meets the ring)
const RATE := Vector2(deg_to_rad(240.0), deg_to_rad(160.0))       # rad/s: traverse, elevation (a head turns faster than this; the gun follows)
const ACCEL := Vector2(deg_to_rad(1400.0), deg_to_rad(1000.0))    # rad/s^2: it winds up to those rates
const ON_TARGET := deg_to_rad(1.2)         # laid this near the aim, it may fire
const HOME := deg_to_rad(1.0)              # ... and this near dead ahead, level, it may stow
const SIGHT_RATE := deg_to_rad(720.0)      # the sight ball keeps up with a glance
# The cab's own bulk, for the interlock (cab frame): its canopy and nose, and the sight ball.
const KEEP_OUT := [AABB(Vector3(-0.98, -0.5, -1.0), Vector3(1.96, 1.25, 2.6)), AABB(Vector3(-0.82, -0.6, -2.5), Vector3(1.64, 0.8, 1.5))]
const COIL_COOL := Color(0.18, 0.08, 0.03)
const COIL_HOT := Color(1.0, 0.45, 0.12)

var hatch: Node3D          # the hinge (the hatch's mesh is local to it)
var ring: Node3D           # the traversing ring: yaw about its Y
var cradle: Node3D         # the elevating mass: pitch about its X
var sight: Node3D          # the sight ball: yaw and pitch
var coil_mat: StandardMaterial3D
var lens_mat: StandardMaterial3D
var t := 0.0               # s along the deploy (0 stowed .. T_FREE out)
var deployed := false      # asked out (the switch); `t` follows it
var yaw := 0.0             # the gun's lay, rad (tests read these)
var pitch := 0.0
var _yaw_v := 0.0
var _pitch_v := 0.0
var sight_yaw := 0.0
var sight_pitch := 0.0
var heat := 0.0            # the coils' glow after a shot, 0..1
var power := 1.0           # the battery bus (the start-up): the sight's window and the coils go dark without it
var limited := false       # the aim lies outside what it can reach (it holds at its stop)


func build(fleet) -> void:
	name = "Turret"
	hatch = Node3D.new()
	hatch.name = "GunHatchHinge"
	hatch.position = HATCH_HINGE
	add_child(hatch)
	_fit(hatch, fleet, &"GunHatch")
	ring = Node3D.new()
	ring.name = "Ring"
	ring.position = GUN_PIVOT
	add_child(ring)
	_fit(ring, fleet, &"GunRing")
	cradle = Node3D.new()
	cradle.name = "Cradle"
	cradle.position = Vector3(0, TRUNNION_UP, 0)
	ring.add_child(cradle)
	_fit(cradle, fleet, &"GunCradle")
	var coils := _fit(cradle, fleet, &"GunCoils")
	coil_mat = StandardMaterial3D.new()
	coil_mat.albedo_color = Color(0.32, 0.30, 0.28)
	coil_mat.metallic = 0.6
	coil_mat.roughness = 0.35
	coil_mat.emission_enabled = true
	coil_mat.emission = COIL_COOL
	coils.material_override = coil_mat
	sight = Node3D.new()
	sight.name = "Sight"
	sight.position = SIGHT
	add_child(sight)
	_fit(sight, fleet, &"SightBall")
	var lens := _fit(sight, fleet, &"SightLens")
	lens_mat = StandardMaterial3D.new()
	lens_mat.albedo_color = Color(0.05, 0.03, 0.02)
	lens_mat.metallic = 0.2
	lens_mat.roughness = 0.08
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.35, 0.08)
	lens.material_override = lens_mat
	_pose()


func _fit(parent: Node3D, fleet, key: StringName) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = String(key)
	mi.mesh = fleet.part(key) if fleet != null else Kit.box(Vector3(0.1, 0.1, 0.1))
	mi.add_to_group("exterior")      # (outside the cabin: the cockpit's fitting checks leave it be)
	parent.add_child(mi)
	return mi


## The deploy's three parts, 0..1, at time `at` along it.
static func phases(at: float) -> Vector3:
	return Vector3(clampf((at - T_HATCH.x) / (T_HATCH.y - T_HATCH.x), 0.0, 1.0),
		clampf((at - T_LIFT.x) / (T_LIFT.y - T_LIFT.x), 0.0, 1.0), 1.0 if at >= T_FREE else 0.0)


## Yaw and pitch (rad) that lay a bore from the trunnion along `dir` (cab frame).
static func lay_for(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	return Vector2(atan2(d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))


## Is the lay inside the mount's stops?
static func reachable(lay: Vector2) -> bool:
	return lay.x >= TRAVERSE.x and lay.x <= TRAVERSE.y and lay.y >= ELEVATE.x and lay.y <= ELEVATE.y


## The trunnion where it is now (cab frame).
func trunnion() -> Vector3:
	return GUN_PIVOT + Vector3(0, LIFT * smoothstep(0.0, 1.0, phases(t).y) + TRUNNION_UP, 0)


func is_out() -> bool:
	return t >= T_FREE


func is_stowed() -> bool:
	return t <= 0.0


## Each frame. want_out: the switch. aim: where the gun should look (a point, cab frame), or null.
## sight_aim: where the gaze is (a direction, cab frame), or null: the sight ball follows it.
func step(delta: float, want_out: bool, aim: Variant, sight_aim: Variant = null) -> void:
	deployed = want_out
	if want_out:
		t = minf(T_FREE, t + delta)
	elif t >= T_FREE and (absf(yaw) > HOME or absf(pitch) > HOME):
		pass                       # (it comes home before it starts down)
	else:
		t = maxf(0.0, t - delta)
	var goal := Vector2.ZERO
	limited = false
	if is_out() and want_out and aim != null:
		var lay := lay_for((aim as Vector3) - trunnion())
		limited = not reachable(lay)
		goal = Vector2(clampf(lay.x, TRAVERSE.x, TRAVERSE.y), clampf(lay.y, ELEVATE.x, ELEVATE.y))
	elif is_out() and want_out:
		goal = Vector2(yaw, pitch)  # (no aim: it holds its lay)
	if is_out():
		var y := _slew(yaw, _yaw_v, goal.x, RATE.x, ACCEL.x, delta)
		yaw = y.x
		_yaw_v = y.y
		var p := _slew(pitch, _pitch_v, goal.y, RATE.y, ACCEL.y, delta)
		pitch = p.x
		_pitch_v = p.y
	else:
		yaw = 0.0
		pitch = 0.0
		_yaw_v = 0.0
		_pitch_v = 0.0
	# The sight ball: it follows the gaze whenever there is power, and rests looking ahead.
	var s_goal := Vector2.ZERO
	if sight_aim != null and power > 0.5:
		s_goal = lay_for(sight_aim)
		s_goal.x = clampf(s_goal.x, deg_to_rad(-100.0), deg_to_rad(170.0))
		s_goal.y = clampf(s_goal.y, deg_to_rad(-30.0), deg_to_rad(60.0))
	sight_yaw = move_toward(sight_yaw, s_goal.x, SIGHT_RATE * delta)
	sight_pitch = move_toward(sight_pitch, s_goal.y, SIGHT_RATE * delta)
	heat = maxf(0.0, heat - delta * 2.2)
	_pose()


## An eased slew toward `goal`: winds up at `accel`, no faster than `rate`, and settles without
## overshooting. Returns (angle, rate).
static func _slew(at: float, v: float, goal: float, rate: float, accel: float, delta: float) -> Vector2:
	var err := goal - at
	var stop := sqrt(2.0 * accel * absf(err))      # the fastest it can go and still stop at the goal
	var want := signf(err) * minf(rate, stop)
	v = move_toward(v, want, accel * delta)
	var next := at + v * delta
	if signf(goal - next) != signf(err):          # (passed it: settle)
		return Vector2(goal, 0.0)
	return Vector2(next, v)


func _pose() -> void:
	var ph := phases(t)
	hatch.rotation = Vector3(0, 0, -HATCH_OPEN * smoothstep(0.0, 1.0, ph.x))
	ring.position = GUN_PIVOT + Vector3(0, LIFT * smoothstep(0.0, 1.0, ph.y), 0)
	ring.rotation = Vector3(0, -yaw, 0)
	cradle.rotation = Vector3(pitch, 0, 0)
	sight.rotation = Vector3(sight_pitch, -sight_yaw, 0)      # (Node3D's default order, YXZ: pitched, then turned)
	coil_mat.emission = COIL_COOL.lerp(COIL_HOT, heat) * (0.25 + 0.75 * power)
	coil_mat.emission_energy_multiplier = 0.6 + 5.0 * heat
	lens_mat.emission_energy_multiplier = (0.15 + (1.6 if deployed else 0.5)) * power


## Out, asked out, and its aim inside its stops? (gunnery.gd also wants the bore on the aim.)
func ready_to_fire() -> bool:
	return is_out() and deployed and not limited


## The muzzles where they are (global).
func muzzles() -> Array:
	var out := []
	for m: Vector3 in MUZZLES:
		out.append(cradle.global_transform * m)
	return out


## The bore's line (global): out of the barrels.
func bore() -> Vector3:
	return -cradle.global_transform.basis.z.normalized()


## Would a shot along `dir` (cab frame) from the trunnion clear the cab itself: its canopy, nose
## and the sight ball? (Its own engines are gunnery.gd's: they are not on this mount.)
func clear_of_cab(dir: Vector3) -> bool:
	var from := trunnion()
	var d := dir.normalized()
	var muzzle := from + d * 0.95       # (the barrels lie clear of everything at their stops)
	for box: AABB in KEEP_OUT:
		if _segment_hits_box(muzzle, muzzle + d * 6.0, box):
			return false
	var c := SIGHT - muzzle
	var along := c.dot(d)
	if along > 0.0 and (c - d * along).length() < SIGHT_R + 0.03:
		return false
	return true


static func _segment_hits_box(a: Vector3, b: Vector3, box: AABB) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for k in 3:
		var lo: float = box.position[k]
		var hi: float = box.end[k]
		if absf(d[k]) < 1e-9:
			if a[k] < lo or a[k] > hi:
				return false
			continue
		var ta: float = (lo - a[k]) / d[k]
		var tb: float = (hi - a[k]) / d[k]
		if ta > tb:
			var sw := ta
			ta = tb
			tb = sw
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true
