## The Vesper's shock pulse (view/weapons/pulse_mount.gd on Codex's arms, view/arms/vesper_arms.gd; fired for itself through
## view/gunnery.gd's own-fire hook). In the VR seat on the Network (XR off), the Vesper on a straight at 1,500 mph. Raids
## are pinned off, so the GUN's first arming makes the fire control and the arms; once armed the world is held still and
## the fire control stepped on its own (the craft stands where it is), every target is put where the test wants it, and
## (after the commuters' check, which has no raid) a director of the test's own is put in (never updated), so its raiders
## are a raid's pack and its kills are counted (kills_by). Then a Raids-on seat, flown on its own frames at 1,500 mph.
## The ring rides with the craft (Ruling W): its centre is the wheel's centre (its muzzle) each frame, and distances are
## from there: in the round for a flyer, over the ground for a raider:
##   check_table            weapon_of(VESPER) is "pulse", its weapon row is the brief's, and it is armed
##   check_lazy             with the GUN never armed: no Arms node on either hull, no fire control (Raids off); armed: the
##                          fire control is made, firing for itself through the pulse's mount, the Arms on the hull the
##                          seat sees (not the hidden pod), out in 1 s, the wheel's glow full (Ruling Y: charged, before
##                          the first release). The first arming's frame is told (Ruling D)
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
##   check_recharge         the trigger at 11.9 s does nothing; at 12.0 s a second ring leaves; the wheel's glow is the
##                          stored charge (Ruling Y: 0 just after a release, half at 6 s, full at 12 s); a trigger held
##                          down through the next charge's end releases nothing (a press, not a hold) until it is let go
##                          and pressed again
##   check_safe_mid_use     (Review Focus 3, Ruling V) SAFE thrown 0.1 s into a spread: the ring finishes it and its raider
##                          at 400 m dies on time; SAFE at 4 s into the recharge, GUN at 6 s: 6 s are left, not refilled;
##                          charged, at SAFE a press releases nothing (stowed), nor once GUN is thrown before it is out
##   check_raid_ends_mid_spread   (Ruling V) a raider shot by other means mid-spread: no hit on it after, one kill; the
##                          raid reset mid-spread: no hit and no kill after, no error, and a raider and a drone put down
##                          after it, ahead of the ring, are not hit by it
##   check_drawn            (Rulings V, X) at rest: not drawn till its wall is COMFORT m off the pod and each engine (the
##                          frame and radius it first shows at told), never drawn nearer them; a wall standing on the
##                          road's plane under the craft, centred on the wheel (within FOLLOW_M), TALL_LO to TALL_HI
##                          degrees tall from the eye straight ahead at 150 m and at 450 m, no more than TALL_HI anywhere on
##                          its first drawn frame; fading; gone after its spread and linger
##   check_no_sight         (Ruling Z) the Vesper armed and out, a raider under the gaze: no gaze sight drawn, no brackets
##                          (the fire control looks for nothing along the gaze for it)
##   check_cost             a ring among a full raid (6 raiders, 10 drones, the gunship) with traffic's most (220) about,
##                          ten times: the mount's own time a frame (its step and fire) over each ring's frames, mean and
##                          worst, the release frames and the frames kills land on told apart; the mean held under COST_MS;
##                          and what the gaze search it no longer gets would cost a frame, told
##   check_flat_range       the flat view on the Range (no seat, no traffic, no raid): nothing built till armed; armed, the
##                          fire control and the arms on the craft's own pod, out in about a second; a press releases a ring
##   check_sight_other      (Ruling Z) the Kiln, armed and out, a raider under the gaze: its gaze sight drawn, bracketing it
##   check_raids_on_arming  Raids on (Ruling D: the first arming measured over 5 ms): the fire control made at load,
##                          dormant, and the arms fitted then on the seat's hull, stowed (not drawn, the hull its own); the
##                          first arming's frame told; armed, the same arms come out
##   check_hand_tick        on that seat's own frames (vr_cockpit.gd _process), a release: one strong tick in each hand
##                          that frame, below a jolt's (an event: each hand held its length), sent at once (no delay: the
##                          engine ignores one); none in the frames after, none for a press while it recharges; no shot
##                          counted (no per-shot tick)
##   check_at_speed         (Ruling W) on the seat's own frames at 1,500 mph, raiders paced at the craft's own speed 300 m
##                          and 440 m ahead and 440 m behind: all three die, each no sooner than the ring reaches it (its
##                          distance from the craft that frame) and at most a frame after; one 470 m ahead lives,
##                          untouched. The drawn ring's centre is the wheel's every frame it is drawn (within FOLLOW_M),
##                          the wheel a few metres from the pod, while the floating origin follows the pod
##   check_sims_frame       on the same frames, the craft put down 30 km off mid-spread (the floating origin goes with
##                          it): the ring drawn round the wheel there too (within FOLLOW_M)
##   check_no_flash         on the same seat's own frames at 1,500 mph, a release and its whole spread: no CanvasLayer's
##                          shown or child count changed, the camera's offsets, field of view and children as they were,
##                          the jolt's vignette at 0; the wall never drawn within COMFORT m of the pod or an engine; it
##                          first shows at the radius it does at rest; TALL_LO to TALL_HI degrees tall straight ahead at
##                          150 m and at 450 m, no more than TALL_HI anywhere on its first drawn frame
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
const SeatKit := preload("res://tests/seat_kit.gd")      # (the seat flown on its own frames at speed, shared)
const ROW := {"radius": 450.0, "rechargeS": 12.0, "gunshipFrac": 0.6, "spreadS": 0.5}
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const COST_MS := 0.10           # the mount's own mean a frame over a ring's frames among a full raid, at the most
const COMFORT := 20.0           # m: the ring's wall is never drawn nearer the pod or an engine (over the ground) than this
const FOLLOW_M := 0.05          # m: the drawn ring's centre is this near the wheel's centre (over the ground), at the most
const TALL_LO := 0.5            # degrees: the wall from the eye straight ahead at 150 m and at 450 m, at the least ...
const TALL_HI := 1.5            # ... and at the most (and anywhere round it on its first drawn frame)
# Paced at the craft's own speed (check_at_speed): [m along the road from the craft, lanes over from the craft's, dies]
const PACED := [[300.0, 0, true], [440.0, 1, true], [-440.0, 0, true], [470.0, -1, false]]
const SECTIONS := 18
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var _next_id := 996000
var seat := SeatKit.new()      # (tests/seat_kit.gd: the craft on a straight, held at speed, its raiders paced)
var _fleet: Array = []          # traffic's own vehicles when the GUN was armed (put back for check_cost)
var _director = null
var _first_r_rest := -1.0       # the radius the ring first shows at, at rest (check_drawn)


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
		check_drawn(v, g)
		sections += 1
		check_no_sight(v, g)
		sections += 1
		check_cost(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	_director = null
	await check_flat_range()
	sections += 1
	await check_sight_other()
	sections += 1
	Raids.enabled = true
	v = await _seat(Pilot.VESPER)
	if check_raids_on_arming(v):
		sections += 1
		check_hand_tick(v)
		sections += 1
		check_at_speed(v)
		sections += 1
		check_sims_frame(v)
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
	seat.on_a_straight(v)
	for i in 10:
		seat.hold_speed(v)
		v._process(DT)
	seat.hold_speed(v)
	return v


## The wheel's centre now (its muzzle), the sims' frame: where the ring is centred.
func _centre(g) -> Vector3:
	return g.to_sim((g.mount.arms.muzzles()[0] as Transform3D).origin)


## The seat's eye (Seat.EYE on the rig), the sims' frame.
func _eye(v, g) -> Vector3:
	return g.to_sim(v.rig.global_transform * Seat.EYE)


## A sims' point `dist` m over the ground from the wheel's centre, `bearing` degrees left of the road's way (0 ahead, 180
## behind, -90 to the right), `up` m over the wheel's height.
func _point(v, g, dist: float, bearing: float, up := 0.0) -> Vector3:
	var c := _centre(g)
	var dir := seat.road_way(v).rotated(deg_to_rad(bearing))
	return Vector3(c.x + dir.x * dist, c.y + dir.y * dist, c.z + up)


## A vehicle at `at` (the sims' plane), standing still, on the craft's road's nearest sample: a commuter, or a raider of
## the test's director's pack (when it has one).
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
	c.dir = seat.way
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


## A raider `dist` m over the ground from the wheel's centre, `bearing` degrees left of the road's way.
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


## A target's distance from the ring's centre `c`: in the round for a flyer, over the ground for a vehicle.
static func _dist(c: Vector3, t) -> float:
	if GunneryScript._is_flyer(t):
		return c.distance_to(Vector3(t.x, t.y, t.z))
	return Vector2(c.x, c.y).distance_to(Vector2(t.x, t.y))


## The gaze from the seat's eye, ahead along the rig, or on vehicle `at`.
func _look(v, at = null) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if at == null:
		cam.look_at(cam.global_position + rig.basis * Vector3(0.0, -0.03, -1.0).normalized(), rig.basis.y)
	else:
		var g = v.gunnery
		cam.look_at(g.to_render(Vector3(at.x, at.y, v.traffic_net.body_height(at))), rig.basis.y)


## One frame of the still world: the gaze laid, the fire control stepped.
func _frame(v, g, dt := DT, at = null) -> void:
	_look(v, at)
	g.step(dt)


## `n` frames of it.
func _frames(v, g, n: int, at = null) -> void:
	for i in n:
		_frame(v, g, DT, at)


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


## Is the ring drawn this frame?
static func _shown(m) -> bool:
	return m.ring != null and m.ring.visible


## How near the drawn wall (at its radius about its centre) comes to the pod or an engine, over the ground (INF when it is
## not drawn).
static func _wall_off_craft(v, m) -> float:
	if not _shown(m):
		return INF
	var r: float = m.drawn_r
	var c: Vector3 = m.centre
	var least := INF
	for b in [v.sim.pod, v.sim.eL, v.sim.eR]:
		least = minf(least, absf(Vector2(b.x - c.x, b.y - c.y).length() - r))
	return least


## How far the drawn ring's centre (its node, the render frame, read back into the sims' frame) stands off the wheel's
## centre now, over the ground (INF when it is not drawn).
static func _off_wheel(g, m) -> float:
	if not _shown(m):
		return INF
	var o: Vector3 = g.to_sim(m.ring.global_position)
	var w: Vector3 = g.to_sim(m.origin())
	return Vector2(o.x - w.x, o.y - w.y).length()


## How tall the drawn wall stands from the eye (degrees), at its point in the way `way` (a unit vector, the sims' plane)
## from its centre: from its foot, on its plane, to its top. -1 when not drawn (or a mount with no standing wall).
static func _tall_deg(eye: Vector3, m, way: Vector2) -> float:
	if not _shown(m) or m.get("ring_tall") == null:
		return -1.0
	var r: float = m.drawn_r
	var c: Vector3 = m.centre
	var p := Vector2(c.x, c.y) + way * r
	var foot := Vector3(p.x, p.y, float(m.ring_h) + float(_const(m, "RING_LIFT", 0.0)))
	var top := foot + Vector3(0.0, 0.0, float(m.ring_tall))
	return rad_to_deg((foot - eye).angle_to(top - eye))


## ... the tallest anywhere round it (64 ways).
static func _tallest_deg(eye: Vector3, m) -> float:
	var most := -1.0
	for k in 64:
		most = maxf(most, _tall_deg(eye, m, Vector2.RIGHT.rotated(TAU * k / 64.0)))
	return most


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
	seat.hold_speed(v)
	v._process(DT)
	var before_ms := (Time.get_ticks_usec() - t0) / 1000.0
	v.gun_wanted = true
	seat.hold_speed(v)
	t0 = Time.get_ticks_usec()
	v._process(DT)
	var arming_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := []
	for i in 3:
		seat.hold_speed(v)
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
	check("out in %.3f s (1.0; %.3f of it in the view's frames since the switch): the leaves open and the wheel rises and fans out (deploy %.2f), the arms drawn; charged (%.1f s to go), its word \"%s\", never released, the wheel's glow %.3f (full: Ruling Y)" % [
		took, begun, mount.deploy_t(), mount.charge, mount.status(), mount.heat()], mount.is_out() and absf(took - 1.0) <= 2.0 * DT and begun > 0.0
		and arms.visible and mount.charge == 0.0 and mount.released == 0 and absf(mount.heat() - 1.0) < 1e-6)
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
	check("a ring released (%s) round the wheel's centre (%.4f m off it): %s" % [left, centred, "; ".join(said)],
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
	var at_once: float = m.heat()
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
	check("a ring (%s); the trigger pressed at 11.9 s: nothing leaves (%s); at 12.0 s a second ring leaves (%s), %d in these 12 s; the wheel's glow %.3f just after the release (0) and %.3f at 6 s (half: the stored charge)" % [
		first, early, at_12, m.released - before, at_once, half], first and not early and at_12 and m.released - before == 2
		and absf(at_once) < 1e-6 and absf(half - 0.5) < 0.01)
	# Held down through the next charge's end: nothing leaves while it is held; let go and pressed, one does.
	var was: int = m.released
	var full := -1.0
	for k in range(1, int(12.1 / DT) + 1):
		g.hold_fire = k >= int(round(11.9 / DT))
		_frame(v, g)
		if k == int(round(12.0 / DT)):
			full = m.heat()
	var while_held: int = m.released - was
	var charged_then: bool = m.charge == 0.0
	g.hold_fire = false
	_frame(v, g)
	var pressed := _press(v, g)
	check("the trigger held down from 11.9 s to 12.1 s into the next charge: %d ring(s) leave while it is held (charged at 12: %s, the wheel's glow %.3f: full); let go and pressed again, one leaves (%s)" % [
		while_held, charged_then, full, pressed], while_held == 0 and charged_then and absf(full - 1.0) < 1e-6 and pressed)
	_clear(v, g)


func check_safe_mid_use(v, g) -> void:
	var m = g.mount
	var raider = _raider_at(v, g, 400.0, 0.0)
	_frames(v, g, 3)
	var left := _press(v, g)
	var gone_at := -1
	var d := -1.0          # (its distance from the ring's centre the frame it went: the wheel stowing moves that centre a little)
	var drawn_after := false
	for k in range(1, int(0.9 / DT)):
		if k == int(round(0.1 / DT)):
			g.want_out = false      # (SAFE, 0.1 s into the spread)
		_frame(v, g)
		if gone_at < 0 and not g.alive(raider):
			gone_at = k
			d = _dist(m.centre, raider)
		if k > int(round(0.1 / DT)) and _shown(m):
			drawn_after = true
	var due := 0.5 * d / 450.0
	check("SAFE thrown 0.1 s into a spread (a ring left: %s): the ring finishes it (drawn after: %s), its raider gone %.4f s in at %.1f m from the ring's centre (due %.4f)" % [
		left, drawn_after, gone_at * DT, d, due], left and drawn_after and gone_at > 0 and gone_at * DT >= due - 1e-4
		and gone_at * DT <= due + DT + 1e-4)
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
	check("SAFE at 4 s into a recharge (a ring left: %s), GUN at 6 s: %.3f s are left (6: its clock ran at SAFE, not refilled), its word \"%s\", the wheel's glow %.3f (0.5)" % [
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


## (Rulings V, X, the comfort rule) At rest (the world still): where, when and how tall the ring is drawn.
func check_drawn(v, g) -> void:
	var m = g.mount
	var eye := _eye(v, g)
	var ahead := seat.road_way(v)
	var left := _press(v, g)
	var on_release: bool = _shown(m)
	var first := -1
	var first_r := 0.0
	var first_tall := -1.0
	var nearest := INF
	var follow := 0.0
	var at := {}          # radius drawn: [frame, light, standing, on the road's plane under the craft, degrees tall ahead]
	var last_drawn := -1
	for k in range(1, int(1.0 / DT)):
		_frame(v, g)
		if not _shown(m):
			continue
		last_drawn = k
		if first < 0:
			first = k
			first_r = m.drawn_r
			first_tall = _tallest_deg(eye, m)
		nearest = minf(nearest, _wall_off_craft(v, m))
		follow = maxf(follow, _off_wheel(g, m))
		if k == int(round(150.0 / 450.0 * 0.5 / DT)) or k == int(round(0.5 / DT)):
			var b: Basis = m.ring.global_basis
			var tall = m.get("ring_tall")
			var standing: bool = tall != null and absf(b.y.normalized().dot(Vector3.UP)) > 0.9999 and absf(b.y.length() - float(tall)) < 1e-3 \
				and absf(b.x.length() - m.drawn_r) < 1e-3 and absf(b.z.length() - m.drawn_r) < 1e-3
			var o: Vector3 = g.to_sim(m.ring.global_position)
			var road: float = g.ground_at(o.x, o.y)
			var placed: bool = o.z >= road and o.z <= road + 0.5
			at[snappedf(m.drawn_r, 0.1)] = [k, snappedf(float(m.ring_light), 0.001), standing, placed, snappedf(_tall_deg(eye, m, ahead), 0.01)]
	_first_r_rest = first_r
	var r150: Array = at.get(150.0, [])
	var r450: Array = at.get(450.0, [])
	print("  RING AT REST: first drawn %d frames after the release, at %.1f m, %.2f degrees tall at the most from the eye" % [first, first_r, first_tall])
	check("a ring (%s): not drawn on the release frame (%s); first drawn %d frames on, at %.1f m, %.2f degrees tall at the most from the eye (at most %.1f); on every frame drawn its wall %.1f m off the pod and the engines at the nearest (at least %.0f), centred %.4f m off the wheel's centre at the most (%.2f)" % [
		left, on_release, first, first_r, first_tall, TALL_HI, nearest, COMFORT, follow, FOLLOW_M], left and not on_release and first > 1
		and first_tall > 0.0 and first_tall <= TALL_HI and nearest >= COMFORT and follow <= FOLLOW_M)
	check("drawn at 150 m (%s) and at 450 m (%s) [frame, light, standing, on the road's plane under the craft, degrees tall from the eye straight ahead (%.1f to %.1f)]: fading; last drawn %d frames on (%.2f s: its spread and its linger), none after" % [
		r150, r450, TALL_LO, TALL_HI, last_drawn, last_drawn * DT], r150.size() == 5 and r450.size() == 5 and bool(r150[2]) and bool(r150[3])
		and bool(r450[2]) and bool(r450[3]) and float(r150[4]) >= TALL_LO and float(r150[4]) <= TALL_HI and float(r450[4]) >= TALL_LO
		and float(r450[4]) <= TALL_HI and float(r450[1]) < float(r150[1]) and float(r450[1]) > 0.0 and last_drawn > int(0.5 / DT)
		and last_drawn < int(1.0 / DT) - 1 and m.ring_t < 0.0)
	check("it hangs in the world under the fire control (%s), not before the camera nor on a CanvasLayer" % [m.ring.get_parent().name if m.ring else null],
		m.ring != null and m.ring.get_parent() == g)
	_clear(v, g)


## (Ruling Z) The Vesper armed and out, a raider ahead under the gaze: no gaze sight, no brackets.
func check_no_sight(v, g) -> void:
	var m = g.mount
	var raider = _raider_at(v, g, 300.0, 0.0)
	_frames(v, g, 10, raider)
	var aimed = m.aimed() if m.has_method("aimed") else null
	check("the Vesper armed and out (%s), a raider 300 m ahead under the gaze: the mount aimed %s; the gaze sight drawn %s, on a vehicle %s (no sight, no brackets)" % [
		m.is_out(), aimed, g.sight.visible, g.aim_car], m.is_out() and aimed == false and not g.sight.visible and g.aim_car == null)
	_clear(v, g)


func check_cost(v, g) -> void:
	var m = g.mount
	for c in _fleet:      # (traffic's own fleet back)
		v.traffic_net.cars.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hw: float = float(v.sim.roads[v.sim.pod.path].w[int(v.sim.pod.hint)]) * 0.5
	var way := seat.road_way(v)
	var P := Vector2(v.sim.pod.x, v.sim.pod.y)
	while v.traffic_net.cars.size() < v.traffic_net.TARGET:      # (traffic's most, near a city: 220, along the road 2 km behind to 4 km ahead)
		var at := P + way * rng.randf_range(-2000.0, 4000.0) + Vector2(-way.y, way.x) * rng.randf_range(-0.8, 0.8) * hw
		_car(v, at, false)
	# What the fire control's gaze search (its _find: traffic's and the flyers' picks along the gaze, the ground) costs a frame
	# here: the search an unaimed mount no longer gets (Ruling Z).
	_look(v)
	var o: Vector3 = g.to_sim(v.cam.global_position)
	var d: Vector3 = GunneryScript.dir_to_sim(-v.cam.global_transform.basis.z.normalized())
	var t_find := Time.get_ticks_usec()
	for i in 240:
		g._find(o, d, DT)
	var find_ms := (Time.get_ticks_usec() - t_find) / 1000.0 / 240.0
	_frame(v, g)
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
	print("  COST: ten rings among a full raid (17 threats) with %d vehicles about: the mount's own step and fire %s; the whole fire control's step %.4f ms mean; %d kills; the gaze search it no longer gets %.4f ms a frame" % [
		v.traffic_net.cars.size(), "; ".join(said), whole_mean, kills, find_ms])
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
		drawn = drawn or _shown(mount)
	check("the flat view on the Range: nothing built till armed (%s); armed, the fire control (%s) and the Arms on the craft's own pod (%s), out (deploy %.2f), drawn; a press releases a ring (%d), drawn (%s)" % [
		none, g != null, arms, mount.deploy_t(), left, drawn],
		none and g.mount == mount and arms != null and mount.get("arms") == arms and mount.is_out() and arms.is_visible_in_tree() and left == 1 and drawn)
	game.queue_free()
	await process_frame
	View.track_override = "network"


## (Ruling Z) Another armed craft keeps its gaze sight: the Kiln (its lance, aimed by the gaze), armed and out on the
## Network (Raids off), the world still, a raider 300 m ahead under the gaze: the sight drawn, bracketing it.
func check_sight_other() -> void:
	var v = await _seat(Pilot.KILN)
	v.gun_wanted = true
	for i in 3:
		seat.hold_speed(v)
		v._process(DT)
	var g = v.gunnery
	if g == null:
		check("the Kiln armed: its fire control made (%s)" % g, false)
		v.queue_free()
		await process_frame
		return
	v.traffic_net.cars.clear()
	g.power = 1.0
	g.want_out = true
	for i in int(1.2 / DT):
		_frame(v, g)
	var P := Vector2(v.sim.pod.x, v.sim.pod.y)
	var raider = _car(v, P + seat.road_way(v) * 300.0, true)
	_frames(v, g, 10, raider)
	var state = g.sight_mat.get_shader_parameter("state")
	var aimed = g.mount.aimed() if g.mount.has_method("aimed") else null
	check("the Kiln armed and out (%s), a raider 300 m ahead under the gaze: the mount aimed %s; the gaze sight drawn (%s), on the raider (%s), bracketing it (state %s: 1)" % [
		g.mount.is_out(), aimed, g.sight.visible, g.aim_car == raider, state], g.mount.is_out() and aimed == true and g.sight.visible
		and g.aim_car == raider and int(state) == 1)
	v.queue_free()
	await process_frame


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
	seat.hold_speed(v)
	v._process(DT)
	var before_ms := (Time.get_ticks_usec() - t0) / 1000.0
	v.gun_wanted = true
	seat.hold_speed(v)
	t0 = Time.get_ticks_usec()
	v._process(DT)
	var arming_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var after := []
	for i in 3:
		seat.hold_speed(v)
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


## (On the Raids-on seat.) The last ring over, it is charged by hand (the recharge is check_recharge's: 12 s more at speed
## would fly the craft off its straight) and the craft put on a straight again (tests/seat_kit.gd ready_on_seat).
func _ready_on_seat(v, g) -> void:
	var m = g.mount
	seat.ready_on_seat(v, g, func() -> bool: return m.ring_t < 0.0, func() -> void: m.charge = 0.0)


## (On the Raids-on seat, armed above.) The cockpit's own frames: out, a release.
func check_hand_tick(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	for i in int(1.2 / DT):
		seat.seat_frame(v, g)
	var shots: int = g.shots
	var was: int = m.released
	var sent := seat.seat_frame(v, g, true)
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
		later += seat.seat_frame(v, g).size()
	var again := seat.seat_frame(v, g, true).size()      # (a press while it recharges)
	for i in 10:
		again += seat.seat_frame(v, g).size()
	check("on the seat's own frames, a release (%s): %s [hand (0 left, 1 right), amp, s, delay]: one tick in each hand, strong (%.2f: at least 0.5) and below a jolt's (1.0), at once; each hand held its length (%s s); none in the 30 frames after (%d), none for a press while it recharges (%d); no shot counted (%d -> %d)" % [
		left, got, amp, held, later, again, shots, g.shots], left and each and amp >= 0.5 and amp < 1.0 and dur > 0.0
		and absf(float(held[0]) - dur) < 1e-3 and absf(float(held[1]) - dur) < 1e-3 and later == 0 and again == 0 and g.shots == shots)


## (Ruling W, on the same seat.) Raiders paced at the craft's own speed at 1,500 mph, a ring released on the seat's own
## frames: who dies, when, from the craft's own place that frame; and the drawn ring's centre against the wheel's.
func check_at_speed(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	var R = v.raids
	_ready_on_seat(v, g)
	var paced := []
	var P := Vector2(v.sim.pod.x, v.sim.pod.y)
	for row: Array in PACED:
		var c = _car(v, P + seat.road_way(v) * float(row[0]), true)
		R.pack.append(c)
		paced.append([c, row[0], row[1], row[2]])
	for i in 3:
		seat.seat_frame(v, g, false, paced)
	var org0 := Vector2(v.org_x, v.org_y)
	var hits: int = g.hits
	seat.seat_frame(v, g, true, paced)
	var left: bool = m.ring_t >= 0.0
	var gone := {}        # car -> [frame, its distance from the ring's centre that frame]
	var nearest := {}     # car -> the nearest it came to the ring's centre while the ring was out
	var follow := 0.0     # the drawn centre off the wheel's, the worst
	var wheel_pod := 0.0  # the wheel's centre off the pod's, the worst (over the ground)
	var drawn := 0
	for k in range(1, int(0.8 / DT)):
		var live := paced.filter(func(p: Array) -> bool: return g.alive(p[0]))
		seat.seat_frame(v, g, false, live)
		for p: Array in paced:
			var c = p[0]
			if not gone.has(c) and not g.alive(c):
				gone[c] = [k, _dist(m.centre, c)]
			if m.ring_t >= 0.0 and g.alive(c):
				nearest[c] = minf(float(nearest.get(c, INF)), _dist(m.centre, c))
		if _shown(m):
			drawn += 1
			follow = maxf(follow, _off_wheel(g, m))
		var w: Vector3 = g.to_sim(m.origin())
		wheel_pod = maxf(wheel_pod, Vector2(w.x - v.sim.pod.x, w.y - v.sim.pod.y).length())
	var org_moved := Vector2(v.org_x, v.org_y).distance_to(org0)
	var said := []
	var right := true
	for p: Array in paced:
		var c = p[0]
		var dies: bool = p[3]
		if dies:
			var k := int(gone[c][0]) if gone.has(c) else -1
			var d := float(gone[c][1]) if gone.has(c) else -1.0
			var due := 0.5 * d / 450.0
			var ok: bool = gone.has(c) and k * DT >= due - 1e-4 and k * DT <= due + DT + 1e-4
			right = right and ok
			said.append("%.0f m %s: %s" % [absf(float(p[1])), "ahead" if float(p[1]) > 0.0 else "behind",
				("gone %.4f s in at %.1f m from the craft, due %.4f" % [k * DT, d, due]) if gone.has(c) else "NEVER REACHED"])
		else:
			var untouched: bool = g.alive(c) and not g._damage.has(c.id)
			right = right and untouched
			said.append("%.0f m ahead: %s (%.1f m from the craft at the nearest while the ring was out)" % [float(p[1]),
				"lives, untouched" if untouched else "TOUCHED", float(nearest.get(c, -1.0))])
	check("at 1,500 mph on the seat's own frames, raiders paced at the craft's speed, a ring released (%s): %s; hits %d -> %d" % [
		left, "; ".join(said), hits, g.hits], left and right and g.hits == hits + 3)
	check("... the drawn ring's centre %.4f m off the wheel's at the worst over %d frames drawn (within %.2f), the wheel %.2f m off the pod at the most, while the floating origin followed the pod %.0f m" % [
		follow, drawn, FOLLOW_M, wheel_pod, org_moved], drawn > 0 and follow <= FOLLOW_M and wheel_pod < 4.0 and org_moved > 300.0)
	for p: Array in paced:
		v.traffic_net.cars.erase(p[0])
	R.pack.clear()
	R._killed.clear()
	R.kills = 0
	R._zero_kills_by()


## (On the same seat.) The craft put down 30 km off mid-spread (the floating origin goes with it): the ring stays on it.
func check_sims_frame(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	var sim = v.sim
	_ready_on_seat(v, g)
	seat.seat_frame(v, g, true)
	var left: bool = m.ring_t >= 0.0
	for i in int(round(0.1 / DT)):
		seat.seat_frame(v, g)
	var there := []
	for r in sim.roads.size():
		var Rd = sim.roads[r]
		if Rd.shaft or Rd.deck or not v.traffic_net._public_road(Rd):
			continue
		for i in range(2, Rd.N - 2, 8):
			if absf(Vector2(Rd.px[i] - sim.pod.x, Rd.py[i] - sim.pod.y).length() - 30000.0) < 300.0:
				there = [r, i]
				break
		if not there.is_empty():
			break
	if there.is_empty():
		check("a road sample 30 km off to put the craft down on", false)
		return
	var org0 := Vector2(v.org_x, v.org_y)
	sim.respawn_on(there[0], there[1], 1)
	var follow := 0.0
	var drawn := 0
	for i in int(0.3 / DT):
		seat.seat_frame(v, g)
		if _shown(m):
			drawn += 1
			follow = maxf(follow, _off_wheel(g, m))
	var moved := Vector2(v.org_x, v.org_y).distance_to(org0)
	check("a ring (%s), the craft put down %.1f km off 0.1 s into its spread (the floating origin with it): drawn round the wheel there, %.4f m off its centre at the worst over %d frames (within %.2f)" % [
		left, moved / 1000.0, follow, drawn, FOLLOW_M], left and moved > 29000.0 and drawn > 0 and follow <= FOLLOW_M)


## The CanvasLayers under the view, each one's [shown, its children], and the camera's [h_offset, v_offset, fov, children].
static func _screen(v) -> Array:
	var layers := []
	for n: Node in v.find_children("*", "CanvasLayer", true, false):
		layers.append([String(v.get_path_to(n)), (n as CanvasLayer).visible, n.get_child_count()])
	var cam: Camera3D = v.cam
	return [layers, [cam.h_offset, cam.v_offset, cam.fov, cam.get_child_count()]]


## (On the same seat.) A release at 1,500 mph and its whole spread on the seat's own frames.
func check_no_flash(v) -> void:
	var g = v.gunnery
	var m = v.craft.weapon
	_ready_on_seat(v, g)
	var before := _screen(v)
	seat.seat_frame(v, g, true)
	var left: bool = m.ring_t >= 0.0
	var same := true
	var glow := 0.0
	var nearest := INF
	var first := -1
	var first_r := 0.0
	var first_tall := -1.0
	var tall := {}
	var changed := []
	for k in range(1, int(0.8 / DT)):
		seat.seat_frame(v, g)
		var now := _screen(v)
		if now != before and changed.is_empty():
			changed = [k, now]
		same = same and now == before
		glow = maxf(glow, float(v._jolt_glow))
		if _shown(m):
			var eye := _eye(v, g)
			if first < 0:
				first = k
				first_r = m.drawn_r
				first_tall = _tallest_deg(eye, m)
			nearest = minf(nearest, _wall_off_craft(v, m))
			if k == int(round(150.0 / 450.0 * 0.5 / DT)) or k == int(round(0.5 / DT)):
				tall[snappedf(m.drawn_r, 0.1)] = snappedf(_tall_deg(eye, m, seat.road_way(v)), 0.01)
	var t150 := float(tall.get(150.0, -1.0))
	var t450 := float(tall.get(450.0, -1.0))
	print("  RING AT 1,500 MPH: first drawn %d frames after the release, at %.1f m (at rest %.1f m), %.2f degrees tall at the most from the eye" % [first, first_r, _first_r_rest, first_tall])
	check("at 1,500 mph on the seat's own frames, a release (%s) and its spread: the CanvasLayers and the camera (offsets, field of view, children) as they were (%s%s), the jolt's vignette at %.2f; the wall drawn (first %d frames on, at %.1f m: at rest %.1f) never within %.0f m of the pod or an engine (%.1f at the nearest)" % [
		left, same, "" if changed.is_empty() else ": changed at frame %d to %s" % changed, glow, first, first_r, _first_r_rest, COMFORT, nearest],
		left and same and glow == 0.0 and first > 0 and nearest >= COMFORT and absf(first_r - _first_r_rest) < 1e-3)
	check("... from the eye at 1,500 mph: %.2f degrees tall at the most on its first drawn frame (at most %.1f); straight ahead %.2f at 150 m and %.2f at 450 m (%.1f to %.1f)" % [
		first_tall, TALL_HI, t150, t450, TALL_LO, TALL_HI], first_tall > 0.0 and first_tall <= TALL_HI and t150 >= TALL_LO and t150 <= TALL_HI
		and t450 >= TALL_LO and t450 <= TALL_HI)
