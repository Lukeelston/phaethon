## The Shrike's look-to-lock missiles as a WeaponMount (view/weapons/weapon_mount.gd), on Codex's arms
## (view/arms/shrike_arms.gd: two cassettes that roll up out of its cheeks, two darts on each). It fires for itself
## (own_fire): the fire control (view/gunnery.gd) finds what the gaze is on and builds its lock there, and hands this the
## trigger each frame (fire); this keeps the locks, the rack and the missiles in flight. Its figures are the craft's
## weapon row (sim/pilot_craft.gd TRAITS[..].weapon: locks, missileV, turnDeg, hits, reach, reloadS, lifeS; lockS is the
## fire control's).
##   locks    a hostile (a raider or a flyer) held under the gaze sight until the fire control's lock reaches 1 joins
##            `locks` (at most the row's `locks`, none twice; a commuter never). A lock is dropped when its target is gone
##            (g.alive false: shot, fled, or the raid's end), is beyond the row's reach of the craft, or the GUN goes to
##            SAFE. Each is bracketed: the gaze sight's own quad (view/gun_sight.gdshader), closed, red; and so is each
##            target a missile in flight is homing on, until it is struck or gone (the volley's targets keep theirs).
##   fire     on the trigger's press (not while it is held), the rack loaded and a lock held: one missile for each lock,
##            each from the next loaded seat (port and starboard in turn: ORDER), its round hidden on its cassette
##            (set_loaded); the locks are emptied and the whole rack reloads together (reloadS: none leaves till it is
##            full again; locks may be taken meanwhile). The reload's clock runs whatever the switch does: thrown to
##            SAFE and back, the rack is not refilled.
##   flight   in the sims' frame, from the seat's mouth along its rail at missileV plus the craft's own speed along that
##            line (kept: it neither gains nor loses with the craft after); each frame it turns toward its target's lead
##            (the fire control's _lead_at, at the missile's own speed) by turnDeg a second at the most. Within HIT_R of
##            its target over the frame (the nearest the two came, each on a straight line) it strikes: g.damage(target,
##            hits). A commuter it passes as near is struck instead (g.damage(c, 0): sparks, never a knock-out) and it is
##            spent. Its target gone, it flies on straight; at lifeS it fizzes out (a spark). No ground and no cover:
##            it is the pilot's weapon, not a threat's.
##   drawn    the missiles in flight as one batch of Codex's dart (missile_mesh), each with the bolts' streak behind it
##            (view/gunnery.gd's ribbon and glow), STREAK_W wide at the least (a bolt's least is 0.22 m), so where it
##            leaves the rail a metre or so from the eye it is a thin line: nothing bright fills the view, and nothing
##            moves the camera or the cockpit.
##   sounds   stand-ins for Task 9, which owns them: a launch and a strike are turret sounds re-pitched (g.play).
## Its arms are fitted on the hull the pilot sees (the VR seat's own, else the craft's pod; view/shrike_airframe.gd
## ensure_arms) the first time the GUN asks them out: a flight with Raids off that never arms them builds none of them,
## nor this one's batches and brackets. With Raids on they are fitted at load, stowed (prepare).
##   weapon = MissileMount.new(craft)      craft: the CraftModel (view/craft_model.gd): its view, sim and pod
class_name MissileMount
extends "res://view/weapons/weapon_mount.gd"

const Shrike := preload("res://view/shrike_airframe.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const Traffic := preload("res://view/network_traffic.gd")      # (its Car, typed: the commuters' look reads each one's members)
const DEPLOY_S := 1.0             # s from stowed to out: the cheeks open and the cassettes roll up (the fixed guns' figure)
const HEAT_FADE := 2.2            # the cassettes' charge windows fade this much a second (the fixed guns' barrels) ...
const LAUNCH_HEAT := 0.35         # ... and each launch warms them this much (a bolt's)
const SEATS := 4                  # the arms' seats: two on each cassette, port then starboard (their slots and muzzles)
const ORDER := [0, 2, 1, 3]       # the seats a volley takes in turn: port, starboard, port, starboard
const HIT_R := 8.0                # m: a missile this near its target, or a commuter on its way, over a frame strikes it
const MAX_FLYING := 8             # missiles in flight at once (two volleys: one lives lifeS, longer than the reload)
const DART_TAIL := 0.27           # m from a dart's middle to its tail, where its streak begins (Codex's dart: 0.52 m long)
const STREAK_W := 0.06            # m: a streak's least width (a bolt's is 0.22: this one leaves a rail a metre from the eye)
const STREAK_COL := Color(2.6, 1.5, 0.55)      # a bolt's (view/gunnery.gd _draw)
const LAUNCH_PITCH := 0.55        # (stand-ins, Task 9's to replace: the turret's shot, lower, for a launch ...)
const STRIKE_PITCH := 0.7         # (... and its impact, lower, for a strike)

var craft                         # the CraftModel (view/craft_model.gd)
var arms = null                   # Codex's arms (view/arms/shrike_arms.gd), fitted at the first arming
var t := 0.0                      # 0 stowed .. 1 out
var max_locks := 4                # the row's figures
var missile_v := 900.0
var turn := deg_to_rad(120.0)     # rad/s
var hits := 40
var reach := 3000.0
var reload_s := 5.0
var life_s := 6.0
var locks: Array = []             # the targets locked (a Car or a flyer), in the order taken
var loaded := SEATS               # rounds in the rack
var reload := 0.0                 # s of the reload left (0: loaded)
var missiles: Array = []          # in flight: {p, v, target, t} (the sims' frame; target null once it is gone)
var dart_batch: MultiMesh = null  # the missiles drawn (made with the arms' first frame out), ...
var streak_batch: MultiMesh = null    # ... their streaks, ...
var brackets: Array = []          # ... and a bracket for each lock and each target homed on (the gaze sight's quad)
var cost_ms := 0.0                # what the last frame's step and fire took (tests read it)
var _asked := false               # asked out this frame (the switch, with power)
var _shown := -1.0                # the deploy the arms were last set to
var _rack := []                   # each seat loaded or not
var _held := false                # the trigger held last frame
var _step_us := 0


func _init(model) -> void:
	craft = model
	var row: Dictionary = model.view.sim.traits.get("weapon", {})
	max_locks = int(row.get("locks", max_locks))
	missile_v = float(row.get("missileV", missile_v))
	turn = deg_to_rad(float(row.get("turnDeg", 120.0)))
	hits = int(row.get("hits", hits))
	reach = float(row.get("reach", reach))
	reload_s = float(row.get("reloadS", reload_s))
	life_s = float(row.get("lifeS", life_s))
	_rack.resize(SEATS)
	_rack.fill(true)


func step(delta: float, want_out: bool, _aim_render: Variant, _gaze_dir_render: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	_asked = want_out
	if not want_out:
		locks.clear()      # (SAFE: every lock dropped)
	elif arms == null:
		_fit_arms()
	t = move_toward(t, 1.0 if want_out else 0.0, delta / DEPLOY_S)
	if arms != null:
		if t != _shown:
			_shown = t
			arms.set_deploy(t)
		if arms.heat > 0.0:
			arms.heat = maxf(0.0, arms.heat - delta * HEAT_FADE)
	if reload > 0.0:
		reload -= delta
		if reload <= 1e-6:
			reload = 0.0
			_refill()
	_step_us = Time.get_ticks_usec() - t0


## Raids on (its fire control made at load, dormant; Ruling D): the arms fitted now, stowed, and their first deploy's
## cut of the hull made too (set a hair out and straight back, before anything is drawn), so the first arming costs no
## frame. Fitting them at the first arming measured 26 ms, cold, and that first deploy 7 ms more (headless,
## tests/probe_missile_arming.gd). With Raids off they stay unbuilt until the GUN asks them out.
func prepare() -> void:
	if arms != null:
		return
	_fit_arms()
	arms.set_deploy(1e-4)
	arms.set_deploy(0.0)
	_shown = 0.0


## Codex's arms on the hull the pilot sees, each seat shown as the rack has it.
func _fit_arms() -> void:
	arms = Shrike.ensure_arms(_hull())
	for slot in SEATS:
		arms.set_loaded(slot, bool(_rack[slot]))
	_shown = -1.0


## The hull the pilot sees, which the arms are fitted on: the VR seat's own (its shell's PodHull: the craft's pod is
## hidden there), else the craft's pod.
func _hull() -> Node3D:
	var shell = craft.view.get("shell") if craft.view != null else null
	if shell is Node3D and (shell as Node3D).has_node("PodHull"):
		return (shell as Node3D).get_node("PodHull")
	return craft.pod


## The rack full again: every round shown on its cassette.
func _refill() -> void:
	_rack.fill(true)
	loaded = SEATS
	if arms != null:
		for slot in SEATS:
			arms.set_loaded(slot, true)
	print("GUN: Shrike RS missiles reloaded")


func is_out() -> bool:
	return t >= 1.0


func ready_to_fire() -> bool:
	return is_out() and _asked


func deploy_t() -> float:
	return t


## Each seat's mouth (global).
func muzzles() -> Array:
	var out := []
	if arms != null:
		for m: Transform3D in arms.muzzles():
			out.append(m.origin)
	return out


## Between the mouths (global), or the hull before the arms are fitted.
func origin() -> Vector3:
	var mouths := muzzles()
	if mouths.is_empty():
		return _hull().global_position
	var at := Vector3.ZERO
	for m: Vector3 in mouths:
		at += m
	return at / mouths.size()


## The charge windows' glow.
func add_heat(amount: float) -> void:
	if arms != null:
		arms.heat = minf(1.0, arms.heat + amount)


## The hull: the fire control's players (the launches) hang there, where the arms are fitted.
func node() -> Node3D:
	return _hull()


func heat() -> float:
	return arms.heat if arms != null else 0.0


func own_fire() -> bool:
	return true


## "RELOAD" while the rack reloads (nothing leaves, though locks may be taken), else "LOCK n" while it holds locks.
func status() -> String:
	if reload > 0.0:
		return "RELOAD"
	if not locks.is_empty():
		return "LOCK %d" % locks.size()
	return ""


# --- each frame, from the fire control -------------------------------------------------------------------------

func fire(g, delta: float, pulling: bool) -> void:
	var t0 := Time.get_ticks_usec()
	if dart_batch == null and arms != null:
		_build_drawing(g)
	_keep_locks(g)
	_fly(g, delta)
	if pulling and not _held and reload <= 0.0 and not locks.is_empty() and loaded >= locks.size():
		_volley(g)
	_held = g.trigger or g.hold_fire
	if dart_batch != null:
		_draw(g)
	cost_ms = (_step_us + Time.get_ticks_usec() - t0) / 1000.0


## Locks dropped (gone, or beyond reach), and one taken: the hostile under the gaze sight once its lock is whole.
func _keep_locks(g) -> void:
	var P = g.view.sim.pod
	for k in range(locks.size() - 1, -1, -1):
		if not g.alive(locks[k]) or _beyond(locks[k], P):
			locks.remove_at(k)
	var c = g.aim_car
	if c == null or not ready_to_fire() or g.lock < 1.0 - 1e-6 or not c.hostile or locks.size() >= max_locks or locks.has(c):
		return
	if g.alive(c) and not _beyond(c, P):
		locks.append(c)


## Is target c beyond reach of the craft (pod P)? A vehicle in the plane, a flyer in the round.
func _beyond(c, P) -> bool:
	var dx: float = c.x - P.x
	var dy: float = c.y - P.y
	var dz: float = c.z - P.z if GunneryScript._is_flyer(c) else 0.0
	return dx * dx + dy * dy + dz * dz > reach * reach


## One missile for each lock, each from the next loaded seat; the locks emptied, the whole rack reloading.
func _volley(g) -> void:
	var mouths: Array = arms.muzzles()
	var P = g.view.sim.pod
	var way := Vector3(P.vx, P.vy, P.vz)
	var away := 0
	for c in locks:
		var slot := _next_seat(mouths.size())
		if slot < 0:
			break      # (art with fewer seats than its locks: no more leave, and the locks are emptied all the same)
		_rack[slot] = false
		loaded -= 1
		arms.set_loaded(slot, false)
		var m: Transform3D = mouths[slot]
		var line: Vector3 = GunneryScript.dir_to_sim(-m.basis.z).normalized()
		if missiles.size() >= MAX_FLYING:
			_fizz(g, missiles.pop_front())
		missiles.append({"p": g.to_sim(m.origin), "v": line * (missile_v + maxf(0.0, way.dot(line))), "target": c, "t": 0.0})
		g.shots += 1
		add_heat(LAUNCH_HEAT)
		g.play("gun", "fire", Vector3.INF, LAUNCH_PITCH)      # (a stand-in for the launch's own sound: Task 9's)
		away += 1
	locks.clear()
	reload = reload_s
	print("GUN: Shrike RS missiles fired: %d away" % away)


## The next loaded seat in ORDER (among the first `seats`), or -1.
func _next_seat(seats: int) -> int:
	for slot: int in ORDER:
		if slot < seats and _rack[slot]:
			return slot
	return -1


## The missiles in flight, a frame: each turns toward its target's lead, flies on, and strikes it, or a commuter on its
## way, or fizzes out at lifeS.
func _fly(g, delta: float) -> void:
	if missiles.is_empty():
		return
	var r2 := HIT_R * HIT_R
	for k in range(missiles.size() - 1, -1, -1):      # (each turns and flies on; on its target it strikes)
		var m: Dictionary = missiles[k]
		var c = m.target
		if c != null and not g.alive(c):
			c = null
			m.target = null      # (its target gone: it flies on straight)
		var v: Vector3 = m.v
		var p: Vector3 = m.p
		var q := Vector3.ZERO
		var w := Vector3.ZERO
		if c != null:
			var flyer := GunneryScript._is_flyer(c)
			q = Vector3(c.x, c.y, c.z if flyer else g._middle(c))
			w = Vector3(c.hx * c.v, c.hy * c.v, c.vz if flyer else 0.0)
			v = _turned(v, g._lead_at(c, q.z, p, v.length()) - p, turn * delta)
		p += v * delta
		m.p = p
		m.v = v
		m.t = float(m.t) + delta
		if c != null and _passed(p, v, q, w, delta, r2):
			missiles.remove_at(k)
			g.damage(c, hits, q)
			g.play("world", "impact", g.to_render(q), STRIKE_PITCH)      # (a stand-in for the strike's own sound: Task 9's)
	_commuters_met(g, delta, r2)
	for k in range(missiles.size() - 1, -1, -1):      # (and at lifeS it fizzes out)
		if float(missiles[k].t) >= life_s:
			_fizz(g, missiles[k])
			missiles.remove_at(k)


## Velocity v turned toward `want` by `most` rad at the most, its speed kept.
static func _turned(v: Vector3, want: Vector3, most: float) -> Vector3:
	var speed := v.length()
	if speed < 1e-6 or want.length_squared() < 1e-6:
		return v
	var from := v / speed
	var to := want.normalized()
	var angle := from.angle_to(to)
	if angle <= most:
		return to * speed
	var axis := from.cross(to)
	if axis.length_squared() < 1e-12:      # (straight behind it: any way round)
		axis = from.cross(Vector3(0.0, 0.0, 1.0) if absf(from.z) < 0.9 else Vector3(1.0, 0.0, 0.0))
	return from.rotated(axis.normalized(), most) * speed


## Did a missile now at p going v pass within sqrt(r2) of a point now at q going w over the last `delta` s (the nearest
## the two came, each on a straight line)? Its target's test, and a commuter's (view/raid_flyers.gd's for its shots).
static func _passed(p: Vector3, v: Vector3, q: Vector3, w: Vector3, delta: float, r2: float) -> bool:
	var r := p - q
	var u := v - w
	var uu := u.length_squared()
	var back := clampf(r.dot(u) / uu, 0.0, delta) if uu > 1.0e-9 else 0.0      # (s ago they were nearest)
	return (r - u * back).length_squared() <= r2


## Commuters met on the way: each missile that passed within sqrt(r2) of a commuter's middle this frame (not a raider,
## not the craft's own stand-in nor the racer) strikes it (g.damage(c, 0): sparks off it, never a knock-out) and is spent.
## Traffic's vehicles are looked over once a frame for all of them: one outside the box round every missile's step is
## passed over at once, one inside it is tried against each missile whose own box it is in.
func _commuters_met(g, delta: float, r2: float) -> void:
	var traffic = g.view.traffic_net
	var n := missiles.size()
	if traffic == null or n == 0:
		return
	var ps := PackedVector3Array()
	var vs := PackedVector3Array()
	var box := PackedFloat32Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for m: Dictionary in missiles:
		var p: Vector3 = m.p
		var b: float = (m.v as Vector3).length() * delta + HIT_R + 12.0      # (its step this frame, the strike's reach, a vehicle's own)
		ps.append(p)
		vs.append(m.v)
		box.append(b)
		lo = Vector2(minf(lo.x, p.x - b), minf(lo.y, p.y - b))
		hi = Vector2(maxf(hi.x, p.x + b), maxf(hi.y, p.y + b))
	var met := []
	met.resize(n)
	var left := n
	var racer = traffic.racer
	for c: Traffic.Car in traffic.cars:
		var x := c.x
		if x < lo.x or x > hi.x:
			continue
		var y := c.y
		if y < lo.y or y > hi.y or c.hostile or c.craft or c == racer:
			continue
		for k in n:
			if met[k] != null or absf(x - ps[k].x) > box[k] or absf(y - ps[k].y) > box[k]:
				continue
			if _passed(ps[k], vs[k], Vector3(x, y, traffic.body_height(c)), Vector3(c.hx * c.v, c.hy * c.v, 0.0), delta, r2):
				met[k] = c
				left -= 1
		if left == 0:
			break
	for k in range(n - 1, -1, -1):
		var c = met[k]
		if c == null:
			continue
		missiles.remove_at(k)
		var at := Vector3(c.x, c.y, traffic.body_height(c))
		g.damage(c, 0, at)      # (a strike: sparks off it, never a knock-out)
		g.play("world", "impact", g.to_render(at), STRIKE_PITCH)      # (the strike's stand-in, as on a target)


## A missile spent at its life's end: it fizzes out where it is (a bolt's spark at the end of its reach).
func _fizz(g, m: Dictionary) -> void:
	g.add_fx(m.p, "spark", 0.25, 6.0)


# --- drawing ----------------------------------------------------------------------------------------------------

## The batches and brackets, under the fire control (drawn about the floating origin as its own are).
func _build_drawing(g) -> void:
	var darts := MultiMeshInstance3D.new()
	darts.name = "MissileDarts"
	dart_batch = MultiMesh.new()
	dart_batch.transform_format = MultiMesh.TRANSFORM_3D
	dart_batch.mesh = arms.missile_mesh()      # (Codex's dart, its own finish)
	dart_batch.instance_count = MAX_FLYING
	dart_batch.visible_instance_count = 0
	darts.multimesh = dart_batch
	darts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	darts.custom_aabb = AABB(Vector3(-30000, -30000, -30000), Vector3(60000, 60000, 60000))
	g.add_child(darts)
	streak_batch = g._batch("MissileStreaks", GunneryScript._bolt_mesh(), GunneryScript._glow_material(true), MAX_FLYING)
	for k in max_locks + MAX_FLYING:
		var b: MeshInstance3D = g._sight_quad("MissileLock%d" % (k + 1))
		var mat := b.material_override as ShaderMaterial
		mat.set_shader_parameter("state", 1)      # (red brackets round a vehicle, ...)
		mat.set_shader_parameter("lock", 1.0)     # (... closed: locked)
		brackets.append(b)


## The missiles in flight, their streaks, and a bracket on each lock and on each target they home on.
func _draw(g) -> void:
	var eye: Vector3 = g.view.cam.global_position
	var n := 0
	for m: Dictionary in missiles:
		var v: Vector3 = m.v
		var dir := Vector3(v.x, v.z, -v.y)      # (the sims' (x, y, up) to the render frame's (x, up, -y))
		var speed := dir.length()
		if speed < 1e-3:
			continue
		dir /= speed
		var at: Vector3 = g.to_render(m.p)
		dart_batch.set_instance_transform(n, Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT), at))
		# Its streak behind it: the bolts' ribbon, as long as it has flown (up to theirs), turned to face the eye about its line.
		var streak := minf(GunneryScript.STREAK, speed * float(m.t) + 0.3)
		var mid := at - dir * (DART_TAIL + streak * 0.5)
		var width := maxf(STREAK_W, eye.distance_to(mid) * GunneryScript.BOLT_WIDTH)
		streak_batch.set_instance_transform(n, GunneryScript.ribbon(mid, dir, streak, width, eye))
		streak_batch.set_instance_color(n, STREAK_COL)
		n += 1
	dart_batch.visible_instance_count = n
	streak_batch.visible_instance_count = n
	var marked := locks.duplicate()
	for m: Dictionary in missiles:
		if m.target != null and not marked.has(m.target):
			marked.append(m.target)
	for k in brackets.size():
		var b: MeshInstance3D = brackets[k]
		b.visible = k < marked.size()
		if not b.visible:
			continue
		var c = marked[k]
		var at: Vector3 = g.to_render(Vector3(c.x, c.y, c.z if GunneryScript._is_flyer(c) else g._middle(c)))
		var size := maxf(2.0 * eye.distance_to(at) * tan(deg_to_rad(GunneryScript.SIGHT_DEG) * 0.5), g.bracket_of(c))
		b.global_transform = Transform3D(Basis().scaled(Vector3.ONE * size), at)
		(b.material_override as ShaderMaterial).set_shader_parameter("power", g.power)
