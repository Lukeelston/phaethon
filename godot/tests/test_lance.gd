## The Kiln's plasma lance (view/weapons/lance_mount.gd on Codex's arms, view/arms/kiln_arms.gd; fired for itself through
## view/gunnery.gd's own-fire hook). In the VR seat on the Network (XR off), the Kiln on a straight at 1,500 mph. Raids
## are pinned off, so the GUN's first arming makes the fire control and the arms; once armed the world is held still and
## the fire control stepped on its own: the gaze is laid by hand (as tests/test_missiles.gd does), every target is put
## where the test wants it and moved by hand, and (after the commuters' check, which has no raid) a director of the
## test's own is put in (never updated), so its raiders are a raid's pack and its kills are counted (kills_by):
##   check_table            weapon_of(KILN) is "lance", its weapon row is the brief's, and it is armed
##   check_lazy             with the GUN never armed: no Arms node on either hull, no fire control (Raids off); armed: the
##                          fire control is made, firing for itself through the lance's mount, the Arms on the hull the
##                          seat sees (not the hidden pod), out in 1 s. The first arming's frame is told (Ruling D)
##   check_ignores_commuters   (Review Focus 5) no raid on: the beam swept across ten commuters for 2 s, through each of
##                          them: all ten still in traffic, no strike, nothing hit, struck_commuter never told, the score
##                          unchanged
##   check_beam_follows_gaze   the gaze 10 degrees right of the craft's forward: the beam's line within 0.5 degrees of it;
##                          40 right: the beam 25 right (the cone's edge, between the forward and the gaze), the sight told
##                          it is held (limited); drawn: one ribbon from the mouth to the beam's end and a glow there,
##                          nothing nearer the eye than the mouth
##   check_burns_raider     a raider 400 m ahead under the gaze, the trigger held: knocked out in 0.2-0.3 s (6 HP at 30 a
##                          second), with no spark and no impact sound of a hit's own while it burns (Ruling T), its burst
##                          when it goes; one 700 m ahead takes nothing (the beam ends at reach)
##   check_heat             held 2.5 s it stops and says GUN HOT; the emitter's heat follows fire_s / fireS (half at 1.25
##                          s); 3.0 s later it burns again and says GUN READY
##   check_gunship_in_two_burns   a 120 HP flyer 300 m off takes 75 in one 2.5 s burn and is shot down in the second
##   check_nearest_first    a drone on the beam in front of a raider: the drone takes the hits and goes, then the raider
##   check_target_gone      its target shot by other means mid-burn: the beam goes on past where it was, no hit on it
##                          after; the raid ended (the director's reset) mid-burn: no hit after, nothing on the beam
##   check_safe_mid_use     (Review Focus 3) SAFE thrown mid-burn: the beam off that frame and no hit lands after it; SAFE
##                          thrown 1 s into cooling and GUN again at once: 2 s of cooling still left; SAFE 1 s into it and
##                          GUN 0.5 s later: 1.5 s left (the clock runs at SAFE)
##   check_remainder        whole hits, the remainder carried: 30 hits in a second at 120 and at 45 frames a second; the
##                          remainder dropped when the beam goes off (at 45: a frame on, a frame off, a frame on: none)
##   check_bare_hits        (Ruling T's switch) g.damage(raider, 1, at, false, true): counted, no spark, no impact sound;
##                          without it, as ever: a spark and the impact; a bare kill still bursts, with its sound
##   check_cost             the beam held on a gunship among a full raid (6 raiders, 10 drones) with traffic's most (220)
##                          about: the mount's own time a frame (its step and fire), mean and worst over 600 frames of burn,
##                          told; the mean held under COST_MS
##   check_flat_range       the flat view on the Range (no seat, no traffic, no raid): nothing built till armed; armed, the
##                          fire control and the arms on the craft's own pod, out in about a second; the trigger burns
##   check_raids_on_arming  Raids on (Ruling D: the first arming above measured over 5 ms): the fire control made at load,
##                          dormant, and the arms fitted then on the seat's hull, stowed (not drawn, the hull its own); the
##                          first arming's frame told; armed, the same arms come out
##   check_buzz             on that seat's own frames (vr_cockpit.gd _process), the trigger held: while it burns, one pulse
##                          a frame to the left hand, a frame long, sent at once (no delay: the engine ignores one); SAFE
##                          thrown: the beam off that frame, and no pulse that frame or after
## Run with --fixed-fps 120: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_lance.gd -- --mute
## Prints LANCE PASS. Puts user://vr_prefs.json back as it found it.
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
const ROW := {"reach": 600.0, "coneDeg": 25.0, "dps": 30.0, "fireS": 2.5, "coolS": 3.0}
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const MPH := 0.44704
const SPEED := 1500.0 * MPH     # m/s
const STRAIGHT := 1600.0        # m of road ahead that must run straight and level
const SKY_LOOK := Vector3(0.0, 0.12, -1.0)      # the gaze up into the empty sky ahead (inside the cone: 7 degrees up)
const COST_MS := 0.10           # the mount's own mean a frame, the beam held on a target among a full raid, at the most
const SECTIONS := 16
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var movers: Array = []          # [target, its velocity (sims' frame)]: moved by hand each frame of the still world
var _next_id := 994000
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
	Seat.best_dir = OS.get_user_data_dir().path_join("test_lance_")
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
	var v = await _seat(Pilot.KILN)
	var g = check_lazy(v)
	if g != null:
		sections += 1
		check_ignores_commuters(v, g)
		sections += 1
		_put_director(v, g)
		check_beam_follows_gaze(v, g)
		sections += 1
		check_burns_raider(v, g)
		sections += 1
		check_heat(v, g)
		sections += 1
		check_gunship_in_two_burns(v, g)
		sections += 1
		check_nearest_first(v, g)
		sections += 1
		check_target_gone(v, g)
		sections += 1
		check_safe_mid_use(v, g)
		sections += 1
		check_remainder(v, g)
		sections += 1
		check_bare_hits(v, g)
		sections += 1
		check_cost(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	await check_flat_range()
	sections += 1
	Raids.enabled = true
	v = await _seat(Pilot.KILN)
	check_raids_on_arming(v)
	sections += 1
	check_buzz(v)
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
	print("LANCE %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
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


## A flyer of the raid's (view/raid_flyers.gd), put up by hand at (x, y, z) in the sims' frame: never flown. `kind`
## "drone" (its own HP) or "gunship" (GUNSHIP_HP), or `hp` of its own.
func _flyer(kind: String, at: Vector3, hp := -1):
	var f = Flyers.Flyer.new()
	_next_id += 1
	f.id = _next_id
	f.kind = kind
	f.x = at.x
	f.y = at.y
	f.z = at.z
	f.hp = hp if hp > 0 else (Flyers.GUNSHIP_HP if kind == "gunship" else Flyers.DRONE_HP)
	f.hp_max = f.hp
	f.r = Flyers.GUNSHIP_R if kind == "gunship" else Flyers.DRONE_R
	_director.flyers._list.append(f)
	return f


## Where `at` is in the render frame: a vehicle's middle, a flyer's own place, or a sims' point.
func _render_of(v, g, at) -> Vector3:
	if at is Vector3:
		return g.to_render(at)
	if GunneryScript._is_flyer(at):
		return g.to_render(Vector3(at.x, at.y, at.z))
	return g.to_render(Vector3(at.x, at.y, v.traffic_net.body_height(at)))


## The gaze from the seat's eye: on `at` (a vehicle, a flyer or a sims' point), along a render-frame direction (`dir`),
## or with neither up into the empty sky ahead (SKY_LOOK).
func _look(v, g, at = null, dir := Vector3.ZERO) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if dir != Vector3.ZERO:
		cam.look_at(cam.global_position + dir, rig.basis.y)
	elif at == null:
		cam.look_at(cam.global_position + rig.basis * SKY_LOOK.normalized(), rig.basis.y)
	else:
		cam.look_at(_render_of(v, g, at), rig.basis.y)


## One frame of the still world: the movers moved, the gaze laid (as _look), the fire control stepped.
func _frame(v, g, at = null, dir := Vector3.ZERO, dt := DT) -> void:
	for m: Array in movers:
		var t = m[0]
		var vel: Vector3 = m[1]
		t.x += vel.x * dt
		t.y += vel.y * dt
		if GunneryScript._is_flyer(t):
			t.z += vel.z * dt
	_look(v, g, at, dir)
	g.step(dt)


## `n` frames of it.
func _frames(v, g, n: int, at = null, dir := Vector3.ZERO) -> void:
	for i in n:
		_frame(v, g, at, dir)


## The trigger let go, and frames until the lance has cooled right down (no cooling left, no heat).
func _cool(v, g) -> void:
	g.hold_fire = false
	var m = g.mount
	for i in int(8.0 / DT):
		_frame(v, g)
		if m.hot <= 0.0 and m.fire_s <= 0.0:
			break
	_frame(v, g)


## The lance cooled, the vehicles and flyers gone, and the director's counts back to none.
func _clear(v, g) -> void:
	movers.clear()
	_cool(v, g)
	v.traffic_net.cars.clear()
	if _director != null:
		_director.pack.clear()
		_director.flyers._list.clear()
		_director.kills = 0
		_director._zero_kills_by()
		_director._killed.clear()
	g._damage.clear()
	_frame(v, g)


## The craft's forward as the lance has it (the emitter's bore: Codex's lift keeps the barrel along the hull) and the
## hull's up there (render frame).
func _forward(g) -> Array:
	var m: Transform3D = g.mount.arms.muzzles()[0]
	return [(-m.basis.z).normalized(), m.basis.y.normalized()]


## The world's sounds (the fire control's world pool) all stopped, so a check sees only what plays after.
func _hush(g) -> void:
	for p: AudioStreamPlayer3D in g._world_audio:
		p.stop()


## How many of the world pool's players are playing `sound`.
func _playing(g, sound: String) -> int:
	var n := 0
	for p: AudioStreamPlayer3D in g._world_audio:
		n += int(p.playing and g._sounds.has(sound) and p.stream == g._sounds[sound])
	return n


## The kinds of the fire control's effects now drawn.
func _fx_kinds(g) -> Array:
	var out := []
	for f: Dictionary in g._fx:
		out.append(String(f.kind))
	return out


# --- the checks ----------------------------------------------------------------------------------------------

func check_table() -> void:
	var row: Dictionary = Pilot.traits(Pilot.KILN).weapon
	check("the Kiln carries \"%s\" (lance), armed %s, its weapon row %s" % [Pilot.weapon_of(Pilot.KILN), Pilot.armed(Pilot.KILN), row],
		Pilot.weapon_of(Pilot.KILN) == "lance" and Pilot.armed(Pilot.KILN) and row == ROW)


## The GUN never armed, then armed (the first time: the fire control and the arms are made then), the world held still,
## and the arms brought out. The fire control, or null (its failure told).
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
	check("armed, its fire control is made, firing for itself through the lance's mount (%s), the Arms on the seat's hull (%s), none on the hidden pod" % [
		script_path, arms], g != null and script_path.ends_with("lance_mount.gd") and v.craft.weapon == mount and mount.own_fire()
		and arms != null and mount.get("arms") == arms and v.craft.pod.get_node_or_null("Arms") == null)
	if g == null or not script_path.ends_with("lance_mount.gd") or arms == null:
		return null
	check("the fire control looks %.0f m along the beam (the row's reach); the mount's cone %.1f degrees, %.0f hits a second, %.1f s of burn, %.1f s to cool" % [
		g.reach, rad_to_deg(mount.cone), mount.dps, mount.fire_max, mount.cool_s], is_equal_approx(g.reach, 600.0) and is_equal_approx(rad_to_deg(mount.cone), 25.0)
		and is_equal_approx(mount.dps, 30.0) and is_equal_approx(mount.fire_max, 2.5) and is_equal_approx(mount.cool_s, 3.0))
	# From here the world is still: the fire control is stepped alone, every target where the test puts it.
	_fleet = v.traffic_net.cars.duplicate()
	v.traffic_net.cars.clear()
	g.power = 1.0
	g.want_out = true
	var begun: float = mount.deploy_t()      # (the view's own frames since the switch: its fire control's first was made SAFE)
	var frames := 0
	while not mount.is_out() and frames < int(2.0 / DT):
		_frame(v, g)
		frames += 1
	var took := begun * 1.0 + frames * DT
	check("out in %.3f s (1.0; %.3f of it in the view's frames since the switch): the leaves open and the lift raises the lance (deploy %.2f), the arms drawn" % [
		took, begun, mount.deploy_t()], mount.is_out() and absf(took - 1.0) <= 2.0 * DT and begun > 0.0 and arms.visible)
	return g


## (Review Focus 5) No raid on (no director: the view's own, Raids off): ten commuters across the road 250 to 470 m ahead
## (inside the cone: none more than 17 degrees off ahead), the gaze swept across them, right to left and back, for 2 s
## with the trigger held.
func check_ignores_commuters(v, g) -> void:
	var m = g.mount
	var T = v.traffic_net
	var hw: float = _road(v)[1]
	var ten := []
	for k in 10:
		var ahead := 250.0 + 24.0 * k
		ten.append(_car(v, _ahead(v, ahead, (float(k) / 9.0 * 2.0 - 1.0) * minf(0.8 * hw, 0.3 * ahead)), false))
	var strikes: int = g.commuter_strikes
	var hits: int = g.hits
	var kills: int = g.kills
	var told := []
	var on_struck := func(car) -> void: told.append(car)
	g.struck_commuter.connect(on_struck)
	var score = v.skill_score.total if v.skill_score != null else null
	var swept := {}                  # the commuters the beam's line passed through, within its length
	var burned := 0
	var frames := int(2.0 / DT)
	g.hold_fire = true
	for i in frames:
		var u := float(i) / float(frames - 1)
		var k := clampi(int(round((1.0 - absf(2.0 * u - 1.0)) * 9.0)), 0, 9)      # (across and back: the k-th commuter's way)
		var from_k: Vector3 = _render_of(v, g, ten[k])
		var next: Vector3 = _render_of(v, g, ten[mini(9, k + 1)])
		var at := from_k.lerp(next, fmod((1.0 - absf(2.0 * u - 1.0)) * 9.0, 1.0))
		_frame(v, g, g.to_sim(at))
		burned += int(m.burning)
		var o: Vector3 = g.to_sim(m.beam_from)
		var d: Vector3 = GunneryScript.dir_to_sim(m.beam_dir)
		for c in ten:
			var t: float = T.ray_car(c, o, d)
			if t >= 0.0 and t <= m.beam_len:
				swept[c] = true
	g.hold_fire = false
	g.struck_commuter.disconnect(on_struck)
	var still := ten.filter(func(c) -> bool: return T.cars.has(c)).size()
	var score_now = v.skill_score.total if v.skill_score != null else null
	check("no raid on (%s): the beam on %d of %d frames, swept through %d of the ten commuters across the road: %d still in traffic, strikes %d -> %d, hits %d -> %d, kills %d -> %d, struck told %d time(s), the score %s -> %s" % [
		v.raids, burned, frames, swept.size(), still, strikes, g.commuter_strikes, hits, g.hits, kills, g.kills, told.size(), score, score_now],
		v.raids == null and burned >= frames - 1 and swept.size() == 10 and still == 10 and g.commuter_strikes == strikes and g.hits == hits
		and g.kills == kills and told.is_empty() and score == score_now)
	for c in ten:
		T.cars.erase(c)
	_cool(v, g)


## The director of the test's own, put in once armed: its raiders are a raid's pack (as in a flight), never updated.
func _put_director(v, g) -> void:
	_director = Raids.new()
	v.add_child(_director)
	_director.traffic = v.traffic_net
	_director.build(v)
	v.raids = _director
	v.traffic_net.raids = _director
	g.killed.connect(_director.on_kill)      # (as the view connects it: craft_view.gd, the frame)


func check_beam_follows_gaze(v, g) -> void:
	var m = g.mount
	var fu := _forward(g)
	var fwd: Vector3 = fu[0]
	var up: Vector3 = fu[1]
	g.hold_fire = true
	var ten := fwd.rotated(up, -deg_to_rad(10.0))
	_frames(v, g, 3, null, ten)
	var off10 := rad_to_deg(m.beam_dir.angle_to(ten))
	var lim10: bool = m.limited()
	var on10: bool = m.burning
	# Drawn: the ribbon from the mouth to the beam's end, the glow there, nothing nearer the eye than the mouth.
	var eye: Vector3 = v.cam.global_position
	var mouth: Vector3 = (m.arms.muzzles()[0] as Transform3D).origin
	var end: Vector3 = m.beam_from + m.beam_dir * m.beam_len
	var rib: Transform3D = m.beam.global_transform
	var near_end := rib * Vector3(0.0, 0.0, 0.5)
	var far_end := rib * Vector3(0.0, 0.0, -0.5)
	var glow_at: Vector3 = m.glow_at      # (headless, the batch keeps no transforms: the mount says where it drew it)
	var drawn: bool = m.beam.visible and m.glow.visible_instance_count == 1
	var nearest := minf(eye.distance_to(near_end), minf(eye.distance_to(far_end), eye.distance_to(glow_at)))
	check("the gaze 10 degrees right of the craft's forward: the beam on (%s) %.3f degrees off it (within 0.5), not held at the cone (%s); drawn (%s): the ribbon from the mouth (%.4f m off it) to the beam's end %.0f m out (%.4f m off), the glow there (%.4f m off); nothing nearer the eye than the mouth (%.3f m; the mouth %.3f)" % [
		on10, off10, lim10, drawn, near_end.distance_to(mouth), m.beam_len, far_end.distance_to(end), glow_at.distance_to(end), nearest, eye.distance_to(mouth)],
		on10 and off10 < 0.5 and not lim10 and drawn and near_end.distance_to(mouth) < 1e-3 and far_end.distance_to(end) < 1e-2
		and glow_at.distance_to(end) < 1e-2 and nearest >= eye.distance_to(mouth) - 1e-3 and m.beam_len > 5.0)
	var forty := fwd.rotated(up, -deg_to_rad(40.0))
	_frames(v, g, 3, null, forty)
	var to_fwd := rad_to_deg(m.beam_dir.angle_to(fwd))
	var to_gaze := rad_to_deg(m.beam_dir.angle_to(forty))
	var right: bool = m.beam_dir.dot(fwd.cross(up)) > 0.0
	check("the gaze 40 degrees right: the beam %.3f degrees right of the forward (25: the cone's edge; %s), %.3f off the gaze (15), still on (%s); held at the cone, the sight told (limited %s)" % [
		to_fwd, "right" if right else "left", to_gaze, m.burning, m.limited()],
		absf(to_fwd - 25.0) < 0.05 and absf(to_gaze - 15.0) < 0.05 and right and m.burning and m.limited())
	_cool(v, g)


func check_burns_raider(v, g) -> void:
	var m = g.mount
	var raider = _car(v, _ahead(v, 400.0, 0.0), true)
	_frames(v, g, 5, raider)
	_hush(g)
	g._fx.clear()
	var kills: int = g.kills
	g.hold_fire = true
	var frames := 0
	var sparks := 0
	var impacts := 0
	var on_it := 0
	while g.alive(raider) and frames < int(1.0 / DT):
		_frame(v, g, raider)
		frames += 1
		if g.alive(raider):
			sparks += _fx_kinds(g).count("spark")
			impacts += _playing(g, "impact")
			on_it += int(m.on_beam == raider)
	var gone_at := frames * DT
	var burst := _fx_kinds(g)
	var boom := _playing(g, "burst")
	check("a raider 400 m ahead under the gaze, the trigger held: knocked out %.3f s into the burn (0.2-0.3: 6 HP at 30 a second), the beam on it all the while (%d of %d frames), kills %d -> %d, the director's raiders %d; no spark (%d) and no impact sound (%d) of a hit's own; its burst when it went (%s; the burst's sound %d)" % [
		gone_at, on_it, frames - 1, kills, g.kills, _director.kills_by.raider, sparks, impacts, burst, boom],
		not g.alive(raider) and gone_at >= 0.2 - 1e-6 and gone_at <= 0.3 + 1e-6 and on_it == frames - 1 and g.kills == kills + 1
		and int(_director.kills_by.raider) == 1 and sparks == 0 and impacts == 0 and burst.has("fireball") and boom >= 1)
	g.hold_fire = false
	_cool(v, g)
	var far = _car(v, _ahead(v, 700.0, 0.0), true)
	_frames(v, g, 5, far)
	g.hold_fire = true
	var longest := 0.0
	var burned := 0
	for i in int(1.0 / DT):
		_frame(v, g, far)
		longest = maxf(longest, m.beam_len)
		burned += int(m.burning)
	check("one 700 m ahead, the beam held on it 1 s (on %d frames): it takes nothing (%s; alive %s), the beam %.1f m long at the most (reach 600), on it never (%s)" % [
		burned, g._damage.get(far.id), g.alive(far), longest, m.on_beam],
		burned == int(1.0 / DT) and not g._damage.has(far.id) and g.alive(far) and longest <= 600.0 + 1e-3 and m.on_beam == null)
	_clear(v, g)


func check_heat(v, g) -> void:
	var m = g.mount
	v._power_note = ""
	g.hold_fire = true
	var frames := 0
	var half := -1.0
	var said_hot := ""
	while frames < int(4.0 / DT):
		_frame(v, g)
		frames += 1
		if frames == int(round(1.25 / DT)):
			half = m.arms.heat
		if not m.burning:
			said_hot = v._power_note
			break
	var stopped := (frames - 1) * DT      # (s of burn: the frame it stops is the first without)
	var status_hot: String = m.status()
	var cold := 0
	while not m.burning and cold < int(5.0 / DT):
		_frame(v, g)
		cold += 1
	var again := cold * DT + DT      # (s after the burn's last frame)
	check("held: it burns %.3f s and stops (2.5), says %s (\"%s\" on the strip); the emitter's heat %.3f at 1.25 s (half: fire_s / fireS); it burns again %.3f s later (3.0), says %s (\"%s\")" % [
		stopped, status_hot, said_hot, half, again, m.status(), v._power_note],
		absf(stopped - 2.5) <= DT + 1e-6 and status_hot == "GUN HOT" and said_hot == "GUN HOT" and absf(half - 0.5) < 0.01
		and absf(again - 3.0) <= DT + 1e-6 and m.burning and m.status() == "GUN READY" and v._power_note == "GUN READY")
	_cool(v, g)


func check_gunship_in_two_burns(v, g) -> void:
	var m = g.mount
	var at := _ahead(v, 300.0, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 20.0))
	_frames(v, g, 5, ship)
	g.hold_fire = true
	var frames := 0
	while m.burning or frames == 0:
		_frame(v, g, ship)
		frames += 1
		if frames > int(3.0 / DT):
			break
	var after_one := int(ship.hp)
	var alive_one: bool = g.alive(ship)
	var cooling := 0
	while not m.burning and cooling < int(4.0 / DT):
		_frame(v, g, ship)
		cooling += 1
	var second := 0
	while g.alive(ship) and second < int(3.0 / DT):
		_frame(v, g, ship)
		second += 1
	check("a %d HP gunship 300 m off: one 2.5 s burn (%.3f s) leaves it %d HP (45: 75 taken), alive (%s); it cools %.3f s, and the second burn shoots it down %.3f s in (1.5; alive %s); the director's gunships %d" % [
		Flyers.GUNSHIP_HP, (frames - 1) * DT, after_one, alive_one, cooling * DT, second * DT, g.alive(ship), _director.kills_by.gunship],
		after_one == Flyers.GUNSHIP_HP - 75 and alive_one and not g.alive(ship) and absf(second * DT - 1.5) <= 2.0 * DT + 1e-6
		and int(_director.kills_by.gunship) == 1)
	_clear(v, g)


## A drone on the beam's line 200 m out, in front of a raider 400 m out: the nearer takes the hits.
func check_nearest_first(v, g) -> void:
	var m = g.mount
	var raider = _car(v, _ahead(v, 400.0, 0.0), true)
	var eye_sim: Vector3 = g.to_sim(v.rig.global_transform * Seat.EYE)
	var mid := Vector3(raider.x, raider.y, v.traffic_net.body_height(raider))
	var drone = _flyer("drone", eye_sim.lerp(mid, 200.0 / eye_sim.distance_to(mid)))
	_frames(v, g, 5, raider)
	g.hold_fire = true
	var frames := 0
	var drone_gone := -1
	var raider_hit_while_drone := false
	while g.alive(raider) and frames < int(1.0 / DT):
		_frame(v, g, raider)
		frames += 1
		if drone_gone < 0 and not g.alive(drone):
			drone_gone = frames
		if drone_gone < 0 and g._damage.has(raider.id):
			raider_hit_while_drone = true
	check("a drone on the beam 200 m out, before a raider 400 m out: the drone goes first, %.3f s in (2 HP: about 0.07), the raider untouched while it flew (%s), then the raider, %.3f s in (%s; kills by kind %s)" % [
		drone_gone * DT, not raider_hit_while_drone, frames * DT, not g.alive(raider), _director.kills_by],
		drone_gone > 0 and drone_gone * DT <= 0.1 and not raider_hit_while_drone and not g.alive(raider) and frames > drone_gone
		and int(_director.kills_by.drone) == 1 and int(_director.kills_by.raider) == 1)
	_clear(v, g)


func check_target_gone(v, g) -> void:
	var m = g.mount
	var at := _ahead(v, 300.0, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 20.0), 100000)
	_frames(v, g, 5, ship)
	g.hold_fire = true
	_frames(v, g, 12, ship)
	var was_on: bool = m.on_beam == ship
	var len_on: float = m.beam_len
	var kills: int = g.kills
	g.damage(ship, int(ship.hp), Vector3(ship.x, ship.y, ship.z))      # (shot down by other means, mid-burn)
	var hits: int = g.hits
	_frames(v, g, 12, null, (_render_of(v, g, Vector3(at.x, at.y, v.sim.pod.z + 20.0)) - v.cam.global_position).normalized())
	check("its target shot down by other means mid-burn (on it before: %s, %.0f m): the beam goes on past where it was (%.0f m, on %s), no hit after (%d -> %d), kills %d -> %d (that one shot alone)" % [
		was_on, len_on, m.beam_len, m.on_beam, hits, g.hits, kills, g.kills],
		was_on and m.burning and m.beam_len > len_on + 50.0 and m.on_beam == null and g.hits == hits and g.kills == kills + 1)
	_clear(v, g)
	# The raid ended (the director's reset) with the beam on a raider and a drone among the threats.
	_director.state = "on"
	var raider = _car(v, _ahead(v, 300.0, 0.0), true)
	var up := _ahead(v, 500.0, 40.0)
	var drone = _flyer("drone", Vector3(up.x, up.y, v.sim.pod.z + 60.0))
	_frames(v, g, 5, raider)
	g.hold_fire = true
	_frame(v, g, raider)
	var on_raider: bool = m.on_beam == raider
	_director.reset()
	hits = g.hits
	kills = g.kills
	var gone: bool = not g.alive(raider) and not g.alive(drone)
	var where := Vector3(raider.x, raider.y, v.traffic_net.body_height(raider))      # (where it was)
	var on_nothing := true
	for i in 24:
		_frame(v, g, where)
		on_nothing = on_nothing and m.on_beam == null
	check("the raid ended mid-burn (the beam on its raider: %s): every threat gone (%s); the beam burns on (%s) on nothing (%s), no hit after (%d -> %d), no kill (%d -> %d, the director's %d)" % [
		on_raider, gone, m.burning, on_nothing, hits, g.hits, kills, g.kills, _director.kills],
		on_raider and gone and m.burning and on_nothing and g.hits == hits and g.kills == kills and _director.kills == 0)
	_clear(v, g)


func check_safe_mid_use(v, g) -> void:
	var m = g.mount
	var at := _ahead(v, 300.0, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 20.0), 100000)
	_frames(v, g, 5, ship)
	g.hold_fire = true
	_frames(v, g, int(0.5 / DT), ship)
	var burning_before: bool = m.burning and m.on_beam == ship
	var hp: int = int(ship.hp)
	g.want_out = false      # (the GUN switch thrown to SAFE mid-burn)
	_frame(v, g, ship)
	var off_at_once: bool = not m.burning and not m.beam.visible and m.buzz() == 0.0
	var hp_then: int = int(ship.hp)
	_frames(v, g, int(0.5 / DT), ship)
	check("SAFE thrown mid-burn (on it before: %s): the beam off that frame (%s: not drawn, no buzz), %d HP before, %d that frame, %d after 0.5 s more (no hit after it)" % [
		burning_before, off_at_once, hp, hp_then, int(ship.hp)], burning_before and off_at_once and hp_then == hp and int(ship.hp) == hp)
	# Overheated, then SAFE 1 s into its cooling and GUN again at once.
	g.want_out = true
	g.hold_fire = false
	_cool(v, g)
	_frames(v, g, int(1.1 / DT), ship)
	g.hold_fire = true
	var frames := 0
	while m.hot <= 0.0 and frames < int(4.0 / DT):
		_frame(v, g, ship)
		frames += 1
	g.hold_fire = false
	_frames(v, g, int(round(1.0 / DT)) - 1, ship)
	g.want_out = false      # (SAFE, 1 s into the cooling ...)
	_frame(v, g, ship)
	g.want_out = true       # (... and GUN again the next frame)
	_frame(v, g, ship)
	var left: float = m.hot
	check("SAFE thrown 1 s into cooling and GUN again at once: %.3f s of cooling left (2.0; not refilled to 3, not ended), \"%s\"" % [left, m.status()],
		absf(left - 2.0) <= 2.0 * DT + 1e-6 and m.status() == "GUN HOT")
	_cool(v, g)
	g.hold_fire = true
	frames = 0
	while m.hot <= 0.0 and frames < int(4.0 / DT):
		_frame(v, g, ship)
		frames += 1
	g.hold_fire = false
	_frames(v, g, int(round(1.0 / DT)) - 1, ship)
	g.want_out = false      # (SAFE, 1 s into the cooling, for 0.5 s ...)
	_frames(v, g, int(round(0.5 / DT)), ship)
	g.want_out = true       # (... then GUN)
	_frame(v, g, ship)
	left = m.hot
	check("SAFE thrown 1 s into cooling, GUN again 0.5 s later: %.3f s of cooling left (1.5: its clock ran at SAFE)" % left, absf(left - 1.5) <= 2.0 * DT + 1e-6)
	_clear(v, g)


func check_remainder(v, g) -> void:
	var m = g.mount
	var at := _ahead(v, 300.0, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 20.0), 100000)
	var taken := []
	for rate: float in [120.0, 45.0]:
		var dt := 1.0 / rate
		for i in 5:
			_frame(v, g, ship, Vector3.ZERO, dt)
		var hp: int = int(ship.hp)
		g.hold_fire = true
		for i in int(round(rate)):
			_frame(v, g, ship, Vector3.ZERO, dt)
		g.hold_fire = false
		_frame(v, g, ship, Vector3.ZERO, dt)
		taken.append(hp - int(ship.hp))
		_cool(v, g)
	# At 45 frames a second, two thirds of a hit a frame: a frame on, a frame off, a frame on.
	var dt45 := 1.0 / 45.0
	var hp0: int = int(ship.hp)
	for held: bool in [true, false, true, false]:
		g.hold_fire = held
		_frame(v, g, ship, Vector3.ZERO, dt45)
	var flicker := hp0 - int(ship.hp)
	check("held a second: %s hits at 120 and 45 frames a second (30 each: whole hits, the remainder carried); at 45, a frame on, a frame off, a frame on: %d hits (0: the remainder dropped when the beam went off)" % [
		taken, flicker], taken == [30, 30] and flicker == 0)
	_clear(v, g)


## Ruling T's switch (view/gunnery.gd damage's `bare`), on the fire control itself.
func check_bare_hits(v, g) -> void:
	var raider = _car(v, _ahead(v, 400.0, 0.0), true)
	var at := Vector3(raider.x, raider.y, v.traffic_net.body_height(raider))
	_hush(g)
	g._fx.clear()
	var hits: int = g.hits
	var killed: bool = g.damage(raider, 1, at, false, true)
	var bare := [killed, int(g._damage.get(raider.id, 0)), g.hits - hits, _fx_kinds(g).count("spark"), _playing(g, "impact")]
	_hush(g)
	g._fx.clear()
	killed = g.damage(raider, 1, at)
	var plain := [killed, int(g._damage.get(raider.id, 0)), _fx_kinds(g).count("spark"), _playing(g, "impact")]
	_hush(g)
	g._fx.clear()
	var last: bool = g.damage(raider, 4, at, false, true)
	var burst := _fx_kinds(g)
	check("bare: a hit counted (%s: [killed, its hits, hits counted, sparks, impact sounds]) with no spark and no impact sound; without: as ever (%s: a spark and the impact); a bare kill (%s) still bursts (%s, the burst's sound %d, no spark)" % [
		bare, plain, last, burst, _playing(g, "burst")],
		bare == [false, 1, 1, 0, 0] and plain == [false, 2, 1, 1] and last and not g.alive(raider) and burst.has("fireball") and burst.has("smoke")
		and not burst.has("spark") and _playing(g, "burst") >= 1)
	_clear(v, g)


func check_cost(v, g) -> void:
	var m = g.mount
	for c in _fleet:      # (traffic's own fleet back)
		v.traffic_net.cars.append(c)
	# ... made up to traffic's most (TARGET, near a city: 220), commuters along the road from 2 km behind to 4 km ahead.
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var hw: float = _road(v)[1]
	while v.traffic_net.cars.size() < v.traffic_net.TARGET:
		_car(v, _ahead(v, rng.randf_range(-2000.0, 4000.0), rng.randf_range(-0.8, 0.8) * hw), false)
	for k in 6:      # (a full raid: six raiders, ten drones, the gunship)
		_car(v, _ahead(v, 800.0 + 300.0 * k, (float(k % 3) - 1.0) * 0.5 * hw), true)
	for k in 10:
		var up := _ahead(v, 900.0 + 150.0 * k, (float(k) - 4.5) * 60.0)
		_flyer("drone", Vector3(up.x, up.y, v.sim.pod.z + 200.0 + 10.0 * k))
	var at := _ahead(v, 300.0, 0.0)
	var ship = _flyer("gunship", Vector3(at.x, at.y, v.sim.pod.z + 20.0), 1000000)
	_frames(v, g, 5, ship)
	g.hold_fire = true
	var costs := PackedFloat32Array()
	var whole := PackedFloat32Array()
	var frames := 0
	while costs.size() < 600 and frames < int(12.0 / DT):
		var t0 := Time.get_ticks_usec()
		_frame(v, g, ship)
		frames += 1
		if m.burning:
			whole.append((Time.get_ticks_usec() - t0) / 1000.0)
			costs.append(m.cost_ms)
	g.hold_fire = false
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
	print("  COST: the mount's own step and fire, the beam on a gunship among %d threats, %d vehicles about: %.4f ms a frame mean, %.4f worst, over %d frames of burn (the whole fire control's step %.4f mean)" % [
		g.threats().size(), v.traffic_net.cars.size(), mean, worst, costs.size(), whole_mean])
	check("the beam held on a gunship among a full raid (%d threats) with traffic's fleet about (%d) for 600 frames of burn: the mount %.4f ms a frame mean (under %.2f), %.4f worst" % [
		g.threats().size(), v.traffic_net.cars.size(), mean, COST_MS, worst], costs.size() == 600 and g.threats().size() == 17 and mean < COST_MS)
	_clear(v, g)


## The flat view (view/craft_view.gd: the GUN is K, the trigger F) on the Range: the arms on the craft's own pod.
func check_flat_range() -> void:
	View.track_override = "range"
	View.vehicle_override = Pilot.KILN
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
	var burned := 0
	if mount == null or not mount.has_method("buzz"):
		check("the flat view on the Range: the Kiln's weapon is the lance's mount (%s)" % mount, false)
		game.queue_free()
		await process_frame
		View.track_override = "network"
		return
	if g != null:
		g.hold_fire = true
		for i in 10:
			game._process(DT)
			burned += int(mount.burning)
		g.hold_fire = false
	check("the flat view on the Range: nothing built till armed (%s); armed, the fire control (%s) and the Arms on the craft's own pod (%s), out (deploy %.2f), drawn; the trigger burns (%d of 10 frames, drawn %s)" % [
		none, g != null, arms, mount.deploy_t(), burned, mount.beam.visible if mount.get("beam") != null else null],
		none and g != null and g.mount == mount and arms != null and mount.get("arms") == arms and mount.is_out() and arms.is_visible_in_tree()
		and burned == 10)
	game.queue_free()
	await process_frame
	View.track_override = "network"


## Raids on: the fire control made at load, dormant, and (Ruling D: the first arming measured over 5 ms) the arms built
## then, stowed, the seat's hull as it was; the first arming builds nothing more.
func check_raids_on_arming(v) -> void:
	var hull: MeshInstance3D = v.shell.get_node("PodHull")
	var g = v.gunnery
	var mount = v.craft.weapon
	if g == null or mount == null:
		check("Raids on: a fire control made at load and the lance's mount (%s, %s)" % [g, mount], false)
		return
	var stowed_arms = hull.get_node_or_null("Arms")
	var closed: Mesh = hull.mesh
	check("Raids on: the fire control is made at load, dormant (%s), through the lance's mount; the Arms built then on the seat's hull (%s), stowed: not drawn (%s), the hull its own mesh (%s)" % [
		g != null and g.dormant, stowed_arms, stowed_arms.visible if stowed_arms != null else null, closed == v.craft.fleet.part(&"Cab")],
		g != null and g.dormant and mount != null and g.mount == mount and stowed_arms != null and mount.get("arms") == stowed_arms
		and not stowed_arms.visible and closed == v.craft.fleet.part(&"Cab") and mount.deploy_t() == 0.0)
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
	check("armed: the fire control awake (%s), the same Arms (%s), coming out (deploy %.3f), drawn (%s)" % [g != null and not g.dormant,
		arms == stowed_arms, mount.deploy_t(), arms.visible if arms != null else null],
		g != null and not g.dormant and arms != null and arms == stowed_arms and mount.deploy_t() > 0.0 and arms.visible)


## (On the Raids-on seat, armed above.) The cockpit's own frames: out, the trigger held, then SAFE.
func check_buzz(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	if g == null or m == null or not m.has_method("buzz"):
		check("a lance's fire control and mount to feel (%s, %s)" % [g, m], false)
		return
	var hand: XRController3D = v.hands.left
	for i in int(1.2 / DT):
		_hold_speed(v)
		v._process(DT)
	g.hold_fire = true
	var sent := []          # each burning frame's pulses: [how many, to the left hand, amp, s, delay]
	var burned := 0
	for i in 30:
		v.gun_pulses.clear()
		_hold_speed(v)
		v._process(DT)
		if m.burning:
			burned += 1
			for p: Array in v.gun_pulses:
				sent.append([v.gun_pulses.size(), p[0] == hand, snappedf(float(p[1]), 0.001), snappedf(float(p[2]), 1e-5), float(p[3])])
	var amp: float = (m.get_script() as Script).get_script_constant_map().get("BUZZ_AMP", -1.0)
	var want := [1, true, snappedf(amp, 0.001), snappedf(DT, 1e-5), 0.0]
	var each_frame := sent.size() == burned and sent.all(func(s: Array) -> bool: return s == want)
	v.gun_wanted = false      # (SAFE)
	v.gun_pulses.clear()
	_hold_speed(v)
	v._process(DT)
	var at_safe: int = v.gun_pulses.size()
	var off: bool = not m.burning
	var later := 0
	for i in 10:
		v.gun_pulses.clear()
		_hold_speed(v)
		v._process(DT)
		later += v.gun_pulses.size()
	g.hold_fire = false
	check("on the seat's own frames, held: it burns %d of 30 frames, a pulse to the left hand each of them (%s; want each %s: one, a frame long, no delay); SAFE thrown: the beam off that frame (%s), %d pulse(s) that frame, %d in the 10 after" % [
		burned, sent.slice(0, 2), want, off, at_safe, later], burned >= 28 and each_frame and off and at_safe == 0 and later == 0)
