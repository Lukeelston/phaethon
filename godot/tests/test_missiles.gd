## The Shrike's look-to-lock missiles (view/weapons/missile_mount.gd on Codex's arms, view/arms/shrike_arms.gd; fired for
## themselves through view/gunnery.gd's own-fire hook). In the VR seat on the Network (XR off), the Shrike on a straight
## at 1,500 mph. Raids are pinned off, so the GUN's first arming makes the fire control and the arms; once armed the
## world is held still and the fire control stepped on its own: the gaze is laid on each target by hand (as
## tests/test_turret.gd does), every target is put where the test wants it and moved by hand, and a director of the
## test's own is put in (never updated), so its raiders are a raid's pack and its kills are counted (kills_by):
##   check_table            weapon_of(SHRIKE) is "missiles", its weapon row is the brief's, and it is armed
##   check_lazy             with the GUN never armed: no Arms node on either hull, no fire control (Raids off); armed: the
##                          fire control is made, firing for itself through the missile mount, the Arms on the hull the
##                          seat sees (not the hidden pod), out in 1 s. The first arming's frame is told (Ruling D)
##   check_lock_builds      the gaze on a raider: no lock at 0.30 s, locks == [it] by 0.35 s; on a commuter 2 s: none;
##                          four raiders in turn (a glance off between): four locks, LOCK 4; a fifth is not added
##   check_volley           no lock: the trigger fires nothing; held while a lock is taken: nothing (a press, not a hold);
##                          pressed with three locks: three missiles, one tick sent to the left hand that frame (at once,
##                          the hand held for the volley's three), three rounds hidden,
##                          locks empty, RELOAD; drawn (three darts, three streaks, each raider still bracketed while a
##                          missile homes on it); held down, no more leave
##   check_homing_kills     each reaches its raider (1.5 km off, crossing at 400 m/s) within lifeS: three kills, the
##                          director's kills_by.raider 3, no bracket left
##   check_reload           at 4.9 s after the volley, a lock held and the trigger pressed, nothing leaves; at 5.0 s the
##                          rack holds four and the four rounds are shown
##   check_gunship_takes_three   a 120 HP flyer takes 40 a missile: alive after two, shot down by the third
##   check_target_gone_mid_flight   (Review Focus 1) its target shot by other means while the missile flies: it flies on
##                          straight and fizzes at lifeS, kills unchanged by it, a lock held on it dropped; the raid ended
##                          (the director's reset) with a raider's and a drone's missile in flight and a lock held: both
##                          fly on straight and fizz at lifeS, no kill, the lock dropped
##   check_commuter_in_the_way   a commuter on the line to its raider: struck (commuter_strikes one more), still in
##                          traffic, the missile spent, its raider untouched
##   check_safe_mid_use     (Review Focus 3) SAFE 2 s into a reload, GUN again at 3 s: 2 s of it left (not 0, not 5),
##                          the rack not refilled; the lock held when SAFE was thrown is gone
##   check_cost             four missiles homing on four flyers for 600 frames, traffic's most (220 vehicles) about: the
##                          mount's own time a frame (its step and fire), mean and worst, told; the mean held under COST_MS
##   check_flat_range       the flat view on the Range (no seat, no traffic, no raid): armed, the fire control is made and
##                          the arms fitted on the craft's own pod, out in about a second; the trigger with no lock fires
##                          nothing
##   check_raids_on_arming  Raids on (Ruling D: the first arming above measured over 5 ms): the fire control made at load,
##                          dormant, and the arms fitted then on the seat's hull, stowed (not drawn, the hull its own, four
##                          rounds); the first arming's frame told; armed, the same arms come out and the hull is cut
##   check_volley_ticks     (Ruling S) on that seat's own frames (vr_cockpit.gd _process), three shots in a frame: a tick
##                          sent to the left hand that frame and one at the first frame at or after each of 0.08 and 0.16 s,
##                          every one sent at once (no delay: the engine ignores a pulse's delay under OpenXR); and three
##                          shots in a frame, then a restart (Y's tap) the next: nothing sent after it
## Run with --fixed-fps 120: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_missiles.gd -- --mute
## Prints MISSILES PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const View := preload("res://view/craft_view.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Craft := preload("res://view/craft_model.gd")
const Sim := preload("res://sim/craft_sim.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const Raids := preload("res://view/network_raids.gd")
const Flyers := preload("res://view/raid_flyers.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const ROW := {"locks": 4, "lockS": 0.35, "missileV": 900.0, "turnDeg": 120.0, "hits": 40, "reach": 3000.0, "reloadS": 5.0, "lifeS": 6.0}
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const MPH := 0.44704
const SPEED := 1500.0 * MPH     # m/s
const STRAIGHT := 1600.0        # m of road ahead that must run straight and level
const FAR := 1500.0             # m: the volley's raiders ...
const CROSS_V := 400.0          # ... crossing at this
const TICK_GAP := 0.08          # s between a volley's ticks in the hand (vr_cockpit.gd _gun_controls)
const COST_MS := 0.15           # the mount's own mean a frame, four missiles homing, at the most
const SECTIONS := 14
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var movers: Array = []          # [target, its velocity (sims' frame)]: moved by hand each frame of the still world
var _next_id := 992000
var _way := 1
var _fleet: Array = []          # traffic's own vehicles when the GUN was armed (put back for check_cost)
var _director = null


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + label)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var raids_were := [Raids.pinned, Raids.enabled]
	var chase_were := [Chase.pinned, Chase.enabled]
	Raids.pinned = true      # (off: the GUN's first arming makes the fire control; the test puts each target where it wants it)
	Raids.enabled = false
	Chase.pinned = true
	Chase.enabled = false
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = OS.get_user_data_dir().path_join("test_missiles_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	check_table()
	sections += 1
	var v = await _seat(Pilot.SHRIKE)
	var g = check_lazy(v)
	if g != null:
		sections += 1
		check_lock_builds(v, g)
		sections += 1
		var volley: Array = check_volley(v, g)
		sections += 1
		if not volley.is_empty():
			check_homing_kills(v, g, volley)
			sections += 1
			check_reload(v, g)
			sections += 1
		check_gunship_takes_three(v, g)
		sections += 1
		check_target_gone_mid_flight(v, g)
		sections += 1
		check_commuter_in_the_way(v, g)
		sections += 1
		check_safe_mid_use(v, g)
		sections += 1
		check_cost(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	await check_flat_range()
	sections += 1
	Raids.enabled = true
	v = await _seat(Pilot.SHRIKE)
	check_raids_on_arming(v)
	sections += 1
	check_volley_ticks(v)
	sections += 1
	v.queue_free()
	await process_frame
	Seat.vehicle_override = ""
	Raids.pinned = raids_were[0]
	Raids.enabled = raids_were[1]
	Chase.pinned = chase_were[0]
	Chase.enabled = chase_were[1]
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	check("every section ran to its end (%d of %d)" % [sections, SECTIONS], sections == SECTIONS)
	print("MISSILES %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


# --- the flight ------------------------------------------------------------------------------------------

## The VR seat in `id` on the Network, on a straight at 1,500 mph, a few frames flown.
func _seat(id: String):
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	_on_a_straight(v)
	for i in 10:
		_hold_speed(v)
		v._process(DT)
	_hold_speed(v)
	return v


## Put the craft at the start of a straight, level stretch of its road (STRAIGHT m of it ahead).
func _on_a_straight(v) -> void:
	var sim = v.sim
	var span := int(ceil(STRAIGHT / float(Sim.NET_STEP)))
	var roads := [int(sim.pod.path)]
	for r in sim.roads.size():
		if r != roads[0]:
			roads.append(r)
	for r: int in roads:
		var R = sim.roads[r]
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 200:
			continue
		var from := clampi(int(sim.pod.hint), 100, R.N - span - 100) if r == roads[0] else 100
		for i in range(from, R.N - span - 100, 6):
			var th := atan2(R.ty[i], R.tx[i])
			var h0: float = sim.road_h(r, float(i))
			var ok := true
			for k in range(i, i + span + 1, 2):
				if absf(angle_difference(th, atan2(R.ty[k], R.tx[k]))) > deg_to_rad(0.15) or absf(sim.road_h(r, float(k)) - h0) > 1.0 \
						or sim.in_pressure(r, k):
					ok = false
					break
			if ok:
				sim.respawn_on(r, i, 1)
				_way = 1
				print("  on road %s at sample %d: %.1f km straight and level ahead, %.0f m wide" % [R.name, i, STRAIGHT / 1000.0, R.w[i]])
				return
	print("  (no straight found: flying where it starts)")


## All three bodies at 1,500 mph along the road under the pod, level.
func _hold_speed(v) -> void:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * _way * SPEED
		b.vy = R.ty[i] * _way * SPEED
		b.vz = 0.0


## The road's way at the pod (a unit vector in the sims' plane) and its half width there.
func _road(v) -> Array:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	return [Vector2(R.tx[i], R.ty[i]) * _way, float(R.w[i]) * 0.5]


## A point `ahead` m on along the road from the pod and `left` m to its left (the sims' plane).
func _ahead(v, ahead: float, left: float) -> Vector2:
	var way: Vector2 = _road(v)[0]
	return Vector2(v.sim.pod.x, v.sim.pod.y) + way * ahead + Vector2(-way.y, way.x) * left


## A vehicle at `at` (the sims' plane) on the craft's road, standing still: a commuter, or a raider of the raid's pack.
func _car(v, at: Vector2, hostile: bool):
	var T = v.traffic_net
	var sim = v.sim
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var near := int(sim.pod.hint)
	for i in range(maxi(0, int(sim.pod.hint) - 10), mini(R.N - 1, int(sim.pod.hint) + int(3500.0 / float(Sim.NET_STEP)))):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	_next_id += 1
	c.id = _next_id
	c.kind = T.CAR
	c.road = road
	c.dir = _way
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = hostile
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	if hostile:
		_director.pack.append(c)
	return c


## A flyer of the raid's (view/raid_flyers.gd), put up by hand at (x, y, z) in the sims' frame: never flown, moved by
## hand. `kind` "drone" (its own HP) or "gunship" (GUNSHIP_HP: the Flyer class, not the module's own gunship).
func _flyer(kind: String, at: Vector3):
	var f = Flyers.Flyer.new()
	_next_id += 1
	f.id = _next_id
	f.kind = kind
	f.x = at.x
	f.y = at.y
	f.z = at.z
	f.hp = Flyers.GUNSHIP_HP if kind == "gunship" else Flyers.DRONE_HP
	f.hp_max = f.hp
	f.r = Flyers.GUNSHIP_R if kind == "gunship" else Flyers.DRONE_R
	_director.flyers._list.append(f)
	return f


## Set `t` going at `vel` (the sims' frame, m/s): its own heading and speed (what the lead reads) and moved by hand each
## frame (_frame).
func _set_moving(t, vel: Vector3) -> void:
	var flat := Vector2(vel.x, vel.y)
	t.v = flat.length()
	if t.v > 0.0:
		t.hx = vel.x / t.v
		t.hy = vel.y / t.v
	if GunneryScript._is_flyer(t):
		t.vx = vel.x
		t.vy = vel.y
		t.vz = vel.z
	movers = movers.filter(func(m: Array) -> bool: return m[0] != t)
	movers.append([t, vel])


## Where `at` is in the render frame: a vehicle's middle, a flyer's own place, or a sims' point.
func _render_of(v, g, at) -> Vector3:
	if at is Vector3:
		return g.to_render(at)
	if GunneryScript._is_flyer(at):
		return g.to_render(Vector3(at.x, at.y, at.z))
	return g.to_render(Vector3(at.x, at.y, v.traffic_net.body_height(at)))


## The gaze from the seat's eye: on `at` (a vehicle, a flyer or a sims' point), or with null up into the empty sky.
func _look(v, g, at) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if at == null:
		cam.look_at(cam.global_position + rig.basis * Vector3(0.0, 0.7, -1.0), rig.basis.y)
	else:
		cam.look_at(_render_of(v, g, at), rig.basis.y)


## One frame of the still world: the movers moved, the gaze laid (as _look), the fire control stepped.
func _frame(v, g, at = null) -> void:
	for m: Array in movers:
		var t = m[0]
		var vel: Vector3 = m[1]
		t.x += vel.x * DT
		t.y += vel.y * DT
		if GunneryScript._is_flyer(t):
			t.z += vel.z * DT
	_look(v, g, at)
	g.step(DT)


## `n` frames of it.
func _frames(v, g, n: int, at = null) -> void:
	for i in n:
		_frame(v, g, at)


## Lock `t`: a glance off it into the sky (the fire control's lock eases off and lets go of what it held), then the gaze
## on it until it joins the locks (at most 1 s). Did it?
func _lock(v, g, t) -> bool:
	_frames(v, g, int(0.4 / DT))
	for i in int(1.0 / DT):
		_frame(v, g, t)
		if g.mount.locks.has(t):
			return true
	return false


## The gaze on `t` straight away (no glance off first) until it joins the locks (at most 1 s). Did it?
func _hold(v, g, t) -> bool:
	for i in int(1.0 / DT):
		_frame(v, g, t)
		if g.mount.locks.has(t):
			return true
	return false


## The trigger pressed (let go first, then held one frame) with the gaze on `at`; left held.
func _press(v, g, at = null) -> void:
	g.hold_fire = false
	_frame(v, g, at)
	g.hold_fire = true
	_frame(v, g, at)


## Let the missiles in flight end (fizz or strike), the trigger let go, the rack reloaded, the vehicles and flyers gone,
## and the director's counts back to none.
func _clear(v, g) -> void:
	g.hold_fire = false
	movers.clear()
	for i in int(7.0 / DT):
		_frame(v, g)
		if g.mount.missiles.is_empty() and g.mount.reload <= 0.0:
			break
	v.traffic_net.cars.clear()
	_director.pack.clear()
	_director.flyers._list.clear()
	_director.kills = 0
	_director._zero_kills_by()
	_director._killed.clear()
	g._damage.clear()
	_frame(v, g)


## How many of the arms' four rounds are drawn (shown on their cassettes).
static func _rounds_shown(arms) -> int:
	var n := 0
	for slot in 4:
		n += int(arms.get_node(_round_path(slot)).visible)
	return n


## A round's node under the arms (view/arms/shrike_arms.gd: two to a cassette, port then starboard).
static func _round_path(slot: int) -> String:
	return "%s/Round%d" % ["PortCassette" if slot < 2 else "StarboardCassette", slot % 2 + 1]


# --- the checks ----------------------------------------------------------------------------------------------

func check_table() -> void:
	var row: Dictionary = Pilot.traits(Pilot.SHRIKE).weapon
	check("the Shrike carries \"%s\" (missiles), armed %s, its weapon row %s" % [Pilot.weapon_of(Pilot.SHRIKE), Pilot.armed(Pilot.SHRIKE), row],
		Pilot.weapon_of(Pilot.SHRIKE) == "missiles" and Pilot.armed(Pilot.SHRIKE) and row == ROW)


## The GUN never armed, then armed (the first time: the fire control and the arms are made then), the world held still,
## the director of the test's own put in, and the arms brought out. The fire control, or null (its failure told).
func check_lazy(v):
	var hull: Node3D = v.shell.get_node("PodHull")
	check("with the GUN never armed there is no Arms node on the seat's hull (%s) nor the craft's pod (%s), and no fire control (%s; Raids off)" % [
		hull.get_node_or_null("Arms"), v.craft.pod.get_node_or_null("Arms"), v.gunnery],
		hull.get_node_or_null("Arms") == null and v.craft.pod.get_node_or_null("Arms") == null and v.gunnery == null)
	var t0 := Time.get_ticks_usec()
	_hold_speed(v)
	v._process(DT)
	var before_ms := (Time.get_ticks_usec() - t0) / 1000.0
	v.gun_wanted = true
	_hold_speed(v)
	t0 = Time.get_ticks_usec()
	v._process(DT)
	var arming_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := []
	for i in 3:
		_hold_speed(v)
		t0 = Time.get_ticks_usec()
		v._process(DT)
		after.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01))
	print("  FIRST ARMING (Raids off): the view's whole _process %.2f ms on the arming frame (%.2f the frame before; %s the three after)" % [
		arming_ms, before_ms, after])
	var g = v.gunnery
	var mount = g.mount if g != null else null
	var script_path: String = (mount.get_script() as Script).resource_path if mount != null else ""
	var arms = hull.get_node_or_null("Arms")
	check("armed, its fire control is made, firing for itself through the missile mount (%s), the Arms on the seat's hull (%s), none on the hidden pod" % [
		script_path, arms], g != null and script_path.ends_with("missile_mount.gd") and v.craft.weapon == mount and mount.own_fire()
		and arms != null and mount.get("arms") == arms and v.craft.pod.get_node_or_null("Arms") == null)
	if g == null or not script_path.ends_with("missile_mount.gd") or arms == null:
		return null
	check("the fire control looks %.0f m for a target (the row's reach), its lock builds in %.2f s (lockS); the mount holds %d rounds, %d to a volley" % [
		g.reach, g.lock_s, mount.loaded, mount.max_locks], is_equal_approx(g.reach, 3000.0) and is_equal_approx(g.lock_s, 0.35)
		and mount.loaded == 4 and mount.max_locks == 4 and _rounds_shown(arms) == 4)
	# From here the world is still: the fire control is stepped alone, every target where the test puts it.
	_fleet = v.traffic_net.cars.duplicate()
	v.traffic_net.cars.clear()
	_director = Raids.new()      # (its raiders are a raid's pack, as in a flight: a director of the test's own, never updated)
	v.add_child(_director)
	_director.traffic = v.traffic_net
	_director.build(v)
	v.raids = _director
	v.traffic_net.raids = _director
	g.killed.connect(_director.on_kill)      # (as the view connects it: craft_view.gd, the frame)
	g.power = 1.0
	g.want_out = true
	var begun: float = mount.deploy_t()      # (the view's own frames since the switch: its fire control's first was made SAFE)
	var frames := 0
	while not mount.is_out() and frames < int(2.0 / DT):
		_frame(v, g)
		frames += 1
	var took := begun * 1.0 + frames * DT
	check("out in %.3f s (1.0; %.3f of it in the view's frames since the switch): the cheeks open and the cassettes rise (deploy %.2f), the arms drawn" % [
		took, begun, mount.deploy_t()], mount.is_out() and absf(took - 1.0) <= 2.0 * DT and begun > 0.0 and arms.visible)
	return g


func check_lock_builds(v, g) -> void:
	var m = g.mount
	var hw: float = _road(v)[1]
	var raider = _car(v, _ahead(v, 500.0, 0.0), true)
	_frames(v, g, int(0.4 / DT))      # (a glance off first: nothing held)
	var early := false
	for i in int(0.30 / DT):
		_frame(v, g, raider)
		early = early or not m.locks.is_empty()
	var frames := int(0.30 / DT)
	while m.locks.is_empty() and frames < int(0.35 / DT) + 2:
		_frame(v, g, raider)
		frames += 1
	check("the gaze on a raider: no lock at 0.30 s (%s); locked by %.3f s (lockS 0.35): locks %s" % [early, frames * DT, m.locks],
		not early and m.locks == [raider] and frames * DT <= 0.35 + 2.0 * DT and m.status() == "LOCK 1")
	_clear(v, g)
	var commuter = _car(v, _ahead(v, 500.0, 0.0), false)
	_frames(v, g, int(2.0 / DT), commuter)
	check("the gaze on a commuter 2 s: no lock (%s), the fire control's own on it (%.2f)" % [m.locks, g.lock], m.locks.is_empty() and g.aim_car == commuter and g.lock >= 1.0)
	_clear(v, g)
	# Four in turn, a glance off between: each 2 degrees apart at 500 m, on the road; then a fifth.
	var pack := []
	for k in 5:
		pack.append(_car(v, _ahead(v, 500.0, (float(k) - 2.0) * minf(17.5, 0.4 * hw)), true))
	var took := []
	for k in 4:
		took.append(_lock(v, g, pack[k]))
	var fifth := _lock(v, g, pack[4])
	check("four raiders in turn: four locks (%s, %s), each once, \"%s\"; a fifth is not added (%s)" % [took, m.locks.size(), m.status(), fifth],
		took == [true, true, true, true] and m.locks == pack.slice(0, 4) and m.status() == "LOCK 4" and not fifth and not m.locks.has(pack[4]))
	_frames(v, g, int(0.5 / DT), pack[0])
	check("... the gaze back on the first a while: it is not locked twice (%d locks)" % m.locks.size(), m.locks.size() == 4)
	_clear(v, g)


## -> the volley's three raiders (crossing at CROSS_V), or [] (its failure told).
func check_volley(v, g) -> Array:
	var m = g.mount
	var arms = m.arms
	var hw: float = _road(v)[1]
	var lat := minf(30.0, 0.5 * hw)
	var three := []
	for k in 3:
		three.append(_car(v, _ahead(v, FAR, (float(k) - 1.0) * lat), true))
	var shots: int = g.shots
	_press(v, g)
	_frames(v, g, 10)
	var none_fired: bool = g.shots == shots and m.missiles.is_empty()
	# Held while the first lock is taken: still nothing (a press fires, not a hold).
	var held_lock := false
	for i in int(1.0 / DT):
		_frame(v, g, three[0])
		if m.locks.has(three[0]):
			held_lock = true
			break
	_frames(v, g, 10, three[0])
	var held_fired: bool = g.shots != shots
	g.hold_fire = false
	var locked := [held_lock, _lock(v, g, three[1]), _lock(v, g, three[2])]
	check("no lock: the trigger pressed fires nothing (%s); held while a lock is taken it fires nothing (%s, locked %s)" % [none_fired, held_fired, held_lock],
		none_fired and held_lock and not held_fired)
	# The brackets: one on each locked raider.
	_frame(v, g)
	var bracketed := 0
	for k in 3:
		var b: MeshInstance3D = m.brackets[k]
		bracketed += int(b.visible and b.global_position.distance_to(_render_of(v, g, three[k])) < 1.0)
	check("three locked (%s): a bracket on each (%d), \"%s\"" % [locked, bracketed, m.status()], locked == [true, true, true] and bracketed == 3 and m.status() == "LOCK 3")
	if locked != [true, true, true]:
		return []
	# They cross at CROSS_V, the trigger is pressed.
	var way: Vector2 = _road(v)[0]
	for c in three:
		_set_moving(c, Vector3(-way.y, way.x, 0.0) * CROSS_V)
	v._gun_shots = g.shots
	var hand: XRController3D = v.hands.left
	v._buzz_hold[hand] = 0.0
	v.gun_pulses.clear()
	_press(v, g)
	v._gun_controls()      # (the cockpit's own: X's state, and the hand's ticks for the shots)
	g.hold_fire = true     # (it read X: up again)
	var hidden := 4 - _rounds_shown(arms)
	check("pressed with three locks: %d missiles (%d shots), three rounds hidden (%d), locks empty (%s), \"%s\"" % [m.missiles.size(), g.shots - shots, hidden,
		m.locks, m.status()], m.missiles.size() == 3 and g.shots == shots + 3 and hidden == 3 and m.loaded == 1 and m.locks.is_empty() and m.status() == "RELOAD")
	var tick_hold: float = v._buzz_hold.get(hand, 0.0)
	var sent: Array = v.gun_pulses.map(func(p: Array) -> float: return snappedf(float(p[3]), 0.001))
	check("the volley's frame sends one tick to the left hand, at once (sent, by their delays: %s), and holds the hand for the volley's three, %.2f s apart: %.3f s (%.3f: the brakes' shudder waits)" % [
		sent, TICK_GAP, tick_hold, 0.012 + 2.0 * TICK_GAP], sent == [0.0] and v.gun_pulses[0][0] == hand and absf(tick_hold - (0.012 + 2.0 * TICK_GAP)) < 1e-4)
	var each_target := []
	for k in m.missiles.size():
		each_target.append(m.missiles[k].target)
	_frame(v, g)
	var shown := 0
	for b: MeshInstance3D in m.brackets:
		if b.visible:
			for c in three:
				shown += int(b.global_position.distance_to(_render_of(v, g, c)) < 1.0)
	check("drawn: %d darts in their batch, %d streaks behind them, one missile on each raider (%s), still bracketed (%d of 3) though the locks are gone" % [
		m.dart_batch.visible_instance_count, m.streak_batch.visible_instance_count, each_target == three, shown],
		m.dart_batch.visible_instance_count == 3 and m.streak_batch.visible_instance_count == 3 and shown == 3 and each_target == three)
	shots = g.shots
	_frames(v, g, int(0.5 / DT))
	check("held down, no more leave (%d shots)" % (g.shots - shots), g.shots == shots)
	g.hold_fire = false
	return three


func check_homing_kills(v, g, three: Array) -> void:
	var m = g.mount
	var kills: int = g.kills
	var gone_at := {}
	var t: float = float(m.missiles[0].t) if not m.missiles.is_empty() else 0.0      # (s since the volley)
	while t < float(ROW.lifeS) and not m.missiles.is_empty():
		_frame(v, g)
		t += DT
		for c in three:
			if not gone_at.has(c) and not v.traffic_net.cars.has(c):
				gone_at[c] = snappedf(t, 0.01)
	var times := []
	for c in three:
		times.append(gone_at.get(c, -1.0))
	var shown := 0
	for b: MeshInstance3D in m.brackets:
		shown += int(b.visible)
	check("each reaches its raider (%.0f m off, crossing at %.0f m/s) within lifeS: knocked out %s s after the volley, %d kills, the director's raiders %d; no bracket left (%d)" % [
		FAR, CROSS_V, times, g.kills - kills, _director.kills_by.raider, shown], gone_at.size() == 3 and times.all(func(s: float) -> bool: return s > 0.0 and s < float(ROW.lifeS))
		and g.kills == kills + 3 and int(_director.kills_by.raider) == 3 and m.missiles.is_empty() and shown == 0)
	movers.clear()


## (Right after check_homing_kills: its volley's reload is under way.)
func check_reload(v, g) -> void:
	var m = g.mount
	var left: float = m.reload
	var since := float(ROW.reloadS) - left      # s since the volley
	var raider = _car(v, _ahead(v, 500.0, 0.0), true)
	_frames(v, g, maxi(0, int(round((4.0 - since) / DT))))      # (to 4.0 s: the lock's glance off and its hold take 0.75 s)
	var locked := _lock(v, g, raider)
	while float(ROW.reloadS) - float(m.reload) < 4.9 - 2.0 * DT - 1e-4:
		_frame(v, g, raider)
	var shots: int = g.shots
	var rack: int = m.loaded
	_press(v, g, raider)      # (two frames: let go, then pressed at 4.9 s)
	var at_49: float = float(ROW.reloadS) - float(m.reload)
	check("%.3f s after the volley, a lock held (%s) and %d round(s) left, the trigger pressed: nothing leaves (%d), \"%s\"" % [at_49, locked, rack,
		g.shots - shots, m.status()], locked and absf(at_49 - 4.9) <= DT and rack == 1 and g.shots == shots and m.missiles.is_empty() and m.status() == "RELOAD")
	g.hold_fire = false
	var n := 0
	while m.reload > 0.0 and n < int(1.0 / DT):
		_frame(v, g, raider)
		n += 1
	var at := at_49 + n * DT
	check("reloaded %.3f s after the volley (5.0): %d in the rack, %d rounds shown, \"%s\"" % [at, m.loaded, _rounds_shown(m.arms), m.status()],
		absf(at - float(ROW.reloadS)) <= 2.0 * DT and m.loaded == 4 and _rounds_shown(m.arms) == 4 and m.status() == "LOCK 1")
	_clear(v, g)


func check_gunship_takes_three(v, g) -> void:
	var m = g.mount
	var at := _ahead(v, FAR, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 150.0))
	var hp := []
	var alive := []
	for k in 3:
		var locked := _lock(v, g, ship)
		_press(v, g)
		g.hold_fire = false
		var frames := 0
		while not m.missiles.is_empty() and frames < int(float(ROW.lifeS) / DT):
			_frame(v, g)
			frames += 1
		hp.append(int(ship.hp))
		alive.append(g.alive(ship) and locked)
		while m.reload > 0.0:
			_frame(v, g)
	check("a %d HP gunship takes %d a missile: %s HP after each, alive %s; the director's gunships %d" % [Flyers.GUNSHIP_HP, ROW.hits, hp, alive, _director.kills_by.gunship],
		hp == [80, 40, 0] and alive == [true, true, false] and int(_director.kills_by.gunship) == 1)
	_clear(v, g)


func check_target_gone_mid_flight(v, g) -> void:
	var m = g.mount
	var lat := minf(30.0, 0.5 * float(_road(v)[1]))
	var raider = _car(v, _ahead(v, FAR, 0.0), true)
	var other = _car(v, _ahead(v, 500.0, lat), true)
	_lock(v, g, raider)
	_press(v, g)
	g.hold_fire = false
	var kills: int = g.kills
	# Its target shot by other means as the missile leaves (bolts' damage: HOSTILE_HP all at once).
	var flying: bool = m.missiles.size() == 1 and m.missiles[0].target == raider
	g.damage(raider, GunneryScript.HOSTILE_HP, Vector3(raider.x, raider.y, v.traffic_net.body_height(raider)))
	var kills_shot: int = g.kills
	_frame(v, g)
	var dir: Vector3 = (m.missiles[0].v as Vector3).normalized() if not m.missiles.is_empty() else Vector3.ZERO
	# ... and a lock taken on another while it flies, and that one shot too.
	var locked := _hold(v, g, other)
	g.damage(other, GunneryScript.HOSTILE_HP, Vector3(other.x, other.y, v.traffic_net.body_height(other)))
	var turned := 0.0
	var last_t := -1.0
	var frames := 0
	while not m.missiles.is_empty() and frames < int((float(ROW.lifeS) + 1.0) / DT):
		turned = maxf(turned, rad_to_deg(dir.angle_to(m.missiles[0].v)))
		last_t = float(m.missiles[0].t)
		_frame(v, g)
		frames += 1
	var ended := last_t + DT
	check("its target shot by other means as it left (%s): it flies on straight (turned %.4f deg), fizzes at %.3f s (lifeS %.1f), kills %d -> %d -> %d (the bolts' damage twice, none by it); the lock held on another (%s) dropped (%s)" % [
		flying, turned, ended, ROW.lifeS, kills, kills_shot, g.kills, locked, m.locks],
		flying and turned < 0.01 and absf(ended - float(ROW.lifeS)) <= 2.0 * DT and kills_shot == kills + 1 and g.kills == kills + 2 and locked and m.locks.is_empty())
	_clear(v, g)
	# The raid ended (the director's reset) with a raider's and a drone's missile in flight, and a lock held.
	_director.state = "on"
	var r2 = _car(v, _ahead(v, FAR, -lat), true)
	var at := _ahead(v, FAR, lat)
	var drone = _flyer("drone", Vector3(at.x, at.y, v.sim.pod.z + 300.0))
	var third = _car(v, _ahead(v, 500.0, 0.0), true)
	var took := [_lock(v, g, r2), _lock(v, g, drone)]
	_press(v, g)
	g.hold_fire = false
	took.append(_hold(v, g, third))
	var out_m := 0.0
	for mi: Dictionary in m.missiles:
		out_m = maxf(out_m, float(mi.t))
	_director.reset()
	var gone: bool = not g.alive(r2) and not g.alive(drone) and not g.alive(third)
	_frame(v, g)
	var dirs := []
	for mi: Dictionary in m.missiles:
		dirs.append((mi.v as Vector3).normalized())
	var worst := 0.0
	last_t = -1.0
	frames = 0
	kills = g.kills
	while not m.missiles.is_empty() and frames < int((float(ROW.lifeS) + 1.0) / DT):
		for k in mini(dirs.size(), m.missiles.size()):
			worst = maxf(worst, rad_to_deg((dirs[k] as Vector3).angle_to(m.missiles[k].v)))
		last_t = float(m.missiles[0].t)
		_frame(v, g)
		frames += 1
	ended = last_t + DT
	check("the raid ended %.2f s into their flight with two in flight (%d, locks taken %s): every target gone (%s); they fly on straight (turned %.4f deg), fizz at %.3f s; no kill (%d -> %d, the director's %d), the lock dropped (%s)" % [
		out_m, dirs.size(), took, gone, worst, ended, kills, g.kills, _director.kills, m.locks],
		took == [true, true, true] and dirs.size() == 2 and gone and worst < 0.01 and absf(ended - float(ROW.lifeS)) <= 2.0 * DT and g.kills == kills
		and _director.kills == 0 and m.locks.is_empty())
	_clear(v, g)


func check_commuter_in_the_way(v, g) -> void:
	var m = g.mount
	var raider = _car(v, _ahead(v, FAR, 0.0), true)
	_lock(v, g, raider)
	# The commuter put on the line from the craft to its raider, 600 m out.
	var from := Vector2(v.sim.pod.x, v.sim.pod.y)
	var commuter = _car(v, from + (Vector2(raider.x, raider.y) - from).normalized() * 600.0, false)
	var strikes: int = g.commuter_strikes
	var kills: int = g.kills
	_press(v, g)
	g.hold_fire = false
	var frames := 0
	while not m.missiles.is_empty() and frames < int(float(ROW.lifeS) / DT):
		_frame(v, g)
		frames += 1
	check("a commuter on the line: struck (%d strike), still in traffic (%s), the missile spent after %.2f s (%d in flight); its raider untouched (%s, kills %d -> %d)" % [
		g.commuter_strikes - strikes, v.traffic_net.cars.has(commuter), frames * DT, m.missiles.size(), g.alive(raider), kills, g.kills],
		g.commuter_strikes == strikes + 1 and v.traffic_net.cars.has(commuter) and m.missiles.is_empty() and frames * DT < 1.0 and g.alive(raider) and g.kills == kills)
	_clear(v, g)


func check_safe_mid_use(v, g) -> void:
	var m = g.mount
	var raider = _car(v, _ahead(v, FAR, 0.0), true)
	var other = _car(v, _ahead(v, 500.0, minf(30.0, 0.5 * float(_road(v)[1]))), true)
	_lock(v, g, raider)
	_press(v, g)
	g.hold_fire = false
	var rack_after: int = m.loaded
	var locked := _lock(v, g, other)      # (locks may be taken while it reloads)
	var since: float = float(ROW.reloadS) - float(m.reload)
	_frames(v, g, maxi(0, int(round((2.0 - since) / DT))), other)
	var held: bool = m.locks.has(other)
	g.want_out = false      # (the GUN switch thrown to SAFE, 2 s into the reload)
	_frame(v, g)
	var dropped: bool = m.locks.is_empty()
	_frames(v, g, int(1.0 / DT) - 1)
	g.want_out = true       # (GUN again at 3 s)
	_frame(v, g)
	var left: float = m.reload
	check("SAFE 2 s into a reload (a lock held then: %s), GUN at 3 s: %.3f s of it left (2.0; not 0, not 5), %d in the rack (as after the volley: %d); the lock gone at SAFE (%s), \"%s\"" % [
		locked and held, left, m.loaded, rack_after, dropped, m.status()],
		locked and held and absf(left - 2.0) <= 2.0 * DT and m.loaded == rack_after and rack_after == 3 and dropped and m.status() == "RELOAD")
	_clear(v, g)


func check_cost(v, g) -> void:
	var m = g.mount
	for c in _fleet:      # (traffic's own fleet back: the missiles look for commuters met on the way among them)
		v.traffic_net.cars.append(c)
	# ... made up to traffic's most (TARGET, near a city: 220), commuters along the road from 2 km behind to 4 km ahead.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hw: float = _road(v)[1]
	while v.traffic_net.cars.size() < v.traffic_net.TARGET:
		_car(v, _ahead(v, rng.randf_range(-2000.0, 4000.0), rng.randf_range(-0.8, 0.8) * hw), false)
	var way: Vector2 = _road(v)[0]
	var targets := []
	for k in 4:
		var at := _ahead(v, 2400.0, (float(k) - 1.5) * 300.0)
		targets.append(_flyer("drone", Vector3(at.x, at.y, v.sim.pod.z + 400.0)))
	var took := []
	for f in targets:
		took.append(_lock(v, g, f))
	for f in targets:
		_set_moving(f, Vector3(way.x, way.y, 0.0) * 1450.0)      # (running away, so all four stay in flight, homing)
	_press(v, g)
	g.hold_fire = false
	var costs := PackedFloat32Array()
	var whole := PackedFloat32Array()
	for i in 600:
		var t0 := Time.get_ticks_usec()
		_frame(v, g)
		whole.append((Time.get_ticks_usec() - t0) / 1000.0)
		costs.append(m.cost_ms)
		if m.missiles.size() != 4:
			break
	var mean := 0.0
	var worst := 0.0
	for c: float in costs:
		mean += c
		worst = maxf(worst, c)
	mean /= maxf(1.0, costs.size())
	var whole_mean := 0.0
	for c: float in whole:
		whole_mean += c
	whole_mean /= maxf(1.0, whole.size())
	print("  COST: the mount's own step and fire, four missiles homing, %d vehicles about: %.4f ms a frame mean, %.4f worst, over %d frames (the whole fire control's step %.4f mean)" % [
		v.traffic_net.cars.size(), mean, worst, costs.size(), whole_mean])
	check("four missiles homing (locks %s) for 600 frames with traffic's fleet about (%d): the mount %.4f ms a frame mean (under %.2f), %.4f worst" % [took, v.traffic_net.cars.size(),
		mean, COST_MS, worst], took == [true, true, true, true] and costs.size() == 600 and mean < COST_MS)
	_clear(v, g)


## The flat view (view/craft_view.gd: the GUN is K, the trigger F) on the Range: the arms on the craft's own pod.
func check_flat_range() -> void:
	View.track_override = "range"
	View.vehicle_override = Pilot.SHRIKE
	var game = View.new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for i in 5:
		game._process(DT)
	var none: bool = game.gunnery == null and game.craft.pod.get_node_or_null("Arms") == null
	game.gun_wanted = true
	for i in int(1.2 / DT):
		game._process(DT)
	var g = game.gunnery
	var arms = game.craft.pod.get_node_or_null("Arms")
	var mount = game.craft.weapon
	var shots: int = g.shots if g != null else -1
	if g != null:
		g.hold_fire = true
		for i in 10:
			game._process(DT)
		g.hold_fire = false
	check("the flat view on the Range: nothing built till armed (%s); armed, the fire control (%s) and the Arms on the craft's own pod (%s), out (deploy %.2f), drawn; the trigger with no lock fires nothing (%d shots)" % [
		none, g != null, arms, mount.deploy_t(), (g.shots - shots) if g != null else -1],
		none and g != null and g.mount == mount and arms != null and mount.get("arms") == arms and mount.is_out() and arms.is_visible_in_tree()
		and g.shots == shots and mount.missiles.is_empty())
	game.queue_free()
	await process_frame
	View.track_override = "network"


## `shots` shots in one frame on the cockpit's own frames (its _process: _gun_controls reads the fire control's count),
## over `n` frames: each gun tick sent, as [the frame it was sent in, its delay]; with `restart`, the cockpit restarts
## (Y's tap, _respawn) after the first frame.
func _ticks_over(v, shots: int, n: int, restart: bool) -> Array:
	v.gun_pulses.clear()
	v.gunnery.shots += shots
	var out := []
	for i in n:
		_hold_speed(v)
		v._process(DT)
		for p: Array in v.gun_pulses:
			out.append([i, snappedf(float(p[3]), 0.001)])
		v.gun_pulses.clear()
		if restart and i == 0:
			v._respawn()
	return out


func check_volley_ticks(v) -> void:
	var want := [[0, 0.0]]
	for k in [1, 2]:
		want.append([int(ceil(k * TICK_GAP / DT - 1e-6)), 0.0])
	var sent := _ticks_over(v, 3, 30, false)
	check("three shots in a frame, on the cockpit's own frames: ticks sent [frame, delay] %s (want %s: at once, at %.3f and %.3f s)" % [sent, want,
		float(want[1][0]) * DT, float(want[2][0]) * DT], sent == want)
	var cut := _ticks_over(v, 3, 30, true)
	check("three shots in a frame, a restart the next: ticks sent %s (want [[0, 0.0]]: none after the restart, none with a delay)" % [cut], cut == [[0, 0.0]])


## Raids on: the fire control made at load, dormant, and (Ruling D: the first arming measured over 5 ms) the arms built
## then, stowed, the seat's hull as it was; the first arming builds nothing more.
func check_raids_on_arming(v) -> void:
	var hull: MeshInstance3D = v.shell.get_node("PodHull")
	var g = v.gunnery
	var mount = v.craft.weapon
	var stowed_arms = hull.get_node_or_null("Arms")
	var closed: Mesh = hull.mesh
	check("Raids on: the fire control is made at load, dormant (%s), through the missile mount; the Arms built then on the seat's hull (%s), stowed: not drawn (%s), the hull its own mesh, all four rounds on their seats" % [
		g != null and g.dormant, stowed_arms, stowed_arms.visible if stowed_arms != null else null],
		g != null and g.dormant and mount != null and g.mount == mount and stowed_arms != null and mount.get("arms") == stowed_arms
		and not stowed_arms.visible and closed == Craft.pod_hull(true) and _rounds_shown(stowed_arms) == 4 and mount.deploy_t() == 0.0)
	var t0 := Time.get_ticks_usec()
	_hold_speed(v)
	v._process(DT)
	var before_ms := (Time.get_ticks_usec() - t0) / 1000.0
	v.gun_wanted = true
	_hold_speed(v)
	t0 = Time.get_ticks_usec()
	v._process(DT)
	var arming_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := []
	for i in 3:
		_hold_speed(v)
		t0 = Time.get_ticks_usec()
		v._process(DT)
		after.append(snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01))
	print("  FIRST ARMING (Raids on): the view's whole _process %.2f ms on the arming frame (%.2f the frame before; %s the three after)" % [
		arming_ms, before_ms, after])
	var arms = hull.get_node_or_null("Arms")
	check("armed: the fire control awake (%s), the same Arms (%s), coming out (deploy %.3f), the hull cut for the cassettes (%s)" % [g != null and not g.dormant,
		arms == stowed_arms, mount.deploy_t(), hull.mesh != closed],
		g != null and not g.dormant and arms != null and arms == stowed_arms and mount.deploy_t() > 0.0 and arms.visible and hull.mesh != closed)
