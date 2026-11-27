## The Orrery's three orbs (view/weapons/orb_mount.gd on Codex's arms, view/arms/orrery_arms.gd; fired for itself through
## view/gunnery.gd's own-fire hook). In the VR seat on the Network (XR off), the Orrery on a straight at 1,500 mph. Raids
## are pinned off, so the GUN's first arming makes the fire control and the arms; once armed the world is held still and
## the fire control stepped on its own (the craft stands where it is), every target put where the test wants it, and
## (after the commuters' check, which has no raid) a director of the test's own put in (never updated), so its raiders and
## flyers are a raid's. Then a Raids-on seat, flown on its own frames at 1,500 mph (tests/seat_kit.gd), its targets keeping
## the craft's pace (Ruling AA: every check of an orb's reach or timing runs twice). Distances are from the craft's present
## place (the pod): a flyer in the round, a raider over the ground.
##   check_table            weapon_of(ORRERY) is "orbs", its weapon row is the brief's, and it is armed
##   check_lazy             with the GUN never armed: no Arms node, no fire control (Raids off); armed: the fire control made,
##                          firing for itself through the orbs' mount, aimed, its gaze search as far as a send; the Arms on
##                          the seat's hull, out in 1 s, the orbs docked while her deploy runs. The first arming's frame told
##   check_orbit            (still, and again at speed) armed 2 s: all three in orbit, each within ON_R of orbitR from the
##                          cab's up axis, APART of 120 degrees apart, none below her highest FORMATION; from the eye none
##                          inside the windscreen's outline (view/canopy.gd's oblong screen and its frame, which it keeps for
##                          the gates that measure them; tests/clash_kit.gd sight) over 600 frames
##   check_ignores_commuters   (Review Focus 5) no raid: 30 s armed among traffic's fleet and twelve commuters within reach,
##                          the gaze on them and the trigger pressed: no orb leaves its orbit, no strike, nothing struck
##   check_strikes_on_its_own   a raider 600 m off: an orb reaches it within 2 s, it takes 3 and lives, a second strike kills
##                          it; three raiders in reach: each orb takes a different one
##   check_out_of_reach     raiders 1,200 m and 920 m off are left alone; one 880 m off is struck
##   check_send             the gaze on a raider 2,000 m off and the trigger pressed: all three go, one shot; it dies at the
##                          second arrival, the third turns back; nothing for a press with no hostile under the gaze or one
##                          beyond the search; a send does not redirect an orb already out
##   check_orb_comes_home   (Review Focus 1) two orbs sent at a raider 1,000 m off, it shot down by other means with both 300
##                          m short: both turn back that frame and are in orbit within 3 s, one kill; the raid reset with
##                          three out: all home within 3 s, no strike after
##   check_safe_mid_use     (Review Focus 3) SAFE with all three 500 m out toward a raider 1 km off: each docks within DOCK_M of
##                          its docks() place before deploy_t() falls below 1; the doors then close; the longest return (an
##                          orb near 2,200 m out) told, the arms waiting for it
##   check_gunship          a 120 HP gunship 100 m off (where an orb's cycle is near its rest: see GUNSHIP_M) dies within 20 s
##                          on their own; every orb rests restS before it leaves again; and, as figures for the tuning, how
##                          long the three take on their own at 400 m, and by repeated sends at 1,000 m
##   check_drawn            an orb 300 m out has the fire control's streak behind it, in the world under the fire control; an
##                          orb in orbit has none
##   check_cost             three orbs working a full raid (6 raiders, 10 drones, the gunship, kept full) with traffic's most
##                          about, sends among it: the mount's own time a frame, mean and worst over 600 frames
##   check_flat_range       the flat view on the Range: nothing built till armed; armed, the arms on the craft's own pod and
##                          the orbs in orbit round it
##   check_raids_on_arming  Raids on: the fire control made at load, dormant, the arms fitted then, stowed; the arming told
##   check_hand_tick        on the seat's own frames: a send is one tick in the left hand, at most a frame later; none as the
##                          orbs strike, none for a press with every orb away; one shot counted
##   check_*_at_speed       the reach and timing checks above again at 1,500 mph, the targets paced
##   check_restart          a respawn 30 km off and the view's restart (Y) with orbs out: every orb in its place the next
##                          frame, no strike after, no error
##   check_no_flash         a send and its sortie at 1,500 mph: no CanvasLayer or camera change, no vignette
## Run with --fixed-fps 120: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_orbs.gd -- --mute
## Prints ORBS PASS. Puts user://vr_prefs.json back as it found it.
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
const OrreryArms := preload("res://view/arms/orrery_arms.gd")
const ClashKit := preload("res://tests/clash_kit.gd")
const SeatKit := preload("res://tests/seat_kit.gd")
const OrbMountScript := preload("res://view/weapons/orb_mount.gd")
const ROW := {"orbs": 3, "reach": 900.0, "sendReach": 2200.0, "orbV": 700.0, "hits": 3, "restS": 1.2, "orbitR": 4.0, "orbitS": 3.0}
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const SPEED := SeatKit.SPEED
const ON_R := 0.2               # m: an orb in orbit is this near orbitR from the cab's up axis
const APART := 10.0             # degrees: the three are 120 apart within this
const DOCK_M := 0.05            # m: a docked orb is this near its docks() place
const GUNSHIP_M := 95.0         # m over the ground the gunship stands off (30 m up: 99.6 m in the round), where 40 strikes of
                                # 3 fit 20 s: an orb's cycle there is 0.26 s of flight and its 1.2 s rest
const COST_MS := 0.10           # the mount's own mean a frame among a full raid, at the most
const SECTIONS := 23
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var _next_id := 997000
var seat := SeatKit.new()       # (tests/seat_kit.gd: the craft on a straight, held at speed, its raiders paced)
var _fleet: Array = []          # traffic's own vehicles when the GUN was armed (put back for the commuters and the cost)
var _armed_at := 0.0            # s of frames since the GUN was thrown (check_orbit: armed 2 s)


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
	Seat.best_dir = OS.get_user_data_dir().path_join("test_orbs_")
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
	var v = await _seat(Pilot.ORRERY)
	var g = check_lazy(v)
	if g != null:
		sections += 1
		await check_orbit(v, g, false)
		sections += 1
		check_ignores_commuters(v, g)
		sections += 1
		_put_director(v, g)
		check_strikes_on_its_own(v, g)
		sections += 1
		check_out_of_reach(v, g)
		sections += 1
		check_send(v, g)
		sections += 1
		check_orb_comes_home(v, g)
		sections += 1
		check_safe_mid_use(v, g)
		sections += 1
		check_gunship(v, g)
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
	v = await _seat(Pilot.ORRERY)
	if check_raids_on_arming(v):
		sections += 1
		await check_orbit(v, v.gunnery, true)
		sections += 1
		check_hand_tick(v)
		sections += 1
		check_strikes_at_speed(v)
		sections += 1
		check_send_at_speed(v)
		sections += 1
		check_comes_home_at_speed(v)
		sections += 1
		check_safe_at_speed(v)
		sections += 1
		check_gunship_at_speed(v)
		sections += 1
		check_restart(v)
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
	print("ORBS %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


# --- the flight and its targets --------------------------------------------------------------------------

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


## The craft's present place (the pod), the sims' frame.
static func _here(v) -> Vector3:
	return Vector3(v.sim.pod.x, v.sim.pod.y, v.sim.pod.z)


## A sims' point `dist` m over the ground from the craft, `bearing` degrees left of the road's way (0 ahead, 180 behind),
## `up` m over the pod's height.
func _point(v, dist: float, bearing: float, up := 0.0) -> Vector3:
	var P := _here(v)
	var dir: Vector2 = seat.road_way(v).rotated(deg_to_rad(bearing))
	return Vector3(P.x + dir.x * dist, P.y + dir.y * dist, P.z + up)


## A vehicle at `at` (the sims' plane), standing still, on the craft's road's nearest sample: a commuter, or a raider of
## the raid's pack (the view's director: the test's own, or the Raids-on seat's).
func _car(v, at: Vector2, hostile: bool):
	var T = v.traffic_net
	var sim = v.sim
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var h := int(sim.pod.hint)
	var near := h
	for i in range(maxi(0, h - int(2400.0 / float(Sim.NET_STEP))), mini(R.N - 1, h + int(2400.0 / float(Sim.NET_STEP)))):
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
	if hostile and v.raids != null:
		v.raids.pack.append(c)
	return c


## A raider `dist` m over the ground from the craft, `bearing` degrees left of the road's way.
func _raider_at(v, dist: float, bearing: float):
	var p := _point(v, dist, bearing)
	return _car(v, Vector2(p.x, p.y), true)


## A flyer of the raid's (view/raid_flyers.gd), put up by hand at `at` (the sims' frame): never flown. `kind` "drone" (its
## own HP) or "gunship" (GUNSHIP_HP), or `hp` of its own.
func _flyer(v, kind: String, at: Vector3, hp := -1):
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
	v.raids.flyers._list.append(f)
	return f


## A target's distance from the craft: in the round for a flyer, over the ground for a vehicle.
static func _dist(v, t) -> float:
	var P := _here(v)
	if GunneryScript._is_flyer(t):
		return P.distance_to(Vector3(t.x, t.y, t.z))
	return Vector2(P.x, P.y).distance_to(Vector2(t.x, t.y))


## How far orb o is from the craft (the sims' frame, in the round), while it is away.
static func _out_m(v, o) -> float:
	return _here(v).distance_to(o.p)


## The gaze from the seat's eye, ahead along the rig, or on target `at` (a vehicle's body, a flyer's middle).
func _look(v, at = null) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if at == null:
		cam.look_at(cam.global_position + rig.basis * Vector3(0.0, -0.03, -1.0).normalized(), rig.basis.y)
		return
	var h: float = float(at.z) if GunneryScript._is_flyer(at) else v.traffic_net.body_height(at)
	cam.look_at(v.gunnery.to_render(Vector3(at.x, at.y, h)), rig.basis.y)


## One frame of the still world: the gaze laid, the fire control stepped.
func _frame(v, g, dt := DT, at = null) -> void:
	_look(v, at)
	g.step(dt)


## `n` frames of it.
func _frames(v, g, n: int, at = null) -> void:
	for i in n:
		_frame(v, g, DT, at)


## The trigger pressed for a frame (a press: the frame after, let go). Whether a send went in that frame.
func _press(v, g, at = null) -> bool:
	var m = g.mount
	var was: int = m.sends
	g.hold_fire = true
	_frame(v, g, DT, at)
	g.hold_fire = false
	return m.sends > was


## Is every orb in orbit?
static func _in_orbit(m) -> bool:
	return m.orbs.all(func(o) -> bool: return o.state == "orbit")


## Every orb rested (by hand: the rest is check_gunship's).
static func _rest_all(m) -> void:
	for o in m.orbs:
		o.rest = 0.0


## The orbs' states.
static func _states(m) -> Array:
	return m.orbs.map(func(o) -> String: return String(o.state))


## The targets gone, every orb back in its place and rested, and the director's counts back to none.
func _clear(v, g) -> void:
	var m = g.mount
	v.traffic_net.cars.clear()
	var R = v.raids
	if R != null:
		R.pack.clear()
		R.flyers._list.clear()
	for i in int(6.0 / DT):
		if _in_orbit(m):
			break
		_frame(v, g)
	_rest_all(m)
	if R != null:
		R.kills = 0
		R._zero_kills_by()
		R._killed.clear()
		R.state = ""
	g._damage.clear()
	_frame(v, g)


## The director of the test's own, put in once armed: its raiders and flyers are a raid's (as in a flight), never updated.
func _put_director(v, g) -> void:
	var d = Raids.new()
	v.add_child(d)
	d.traffic = v.traffic_net
	d.build(v)
	v.raids = d
	v.traffic_net.raids = d
	g.killed.connect(d.on_kill)      # (as the view connects it: craft_view.gd, the frame)


## The canopy's oblong windscreen and its frame (hidden in the fleet's cockpits; view/canopy.gd keeps their meshes for the
## gates that measure them) as colliders in the cab's frame (tests/clash_kit.gd), for sight lines from the eye.
func _windscreen(v) -> ClashKit:
	var kit := ClashKit.new()
	var hull: Node3D = v.shell.get_node("PodHull")
	for part in ["windscreen", "frame"]:
		var n: MeshInstance3D = v.canopy.get_node(part)
		var was := n.visible
		n.visible = true
		kit.gather_part(hull, n)
		n.visible = was
	kit.arm(root)
	await physics_frame
	await physics_frame
	return kit


# --- the seat's own frames ----------------------------------------------------------------------------------

## One of the seat's own frames at speed (tests/seat_kit.gd seat_frame): the paced raiders and flyers stood where they must
## be after it, the gaze on `at` (or ahead), the trigger held or not. The pulses sent to the hands in it.
func _sf(v, g, held := false, paced := [], flying := [], at = null) -> Array:
	seat.hold_speed(v)
	seat.pace(v, paced)
	_pace_flyers(v, flying)
	_look(v, at)
	return seat.seat_frame(v, g, held)


## Each paced flyer ([flyer, m along the road's way from the craft, m up]) put where it must be after the frame to come:
## that far from where the pod will be (its speed held), that far over its height; stopped (never flown), as the paced
## raiders are.
func _pace_flyers(v, flying: Array) -> void:
	var P := _here(v)
	var way: Vector2 = seat.road_way(v)
	for row: Array in flying:
		var f = row[0]
		var d := float(row[1]) + SPEED * DT
		f.x = P.x + way.x * d
		f.y = P.y + way.y * d
		f.z = P.z + float(row[2])


## A raider paced `ahead` m along the road from the craft (behind: less than 0), `lanes` over: [car, ahead, lanes].
func _paced_raider(v, ahead: float, lanes := 0) -> Array:
	var P := _here(v)
	var c = _car(v, Vector2(P.x, P.y) + seat.road_way(v) * ahead, true)
	return [c, ahead, lanes]


## (On the Raids-on seat.) The targets gone, every orb home in its place on the seat's frames (6 s at the most), rested by
## hand, and the craft put on a straight again (tests/seat_kit.gd ready_on_seat).
func _ready_on_seat(v, g) -> void:
	var m = g.mount
	var R = v.raids
	for c in R.pack:
		v.traffic_net.cars.erase(c)
	R.pack.clear()
	R.flyers._list.clear()
	R._killed.clear()
	R.kills = 0
	R._zero_kills_by()
	for i in int(6.0 / DT):
		if _in_orbit(m):
			break
		_sf(v, g)
	seat.ready_on_seat(v, g, _in_orbit.bind(m), _rest_all.bind(m))


# --- the checks: the table, the arming, the orbit ------------------------------------------------------------

func check_table() -> void:
	var row: Dictionary = Pilot.traits(Pilot.ORRERY).weapon
	check("the Orrery carries \"%s\" (orbs), armed %s, its weapon row %s" % [Pilot.weapon_of(Pilot.ORRERY), Pilot.armed(Pilot.ORRERY), row],
		Pilot.weapon_of(Pilot.ORRERY) == "orbs" and Pilot.armed(Pilot.ORRERY) and row == ROW)


## The GUN never armed, then armed (the first time: the fire control and the arms are made then), the world held still,
## and the orbs brought out. The fire control, or null (its failure told).
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
	check("armed, its fire control is made, firing for itself through the orbs' mount (%s), aimed, the Arms on the seat's hull (%s), none on the hidden pod" % [
		script_path, arms], g != null and script_path.ends_with("orb_mount.gd") and v.craft.weapon == mount and mount.own_fire()
		and mount.aimed() and arms != null and mount.get("arms") == arms and v.craft.pod.get_node_or_null("Arms") == null)
	if g == null or not script_path.ends_with("orb_mount.gd") or arms == null:
		return null
	check("the mount's figures are the row's: %d orbs (Codex's %d), %.0f m on their own, %.0f m sent, %.0f m/s, %d hits, %.1f s rest, %.1f m out, a turn in %.1f s; the fire control's gaze search reaches %.0f m (sendReach)" % [
		mount.orbs.size(), (arms.orbs as Array).size(), mount.reach, mount.send_reach, mount.orb_v, mount.hits, mount.rest_s, mount.orbit_r, mount.orbit_s, g.reach],
		mount.orbs.size() == 3 and is_equal_approx(mount.reach, 900.0) and is_equal_approx(mount.send_reach, 2200.0) and is_equal_approx(mount.orb_v, 700.0)
		and mount.hits == 3 and is_equal_approx(mount.rest_s, 1.2) and is_equal_approx(mount.orbit_r, 4.0) and is_equal_approx(mount.orbit_s, 3.0)
		and is_equal_approx(g.reach, 2200.0))
	# From here the world is still: the fire control is stepped alone, every target where the test puts it, the craft at
	# rest (its speed is what the orbs' is reckoned from: at rest they fly at orbV).
	for b in [v.sim.eL, v.sim.eR, v.sim.pod]:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
	_fleet = v.traffic_net.cars.duplicate()
	v.traffic_net.cars.clear()
	g.power = 1.0
	g.want_out = true
	var begun: float = mount.deploy_t()      # (the view's own frames since the switch)
	var frames := 0
	var docked := true
	while not mount.is_out() and frames < int(2.0 / DT):
		_frame(v, g)
		frames += 1
		docked = docked and (mount.is_out() or _states(mount).all(func(s: String) -> bool: return s == "docked"))      # (out: they leave that frame)
	var took := begun * 1.0 + frames * DT
	_armed_at = took
	check("out in %.3f s (1.0; %.3f of it in the view's frames since the switch): the doors open and the orbs rise (deploy %.2f), the arms drawn; every orb docked while her deploy ran (%s), the states now %s" % [
		took, begun, mount.deploy_t(), docked, _states(mount)], mount.is_out() and absf(took - 1.0) <= 2.0 * DT and begun > 0.0
		and arms.visible and docked)
	return g


## (Still, or on the seat's own frames at speed.) Armed 2 s: the orbs in orbit, where they should be, and from the eye out
## of the windscreen's outline for 600 frames.
func check_orbit(v, g, at_speed: bool) -> void:
	var m = g.mount
	var label := "at 1,500 mph on the seat's own frames" if at_speed else "at rest"
	var kit: ClashKit = await _windscreen(v)
	var space := root.world_3d.direct_space_state
	var hull: Node3D = v.shell.get_node("PodHull")
	var top := -INF
	for f: Vector3 in OrreryArms.FORMATION:
		top = maxf(top, f.y)
	for i in maxi(0, int(round((2.0 - _armed_at) / DT))):
		if at_speed:
			_sf(v, g)
		else:
			_frame(v, g)
	var org0 := Vector2(v.org_x, v.org_y)
	var all_in := 0
	var worst_r := 0.0
	var low := INF
	var gaps := [INF, -INF]
	var inside := 0
	var first_inside := ""
	var el := [INF, -INF]
	var far := [INF, -INF]
	for frame in 600:
		if at_speed:
			_sf(v, g)
		else:
			_frame(v, g)
		all_in += int(_in_orbit(m))
		var to_arms: Transform3D = (m.arms as Node3D).global_transform.affine_inverse()
		var to_hull: Transform3D = hull.global_transform.affine_inverse()
		var eye: Vector3 = to_hull * (v.rig.global_transform * Seat.EYE)
		var bearings := []
		for k in m.orbs.size():
			var node: Node3D = m.arms.orbs[k]
			var local: Vector3 = to_arms * node.global_position
			worst_r = maxf(worst_r, absf(Vector2(local.x, local.z).length() - m.orbit_r))
			low = minf(low, local.y)
			bearings.append(fposmod(rad_to_deg(atan2(-local.z, local.x)), 360.0))
			var at: Vector3 = to_hull * node.global_position
			var seen := kit.sight(space, eye, at)
			if not seen.is_empty():
				inside += 1
				if first_inside == "":
					first_inside = "orb %d at frame %d, through %s" % [k, frame, seen]
			var d := at - eye
			el[0] = minf(el[0], rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
			el[1] = maxf(el[1], rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length())))
			far[0] = minf(far[0], d.length())
			far[1] = maxf(far[1], d.length())
		bearings.sort()
		for k in bearings.size():
			var gap: float = fposmod(float(bearings[(k + 1) % bearings.size()]) - float(bearings[k]), 360.0)
			gaps[0] = minf(gaps[0], gap)
			gaps[1] = maxf(gaps[1], gap)
	kit.free_bodies()
	var moved := Vector2(v.org_x, v.org_y).distance_to(org0)
	print("  ORBIT (%s): seen from the eye %.1f to %.1f degrees up, %.2f to %.2f m off; the floating origin moved %.0f m" % [label, el[0], el[1], far[0], far[1], moved])
	check("%s, armed 2 s: all three in orbit in %d of 600 frames, each within %.3f m of %.1f m from the cab's up axis at the worst (within %.1f), %.1f to %.1f degrees apart (120 within %.0f), the lowest %.3f m over the cab's origin (her highest FORMATION %.3f)%s" % [
		label, all_in, worst_r, m.orbit_r, ON_R, gaps[0], gaps[1], APART, low, top, " while the craft flew %.0f m" % moved if at_speed else ""],
		all_in == 600 and worst_r <= ON_R and gaps[0] >= 120.0 - APART and gaps[1] <= 120.0 + APART and low >= top and (not at_speed or moved > 3000.0))
	check("%s: from the eye none inside the windscreen's outline (the canopy's oblong screen and its frame) over 600 frames (%d sight lines through it%s); seen %.1f to %.1f degrees up" % [
		label, inside, ": first " + first_inside if inside > 0 else "", el[0], el[1]], inside == 0)


## (Review Focus 5) No raid on (no director: the view's own, Raids off): 30 s armed among traffic's fleet and twelve
## commuters in reach, the gaze on one commuter after another and the trigger pressed each second.
func check_ignores_commuters(v, g) -> void:
	var m = g.mount
	var T = v.traffic_net
	for c in _fleet:
		T.cars.append(c)
	var twelve := []
	for k in 12:
		var p := _point(v, 60.0 + 70.0 * k, 30.0 * k)
		twelve.append(_car(v, Vector2(p.x, p.y), false))
	var strikes: int = m.strikes
	var hits: int = g.hits
	var spared: int = g.commuter_strikes
	var shots: int = g.shots
	var sends: int = m.sends
	var told := []
	var on_struck := func(car) -> void: told.append(car)
	g.struck_commuter.connect(on_struck)
	var away := 0
	var under := 0
	for i in int(30.0 / DT):
		var at = twelve[(i / 120) % twelve.size()]
		if i % 120 == 60:
			g.hold_fire = true
		_frame(v, g, DT, at)
		g.hold_fire = false
		under += int(g.aim_car != null and not g.aim_car.hostile)
		away += int(not _in_orbit(m))
	g.struck_commuter.disconnect(on_struck)
	var still := twelve.filter(func(c) -> bool: return T.cars.has(c)).size()
	check("no raid on (%s): 30 s armed among %d vehicles (traffic's own and twelve commuters 60 to 830 m off), a commuter under the gaze %d frames, the trigger pressed 30 times: no orb left its orbit (%d frames with one away), %d of 12 still in traffic, strikes %d -> %d, hits %d -> %d, commuters struck %d -> %d (told %d), sends %d -> %d, shots %d -> %d" % [
		v.raids, T.cars.size(), under, away, still, strikes, m.strikes, hits, g.hits, spared, g.commuter_strikes, told.size(), sends, m.sends, shots, g.shots],
		v.raids == null and under > 600 and away == 0 and still == 12 and m.strikes == strikes and g.hits == hits and g.commuter_strikes == spared
		and told.is_empty() and m.sends == sends and g.shots == shots)
	T.cars.clear()


# --- the checks: at rest, the world still --------------------------------------------------------------------

## The first strike on `r` and its death, `frames` frames at the most (`step`: one frame of the test's own). [s to the
## first strike, the hits it had then, alive then, s to its death] (-1 for one that did not come).
func _strike_and_kill(v, g, r, frames: int, step: Callable) -> Array:
	var first := -1.0
	var took := -1
	var lived := false
	for i in range(1, frames):
		step.call()
		if first < 0.0 and g._damage.has(r.id):
			first = i * DT
			took = int(g._damage[r.id])
			lived = g.alive(r)
		if not g.alive(r):
			return [first, took, lived, i * DT]
	return [first, took, lived, -1.0]


func check_strikes_on_its_own(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var r = _raider_at(v, 600.0, 0.0)
	var hits: int = g.hits
	var kills: int = g.kills
	var got := _strike_and_kill(v, g, r, int(5.0 / DT), func() -> void: _frame(v, g))
	check("a raider 600 m off: an orb reaches it %.3f s on (within 2), it takes %d (3) and lives (%s); a second strike kills it %.3f s on (6 HP: hits %d -> %d, kills %d -> %d, the director's raiders %d)" % [
		got[0], got[1], got[2], got[3], hits, g.hits, kills, g.kills, v.raids.kills_by.raider],
		float(got[0]) > 0.0 and float(got[0]) <= 2.0 and int(got[1]) == 3 and bool(got[2]) and float(got[3]) > float(got[0])
		and g.hits == hits + 2 and g.kills == kills + 1 and int(v.raids.kills_by.raider) == 1)
	_clear(v, g)
	var three := [_raider_at(v, 400.0, 0.0), _raider_at(v, 550.0, 120.0), _raider_at(v, 700.0, 240.0)]
	for i in 6:
		_frame(v, g)
		if _states(m).all(func(s: String) -> bool: return s == "out"):
			break
	var targets: Array = m.orbs.map(func(o): return o.target)
	var each: bool = three.all(func(c) -> bool: return targets.count(c) == 1)
	check("three raiders 400, 550 and 700 m off: each orb takes a different one (the orbs %s, on %s)" % [_states(m), targets.map(func(c) -> int: return three.find(c))], each)
	_clear(v, g)


func check_out_of_reach(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var far = _raider_at(v, 1200.0, 0.0)
	var edge = _raider_at(v, 920.0, 60.0)
	var inside = _raider_at(v, 880.0, -60.0)
	var taken := {}
	for i in int(5.0 / DT):
		_frame(v, g)
		for o in m.orbs:
			if o.target != null:
				taken[o.target] = true
	check("raiders 1,200 m and 920 m off (reach 900) are left alone over 5 s (taken %s, %s; struck %s, %s); one 880 m off is taken (%s) and struck (%s)" % [
		taken.has(far), taken.has(edge), g._damage.has(far.id), g._damage.has(edge.id), taken.has(inside), not g.alive(inside) or g._damage.has(inside.id)],
		not taken.has(far) and not taken.has(edge) and g.alive(far) and g.alive(edge) and not g._damage.has(far.id) and not g._damage.has(edge.id)
		and taken.has(inside) and (not g.alive(inside) or g._damage.has(inside.id)))
	_clear(v, g)


func check_send(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var r = _raider_at(v, 2000.0, 0.0)
	_frames(v, g, 10, r)
	var on: bool = g.aim_car == r
	var shots: int = g.shots
	var sent := _press(v, g, r)
	var all_out: bool = m.orbs.all(func(o) -> bool: return o.state == "out" and o.target == r)
	var got := _send_run(v, g, r, func() -> void: _frame(v, g, DT, r if g.alive(r) else null))
	var due: float = (2000.0 - m.orbit_r - 8.0) / m.orb_v
	check("the gaze on a raider 2,000 m off (under the sight: %s): a press sends all three (%s, %s), one shot (%d -> %d); the first strikes %.3f s on (due %.3f: orbV from the orbit); it dies %.3f s on, at the second strike (%d when it went), %d strikes in all (the third turned back short of it), all home again (%s)" % [
		on, sent, all_out, shots, g.shots, got.first, due, got.dead, got.at_death, got.strikes, _in_orbit(m)],
		on and sent and all_out and g.shots == shots + 1 and got.first >= due - 0.05 and got.first <= due + 0.1 and got.dead >= got.first
		and got.dead - got.first <= 0.1 and got.at_death == 2 and got.strikes == 2 and _in_orbit(m))
	_clear(v, g)
	# No hostile under the gaze, or one beyond the gaze's search (sendReach): nothing goes.
	shots = g.shots
	var sends: int = m.sends
	var none := _press(v, g)
	var kind: String = g.aim_kind
	var beyond = _raider_at(v, 2300.0, 0.0)
	_frames(v, g, 10, beyond)
	var seen = g.aim_car
	var far := _press(v, g, beyond)
	_frames(v, g, 5, beyond)
	check("with no hostile under the gaze (it is on the %s) a press sends nothing (%s); nor at a raider 2,300 m off, beyond sendReach (under the sight: %s; sent %s): every orb in its place (%s), sends %d -> %d, shots %d -> %d" % [
		kind, none, seen, far, _in_orbit(m), sends, m.sends, shots, g.shots], not none and kind != "vehicle" and seen == null and not far
		and _in_orbit(m) and m.sends == sends and g.shots == shots)
	_clear(v, g)
	# A send redirects no orb already out.
	var a = _raider_at(v, 500.0, 30.0)
	var b = _raider_at(v, 650.0, -30.0)
	var c = _raider_at(v, 1500.0, 0.0)
	_frames(v, g, 3, c)
	var before: Array = m.orbs.map(func(o): return o.target)
	var pressed := _press(v, g, c)
	var after: Array = m.orbs.map(func(o): return o.target)
	var kept := true
	var to_c := 0
	for k in before.size():
		if before[k] != null:
			kept = kept and after[k] == before[k]
		else:
			to_c += int(after[k] == c)
	check("raiders 500 and 650 m off taken on their own by two orbs (%s), the third in its place; the gaze on one 1,500 m off and a press (%s): only the third goes at it (%d), the two out keep theirs (%s)" % [
		before.map(func(t) -> int: return [a, b, c].find(t)), pressed, to_c, kept],
		before.count(a) == 1 and before.count(b) == 1 and before.count(null) == 1 and pressed and to_c == 1 and kept)
	_clear(v, g)


## After a send at `r`, frames (`step`) till it is gone and every orb home (6 s at the most): {first: s to the first strike,
## dead: s to its death, at_death: the strikes landed by then (two orbs may land in one frame), strikes: in all}.
func _send_run(v, g, r, step: Callable) -> Dictionary:
	var m = g.mount
	var s0: int = m.strikes
	var out := {"first": -1.0, "dead": -1.0, "at_death": -1, "strikes": 0}
	for i in range(1, int(6.0 / DT)):
		step.call()
		if out.first < 0.0 and m.strikes > s0:
			out.first = i * DT
		if out.dead < 0.0 and not g.alive(r):
			out.dead = i * DT
			out.at_death = m.strikes - s0
		if out.dead > 0.0 and _in_orbit(m):
			break
	out.strikes = m.strikes - s0
	return out


## A target's middle (the sims' frame): a flyer's own, a vehicle's body.
static func _middle(v, t) -> Vector3:
	return Vector3(t.x, t.y, float(t.z) if GunneryScript._is_flyer(t) else v.traffic_net.body_height(t))


## (Review Focus 1, at rest.) Two orbs sent at a raider, it shot down by other means with both 300 m short; and the raid
## reset with three out.
func check_orb_comes_home(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var e = _flyer(v, "drone", _point(v, 100.0, 90.0, 30.0))
	var tgt = _raider_at(v, 1000.0, 0.0)
	_frames(v, g, 2, tgt)
	var pressed := _press(v, g, tgt)
	var two: Array = m.orbs.filter(func(o) -> bool: return o.target == tgt)
	for i in int(3.0 / DT):
		if two.all(func(o) -> bool: return o.p.distance_to(_middle(v, tgt)) <= 300.0):
			break
		_frame(v, g, DT, tgt)
	var short: Array = two.map(func(o) -> float: return snappedf(o.p.distance_to(_middle(v, tgt)), 0.1))
	var kills: int = g.kills
	var strikes: int = m.strikes
	var out_then: Array = two.map(func(o) -> float: return _out_m(v, o))
	g.damage(tgt, GunneryScript.HOSTILE_HP, _middle(v, tgt))      # (shot down by other means)
	_frame(v, g)
	var turned := true
	for k in two.size():
		turned = turned and two[k].state == "back" and _out_m(v, two[k]) <= float(out_then[k]) + 1e-3
	var home := -1.0
	for i in range(1, int(3.5 / DT)):
		_frame(v, g)
		if _in_orbit(m):
			home = (i + 1) * DT
			break
	check("a drone 100 m off taken on its own (gone: %s), two orbs sent at a raider 1,000 m off (%s, %d); the raider shot down by other means with both %s m short: both turned back that frame, no further out (%s), every orb home %.3f s on (within 3); kills %d -> %d (that one alone), strikes %d -> %d" % [
		not g.alive(e), pressed, two.size(), short, turned, home, kills, g.kills, strikes, m.strikes],
		not g.alive(e) and pressed and two.size() == 2 and short.all(func(s: float) -> bool: return s <= 300.0 and s > 250.0) and turned
		and home > 0.0 and home <= 3.0 and g.kills == kills + 1 and m.strikes == strikes)
	_clear(v, g)
	# The raid reset (a restart's, a respawn's: the pack taken out of traffic) with three out.
	var three := [_raider_at(v, 600.0, 0.0), _raider_at(v, 700.0, 120.0), _raider_at(v, 800.0, 240.0)]
	_frames(v, g, int(0.3 / DT))
	var out_n: int = _states(m).count("out")
	var hits: int = g.hits
	strikes = m.strikes
	kills = g.kills
	v.raids.reset()
	home = -1.0
	for i in range(1, int(3.5 / DT)):
		_frame(v, g)
		if _in_orbit(m):
			home = i * DT
			break
	check("the raid reset with %d orbs out at three raiders (gone: %s): every orb home %.3f s on (within 3), no strike after (%d -> %d, hits %d -> %d), no kill (%d -> %d)" % [
		out_n, three.all(func(c) -> bool: return not g.alive(c)), home, strikes, m.strikes, hits, g.hits, kills, g.kills],
		out_n == 3 and home > 0.0 and home <= 3.0 and m.strikes == strikes and g.hits == hits and g.kills == kills)
	_clear(v, g)


## (Review Focus 3, at rest.) SAFE with all three out: home and docked before the doors close; and the longest return.
func check_safe_mid_use(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var r = _raider_at(v, 1000.0, 0.0)
	_frames(v, g, 10, r)
	var sent := _press(v, g, r)
	for i in int(2.0 / DT):
		if m.orbs.all(func(o) -> bool: return o.state == "out" and _out_m(v, o) >= 500.0):
			break
		_frame(v, g, DT, r)
	var out_m := INF
	for o in m.orbs:
		out_m = minf(out_m, _out_m(v, o) if o.state == "out" else -1.0)
	var got := _safe(v, g, func() -> void: _frame(v, g), 8.0)
	check("SAFE with all three %.0f m out toward a raider 1,000 m off (sent: %s): each docked (%s s after SAFE) within %.4f m of its docks() place at the most (%.2f), before the deploy first fell below 1 (%.3f s after); no strike after SAFE (%d)" % [
		out_m, sent, got.docked, got.off, DOCK_M, got.below, got.strikes], sent and out_m >= 500.0 and got.all_docked_first and got.off <= DOCK_M
		and got.below > 0.0 and got.strikes == 0)
	check("... the doors then close: the deploy at 0 %.3f s after SAFE (%.3f s after it fell below 1), the arms hidden (%s), the orbs held in their seats as they closed (%.4f m off at the most)" % [
		got.closed, got.closed - got.below, got.hidden, got.held], got.closed > got.below and got.closed - got.below <= 1.0 + 2.0 * DT
		and got.hidden and got.held <= DOCK_M)
	g.want_out = true
	_clear(v, g)
	# The longest return: an orb near 2,200 m out.
	var far = _raider_at(v, 2195.0, 0.0)
	_frames(v, g, 10, far)
	sent = _press(v, g, far)
	for i in int(5.0 / DT):
		if m.orbs.any(func(o) -> bool: return o.state == "out" and _out_m(v, o) >= 2150.0):
			break
		_frame(v, g, DT, far)
	out_m = 0.0
	for o in m.orbs:
		out_m = maxf(out_m, _out_m(v, o) if o.state == "out" else 0.0)
	got = _safe(v, g, func() -> void: _frame(v, g), 8.0)
	var most: float = out_m / m.orb_v + 1.0
	print("  LONGEST RETURN (at rest): SAFE with an orb %.0f m out: the last docked %.3f s after, the deploy held at 1 till then (%s)" % [out_m, got.docked_s, got.all_docked_first])
	check("SAFE with an orb %.0f m out toward a raider 2,195 m off (sent: %s, it lives: %s): the arms waited (the deploy held at 1 till the last docked: %s), %.3f s after SAFE (at most %.2f: its flight home at orbV and its glide)" % [
		out_m, sent, g.alive(far), got.all_docked_first, got.docked_s, most], sent and out_m >= 2150.0 and g.alive(far) and got.all_docked_first
		and got.docked_s > 0.0 and got.docked_s <= most)
	g.want_out = true
	_clear(v, g)


## SAFE thrown (the fire control's switch, or on the seat the cockpit's) and frames (`step`) till the doors are shut
## (`most` s at the most): when each orb docked and how near its seat, when the deploy first fell below 1 and whether all
## were docked then, when it reached 0, the arms hidden then, and the strikes after SAFE.
func _safe(v, g, step: Callable, most: float) -> Dictionary:
	var m = g.mount
	var strikes: int = m.strikes
	g.want_out = false
	v.gun_wanted = false
	var out := {"docked": [], "docked_s": -1.0, "off": 0.0, "below": -1.0, "all_docked_first": false, "closed": -1.0, "hidden": false, "held": 0.0, "strikes": 0}
	var at := [-1.0, -1.0, -1.0]
	for i in range(1, int(most / DT)):
		step.call()
		var docks: Array = m.arms.docks()
		for k in m.orbs.size():
			var gap: float = (m.arms.orbs[k] as Node3D).global_position.distance_to((docks[k] as Transform3D).origin)
			if at[k] < 0.0 and m.orbs[k].state == "docked":
				at[k] = i * DT
				out.off = maxf(out.off, gap)
			if out.below > 0.0 and m.orbs[k].state == "docked":
				out.held = maxf(out.held, gap)
		if out.docked_s < 0.0 and at.all(func(s: float) -> bool: return s > 0.0):
			out.docked_s = i * DT
		if out.below < 0.0 and m.deploy_t() < 1.0:
			out.below = i * DT
			out.all_docked_first = at.all(func(s: float) -> bool: return s > 0.0)
		if m.deploy_t() <= 0.0:
			out.closed = i * DT
			out.hidden = not (m.arms as Node3D).visible
			break
	out.docked = at.map(func(s: float) -> float: return snappedf(s, 0.001))
	out.strikes = m.strikes - strikes
	return out


## A 120 HP gunship GUNSHIP_M off on their own; the rest between sorties; and the tuning's two figures.
func check_gunship(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var ship = _flyer(v, "gunship", _point(v, GUNSHIP_M, 15.0, 30.0), 120)
	var dist := _dist(v, ship)
	var got := _gunship_run(v, g, ship, 25.0, func() -> void: _frame(v, g))
	check("a 120 HP gunship %.1f m off (in the round), on their own: shot down %.2f s on (within 20), %d strikes; every orb back in its place rested %.3f s at the least before it left again (restS %.1f)" % [
		dist, got.dead, got.strikes, got.rest, m.rest_s], got.dead > 0.0 and got.dead <= 20.0 and got.strikes == 40 and got.rest >= m.rest_s - DT - 1e-6)
	_clear(v, g)
	# Figures for the tuning (not bars): at 400 m on their own, and at 1,000 m (beyond reach) by repeated sends.
	ship = _flyer(v, "gunship", _point(v, 400.0, 15.0, 0.0), 120)
	var own := _gunship_run(v, g, ship, 60.0, func() -> void: _frame(v, g))
	_clear(v, g)
	ship = _flyer(v, "gunship", _point(v, 1000.0, 0.0, 30.0), 120)
	var sent := _gunship_run(v, g, ship, 80.0, _press_every_other.bind(v, g, ship, [0]))
	print("  GUNSHIP FIGURES: 120 HP, the three on their own %.0f m off: %.2f s (%d strikes); by repeated sends %.0f m off: %.2f s (%d strikes, %d sends)" % [
		400.0, own.dead, own.strikes, 1000.0, sent.dead, sent.strikes, sent.sends])
	check("the tuning's figures were measured: the gunship 400 m off on their own %.2f s, 1,000 m off by sends %.2f s" % [own.dead, sent.dead], own.dead > 0.0 and sent.dead > 0.0)
	_clear(v, g)


## A frame of the still world, the gaze on `ship`, the trigger pressed every other frame (each press sends whatever is in
## orbit then); `n` counts the frames.
func _press_every_other(v, g, ship, n: Array) -> void:
	n[0] += 1
	g.hold_fire = n[0] % 2 == 1
	_frame(v, g, DT, ship if g.alive(ship) else null)
	g.hold_fire = false


## Frames (`step`) till `ship` is shot down, `most` s at the most: {dead: s (-1), strikes, sends, rest: the least s an orb
## stood rested in its place between coming home and leaving again}.
func _gunship_run(v, g, ship, most: float, step: Callable) -> Dictionary:
	var m = g.mount
	var strikes: int = m.strikes
	var sends: int = m.sends
	var was: Array = _states(m)
	var home_at := [-1.0, -1.0, -1.0]
	var least := INF
	var dead := -1.0
	for i in range(1, int(most / DT)):
		step.call()
		var now: Array = _states(m)
		for k in now.size():
			if was[k] == "back" and now[k] == "orbit":
				home_at[k] = i * DT
			elif was[k] == "orbit" and now[k] == "out" and home_at[k] >= 0.0:
				least = minf(least, i * DT - float(home_at[k]))
		was = now
		if not g.alive(ship):
			dead = i * DT
			break
	return {"dead": dead, "strikes": m.strikes - strikes, "sends": m.sends - sends, "rest": least}


## (At rest.) An orb 300 m out: its streak behind it, in the world; none in orbit.
func check_drawn(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	var none: int = m.drawn.size()
	var r = _raider_at(v, 600.0, 0.0)
	for i in int(1.0 / DT):
		_frame(v, g)
		if m.orbs.any(func(o) -> bool: return o.state == "out" and _out_m(v, o) >= 300.0):
			break
	var k: int = _states(m).find("out")
	var said := "no orb out"
	var ok := false
	if k >= 0 and m.drawn.size() == 1:
		var d: Array = m.drawn[0]
		var orb: Vector3 = (m.arms.orbs[k] as Node3D).global_position
		var o = m.orbs[k]
		var behind: float = ((d[1] as Vector3) - orb).normalized().dot(d[2])
		said = "orb %d %.0f m out, drawn where it is (%.4f m off), its streak %.1f m long and %.3f m wide (%.2f at the least), behind it (%.2f along its way)" % [
			k, _out_m(v, o), orb.distance_to(g.to_render(o.p)), d[3], d[4], OrbMountScript.STREAK_W, behind]
		ok = orb.distance_to(g.to_render(o.p)) < 1e-3 and float(d[3]) > 1.0 and float(d[3]) <= GunneryScript.STREAK + 1e-3 and float(d[4]) >= OrbMountScript.STREAK_W - 1e-6 and behind < -0.99
	var under: Node = g.get_node_or_null("OrbStreaks")
	check("in orbit no streak is drawn (%d); %s; the streaks hang in the world under the fire control (%s), not before the camera nor on a CanvasLayer" % [
		none, said, under.get_parent().name if under else null], none == 0 and ok and under != null and under.get_parent() == g and under is MultiMeshInstance3D)
	_clear(v, g)


## Three orbs working a full raid (kept full: 6 raiders, 10 drones, the gunship, all in reach) with traffic's most about,
## and a send at the gunship every half second: the mount's own time a frame (its step and fire), mean and worst.
func check_cost(v, g) -> void:
	var m = g.mount
	_clear(v, g)
	for c in _fleet:
		v.traffic_net.cars.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var hw: float = float(v.sim.roads[v.sim.pod.path].w[int(v.sim.pod.hint)]) * 0.5
	var way: Vector2 = seat.road_way(v)
	var P := Vector2(v.sim.pod.x, v.sim.pod.y)
	while v.traffic_net.cars.size() < v.traffic_net.TARGET:      # (traffic's most, near a city: 220, along the road 2 km behind to 4 km ahead)
		var at := P + way * rng.randf_range(-2000.0, 4000.0) + Vector2(-way.y, way.x) * rng.randf_range(-0.8, 0.8) * hw
		_car(v, at, false)
	var R = v.raids
	var ship = null
	var costs := PackedFloat32Array()
	var whole := PackedFloat32Array()
	var kills: int = g.kills
	var strikes: int = m.strikes
	var sends: int = m.sends
	for i in 600:
		R.pack = R.pack.filter(func(c) -> bool: return g.alive(c))
		for k in range(R.pack.size(), 6):
			_raider_at(v, rng.randf_range(150.0, 850.0), rng.randf_range(-180.0, 180.0))
		var drones: int = R.flyers._list.filter(func(f) -> bool: return f.kind == "drone").size()
		for k in range(drones, 10):
			_flyer(v, "drone", _point(v, rng.randf_range(150.0, 800.0), rng.randf_range(-180.0, 180.0), rng.randf_range(60.0, 120.0)))
		if ship == null or not g.alive(ship):
			ship = _flyer(v, "gunship", _point(v, 400.0, 30.0, 60.0), 120)
		g.hold_fire = i % 180 == 90      # (a send each 1.5 s among the orbs' own work)
		var t0 := Time.get_ticks_usec()
		_frame(v, g, DT, ship)
		whole.append((Time.get_ticks_usec() - t0) / 1000.0)
		g.hold_fire = false
		costs.append(m.cost_ms)
	var mean := 0.0
	var worst := 0.0
	for c: float in costs:
		mean += c
		worst = maxf(worst, c)
	mean /= costs.size()
	var whole_mean := 0.0
	for c: float in whole:
		whole_mean += c
	whole_mean /= whole.size()
	print("  COST: three orbs over 600 frames among a full raid (17 threats, kept full) with %d vehicles about: the mount's own step and fire %.4f ms mean, %.4f worst; the whole fire control's step (its gaze search to %.0f m among them) %.4f ms mean; %d kills, %d strikes, %d sends" % [
		v.traffic_net.cars.size(), mean, worst, g.reach, whole_mean, g.kills - kills, m.strikes - strikes, m.sends - sends])
	check("three orbs working a full raid with traffic's fleet about (%d): the mount %.4f ms a frame mean over 600 frames (under %.2f), %.4f worst; %d strikes, %d kills" % [
		v.traffic_net.cars.size(), mean, COST_MS, worst, m.strikes - strikes, g.kills - kills], mean < COST_MS and m.strikes - strikes >= 10)
	_clear(v, g)


## The flat view (view/craft_view.gd: the GUN is K, the trigger F) on the Range: the arms on the craft's own pod.
func check_flat_range() -> void:
	View.track_override = "range"
	View.vehicle_override = Pilot.ORRERY
	var game = View.new()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	for i in 5:
		game._process(DT)
	var none: bool = game.gunnery == null and game.craft.pod.get_node_or_null("Arms") == null
	game.gun_wanted = true
	for i in int(2.2 / DT):
		game._process(DT)
	var g = game.gunnery
	var arms = game.craft.pod.get_node_or_null("Arms")
	var mount = game.craft.weapon
	if mount == null or mount.get("orbs") == null or g == null or arms == null:
		check("the flat view on the Range: the Orrery's weapon is the orbs' mount (%s), a fire control made (%s), the Arms on its pod (%s)" % [mount, g, arms], false)
		game.queue_free()
		await process_frame
		View.track_override = "network"
		return
	var worst := 0.0
	var to_arms: Transform3D = (arms as Node3D).global_transform.affine_inverse()
	for k in mount.orbs.size():
		var local: Vector3 = to_arms * (arms.orbs[k] as Node3D).global_position
		worst = maxf(worst, absf(Vector2(local.x, local.z).length() - mount.orbit_r))
	check("the flat view on the Range: nothing built till armed (%s); armed 2.2 s, the fire control (%s) and the Arms on the craft's own pod (%s), out (deploy %.2f), drawn; the orbs in orbit round it (%s), %.4f m off %.1f m at the worst" % [
		none, g != null, arms, mount.deploy_t(), _states(mount), worst, mount.orbit_r],
		none and g.mount == mount and mount.get("arms") == arms and mount.is_out() and arms.is_visible_in_tree() and _in_orbit(mount) and worst <= ON_R)
	game.queue_free()
	await process_frame
	View.track_override = "network"


# --- the checks: Raids on, the seat's own frames at 1,500 mph -----------------------------------------------------

## Raids on: the fire control made at load, dormant, and the arms fitted then, stowed; the first arming builds nothing
## more. Whether the checks after it can run.
func check_raids_on_arming(v) -> bool:
	var hull: MeshInstance3D = v.shell.get_node("PodHull")
	var g = v.gunnery
	var mount = v.craft.weapon
	if g == null or mount == null or mount.get("orbs") == null or v.raids == null:
		check("Raids on: a fire control made at load, the orbs' mount and the raid's director (%s, %s, %s)" % [g, mount, v.raids], false)
		return false
	v.raids.first_after = INF      # (no alarm while the test flies: every target is the test's own)
	var stowed_arms = hull.get_node_or_null("Arms")
	var closed: Mesh = hull.mesh
	check("Raids on: the fire control is made at load, dormant (%s), through the orbs' mount; the Arms built then on the seat's hull (%s), stowed: not drawn (%s), the hull its own mesh (%s), the orbs docked (%s)" % [
		g.dormant, stowed_arms, stowed_arms.visible if stowed_arms != null else null, closed == v.craft.fleet.part(&"Cab"), _states(mount)],
		g.dormant and g.mount == mount and stowed_arms != null and mount.get("arms") == stowed_arms and not stowed_arms.visible
		and closed == v.craft.fleet.part(&"Cab") and mount.deploy_t() == 0.0 and _states(mount).all(func(s: String) -> bool: return s == "docked"))
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
	_armed_at = 4.0 * DT
	return true


## The pulses sent to the hands, as [hand (0 left, 1 right), amp, s, delay].
static func _said(v, pulses: Array) -> Array:
	var hands := [v.hands.left, v.hands.right]
	return pulses.map(func(p: Array) -> Array: return [hands.find(p[0]), snappedf(float(p[1]), 0.001), snappedf(float(p[2]), 0.001), float(p[3])])


func check_hand_tick(v) -> void:
	var g = v.gunnery
	var m = g.mount
	_ready_on_seat(v, g)
	var paced := [_paced_raider(v, 1500.0)]
	var r = paced[0][0]
	for i in 5:
		_sf(v, g, false, paced, [], r)
	var shots: int = g.shots
	var sends: int = m.sends
	var got := []
	got.append_array(_sf(v, g, true, paced, [], r))
	var sent: bool = m.sends == sends + 1
	for i in 2:
		got.append_array(_sf(v, g, false, paced, [], r))
	var said := _said(v, got)
	var one: bool = said.size() == 1 and int(said[0][0]) == 0 and is_equal_approx(float(said[0][1]), Seat.GUN_TICK_AMP) and float(said[0][3]) == 0.0
	var again := _sf(v, g, true, paced, [], r).size()      # (a press with every orb away)
	for i in 2:
		again += _sf(v, g, false, paced, [], r).size()
	var s0: int = m.strikes
	var later := 0
	for i in int(2.5 / DT):
		later += _sf(v, g, false, paced, [], r).size()
	check("on the seat's own frames, a send (%s) at a raider paced 1,500 m ahead: %s [hand (0 left, 1 right), amp, s, delay] over it and the two frames after: one tick in the hand that fires, at once; none for a press with every orb away (%d), none over the 2.5 s after as the orbs strike (%d strikes, %d ticks); one shot counted (%d -> %d)" % [
		sent, said, again, m.strikes - s0, later, shots, g.shots], sent and one and again == 0 and m.strikes - s0 >= 1 and later == 0 and g.shots == shots + 1)


func check_strikes_at_speed(v) -> void:
	var g = v.gunnery
	var m = g.mount
	_ready_on_seat(v, g)
	var paced := [_paced_raider(v, 600.0)]
	var r = paced[0][0]
	var kills: int = g.kills
	var got := _strike_and_kill(v, g, r, int(5.0 / DT), func() -> void: _sf(v, g, false, paced))
	check("at 1,500 mph on the seat's own frames, a raider paced 600 m ahead: an orb reaches it %.3f s on (within 2: it closes at orbV), it takes %d (3) and lives (%s); a second strike kills it %.3f s on (kills %d -> %d)" % [
		got[0], got[1], got[2], got[3], kills, g.kills], float(got[0]) > 0.0 and float(got[0]) <= 2.0 and int(got[1]) == 3 and bool(got[2])
		and float(got[3]) > float(got[0]) and g.kills == kills + 1)
	_ready_on_seat(v, g)
	paced = [_paced_raider(v, 400.0), _paced_raider(v, 550.0, 1), _paced_raider(v, 700.0, -1)]
	var three: Array = paced.map(func(p: Array): return p[0])
	for i in 6:
		_sf(v, g, false, paced)
		if _states(m).all(func(s: String) -> bool: return s == "out"):
			break
	var targets: Array = m.orbs.map(func(o): return o.target)
	check("at 1,500 mph, three raiders paced 400, 550 and 700 m ahead: each orb takes a different one (the orbs %s, on %s)" % [_states(m), targets.map(func(c) -> int: return three.find(c))],
		three.all(func(c) -> bool: return targets.count(c) == 1))
	_ready_on_seat(v, g)
	paced = [_paced_raider(v, 1200.0), _paced_raider(v, 920.0, 1)]
	var taken := {}
	for i in int(3.0 / DT):
		_sf(v, g, false, paced)
		for o in m.orbs:
			if o.target != null:
				taken[o.target] = true
	check("at 1,500 mph, raiders paced 1,200 m and 920 m ahead (%.0f m and %.0f m off) are left alone over 3 s (taken %s, %s; every orb in its place: %s)" % [
		_dist(v, paced[0][0]), _dist(v, paced[1][0]), taken.has(paced[0][0]), taken.has(paced[1][0]), _in_orbit(m)],
		not taken.has(paced[0][0]) and not taken.has(paced[1][0]) and _in_orbit(m) and _dist(v, paced[1][0]) > 900.0)


func check_send_at_speed(v) -> void:
	var g = v.gunnery
	var m = g.mount
	_ready_on_seat(v, g)
	var paced := [_paced_raider(v, 2000.0)]
	var r = paced[0][0]
	for i in 10:
		_sf(v, g, false, paced, [], r)
	var on: bool = g.aim_car == r
	var shots: int = g.shots
	var sends: int = m.sends
	_sf(v, g, true, paced, [], r)
	var all_out: bool = m.orbs.all(func(o) -> bool: return o.state == "out" and o.target == r)
	var got := _send_run(v, g, r, func() -> void: _sf(v, g, false, paced, [], r if g.alive(r) else null))
	var due: float = (2000.0 - m.orbit_r - 8.0) / m.orb_v
	check("at 1,500 mph, the gaze on a raider paced 2,000 m ahead (under the sight: %s): a press sends all three (%s), one shot (%d -> %d); the first strikes %.3f s on (due %.3f: closing at orbV); it dies %.3f s on, at the second strike (%d when it went), %d strikes in all, all home again (%s)" % [
		on, all_out, shots, g.shots, got.first, due, got.dead, got.at_death, got.strikes, _in_orbit(m)],
		on and m.sends == sends + 1 and all_out and g.shots == shots + 1 and got.first >= due - 0.1 and got.first <= due + 0.15
		and got.dead >= got.first and got.dead - got.first <= 0.1 and got.at_death == 2 and got.strikes == 2 and _in_orbit(m))


func check_comes_home_at_speed(v) -> void:
	var g = v.gunnery
	var m = g.mount
	var R = v.raids
	_ready_on_seat(v, g)
	var near := _paced_raider(v, 300.0, 1)
	var far := _paced_raider(v, 1000.0)
	var tgt = far[0]
	var paced := [near, far]
	for i in 2:
		_sf(v, g, false, paced, [], tgt)
	_sf(v, g, true, paced, [], tgt)
	var two: Array = m.orbs.filter(func(o) -> bool: return o.target == tgt)
	v.traffic_net.cars.erase(near[0])      # (the near one taken away: its orb turns back)
	R.pack.erase(near[0])
	paced = [far]
	for i in int(3.0 / DT):
		if two.all(func(o) -> bool: return o.p.distance_to(_middle(v, tgt)) <= 300.0):
			break
		_sf(v, g, false, paced, [], tgt)
	var short: Array = two.map(func(o) -> float: return snappedf(o.p.distance_to(_middle(v, tgt)), 0.1))
	var kills: int = g.kills
	var strikes: int = m.strikes
	var out_then: Array = two.map(func(o) -> float: return _out_m(v, o))
	g.damage(tgt, GunneryScript.HOSTILE_HP, _middle(v, tgt))      # (shot down by other means)
	_sf(v, g)
	var turned := true
	for k in two.size():
		turned = turned and two[k].state == "back" and _out_m(v, two[k]) <= float(out_then[k]) + 1e-3
	var home := -1.0
	for i in range(1, int(3.5 / DT)):
		_sf(v, g)
		if _in_orbit(m):
			home = (i + 1) * DT
			break
	check("at 1,500 mph, two orbs sent at a raider paced 1,000 m ahead (%d); it shot down by other means with both %s m short: both turned back that frame, nearer the craft (%s), every orb home %.3f s on (within 3); kills %d -> %d (that one alone), strikes %d -> %d" % [
		two.size(), short, turned, home, kills, g.kills, strikes, m.strikes],
		two.size() == 2 and short.all(func(s: float) -> bool: return s <= 300.0 and s > 250.0) and turned and home > 0.0 and home <= 3.0
		and g.kills == kills + 1 and m.strikes == strikes)
	_ready_on_seat(v, g)
	paced = [_paced_raider(v, 600.0), _paced_raider(v, 700.0, 1), _paced_raider(v, 800.0, -1)]
	for i in int(0.3 / DT):
		_sf(v, g, false, paced)
	var out_n: int = _states(m).count("out")
	strikes = m.strikes
	kills = g.kills
	R.reset()
	home = -1.0
	for i in range(1, int(3.5 / DT)):
		_sf(v, g)
		if _in_orbit(m):
			home = i * DT
			break
	check("at 1,500 mph, the raid reset with %d orbs out at three paced raiders: every orb home %.3f s on (within 3), no strike after (%d -> %d), no kill (%d -> %d)" % [
		out_n, home, strikes, m.strikes, kills, g.kills], out_n == 3 and home > 0.0 and home <= 3.0 and m.strikes == strikes and g.kills == kills)


func check_safe_at_speed(v) -> void:
	var g = v.gunnery
	var m = g.mount
	_ready_on_seat(v, g)
	var paced := [_paced_raider(v, 1000.0)]
	var r = paced[0][0]
	for i in 10:
		_sf(v, g, false, paced, [], r)
	_sf(v, g, true, paced, [], r)
	var sent: bool = _states(m).count("out") == 3
	for i in int(2.0 / DT):
		if m.orbs.all(func(o) -> bool: return o.state == "out" and _out_m(v, o) >= 500.0):
			break
		_sf(v, g, false, paced, [], r)
	var got := _safe(v, g, func() -> void: _sf(v, g, false, paced), 8.0)
	check("at 1,500 mph, SAFE with all three 500 m out toward a raider paced 1,000 m ahead (sent: %s): each docked (%s s after SAFE) within %.4f m of its docks() place at the most (%.2f), before the deploy first fell below 1 (%.3f s after); no strike after SAFE (%d)" % [
		sent, got.docked, got.off, DOCK_M, got.below, got.strikes], sent and got.all_docked_first and got.off <= DOCK_M and got.below > 0.0 and got.strikes == 0)
	check("... the doors then close: the deploy at 0 %.3f s after SAFE (%.3f s after it fell below 1), the arms hidden (%s), the orbs held in their seats as they closed (%.4f m off at the most)" % [
		got.closed, got.closed - got.below, got.hidden, got.held], got.closed > got.below and got.closed - got.below <= 1.0 + 2.0 * DT
		and got.hidden and got.held <= DOCK_M)
	v.gun_wanted = true
	_ready_on_seat(v, g)
	# The longest return: an orb near 2,200 m out behind the craft, which runs from it at 1,500 mph.
	paced = [_paced_raider(v, -2195.0)]
	r = paced[0][0]
	for i in 10:
		_sf(v, g, false, paced, [], r)
	var on: bool = g.aim_car == r
	_sf(v, g, true, paced, [], r)
	sent = _states(m).count("out") == 3
	for i in int(5.0 / DT):
		if m.orbs.any(func(o) -> bool: return o.state == "out" and _out_m(v, o) >= 2150.0):
			break
		_sf(v, g, false, paced, [], r)
	var out_m := 0.0
	for o in m.orbs:
		out_m = maxf(out_m, _out_m(v, o) if o.state == "out" else 0.0)
	got = _safe(v, g, func() -> void: _sf(v, g, false, paced), 8.0)
	var most: float = out_m / m.orb_v + 1.0
	print("  LONGEST RETURN (at 1,500 mph, the craft running from it): SAFE with an orb %.0f m out behind: the last docked %.3f s after, the deploy held at 1 till then (%s)" % [out_m, got.docked_s, got.all_docked_first])
	check("at 1,500 mph, SAFE with an orb %.0f m out behind the craft (a raider paced 2,195 m behind under the gaze: %s; sent %s): the arms waited (the deploy held at 1 till the last docked: %s), %.3f s after SAFE (at most %.2f: home at orbV, and its glide)" % [
		out_m, on, sent, got.all_docked_first, got.docked_s, most], on and sent and out_m >= 2150.0 and got.all_docked_first
		and got.docked_s > 0.0 and got.docked_s <= most)
	v.gun_wanted = true
	_ready_on_seat(v, g)


func check_gunship_at_speed(v) -> void:
	var g = v.gunnery
	_ready_on_seat(v, g)
	var ship = _flyer(v, "gunship", _point(v, GUNSHIP_M, 0.0, 30.0), 120)
	var flying := [[ship, GUNSHIP_M, 30.0]]
	var org0 := Vector2(v.org_x, v.org_y)
	var got := _gunship_run(v, g, ship, 25.0, func() -> void: _sf(v, g, false, [], flying))
	check("at 1,500 mph on the seat's own frames, a 120 HP gunship paced %.0f m ahead, 30 m up: shot down %.2f s on (within 20), %d strikes, the craft %.1f km on" % [
		GUNSHIP_M, got.dead, got.strikes, Vector2(v.org_x, v.org_y).distance_to(org0) / 1000.0], got.dead > 0.0 and got.dead <= 20.0 and got.strikes == 40)


## A road sample about `m` m from the craft on a public road, not a shaft or a deck: [road, sample], or [].
static func _sample_off(v, m: float) -> Array:
	var sim = v.sim
	for r in sim.roads.size():
		var Rd = sim.roads[r]
		if Rd.shaft or Rd.deck or not v.traffic_net._public_road(Rd):
			continue
		for i in range(2, Rd.N - 2, 8):
			if absf(Vector2(Rd.px[i] - sim.pod.x, Rd.py[i] - sim.pod.y).length() - m) < 300.0:
				return [r, i]
	return []


func check_restart(v) -> void:
	var g = v.gunnery
	var m = g.mount
	var sim = v.sim
	for how in ["respawn", "restart"]:
		_ready_on_seat(v, g)
		var paced := [_paced_raider(v, 600.0), _paced_raider(v, 700.0, 1), _paced_raider(v, 800.0, -1)]
		for i in int(0.2 / DT):
			_sf(v, g, false, paced)
		var out_n: int = _states(m).count("out")
		var there := _sample_off(v, 30000.0)
		if how == "respawn" and there.is_empty():
			check("a road sample 30 km off to put the craft down on", false)
			continue
		var P0 := _here(v)
		if how == "respawn":
			sim.respawn_on(there[0], there[1], 1)
		else:
			v._respawn()      # (Y: the view's restart)
		var hits: int = g.hits
		var strikes: int = m.strikes
		_sf(v, g)
		var placed := _in_orbit(m)
		var moved := _here(v).distance_to(P0)
		for i in int(2.0 / DT):
			_sf(v, g)
		check("%s (the craft put down %.1f km off) with %d orbs out at three paced raiders: every orb in its place the next frame (%s), no strike over the 2 s after (%d -> %d, hits %d -> %d)" % [
			"a respawn" if how == "respawn" else "the view's restart (Y)", moved / 1000.0, out_n, placed, strikes, m.strikes, hits, g.hits],
			out_n == 3 and moved > 500.0 and placed and m.strikes == strikes and g.hits == hits)


## The CanvasLayers under the view, each one's [shown, its children], and the camera's [h_offset, v_offset, fov, children].
static func _screen(v) -> Array:
	var layers := []
	for n: Node in v.find_children("*", "CanvasLayer", true, false):
		layers.append([String(v.get_path_to(n)), (n as CanvasLayer).visible, n.get_child_count()])
	var cam: Camera3D = v.cam
	return [layers, [cam.h_offset, cam.v_offset, cam.fov, cam.get_child_count()]]


func check_no_flash(v) -> void:
	var g = v.gunnery
	var m = g.mount
	_ready_on_seat(v, g)
	var paced := [_paced_raider(v, 1500.0)]
	var r = paced[0][0]
	for i in 5:
		_sf(v, g, false, paced, [], r)
	var before := _screen(v)
	_sf(v, g, true, paced, [], r)
	var sent: bool = _states(m).count("out") == 3
	var same := true
	var glow := 0.0
	var changed := []
	var s0: int = m.strikes
	for k in range(1, int(3.0 / DT)):
		_sf(v, g, false, paced, [], r if g.alive(r) else null)
		var now := _screen(v)
		if now != before and changed.is_empty():
			changed = [k, now]
		same = same and now == before
		glow = maxf(glow, float(v._jolt_glow))
	check("at 1,500 mph on the seat's own frames, a send (%s) and its sortie (%d strikes): the CanvasLayers and the camera (offsets, field of view, children) as they were (%s%s), the jolt's vignette at %.2f" % [
		sent, m.strikes - s0, same, "" if changed.is_empty() else ": changed at frame %d to %s" % changed, glow], sent and m.strikes - s0 >= 1 and same and glow == 0.0)
