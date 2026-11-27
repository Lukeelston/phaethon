## The Vesper's shock pulse (view/weapons/pulse_mount.gd on Codex's arms, view/arms/vesper_arms.gd; fired for itself through
## view/gunnery.gd's own-fire hook). In the VR seat on the Network (XR off), the Vesper on a straight at 1,500 mph. Raids
## are pinned off, so the GUN's first arming makes the fire control and the arms; once armed the world is held still and
## the fire control stepped on its own (the craft stands where it is: the ring spreads round it as round a craft at
## rest), every target is put where the test wants it, and (after the commuters' check, which has no raid) a director of
## the test's own is put in (never updated), so its raiders are a raid's pack and its kills are counted (kills_by).
## Distances are from the release point, the wheel's centre (its muzzle), as the ring's are: in the round for a flyer,
## over the ground for a raider:
##   check_table            weapon_of(VESPER) is "pulse", its weapon row is the brief's, and it is armed
##   check_lazy             with the GUN never armed: no Arms node on either hull, no fire control (Raids off); armed: the
##                          fire control is made, firing for itself through the pulse's mount, the Arms on the hull the
##                          seat sees (not the hidden pod), out in 1 s. The first arming's frame is told (Ruling D)
##   check_ignores_commuters   (Review Focus 5) no raid on: a ring released among ten commuters 40 to 400 m round the
##                          craft: all ten still in traffic, no strike, nothing hit, struck_commuter never told, the score
##                          unchanged; the ring did go out
##   check_ring_kills_in_radius   raiders at 100, 300 and 440 m and drones at 200 m (80 m up) and 430 m, and a raider at
##                          the radius itself: all six die, each no sooner than the ring reaches it (spreadS x d /
##                          radius) and at most a frame after, each hit once, bare (no spark or impact sound of a hit's
##                          own; the kill's burst); a raider at 470 m and a drone 440 m off over the ground but 140 m up
##                          (462 m in the round) live, untouched
##   check_gunship_never_killed_fresh   a 120 HP gunship inside takes 72 (seen and heard as a hit: a spark and the impact
##                          sound) and lives; the charge ends 12 s after the release ("PULSE READY" on the strip) and a
##                          second pulse then kills it
##   check_recharge         the trigger at 11.9 s does nothing; at 12.0 s a second ring leaves; the wheel's heat follows the
##                          charge (half at 6 s); a trigger held down through the next charge's end releases nothing (a
##                          press, not a hold) until it is let go and pressed again
##   check_safe_mid_use     (Review Focus 3, Ruling V) SAFE thrown 0.1 s into a spread: the ring finishes it and its raider
##                          at 400 m dies on time; SAFE at 4 s into the recharge, GUN at 6 s: 6 s are left, not refilled;
##                          charged, at SAFE a press releases nothing (stowed), nor once GUN is thrown before it is out
##   check_raid_ends_mid_spread   (Ruling V) a raider shot by other means mid-spread: no hit on it after, one kill; the
##                          raid reset mid-spread: no hit and no kill after, no error, and a raider and a drone put down
##                          after it, ahead of the ring, are not hit by it
##   check_sims_frame       the floating origin moved 36 km mid-spread: the ring drawn where its figures say about it
##                          (the sims' frame), and its raider dies on time
##   check_drawn            (Ruling V, the comfort rule) at rest: not drawn till its band is COMFORT m off the pod and
##                          each engine (the frame and radius it first shows at told), never drawn nearer them; flat, on the
##                          road's plane under the release point; drawn at 150 m and at 450 m, fading; gone after its spread
##   check_cost             a ring among a full raid (6 raiders, 10 drones, the gunship) with traffic's most (220) about,
##                          ten times: the mount's own time a frame (its step and fire) over each ring's frames, mean and
##                          worst, the release frames and the frames kills land on told apart; the mean held under COST_MS
##   check_flat_range       the flat view on the Range (no seat, no traffic, no raid): nothing built till armed; armed, the
##                          fire control and the arms on the craft's own pod, out in about a second; a press releases a ring
##   check_raids_on_arming  Raids on (Ruling D: the first arming measured over 5 ms): the fire control made at load,
##                          dormant, and the arms fitted then on the seat's hull, stowed (not drawn, the hull its own); the
##                          first arming's frame told; armed, the same arms come out
##   check_hand_tick        on that seat's own frames (vr_cockpit.gd _process), a release: one strong tick in each hand
##                          that frame, below a jolt's (an event: each hand held its length), sent at once (no delay: the
##                          engine ignores one); none in the frames after, none for a press while it recharges; no shot
##                          counted (no per-shot tick)
##   check_no_flash         on the same seat's own frames at 1,500 mph, a release and its whole spread: no CanvasLayer's
##                          shown or child count changed, the camera's offsets, field of view and children as they were,
##                          the jolt's vignette at 0; the band never drawn within COMFORT m of the pod or an engine
## Run with --fixed-fps 120: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_pulse.gd -- --mute
## Prints PULSE PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const View := preload("res://view/craft_view.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Sim := preload("res://sim/craft_sim.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const Raids := preload("res://view/network_raids.gd")
const Flyers := preload("res://view/raid_flyers.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const ROW := {"radius": 450.0, "rechargeS": 12.0, "gunshipFrac": 0.6, "spreadS": 0.5}
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const MPH := 0.44704
const SPEED := 1500.0 * MPH     # m/s
const STRAIGHT := 1600.0        # m of road ahead that must run straight and level
const COST_MS := 0.10           # the mount's own mean a frame over a ring's frames among a full raid, at the most
const COMFORT := 20.0           # m: the ring's band is never drawn nearer the pod or an engine (over the ground) than this
const SECTIONS := 15
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var _next_id := 996000
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
	Seat.best_dir = OS.get_user_data_dir().path_join("test_pulse_")
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
	var v = await _seat(Pilot.VESPER)
	var g = check_lazy(v)
	if g != null:
		sections += 1
		check_ignores_commuters(v, g)
		sections += 1
		_put_director(v, g)
		check_ring_kills_in_radius(v, g)
		sections += 1
		check_gunship_never_killed_fresh(v, g)
		sections += 1
		check_recharge(v, g)
		sections += 1
		check_safe_mid_use(v, g)
		sections += 1
		check_raid_ends_mid_spread(v, g)
		sections += 1
		check_sims_frame(v, g)
		sections += 1
		check_drawn(v, g)
		sections += 1
		check_cost(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	await check_flat_range()
	sections += 1
	Raids.enabled = true
	v = await _seat(Pilot.VESPER)
	if check_raids_on_arming(v):
		sections += 1
		check_hand_tick(v)
		sections += 1
		check_no_flash(v)
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
	print("PULSE %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
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
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 400:
			continue
		var from := clampi(int(sim.pod.hint), 300, R.N - span - 100) if r == roads[0] else 300
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


## The road's way at the pod (a unit vector in the sims' plane).
func _road_way(v) -> Vector2:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	return Vector2(R.tx[i], R.ty[i]) * _way


## Where a ring released now would leave: the wheel's centre (its muzzle), the sims' frame.
func _centre(g) -> Vector3:
	return g.to_sim((g.mount.arms.muzzles()[0] as Transform3D).origin)


## A sims' point `dist` m over the ground from the release point (_centre), `bearing` degrees left of the road's way (0
## ahead, 180 behind, -90 to the right), `up` m over the release point's height.
func _point(v, g, dist: float, bearing: float, up := 0.0) -> Vector3:
	var c := _centre(g)
	var dir := _road_way(v).rotated(deg_to_rad(bearing))
	return Vector3(c.x + dir.x * dist, c.y + dir.y * dist, c.z + up)


## A vehicle at `at` (the sims' plane), standing still, on the craft's road's nearest sample: a commuter, or a raider of
## the raid's pack.
func _car(v, at: Vector2, hostile: bool):
	var T = v.traffic_net
	var sim = v.sim
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var h := int(sim.pod.hint)
	var near := h
	for i in range(maxi(0, h - int(1200.0 / float(Sim.NET_STEP))), mini(R.N - 1, h + int(1800.0 / float(Sim.NET_STEP)))):
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
	if hostile and _director != null:
		_director.pack.append(c)
	return c


## A raider `dist` m over the ground from the release point, `bearing` degrees left of the road's way.
func _raider_at(v, g, dist: float, bearing: float):
	var p := _point(v, g, dist, bearing)
	return _car(v, Vector2(p.x, p.y), true)


## A flyer of the raid's (view/raid_flyers.gd), put up by hand at `at` (the sims' frame): never flown. `kind` "drone" (its
## own HP) or "gunship" (GUNSHIP_HP), or `hp` of its own.
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


## A target's distance from the release point `c`: in the round for a flyer, over the ground for a vehicle.
static func _dist(c: Vector3, t) -> float:
	if GunneryScript._is_flyer(t):
		return c.distance_to(Vector3(t.x, t.y, t.z))
	return Vector2(c.x, c.y).distance_to(Vector2(t.x, t.y))


## The gaze from the seat's eye, ahead along the rig (the pulse is not aimed: the gaze only lays the fire control's sight).
func _look(v) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * Vector3(0.0, -0.03, -1.0).normalized(), rig.basis.y)


## One frame of the still world: the gaze laid, the fire control stepped.
func _frame(v, g, dt := DT) -> void:
	_look(v)
	g.step(dt)


## `n` frames of it.
func _frames(v, g, n: int) -> void:
	for i in n:
		_frame(v, g)


## The trigger pressed for a frame (a press: the frame after, let go). Whether a ring left in that frame.
func _press(v, g) -> bool:
	var m = g.mount
	var was: int = m.released
	g.hold_fire = true
	_frame(v, g)
	g.hold_fire = false
	return m.released > was


## Frames, the trigger let go, until the ring is over and the pulse is charged again (13 s at the most).
func _charged(v, g) -> void:
	g.hold_fire = false
	var m = g.mount
	for i in int(13.0 / DT):
		if m.charge <= 0.0 and m.ring_t < 0.0:
			break
		_frame(v, g)
	_frame(v, g)


## Charged again, the vehicles and flyers gone, and the director's counts back to none.
func _clear(v, g) -> void:
	_charged(v, g)
	v.traffic_net.cars.clear()
	if _director != null:
		_director.pack.clear()
		_director.flyers._list.clear()
		_director.kills = 0
		_director._zero_kills_by()
		_director._killed.clear()
		_director.state = ""
	g._damage.clear()
	_frame(v, g)


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


## The mount's figure `name` (a constant of its script), or `none`.
static func _const(m, name: String, none = null):
	return (m.get_script() as Script).get_script_constant_map().get(name, none)


## The ring's band as drawn this frame over the ground about the release point: [inner, outer] m, or [] when not drawn.
static func _band(m) -> Array:
	if m.ring == null or not m.ring.visible:
		return []
	var r: float = m.drawn_r
	return [r * (1.0 - float(_const(m, "BAND", 0.0))), r]


## How near the drawn band comes to the pod or an engine, over the ground (INF when it is not drawn).
static func _band_off_craft(v, m) -> float:
	var band := _band(m)
	if band.is_empty():
		return INF
	var c: Vector3 = m.centre
	var least := INF
	for b in [v.sim.pod, v.sim.eL, v.sim.eR]:
		var d := Vector2(b.x - c.x, b.y - c.y).length()
		var off := 0.0
		if d < band[0]:
			off = band[0] - d
		elif d > band[1]:
			off = d - band[1]
		least = minf(least, off)
	return least


# --- the checks ----------------------------------------------------------------------------------------------

func check_table() -> void:
	var row: Dictionary = Pilot.traits(Pilot.VESPER).weapon
	check("the Vesper carries \"%s\" (pulse), armed %s, its weapon row %s" % [Pilot.weapon_of(Pilot.VESPER), Pilot.armed(Pilot.VESPER), row],
		Pilot.weapon_of(Pilot.VESPER) == "pulse" and Pilot.armed(Pilot.VESPER) and row == ROW)


## The GUN never armed, then armed (the first time: the fire control and the arms are made then), the world held still,
## and the wheel brought out. The fire control, or null (its failure told).
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
	check("armed, its fire control is made, firing for itself through the pulse's mount (%s), the Arms on the seat's hull (%s), none on the hidden pod" % [
		script_path, arms], g != null and script_path.ends_with("pulse_mount.gd") and v.craft.weapon == mount and mount.own_fire()
		and arms != null and mount.get("arms") == arms and v.craft.pod.get_node_or_null("Arms") == null)
	if g == null or not script_path.ends_with("pulse_mount.gd") or arms == null:
		return null
	check("the mount's figures are the row's: %.0f m in %.2f s, %.0f s to recharge, %.2f of the gunship's HP" % [
		mount.radius, mount.spread_s, mount.recharge_s, mount.gunship_frac], is_equal_approx(mount.radius, 450.0)
		and is_equal_approx(mount.spread_s, 0.5) and is_equal_approx(mount.recharge_s, 12.0) and is_equal_approx(mount.gunship_frac, 0.6))
	# From here the world is still: the fire control is stepped alone, every target where the test puts it.
	_fleet = v.traffic_net.cars.duplicate()
	v.traffic_net.cars.clear()
	g.power = 1.0
	g.want_out = true
	var begun: float = mount.deploy_t()      # (the view's own frames since the switch)
	var frames := 0
	while not mount.is_out() and frames < int(2.0 / DT):
		_frame(v, g)
		frames += 1
	var took := begun * 1.0 + frames * DT
	check("out in %.3f s (1.0; %.3f of it in the view's frames since the switch): the leaves open and the wheel rises and fans out (deploy %.2f), the arms drawn; charged (%.1f s to go), its word \"%s\"" % [
		took, begun, mount.deploy_t(), mount.charge, mount.status()], mount.is_out() and absf(took - 1.0) <= 2.0 * DT and begun > 0.0
		and arms.visible and mount.charge == 0.0)
	return g


## (Review Focus 5) No raid on (no director: the view's own, Raids off): ten commuters round the craft, 40 to 400 m out
## (all inside the ring's radius), a ring released among them.
func check_ignores_commuters(v, g) -> void:
	var m = g.mount
	var T = v.traffic_net
	var ten := []
	for k in 10:
		var p := _point(v, g, 40.0 + 40.0 * k, 36.0 * k)
		ten.append(_car(v, Vector2(p.x, p.y), false))
	var strikes: int = g.commuter_strikes
	var hits: int = g.hits
	var kills: int = g.kills
	var told := []
	var on_struck := func(car) -> void: told.append(car)
	g.struck_commuter.connect(on_struck)
	var score = v.skill_score.total if v.skill_score != null else null
	var left := _press(v, g)
	var widest := 0.0
	for i in int(0.8 / DT):
		_frame(v, g)
		widest = maxf(widest, m.ring_r)
	g.struck_commuter.disconnect(on_struck)
	var still := ten.filter(func(c) -> bool: return T.cars.has(c)).size()
	var score_now = v.skill_score.total if v.skill_score != null else null
	check("no raid on (%s): a ring released (%s) and spread to %.0f m among ten commuters 40 to 400 m round the craft: %d still in traffic, strikes %d -> %d, hits %d -> %d, kills %d -> %d, struck told %d time(s), the score %s -> %s" % [
		v.raids, left, widest, still, strikes, g.commuter_strikes, hits, g.hits, kills, g.kills, told.size(), score, score_now],
		v.raids == null and left and widest >= 450.0 - 1e-3 and still == 10 and g.commuter_strikes == strikes and g.hits == hits
		and g.kills == kills and told.is_empty() and score == score_now)
	for c in ten:
		T.cars.erase(c)
	_charged(v, g)


## The director of the test's own, put in once armed: its raiders are a raid's pack (as in a flight), never updated.
func _put_director(v, g) -> void:
	_director = Raids.new()
	v.add_child(_director)
	_director.traffic = v.traffic_net
	_director.build(v)
	v.raids = _director
	v.traffic_net.raids = _director
	g.killed.connect(_director.on_kill)      # (as the view connects it: craft_view.gd, the frame)


## The frames after a release until each of `targets` is gone (or the ring is over): {target: frames after the release
## frame it went in}. The spark and impact-sound counts while it ran are put in `seen` (["spark", n], ["impact", n]).
func _spread(v, g, targets: Array, seen := {}) -> Dictionary:
	var m = g.mount
	var gone := {}
	var sparks := 0
	var impacts := 0
	for k in range(1, int(0.9 / DT)):
		_frame(v, g)
		sparks += _fx_kinds(g).count("spark")
		impacts += _playing(g, "impact")
		for t in targets:
			if not gone.has(t) and not g.alive(t):
				gone[t] = k
		if m.ring_t < 0.0:
			break
	seen["spark"] = sparks
	seen["impact"] = impacts
	return gone


func check_ring_kills_in_radius(v, g) -> void:
	var m = g.mount
	var c0 := _centre(g)
	var dying := [
		["a raider 100 m ahead", _raider_at(v, g, 100.0, 0.0)],
		["a raider 300 m behind", _raider_at(v, g, 300.0, 180.0)],
		["a raider 440 m off to the left", _raider_at(v, g, 440.0, 60.0)],
		["a drone 200 m off, 80 m up", _flyer("drone", _point(v, g, 200.0, -35.0, 80.0))],
		["a drone 430 m behind", _flyer("drone", _point(v, g, 430.0, 150.0, 15.0))],
		["a raider at the radius, 450 m off to the right", _raider_at(v, g, 450.0, -90.0)],
	]
	var living := [
		["a raider 470 m ahead", _raider_at(v, g, 470.0, 0.0)],
		["a drone 440 m off over the ground, 140 m up", _flyer("drone", _point(v, g, 440.0, 110.0, 140.0))],
	]
	_frames(v, g, 3)
	_hush(g)
	g._fx.clear()
	var hits: int = g.hits
	var kills: int = g.kills
	var left := _press(v, g)
	var centred: float = m.centre.distance_to(c0)
	var all := []
	for d: Array in dying + living:
		all.append(d[1])
	var seen := {}
	var gone := _spread(v, g, all, seen)
	var said := []
	var on_time := true
	for d: Array in dying:
		var t = d[1]
		var dist := _dist(c0, t)
		var due := 0.5 * dist / 450.0
		var at := float(gone.get(t, -1)) * DT
		var ok: bool = gone.has(t) and at >= due - 1e-6 and at <= due + DT + 1e-6
		on_time = on_time and ok
		said.append("%s (%.1f m): gone %.4f s in, due %.4f%s" % [d[0], dist, at, due, "" if ok else " WRONG"])
	var spared := true
	for d: Array in living:
		var t = d[1]
		var untouched: bool = g.alive(t) and (int(t.hp) == int(t.hp_max) if GunneryScript._is_flyer(t) else not g._damage.has(t.id))
		spared = spared and untouched
		said.append("%s (%.1f m): %s" % [d[0], _dist(c0, t), "lives, untouched" if untouched else "TOUCHED"])
	check("a ring released (%s) from the wheel's centre (%.4f m off it): %s" % [left, centred, "; ".join(said)],
		left and centred < 0.01 and on_time and spared)
	check("each hit once (hits %d -> %d: six), kills %d -> %d, the director's by kind %s (four raiders, two drones); bare: no spark (%d) and no impact sound (%d) of a hit's own, the kills' bursts drawn" % [
		hits, g.hits, kills, g.kills, _director.kills_by, seen.spark, seen.impact],
		g.hits == hits + 6 and g.kills == kills + 6 and int(_director.kills_by.raider) == 4 and int(_director.kills_by.drone) == 2
		and int(seen.spark) == 0 and int(seen.impact) == 0)
	_clear(v, g)


func check_gunship_never_killed_fresh(v, g) -> void:
	var m = g.mount
	var ship = _flyer("gunship", _point(v, g, 300.0, 20.0, 40.0))
	_frames(v, g, 3)
	_hush(g)
	g._fx.clear()
	v._power_note = ""
	var left := _press(v, g)
	var sparked := 0
	var heard := 0
	var hit_at := -1
	var elapsed := 0      # (frames since the release's)
	for k in range(1, int(0.9 / DT)):
		_frame(v, g)
		elapsed += 1
		if hit_at < 0 and int(ship.hp) < Flyers.GUNSHIP_HP:
			hit_at = k
			sparked = _fx_kinds(g).count("spark")
			heard = _playing(g, "impact")
		if m.ring_t < 0.0:
			break
	var after_one := int(ship.hp)
	var alive_one: bool = g.alive(ship)
	while m.charge > 0.0 and elapsed < int(13.0 / DT):
		_frame(v, g)
		elapsed += 1
	var said: String = v._power_note
	var word: String = m.status()
	var second := _press(v, g)
	var gone := _spread(v, g, [ship])
	check("a %d HP gunship 300 m off: one ring (%s) leaves it %d HP (48: 72 taken), alive (%s), hit %.3f s in, seen and heard as a hit (sparks %d, impact sounds %d); charged %.3f s after the release (12), \"%s\" (\"%s\" on the strip); a second ring (%s) shoots it down %.3f s in (alive %s); the director's gunships %d" % [
		Flyers.GUNSHIP_HP, left, after_one, alive_one, hit_at * DT, sparked, heard, elapsed * DT, word, said, second,
		float(gone.get(ship, -1)) * DT, g.alive(ship), _director.kills_by.gunship],
		left and after_one == Flyers.GUNSHIP_HP - 72 and alive_one and sparked >= 1 and heard >= 1 and absf(elapsed * DT - 12.0) <= DT + 1e-6
		and word == "PULSE READY" and said == "PULSE READY" and second and gone.has(ship) and not g.alive(ship) and int(_director.kills_by.gunship) == 1)
	_clear(v, g)


func check_recharge(v, g) -> void:
	var m = g.mount
	var before: int = m.released
	var first := _press(v, g)
	var half := -1.0
	var early := false
	var at_12 := false
	for k in range(1, int(12.0 / DT) + 1):
		if k == int(round(11.9 / DT)):
			early = _press(v, g)
		elif k == int(round(12.0 / DT)):
			at_12 = _press(v, g)
		else:
			_frame(v, g)
		if k == int(round(6.0 / DT)):
			half = m.heat()
	check("a ring (%s); the trigger pressed at 11.9 s: nothing leaves (%s); at 12.0 s a second ring leaves (%s), %d in these 12 s; the wheel's heat %.3f at 6 s (half: the charge's)" % [
		first, early, at_12, m.released - before, half], first and not early and at_12 and m.released - before == 2 and absf(half - 0.5) < 0.01)
	# Held down through the next charge's end: nothing leaves while it is held; let go and pressed, one does.
	var was: int = m.released
	for k in range(1, int(12.1 / DT) + 1):
		g.hold_fire = k >= int(round(11.9 / DT))
		_frame(v, g)
	var while_held: int = m.released - was
	var charged_then: bool = m.charge == 0.0
	g.hold_fire = false
	_frame(v, g)
	var pressed := _press(v, g)
	check("the trigger held down from 11.9 s to 12.1 s into the next charge: %d ring(s) leave while it is held (charged at 12: %s); let go and pressed again, one leaves (%s)" % [
		while_held, charged_then, pressed], while_held == 0 and charged_then and pressed)
	_clear(v, g)


func check_safe_mid_use(v, g) -> void:
	var m = g.mount
	var raider = _raider_at(v, g, 400.0, 0.0)
	var c0 := _centre(g)
	_frames(v, g, 3)
	var left := _press(v, g)
	var gone_at := -1
	var drawn_after := false
	for k in range(1, int(0.9 / DT)):
		if k == int(round(0.1 / DT)):
			g.want_out = false      # (SAFE, 0.1 s into the spread)
		_frame(v, g)
		if gone_at < 0 and not g.alive(raider):
			gone_at = k
		if k > int(round(0.1 / DT)) and m.ring != null and m.ring.visible:
			drawn_after = true
	var due := 0.5 * _dist(c0, raider) / 450.0
	check("SAFE thrown 0.1 s into a spread (a ring left: %s): the ring finishes it (drawn after: %s), its raider %.1f m off gone %.4f s in (due %.4f)" % [
		left, drawn_after, _dist(c0, raider), gone_at * DT, due], left and drawn_after and gone_at > 0 and gone_at * DT >= due - 1e-6
		and gone_at * DT <= due + DT + 1e-6)
	# SAFE at 4 s into the recharge (the release above), GUN at 6 s.
	g.want_out = true
	_charged(v, g)
	_frames(v, g, int(1.1 / DT))
	var again := _press(v, g)
	for k in range(1, int(round(6.0 / DT)) + 1):
		if k == int(round(4.0 / DT)):
			g.want_out = false      # (SAFE, 4 s into the recharge ...)
		elif k == int(round(6.0 / DT)):
			g.want_out = true       # (... and GUN at 6 s)
		_frame(v, g)
	var left_s: float = m.charge
	check("SAFE at 4 s into a recharge (a ring left: %s), GUN at 6 s: %.3f s are left (6: its clock ran at SAFE, not refilled), its word \"%s\", the wheel's heat %.3f (0.5)" % [
		again, left_s, m.status(), m.heat()], again and absf(left_s - 6.0) <= 2.0 * DT + 1e-6 and m.status() == "" and absf(m.heat() - 0.5) < 0.01)
	# Charged: at SAFE a press releases nothing; GUN thrown, nothing before the wheel is out; out, one leaves.
	_charged(v, g)
	var word: String = m.status()
	g.want_out = false
	_frames(v, g, int(1.1 / DT))
	var at_safe := _press(v, g)
	g.want_out = true
	_frames(v, g, int(0.5 / DT))
	var coming := _press(v, g)
	_frames(v, g, int(0.7 / DT))
	var out := _press(v, g)
	check("charged (\"%s\"): at SAFE, the wheel stowed, a press releases nothing (%s); GUN thrown, half out, nothing (%s); out, a ring leaves (%s)" % [
		word, at_safe, coming, out], word == "PULSE READY" and not at_safe and not coming and out)
	_clear(v, g)


## (Ruling V) Its raider shot down by other means mid-spread, and the raid reset mid-spread.
func check_raid_ends_mid_spread(v, g) -> void:
	var m = g.mount
	var raider = _raider_at(v, g, 300.0, 0.0)
	_frames(v, g, 3)
	var left := _press(v, g)
	_frames(v, g, int(round(0.1 / DT)))
	var kills: int = g.kills
	g.damage(raider, GunneryScript.HOSTILE_HP, Vector3(raider.x, raider.y, v.traffic_net.body_height(raider)))      # (shot down by other means)
	var hits: int = g.hits
	for i in int(0.8 / DT):
		_frame(v, g)
	check("its raider 300 m off shot down by other means 0.1 s into the spread (a ring left: %s): no hit after (%d -> %d), kills %d -> %d (that one shot alone)" % [
		left, hits, g.hits, kills, g.kills], left and g.hits == hits and g.kills == kills + 1)
	_clear(v, g)
	# The raid reset (the director's: a restart, a respawn) with the ring under way and threats ahead of it.
	_director.state = "on"
	var ahead := [_raider_at(v, g, 400.0, 0.0), _flyer("drone", _point(v, g, 350.0, 30.0, 60.0)), _flyer("gunship", _point(v, g, 420.0, -20.0, 50.0))]
	_frames(v, g, 3)
	left = _press(v, g)
	_frames(v, g, int(round(0.2 / DT)))
	_director.reset()
	hits = g.hits
	kills = g.kills
	var gone: bool = ahead.all(func(t) -> bool: return not g.alive(t))
	var late := [_raider_at(v, g, 420.0, 0.0), _flyer("drone", _point(v, g, 300.0, 90.0, 30.0))]      # (put down after it, ahead of the ring)
	for i in int(0.8 / DT):
		_frame(v, g)
	var late_ok: bool = late.all(func(t) -> bool: return g.alive(t) and (int(t.hp) == int(t.hp_max) if GunneryScript._is_flyer(t) else not g._damage.has(t.id)))
	check("the raid reset 0.2 s into a spread (a ring left: %s; the threats ahead of it gone: %s): no hit after (%d -> %d), no kill (%d -> %d, the director's %d); a raider and a drone put down after it, ahead of the ring, not hit by it (%s)" % [
		left, gone, hits, g.hits, kills, g.kills, _director.kills, late_ok], left and gone and g.hits == hits and g.kills == kills
		and _director.kills == 0 and late_ok)
	_clear(v, g)


## The floating origin moved mid-spread: the ring stays where it was released (the sims' frame).
func check_sims_frame(v, g) -> void:
	var m = g.mount
	var raider = _raider_at(v, g, 300.0, 0.0)
	var c0 := _centre(g)
	_frames(v, g, 3)
	var org := Vector2(v.org_x, v.org_y)
	var left := _press(v, g)
	_frames(v, g, int(round(0.1 / DT)))
	v.org_x += 30000.0      # (the origin moved 36 km: everything drawn about it is drawn 36 km over)
	v.org_y -= 20000.0
	var off := INF
	var gone_at := -1
	for k in range(int(round(0.1 / DT)) + 1, int(0.9 / DT)):
		_frame(v, g)
		if gone_at < 0 and not g.alive(raider):
			gone_at = k
		if k == int(round(0.3 / DT)) and m.ring.visible:
			var want := Vector3(m.centre.x - v.org_x, m.ring_h, -(m.centre.y - v.org_y))
			off = Vector2(m.ring.global_position.x - want.x, m.ring.global_position.z - want.z).length()
	v.org_x = org.x
	v.org_y = org.y
	var due := 0.5 * _dist(c0, raider) / 450.0
	check("the floating origin moved 36 km 0.1 s into the spread (a ring left: %s): drawn %.4f m off where its figures say about it at 0.3 s (within 0.01); its raider gone %.4f s in (due %.4f)" % [
		left, off, gone_at * DT, due], left and off < 0.01 and gone_at > 0 and gone_at * DT >= due - 1e-6 and gone_at * DT <= due + DT + 1e-6)
	_frame(v, g)
	_clear(v, g)


## (Ruling V, the comfort rule) At rest (the world still): where and when the ring is drawn.
func check_drawn(v, g) -> void:
	var m = g.mount
	var c0 := _centre(g)
	var left := _press(v, g)
	var on_release: bool = m.ring != null and m.ring.visible
	var first := -1
	var first_r := 0.0
	var nearest := INF
	var at := {}          # radius drawn: [frame, light, flat, on the road's plane under the release point]
	var last_drawn := -1
	for k in range(1, int(1.0 / DT)):
		_frame(v, g)
		if m.ring == null or not m.ring.visible:
			continue
		last_drawn = k
		if first < 0:
			first = k
			first_r = m.drawn_r
		nearest = minf(nearest, _band_off_craft(v, m))
		if k == int(round(150.0 / 450.0 * 0.5 / DT)) or k == int(round(0.5 / DT)):
			var b: Basis = m.ring.global_basis
			var flat: bool = absf(b.y.normalized().dot(Vector3.UP)) > 0.9999 and absf(b.x.length() - m.drawn_r) < 1e-3 and absf(b.z.length() - m.drawn_r) < 1e-3
			var o: Vector3 = g.to_sim(m.ring.global_position)
			var road: float = g.ground_at(c0.x, c0.y)
			var placed: bool = Vector2(o.x - c0.x, o.y - c0.y).length() < 0.01 and o.z >= road and o.z <= road + 0.5
			at[snappedf(m.drawn_r, 0.1)] = [k, snappedf(float(m.ring_light), 0.001), flat, placed]
	var r150: Array = at.get(150.0, [])
	var r450: Array = at.get(450.0, [])
	print("  RING: first drawn %d frames after the release, at %.1f m (its band's inner edge %.1f m)" % [first, first_r, first_r * (1.0 - float(_const(m, "BAND", 0.0)))])
	check("a ring (%s): not drawn on the release frame (%s); first drawn %d frames on, at %.1f m; on every frame drawn its band %.1f m off the pod and the engines at the nearest (at least %.0f)" % [
		left, on_release, first, first_r, nearest, COMFORT], left and not on_release and first > 1 and nearest >= COMFORT)
	check("drawn at 150 m (%s) and at 450 m (%s) [frame, light, flat, on the road's plane under the release point]: fading; last drawn %d frames on (%.2f s: its spread and its linger), none after" % [
		r150, r450, last_drawn, last_drawn * DT], r150.size() == 4 and r450.size() == 4 and bool(r150[2]) and bool(r150[3]) and bool(r450[2])
		and bool(r450[3]) and float(r450[1]) < float(r150[1]) and float(r450[1]) > 0.0 and last_drawn > int(0.5 / DT) and last_drawn < int(1.0 / DT) - 1
		and m.ring_t < 0.0)
	check("it hangs in the world under the fire control (%s), not before the camera nor on a CanvasLayer" % [m.ring.get_parent().name if m.ring else null],
		m.ring != null and m.ring.get_parent() == g)
	_clear(v, g)


func check_cost(v, g) -> void:
	var m = g.mount
	for c in _fleet:      # (traffic's own fleet back)
		v.traffic_net.cars.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hw: float = float(v.sim.roads[v.sim.pod.path].w[int(v.sim.pod.hint)]) * 0.5
	var way := _road_way(v)
	var P := Vector2(v.sim.pod.x, v.sim.pod.y)
	while v.traffic_net.cars.size() < v.traffic_net.TARGET:      # (traffic's most, near a city: 220, along the road 2 km behind to 4 km ahead)
		var at := P + way * rng.randf_range(-2000.0, 4000.0) + Vector2(-way.y, way.x) * rng.randf_range(-0.8, 0.8) * hw
		_car(v, at, false)
	var ring_ms := PackedFloat32Array()
	var release_ms := PackedFloat32Array()
	var kill_ms := PackedFloat32Array()
	var whole := PackedFloat32Array()
	var kills := 0
	for round_k in 10:
		for k in 6:      # (a full raid: six raiders, ten drones, the gunship, all inside the radius)
			_raider_at(v, g, 80.0 + 60.0 * k, 50.0 * k + 15.0 * round_k)
		for k in 10:
			_flyer("drone", _point(v, g, 60.0 + 38.0 * k, 36.0 * k + 7.0 * round_k, 60.0 + 8.0 * k))
		_flyer("gunship", _point(v, g, 380.0, 15.0 * round_k, 60.0))
		_frames(v, g, 2)
		var before: int = g.kills
		var t0 := Time.get_ticks_usec()
		var left := _press(v, g)
		whole.append((Time.get_ticks_usec() - t0) / 1000.0)
		release_ms.append(m.cost_ms)
		ring_ms.append(m.cost_ms)
		while left and m.ring_t >= 0.0:
			var was: int = g.kills
			t0 = Time.get_ticks_usec()
			_frame(v, g)
			whole.append((Time.get_ticks_usec() - t0) / 1000.0)
			ring_ms.append(m.cost_ms)
			if g.kills > was:
				kill_ms.append(m.cost_ms)
		kills += g.kills - before
		_director.pack.clear()
		_director.flyers._list.clear()
		_charged(v, g)
	var said := []
	var mean_all := 0.0
	for set: Array in [["over the rings' frames", ring_ms], ["the release frames", release_ms], ["the frames kills landed on", kill_ms]]:
		var mean := 0.0
		var worst := 0.0
		for c: float in set[1]:
			mean += c
			worst = maxf(worst, c)
		mean /= maxf(1.0, (set[1] as PackedFloat32Array).size())
		if set[0] == "over the rings' frames":
			mean_all = mean
		said.append("%s (%d): %.4f ms mean, %.4f worst" % [set[0], (set[1] as PackedFloat32Array).size(), mean, worst])
	var whole_mean := 0.0
	for c: float in whole:
		whole_mean += c
	whole_mean /= maxf(1.0, whole.size())
	print("  COST: ten rings among a full raid (17 threats) with %d vehicles about: the mount's own step and fire %s; the whole fire control's step %.4f ms mean; %d kills" % [
		v.traffic_net.cars.size(), "; ".join(said), whole_mean, kills])
	check("ten rings among a full raid with traffic's fleet about (%d): the mount %.4f ms a frame mean over the rings' frames (under %.2f); %d kills (16 a ring: the gunship lives through one)" % [
		v.traffic_net.cars.size(), mean_all, COST_MS, kills], ring_ms.size() >= 10 * int(0.5 / DT) and mean_all < COST_MS and kills == 160)
	_clear(v, g)


## The flat view (view/craft_view.gd: the GUN is K, the trigger F) on the Range: the arms on the craft's own pod.
func check_flat_range() -> void:
	View.track_override = "range"
	View.vehicle_override = Pilot.VESPER
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
	if mount == null or mount.get("released") == null or g == null:
		check("the flat view on the Range: the Vesper's weapon is the pulse's mount (%s), a fire control made (%s)" % [mount, g], false)
		game.queue_free()
		await process_frame
		View.track_override = "network"
		return
	g.hold_fire = true
	game._process(DT)
	g.hold_fire = false
	var left: int = mount.released
	var drawn := false
	for i in int(0.6 / DT):
		game._process(DT)
		drawn = drawn or (mount.ring != null and mount.ring.visible)
	check("the flat view on the Range: nothing built till armed (%s); armed, the fire control (%s) and the Arms on the craft's own pod (%s), out (deploy %.2f), drawn; a press releases a ring (%d), drawn (%s)" % [
		none, g != null, arms, mount.deploy_t(), left, drawn],
		none and g.mount == mount and arms != null and mount.get("arms") == arms and mount.is_out() and arms.is_visible_in_tree() and left == 1 and drawn)
	game.queue_free()
	await process_frame
	View.track_override = "network"


## Raids on: the fire control made at load, dormant, and (Ruling D: the first arming measured over 5 ms) the arms built
## then, stowed, the seat's hull as it was; the first arming builds nothing more. Whether the checks after it can run.
func check_raids_on_arming(v) -> bool:
	var hull: MeshInstance3D = v.shell.get_node("PodHull")
	var g = v.gunnery
	var mount = v.craft.weapon
	if g == null or mount == null or mount.get("released") == null:
		check("Raids on: a fire control made at load and the pulse's mount (%s, %s)" % [g, mount], false)
		return false
	var stowed_arms = hull.get_node_or_null("Arms")
	var closed: Mesh = hull.mesh
	check("Raids on: the fire control is made at load, dormant (%s), through the pulse's mount; the Arms built then on the seat's hull (%s), stowed: not drawn (%s), the hull its own mesh (%s)" % [
		g.dormant, stowed_arms, stowed_arms.visible if stowed_arms != null else null, closed == v.craft.fleet.part(&"Cab")],
		g.dormant and g.mount == mount and stowed_arms != null and mount.get("arms") == stowed_arms
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
	check("armed: the fire control awake (%s), the same Arms (%s), coming out (deploy %.3f), drawn (%s)" % [not g.dormant,
		arms == stowed_arms, mount.deploy_t(), arms.visible if arms != null else null],
		not g.dormant and arms != null and arms == stowed_arms and mount.deploy_t() > 0.0 and arms.visible)
	return true


## One of the cockpit's own frames, the craft held at speed, the trigger held or not: the pulses sent in it.
func _seat_frame(v, g, held := false) -> Array:
	v.gun_pulses.clear()
	g.hold_fire = held
	_hold_speed(v)
	v._process(DT)
	g.hold_fire = false
	return v.gun_pulses.duplicate()


## (On the Raids-on seat, armed above.) The cockpit's own frames: out, a release.
func check_hand_tick(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	for i in int(1.2 / DT):
		_seat_frame(v, g)
	var shots: int = g.shots
	var was: int = m.released
	var sent := _seat_frame(v, g, true)
	var left: bool = m.released == was + 1
	var hands := [v.hands.left, v.hands.right]
	var got := []
	for p: Array in sent:
		got.append([hands.find(p[0]), snappedf(float(p[1]), 0.001), snappedf(float(p[2]), 0.001), float(p[3])])
	var held := [snappedf(float(v._buzz_hold.get(hands[0], 0.0)), 1e-4), snappedf(float(v._buzz_hold.get(hands[1], 0.0)), 1e-4)]
	var amp := float(got[0][1]) if got.size() == 2 else -1.0
	var dur := float(got[0][2]) if got.size() == 2 else -1.0
	var each: bool = got.size() == 2 and got[0][0] == 0 and got[1][0] == 1 and got[1][1] == got[0][1] and got[1][2] == got[0][2] \
		and float(got[0][3]) == 0.0 and float(got[1][3]) == 0.0
	var later := 0
	for i in 30:
		later += _seat_frame(v, g).size()
	var again := _seat_frame(v, g, true).size()      # (a press while it recharges)
	for i in 10:
		again += _seat_frame(v, g).size()
	check("on the seat's own frames, a release (%s): %s [hand (0 left, 1 right), amp, s, delay]: one tick in each hand, strong (%.2f: at least 0.5) and below a jolt's (1.0), at once; each hand held its length (%s s); none in the 30 frames after (%d), none for a press while it recharges (%d); no shot counted (%d -> %d)" % [
		left, got, amp, held, later, again, shots, g.shots], left and each and amp >= 0.5 and amp < 1.0 and dur > 0.0
		and absf(float(held[0]) - dur) < 1e-3 and absf(float(held[1]) - dur) < 1e-3 and later == 0 and again == 0 and g.shots == shots)


## The CanvasLayers under the view, each one's [shown, its children], and the camera's [h_offset, v_offset, fov, children].
static func _screen(v) -> Array:
	var layers := []
	for n: Node in v.find_children("*", "CanvasLayer", true, false):
		layers.append([String(v.get_path_to(n)), (n as CanvasLayer).visible, n.get_child_count()])
	var cam: Camera3D = v.cam
	return [layers, [cam.h_offset, cam.v_offset, cam.fov, cam.get_child_count()]]


## (On the same seat.) A release at 1,500 mph and its whole spread on the seat's own frames. The last ring over, it is
## charged by hand (the recharge is check_recharge's: 12 s more at speed would fly the craft off its straight) and the craft
## put on a straight again.
func check_no_flash(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	for i in int(1.0 / DT):
		if m.ring_t < 0.0:
			break
		_seat_frame(v, g)
	m.charge = 0.0
	_on_a_straight(v)
	for i in 10:
		_seat_frame(v, g)
	var before := _screen(v)
	_seat_frame(v, g, true)
	var left: bool = m.ring_t >= 0.0
	var same := true
	var glow := 0.0
	var nearest := INF
	var first := -1
	var first_r := 0.0
	var changed := []
	for k in range(1, int(0.8 / DT)):
		_seat_frame(v, g)
		var now := _screen(v)
		if now != before and changed.is_empty():
			changed = [k, now]
		same = same and now == before
		glow = maxf(glow, float(v._jolt_glow))
		if m.ring != null and m.ring.visible:
			if first < 0:
				first = k
				first_r = m.drawn_r
			nearest = minf(nearest, _band_off_craft(v, m))
	print("  RING AT 1,500 MPH: first drawn %d frames after the release, at %.1f m" % [first, first_r])
	check("at 1,500 mph on the seat's own frames, a release (%s) and its spread: the CanvasLayers and the camera (offsets, field of view, children) as they were (%s%s), the jolt's vignette at %.2f; the band drawn (first %d frames on, at %.1f m) never within %.0f m of the pod or an engine (%.1f at the nearest)" % [
		left, same, "" if changed.is_empty() else ": changed at frame %d to %s" % changed, glow, first, first_r, COMFORT, nearest],
		left and same and glow == 0.0 and first > 0 and nearest >= COMFORT)
