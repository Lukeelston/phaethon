## The Orrery's three survey orbs as a WeaponMount (view/weapons/weapon_mount.gd), on Codex's arms (view/arms/orrery_arms.gd:
## three orbs in cradles under doors in its bonnet, raised by her deploy from their seats to their FORMATION over it; once
## deployed, gameplay moves them: `orbs`, and `docks()` their seats). It fires for itself (own_fire): the fire control
## (view/gunnery.gd) finds what the gaze is on (it is aimed: the gaze sight brackets a hostile there, as far as a send can
## go) and hands this the trigger each frame (fire); this keeps the orbs. Its figures are the craft's weapon row
## (sim/pilot_craft.gd TRAITS[..].weapon: orbs, reach, sendReach, orbV, hits, restS, orbitR, orbitS). Each orb is:
##   docked   in its cradle: her deploy moves it (on SAFE, docked by the mount, it is held in its seat while she stows)
##   orbit    circling the craft in the cab's own frame (it rides the cab's pitch and bank): orbitR m out from the cab's up
##            axis, ORBIT_UP m over its origin, one turn in orbitS, the orbs evenly apart. ORBIT_UP is above her highest
##            FORMATION and, from the seat's eye, above the windscreen's outline (view/canopy.gd's oblong screen: the
##            forward view of the road) all the way round (tests/test_orbs.gd check_orbit)
##   out      flying at a threat in the sims' frame, at orbV plus the craft's own speed, toward where it will meet it (the
##            fire control's _lead_at at that speed), turning at once; within HIT_R of it over a frame (the nearest the two
##            came, each on a straight line) it strikes it: g.damage(t, hits, at, quiet), seen and heard as a hit
##   back     flying home to its place in the orbit as the craft moves, at the same speed toward where the place will be;
##            and near the cab gliding in the cab's frame at NEAR_V, by way of its gate (over its FORMATION at the orbit's
##            height, so no glide crosses the cabin): from its cradle, by her FORMATION and its gate, to its place when the
##            GUN brings the arms out; on SAFE from its place, by its gate and her FORMATION, down into its seat
## What it does:
##   on its own   an orb in orbit and rested takes the nearest of the raid's threats (g.threats(): its raiders and flyers)
##            within reach of the craft's present place (a flyer in the round, a raider over the ground) that no other orb
##            is out at; after its strike it flies back, and rests restS once it is in its place
##   sent     on the trigger's press, every orb in orbit (rested or not) goes at the gaze's target (g.aim_car, a hostile
##            within sendReach of the craft's present place); with none there, nothing. An orb out or coming back is not
##            redirected. A send that sends any is one shot (g.shots: the cockpit's one tick in the hand that fires)
##   gone     an orb whose target is gone before it arrives (shot, fled, the raid ended or reset), or has run beyond
##            sendReach of the craft, turns back. A jump of the craft (a restart, a respawn: it moved JUMP_M more in a
##            frame than its speed takes it) puts every orb away back in its place at once, its target dropped
##   SAFE     every orb comes home and docks (into docks()'s places), and only then does the deploy fall below 1: her doors
##            close over the orbs held in their seats. The arms wait for the last: the longest, an orb 2,200 m out with the
##            craft running from it at any speed, closes at orbV, about 3.2 s, and its glide home 0.5 s more
##   commuters    never looked at: no target, no strike, no spark, no charge
##   drawn    her orbs where they are; one away (out, or flying home) has the fire control's streak behind it (the bolts'
##            ribbon and glow: view/gunnery.gd ribbon), STREAK_W wide at the least, as long as it has flown up to a bolt's,
##            in the orbs' mint: nothing bright fills the view, nothing moves the camera or the cockpit. The bay's glow
##            (heat) is the share of its orbs away
##   felt     one tick on a send (the fire control's shot count): nothing on a strike
##   sounds   a strike (audio/raid_sounds.gd orb_strike, at the mount: g.play_own; the brief's place for a weapon's own, so
##            the pilot hears each orb strike home, up to 2.2 km off), unheard; a send: the turret's shot, lower (kept
##            from the stand-ins)
## Its arms are fitted on the hull the pilot sees (view/fleet_airframe.gd ensure_arms: the hull last dressed, the VR seat's
## own, else the craft's pod) the first time the GUN asks them out: a flight with Raids off that never arms them builds
## none of them, nor this one's streaks. With Raids on they are fitted at load, stowed (prepare).
##   weapon = OrbMount.new(craft)      craft: the CraftModel (view/craft_model.gd): its view, sim and fleet airframe
class_name OrbMount
extends "res://view/weapons/weapon_mount.gd"

const GunneryScript := preload("res://view/gunnery.gd")
const MissileMountScript := preload("res://view/weapons/missile_mount.gd")      # (its _passed: the nearest two came)
const PilotCraft := preload("res://sim/pilot_craft.gd")
const OrreryArms := preload("res://view/arms/orrery_arms.gd")
const DEPLOY_S := 1.0             # s from stowed to out: the doors open and the orbs rise to her FORMATION (the fixed guns' figure)
const ORBIT_UP := 1.2             # m over the cab's origin the orbit stands: over her highest FORMATION (0.905), 0.36 over the
                                  # roof's top, and from the eye 12 to 16 degrees up (the windscreen's top edge is 6 ahead)
const NEAR_V := 12.0              # m/s an orb glides at in the cab's frame (its place goes round at 8.4 m/s at 4 m in 3 s)
const HIT_R := 8.0                # m: an orb this near its target over a frame strikes it (the missiles' figure)
const JUMP_M := 100.0             # m the craft moved in a frame beyond what its speed takes it: a jump (a restart, a respawn)
const ORB_R := 0.071              # m: an orb's radius (her ball, 0.101 x ORB_SCALE): where its streak begins
const STREAK_W := 0.06            # m: a streak's least width (the missiles'; a bolt's is 0.22)
const STREAK_COL := Color(0.6, 2.2, 1.9)      # the orbs' lens's mint, made a glow (a bolt's is 2.6, 1.5, 0.55)
const HEAT_EASE := 2.0            # the bay's glow moves this much a second toward the share of its orbs away
const SEND_PITCH := 0.8           # a send: the turret's shot, lower (kept)


## One orb's state (the mount's `orbs`, one each of the arms' orbs).
class Orb:
	var state := "docked"         # "docked" | "orbit" | "out" | "back"
	var p := Vector3.ZERO         # the sims' frame: where it is while away (out, or back and not near)
	var v := Vector3.ZERO         # ... its velocity there this frame (its streak's line)
	var q := Vector3.ZERO         # the cab's frame (the arms'): where it is while it glides near
	var near := false             # back: gliding in the cab's frame (else flying home in the sims' frame)
	var home := "orbit"           # back: to its place in the orbit, or "dock": into its seat
	var legs: Array = []          # ... the glide's places still to reach (the cab's frame); none left: its place in the orbit
	var target = null             # out: the threat it goes at (a Car or a flyer)
	var rest := 0.0               # s before it may take a threat on its own (in orbit)
	var flown := 0.0              # m it has flown since it left its place (its streak's length)


var craft                         # the CraftModel (view/craft_model.gd)
var arms = null                   # Codex's arms (view/arms/orrery_arms.gd), fitted at the first arming
var t := 0.0                      # 0 stowed .. 1 out (the arms' deploy)
var count := 3                    # the row's figures
var reach := 900.0
var send_reach := 2200.0
var orb_v := 700.0
var hits := 3
var rest_s := 1.2
var orbit_r := 4.0
var orbit_s := 3.0
var orbs: Array = []              # Orb, one each of the arms' orbs (made with them)
var spin := 0.0                   # rad: the orbit's turn now
var sends := 0                    # sends that sent an orb this flight (tests read these)
var strikes := 0                  # strikes landed
var streaks: MultiMesh = null     # the orbs' streaks (made with the arms' first frame out: _build_drawing)
var drawn: Array = []             # ... those drawn this frame: [the orb (render frame), the streak's middle, its way, length,
                                  # width] (tests read it: headless, a batch keeps none)
var cost_ms := 0.0                # what the last frame's step and fire took (tests read it)
var _asked := false               # asked out this frame (the switch, with power)
var _shown := -1.0                # the deploy the arms were last set to
var _held := false                # the trigger held last frame
var _seated := false              # docked on SAFE: held in their seats while her deploy stows (and comes out again)
var _was_at := Vector3.INF        # the craft's place last frame (the sims' frame): a jump is told from it
var _step_us := 0


func _init(model) -> void:
	craft = model
	var row: Dictionary = model.view.sim.traits.get("weapon", {})
	count = maxi(1, int(row.get("orbs", count)))
	reach = float(row.get("reach", reach))
	send_reach = float(row.get("sendReach", send_reach))
	orb_v = maxf(1.0, float(row.get("orbV", orb_v)))
	hits = int(row.get("hits", hits))
	rest_s = float(row.get("restS", rest_s))
	orbit_r = float(row.get("orbitR", orbit_r))
	orbit_s = maxf(0.01, float(row.get("orbitS", orbit_s)))


func step(delta: float, want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_asked = want_out
	if want_out and arms == null:
		_fit_arms()
	var home := true      # (every orb docked: only then may the arms stow)
	for o: Orb in orbs:
		home = home and o.state == "docked"
	t = move_toward(t, 1.0 if want_out or not home else 0.0, delta / DEPLOY_S)
	if arms != null and t != _shown:
		_shown = t
		arms.set_deploy(t)
		if _seated:
			_seat_orbs()      # (her deploy moves them; docked on SAFE, they stay in their seats)
	if t <= 0.0:
		_seated = false
	_step_us = Time.get_ticks_usec() - t0


## Raids on (its fire control made at load, dormant; Ruling D): the arms fitted now, stowed, so the first arming fits none
## in its frame. With Raids off they stay unbuilt until the GUN asks them out.
func prepare() -> void:
	if arms == null:
		_fit_arms()


## Codex's arms on the hull the pilot sees (the hull last dressed: view/fleet_airframe.gd ensure_arms), an Orb for each orb.
func _fit_arms() -> void:
	arms = craft.fleet.ensure_arms() if craft.fleet != null else null
	_shown = -1.0
	orbs.clear()
	if arms != null:
		for k in mini(count, (arms.orbs as Array).size()):
			orbs.append(Orb.new())


## The hull the pilot sees, which the arms are fitted on: the VR seat's own, else the craft's pod.
func _hull() -> Node3D:
	var fleet = craft.fleet
	if fleet != null and is_instance_valid(fleet.drawn_hull):
		return fleet.drawn_hull
	return craft.pod


func is_out() -> bool:
	return t >= 1.0


func ready_to_fire() -> bool:
	return is_out() and _asked


func deploy_t() -> float:
	return t


## The orbs' lenses (global).
func muzzles() -> Array:
	var out := []
	if arms != null:
		for m: Transform3D in arms.muzzles():
			out.append(m.origin)
	return out


## The cab (its arms), or the hull before they are fitted.
func origin() -> Vector3:
	return (arms as Node3D).global_position if arms != null else _hull().global_position


## The hull: the fire control's players (a send's and a strike's sounds) hang there, where the arms are fitted.
func node() -> Node3D:
	return _hull()


func heat() -> float:
	return arms.heat if arms != null else 0.0


func own_fire() -> bool:
	return true


func own_sounds() -> Array:
	return ["orb_strike"]


## Orb k's place in the orbit now (the cab's frame: the arms').
func place(k: int) -> Vector3:
	var a := spin + TAU * float(k) / float(maxi(1, orbs.size()))
	return Vector3(orbit_r * cos(a), ORBIT_UP, -orbit_r * sin(a))


## Orb k's gate (the cab's frame): over her FORMATION, at the orbit's height. Every glide between the orbit and the bonnet
## goes by it: level over the cabin, then straight down in front of the screen.
func _gate(k: int) -> Vector3:
	var f: Vector3 = OrreryArms.FORMATION[k]
	return Vector3(f.x, maxf(ORBIT_UP, f.y), f.z)


# --- each frame, from the fire control -------------------------------------------------------------------------

func fire(g, delta: float, pulling: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if arms == null:
		cost_ms = _step_us / 1000.0
		return
	if streaks == null:
		_build_drawing(g)
	spin = fmod(spin + delta * TAU / orbit_s, TAU)
	var P = g.view.sim.pod
	var here := Vector3(P.x, P.y, P.z)
	var vel := Vector3(P.vx, P.vy, P.vz)
	var speed := orb_v + vel.length()      # (out and back: orbV plus the craft's own speed)
	var frame: Transform3D = (arms as Node3D).global_transform      # (the cab's frame, the render frame's)
	if _was_at != Vector3.INF and here.distance_to(_was_at) > vel.length() * delta * 2.0 + JUMP_M:
		_recall()      # (a restart, a respawn: every orb away back in its place at once)
	_was_at = here
	for k in orbs.size():
		var o: Orb = orbs[k]
		match o.state:
			"docked":
				if t >= 1.0 and _asked:
					_launch(o, k)
			"orbit":
				o.rest = maxf(0.0, o.rest - delta)
				if not _asked:
					_go_home(o, k, "dock")
			"out":
				if not _asked:
					_turn_back(o)      # (SAFE: home at once)
				else:
					_fly_out(g, o, here, speed, delta)
			"back":
				if o.near:
					if o.home != ("orbit" if _asked else "dock"):
						_go_home(o, k, "orbit" if _asked else "dock")
					_glide(o, k, delta)
				else:
					_fly_back(g, o, k, frame, vel, speed, delta)
	if ready_to_fire():
		if pulling and not _held:
			_send(g, here, frame)
		_on_their_own(g, here, frame)
	_held = g.trigger or g.hold_fire
	var away := 0
	for o: Orb in orbs:
		away += int(o.state == "out" or o.state == "back")
	arms.heat = move_toward(arms.heat, float(away) / float(maxi(1, orbs.size())), delta * HEAT_EASE)
	_draw(g)
	cost_ms = (_step_us + Time.get_ticks_usec() - t0) / 1000.0


## A docked orb leaves its cradle (the arms out, asked out): up by her FORMATION and its gate to its place.
func _launch(o: Orb, k: int) -> void:
	o.state = "back"
	o.near = true
	o.home = "orbit"
	o.q = (arms.orbs[k] as Node3D).position
	o.legs = [OrreryArms.FORMATION[k], _gate(k)]
	o.rest = 0.0
	o.target = null
	_seated = false


## Orb k (in orbit, or gliding near) glides home in the cab's frame: to its place ("orbit"), or into its seat ("dock").
## From its place or on its way out to it, by its gate; on its way up from the bonnet or down to it, straight back.
func _go_home(o: Orb, k: int, home: String) -> void:
	var rising := o.state == "back" and o.near and o.home == "orbit" and not o.legs.is_empty()      # (up from the bonnet, short of its gate)
	var sinking := o.state == "back" and o.near and o.home == "dock" and o.legs.size() < 3          # (past its gate, on its way down)
	if o.state == "orbit":
		o.q = place(k)
	o.state = "back"
	o.near = true
	o.home = home
	o.target = null
	if home == "dock":
		o.legs = [OrreryArms.FORMATION[k], OrreryArms.SEATS[k]] if rising else [_gate(k), OrreryArms.FORMATION[k], OrreryArms.SEATS[k]]
	else:
		o.legs = [_gate(k)] if sinking else []


## A glide's frame: on toward its next place at NEAR_V (its place in the orbit, moving, once none is left). There: in orbit,
## or docked in its seat.
func _glide(o: Orb, k: int, delta: float) -> void:
	var step := NEAR_V * delta
	while step > 0.0:
		var to: Vector3 = o.legs[0] if not o.legs.is_empty() else place(k)
		var d := o.q.distance_to(to)
		if d > step:
			o.q += (to - o.q) / d * step
			return
		o.q = to
		step -= d
		if o.legs.is_empty():
			o.state = "orbit"
			o.near = false
			return
		o.legs.pop_front()
		if o.legs.is_empty() and o.home == "dock":
			o.state = "docked"
			o.near = false
			if _all_docked():
				_seated = true      # (home, all of them: her deploy may stow, the orbs held in their seats)
			return


func _all_docked() -> bool:
	for o: Orb in orbs:
		if o.state != "docked":
			return false
	return true


## Every docked orb in its seat (her deploy has them elsewhere at this point of it).
func _seat_orbs() -> void:
	for k in orbs.size():
		if (orbs[k] as Orb).state == "docked":
			(arms.orbs[k] as Node3D).position = OrreryArms.SEATS[k]


## Out at a threat: on toward where it will meet it, and the strike within HIT_R of it. Its target gone, or run beyond
## sendReach of the craft: it turns back.
func _fly_out(g, o: Orb, here: Vector3, speed: float, delta: float) -> void:
	var c = o.target
	if not g.alive(c) or _beyond(c, here, send_reach):
		_turn_back(o)
		return
	var flyer := GunneryScript._is_flyer(c)
	var at := Vector3(c.x, c.y, c.z if flyer else g._middle(c))
	var w := Vector3(c.hx * c.v, c.hy * c.v, c.vz if flyer else 0.0)
	var meet: Vector3 = g._lead_at(c, at.z, o.p, speed)
	var line := meet - o.p
	if line.length_squared() > 1e-8:
		o.v = line.normalized() * speed
	o.p += o.v * delta
	o.flown += speed * delta
	if MissileMountScript._passed(o.p, o.v, at, w, delta, HIT_R * HIT_R):
		_turn_back(o)
		strikes += 1
		g.damage(c, hits, at, true)      # (quiet: a commuter would never be touched)
		g.play_own("gun", "orb_strike", g.to_render(at))      # (the strike: at the mount; its stand-in, at the strike)


## Home again from out: back to its place in the orbit, its target dropped.
func _turn_back(o: Orb) -> void:
	o.state = "back"
	o.near = false
	o.home = "orbit"
	o.target = null


## Flying home in the sims' frame: toward where its place will be (the place moves with the craft), at `speed`. There
## within a frame: in its place, rested restS from now; or, on SAFE, gliding on from it into its seat.
func _fly_back(g, o: Orb, k: int, frame: Transform3D, vel: Vector3, speed: float, delta: float) -> void:
	var at: Vector3 = g.to_sim(frame * place(k))
	var meet := at + vel * (o.p.distance_to(at) / speed)
	meet = at + vel * (o.p.distance_to(meet) / speed)
	var line := meet - o.p
	var step := speed * delta
	if line.length() <= step:
		if _asked:
			o.state = "orbit"
			o.rest = rest_s
		else:
			o.state = "orbit"
			_go_home(o, k, "dock")
		return
	o.v = line.normalized() * speed
	o.p += o.v * delta
	o.flown += step


## Every orb away (out, or flying home) back in its place at once: in orbit (rested restS), or on SAFE gliding on from it.
func _recall() -> void:
	var n := 0
	for k in orbs.size():
		var o: Orb = orbs[k]
		if o.state == "out" or (o.state == "back" and not o.near):
			n += 1
			o.state = "orbit"
			o.target = null
			o.rest = rest_s
			if not _asked:
				_go_home(o, k, "dock")
	if n > 0:
		print("GUN: %s orbs recalled: %d (the craft was put down elsewhere)" % [_name(), n])


## Is threat c beyond `most` m of the craft's place (the sims' frame)? A vehicle over the ground, a flyer in the round.
static func _beyond(c, here: Vector3, most: float) -> bool:
	return _dist(c, here) > most


static func _dist(c, here: Vector3) -> float:
	var dx: float = c.x - here.x
	var dy: float = c.y - here.y
	var dz: float = c.z - here.z if GunneryScript._is_flyer(c) else 0.0
	return sqrt(dx * dx + dy * dy + dz * dz)


## The trigger's press: every orb in orbit (rested or not) at the gaze's target, a hostile within sendReach; else none.
func _send(g, here: Vector3, frame: Transform3D) -> void:
	var c = g.aim_car
	if c == null or not c.hostile or not g.alive(c) or _beyond(c, here, send_reach):
		return
	var n := 0
	for k in orbs.size():
		var o: Orb = orbs[k]
		if o.state == "orbit":
			_go(g, o, k, c, frame)
			n += 1
	if n == 0:
		return
	sends += 1
	g.shots += 1      # (one shot: the cockpit's one tick in the hand that fires)
	g.play("gun", "fire", Vector3.INF, SEND_PITCH)      # (the send: the turret's shot, lower: kept)
	print("GUN: %s orbs sent: %d at a %s %.0f m off" % [_name(), n, String(c.kind) if GunneryScript._is_flyer(c) else "raider", _dist(c, here)])


## Each orb in orbit and rested takes the nearest threat within reach that no other orb is out at.
func _on_their_own(g, here: Vector3, frame: Transform3D) -> void:
	var free := []
	for k in orbs.size():
		var o: Orb = orbs[k]
		if o.state == "orbit" and o.rest <= 0.0:
			free.append(k)
	if free.is_empty():
		return
	var taken := []
	for o: Orb in orbs:
		if o.state == "out":
			taken.append(o.target)
	var near := []      # [m from the craft, the threat]
	for c in g.threats():      # (the raid's raiders and flyers: never a commuter)
		if taken.has(c) or not g.alive(c):
			continue
		var d := _dist(c, here)
		if d <= reach:
			near.append([d, c])
	if near.is_empty():
		return
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(free.size(), near.size()):
		_go(g, orbs[free[i]], free[i], near[i][1], frame)


## Orb k leaves its place for threat c.
func _go(g, o: Orb, k: int, c, frame: Transform3D) -> void:
	o.state = "out"
	o.target = c
	o.p = g.to_sim(frame * place(k))
	o.v = Vector3.ZERO
	o.flown = 0.0


func _name() -> String:
	var id: String = craft.view.sim.P.vehicle
	return PilotCraft.NAMES.get(id, id.capitalize())


# --- drawing ----------------------------------------------------------------------------------------------------

## The streaks' batch, under the fire control (drawn about the floating origin as its own are).
func _build_drawing(g) -> void:
	streaks = g._batch("OrbStreaks", GunneryScript._bolt_mesh(), GunneryScript._glow_material(true), maxi(1, orbs.size()))


## Her orbs where they are, and a streak behind each one away.
func _draw(g) -> void:
	var eye: Vector3 = g.view.cam.global_position
	var n := 0
	drawn.clear()
	for k in orbs.size():
		var o: Orb = orbs[k]
		var orb: Node3D = arms.orbs[k]
		if o.state == "orbit":
			orb.position = place(k)
		elif o.state == "docked":
			if t >= 1.0:
				orb.position = OrreryArms.SEATS[k]      # (docked on SAFE, the doors still open: in its seat; below 1, her deploy or _seat_orbs)
		elif o.state == "back" and o.near:
			orb.position = o.q
		elif o.state == "out" or o.state == "back":
			var at: Vector3 = g.to_render(o.p)
			orb.global_position = at
			var dir := Vector3(o.v.x, o.v.z, -o.v.y)      # (the sims' (x, y, up) to the render frame's (x, up, -y))
			var speed := dir.length()
			if speed < 1e-3:
				continue
			dir /= speed
			var streak := minf(GunneryScript.STREAK, o.flown + 0.3)
			var mid := at - dir * (ORB_R + streak * 0.5)
			var width := maxf(STREAK_W, eye.distance_to(mid) * GunneryScript.BOLT_WIDTH)
			streaks.set_instance_transform(n, GunneryScript.ribbon(mid, dir, streak, width, eye))
			streaks.set_instance_color(n, STREAK_COL)
			drawn.append([at, mid, dir, streak, width])
			n += 1
	streaks.visible_instance_count = n
