## Raids' gunship (view/raid_flyers.gd; the stage 2 plan, task 3, with its rulings C, K and L). In the VR seat on the
## Network (XR off), the Phaethon, Raids pinned on (but for the first), each raid put down by the director's own arrival
## (an alarm, its city set to the first ground city that is not the start's, a frame: as test_raid_flyers.gd's _raid_on):
##   check_off_builds_nothing   Raids off: no director, no flyers node; 60 frames flown, the gunship's model not loaded
##   check_cadence              has_gunship(1..5): false, false, true, false, true; the director's own arrivals: the first
##                              and second none (the gunship's model still not loaded after them), the third one (loaded
##                              then: that frame told), its HP GUNSHIP_HP and pick radius GUNSHIP_R
##   check_station_and_strafe   the gunship alone, the pilot 5 km off the zone, 60 s: seen above 150 m over the road and
##                              below 30 m; while below 30 m, within the Phaethon's assist cone (its fixed guns'
##                              assist_deg, 3 degrees) of a craft following 800 m behind it on the road's middle for at
##                              least 5 s on end; over a hall, never within 5 m of its roof's height; always within its
##                              zone +-1 km
##   check_shot_hits_pilot      the director stepped alone, no commuters: a pilot holding a straight line at 300 m/s toward
##                              its station from 2.2 km is hit (hit_taken "gunship") within 30 s; one held 1.2 km short of
##                              it, moving 30 m across the road after each warning (the shot it ends in; to the side away
##                              from the shots still in flight), is shot at and never hit in 60 s
##   check_shot_kills_commuter  the gunship alone, the pilot 5 km off the zone: raids.lost rises from its shots
##   check_cover                (ruling K) the craft in the zone's hall 6 samples in from the mouth by the gunship's
##                              station: in 4 s no shot at the pilot (it fires on commuters or holds) and no hit; on the
##                              open road as far from the station the other way: a shot at it within 3 s. A deck built as
##                              test_raid_flyers' check_cover's (the craft 30 m under the zone road's deck, the director
##                              stepped alone, no commuters): no shot and no hit in 4 s; on the deck there: a shot at it
##                              within 3 s. A shot at the craft under the deck (the gun's own _shoot laid on it: the
##                              test's own, no glow; its _fire holds one) reaches it and takes no hit; the same at it on
##                              the deck takes one. The craft in the open just past the hall's far end, the gunship held
##                              200 m over the hall 1 km back (its line to the craft through the roof): no shot at it in
##                              4 s, the pilot left alone; held over the open road the other side: a shot within 3 s
##   check_hold_fire            (ruling C) the director stepped alone, commuters made about it (held where they are): the
##                              craft 120 m behind the gunship held on its run in the open, and 120 m under it on station:
##                              no glow begun, no shot, no glow drawn in 4 s each (the craft 5 km off instead: it glows);
##                              a glow at the craft begun 170 m under it, the craft come to 140 m 0.2 s in: the glow out
##                              that frame (none drawn), and no shot
##   check_crash_ends_shots     a shot laid on the craft while it is down (crash_t): it ends on the craft (gone at
##                              SHOT_HIT, never through it) and takes no hit
##   check_transit_keeps_to_road  a pack of 6 going one way, the craft out of reach, the director stepped alone (the pack
##                              held where it is): two runs the pack's way, the flight back between them along the road
##                              (over 4 km), at STATION_ALT over it, its speed changing no faster than its run's ends do,
##                              and never past the road's half width by more than 10 m
##   check_takes_punishment     119 hits (the fire control's damage) leave it; the 120th kills it: kills_by.gunship 1, its
##                              burst's fireball three times a raider's, its model hidden
##   check_cleared_and_away     every raider and drone killed, the gunship left: still on, the dash naming it (no
##                              "0 RAIDERS", no "0 DRONES"); it killed: "cleared". The pilot beyond R_KEEP of the town but
##                              within it of the gunship: the away clock does not run; the gunship gone: lost ("away")
##   check_reset_clears_flyers_and_shots   (the plan's review focus 2) drones up and shots in flight: raids.reset()
##                              empties flyers.all() and flyers.shots the same frame and draws nothing; 120 frames on, no
##                              hit_taken; traffic's floor free
##   check_cost                 the gunship alone firing (the pilot in reach, traffic about), 600 frames: the module's
##                              update, mean and worst (the mean under COST_MS); with ten drones too (under FLEET_MS)
##   (and at the end, over every frame of the test but the test's own shots: every shot no faster than SHOT_V and its way
##   never changed after it was fired, the muzzle's glow drawn at least SHOT_WARN before it, none fired from nearer than
##   HOLD_FIRE to the pilot: the plan's fairness; and the gunship never flew faster than the town's limit)
## Run with --fixed-fps 120 (traffic and the director run on the engine's frame time; a frame is let pass for every
## step). Prints RAID GUNSHIP PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Art := preload("res://view/raid_flyer_art.gd")
const Traffic := preload("res://view/network_traffic.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const KEEP_M := 1000.0           # m: the gunship stays within its town zone by this
const COST_MS := 0.1             # ms a frame: the gunship's and its shots' update, mean
const FLEET_MS := 0.2            # ... with ten drones too (the plan's 0.5 ms is the director, flyers and weapons together)
const SECTIONS := 13
const SPEED_MARGIN := 0.5        # m/s: a speed read from places frame to frame
var failures := 0
var sections := 0                # (a section that dies on a script error never counts itself: the verdict then fails)
var last_ms := 0.0               # the view's _process on the last frame
var track := true                # the gunship's speed read each frame (not while the test moves it)
var gun_fastest := 0.0           # m/s: the fastest the gunship flew a frame, the whole test ...
var gun_fastest_in := ""         # ... and what it was doing then
# the shots' fairness, over every frame of the test
var seen := {}                   # shot n -> [its v, its place and its t when first seen]
var forced := {}                 # shot n -> true: the test's own (no glow before them)
var fair_shots := 0
var fair_fastest := 0.0          # m/s: the fastest a shot's v, or its flight from where it was first seen
var fair_turned := 0.0           # rad: the most a shot's v turned after it was fired
var fair_strayed := 0.0          # the most a shot's flight strayed off its v's line, against its places' rounding
var fair_glow_least := INF       # s: the least the muzzle's glow was drawn on end before a shot
var fair_nearest := INF          # m: the nearest the pilot was to where a shot was fired from
var glow_run := 0                # frames the muzzle's glow has been drawn on end
var last_n := 0                  # the last shot seen


func _initialize() -> void:
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.spot_override = "E3@9000"
	Cockpit.vehicle_override = Pilot.STANDARD
	Cockpit.best_dir = OS.get_user_data_dir().path_join("test_raid_gunship_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Chase.pinned = true
	Chase.enabled = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	await check_off_builds_nothing()
	Raids.pinned = true
	Raids.enabled = true
	var v = await _cockpit()
	var R = v.raids
	if R == null or not ("flyers" in R) or not R.has_method("has_gunship"):
		_check("raids pinned on: the cockpit has a director (%s) with flyers and has_gunship" % [R], false)
	else:
		v.traffic_net._hw_time = -1.0e9      # (no street racer drops in: it would hold traffic's floor)
		await check_cadence(v)               # (first: the gunship's model must still be cold)
		await check_station_and_strafe(v)
		await check_shot_hits_pilot(v)
		await check_shot_kills_commuter(v)
		await check_cover(v)
		await check_hold_fire(v)
		await check_crash_ends_shots(v)
		await check_transit_keeps_to_road(v)
		await check_takes_punishment(v)
		await check_cleared_and_away(v)
		await check_reset_clears_flyers_and_shots(v)
		await check_cost(v)
		R.reset()
		var F = R.flyers
		_check("over every frame of this test, %d shots (the test's own %d left out): the fastest %.2f m/s (its v, and its place over half a second and more, less its places' rounding; SHOT_V %.0f), the most one's v turned after it was fired %.6f rad, its flight off that line at most %.2f of its places' rounding, the muzzle's glow drawn at least %.3f s on end before each (SHOT_WARN %.1f), the pilot at least %.0f m from where each was fired (HOLD_FIRE %.0f)" % [
				fair_shots, forced.size(), fair_fastest, F.SHOT_V, fair_turned, fair_strayed, fair_glow_least, F.SHOT_WARN, fair_nearest, F.HOLD_FIRE],
			fair_shots >= 20 and fair_fastest <= F.SHOT_V + SPEED_MARGIN and fair_turned == 0.0 and fair_strayed <= 1.0 and fair_glow_least >= F.SHOT_WARN - 0.5 * STEP
				and fair_nearest >= F.HOLD_FIRE)
		_check("over every frame of this test (but those the test moved it on), the fastest the gunship flew %.2f m/s, on its %s (the town's limit %.2f)" % [gun_fastest, gun_fastest_in, Traffic.SF_V],
			gun_fastest > Traffic.SF_V * 0.9 and gun_fastest <= Traffic.SF_V + SPEED_MARGIN)
	_check("every section ran to its end (%d of %d)" % [sections, SECTIONS], sections == SECTIONS)
	v.queue_free()
	await process_frame
	Raids.pinned = false
	Raids.enabled = false
	Cockpit.vehicle_override = ""
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID GUNSHIP %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


# --- the stage ---------------------------------------------------------------------------------------------------

func _cockpit():
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	return v


## The gunship and where it is (for its speed frame to frame: in full, not a 32-bit Vector3), or [].
static func _gun_at(v) -> Array:
	var R = v.raids
	if R == null or R.flyers == null or R.flyers.gunship() == null:
		return []
	var g = R.flyers.gunship()
	return [g, g.x, g.y, g.z]


## After a frame: the shots' fairness (each new one: the glow's run before it, the pilot's distance from where it was
## fired; each one: its speed, and its way against its first), the glow's run, the gunship's speed.
func _watch(v, gun_was: Array) -> void:
	var R = v.raids
	if R == null or R.flyers == null:
		return
	var F = R.flyers
	var P = v.sim.pod
	for s in F.shots:
		var n: int = s.n
		var vel: Vector3 = s.v
		var p: Vector3 = s.p
		if forced.has(n):
			continue
		fair_fastest = maxf(fair_fastest, vel.length())
		if not seen.has(n):
			seen[n] = [vel, p, float(s.t)]
			if n > last_n:
				fair_shots += 1
				fair_glow_least = minf(fair_glow_least, glow_run * STEP)
				var from: Vector3 = p - vel * float(s.t)
				fair_nearest = minf(fair_nearest, from.distance_to(Vector3(P.x, P.y, P.z)))
				last_n = n
		else:
			# its v never changed; its place, from where it was first seen over half a second and more, on that v's line
			# and no faster, to within the rounding of the two places (32-bit, 100 km and more out: some cm)
			var first: Vector3 = seen[n][0]
			fair_turned = maxf(fair_turned, 0.0 if vel == first else first.angle_to(vel))
			var dt: float = float(s.t) - float(seen[n][2])
			if dt >= 0.5:
				var flown: Vector3 = p - (seen[n][1] as Vector3)
				var u := first.normalized()
				var tol := 2.0 * sqrt(3.0) * _ulp(maxf(maxf(absf(p.x), absf(p.y)), absf(p.z)))
				fair_fastest = maxf(fair_fastest, (flown.length() - tol) / dt)
				fair_strayed = maxf(fair_strayed, (flown - u * flown.dot(u)).length() / tol)
	var lit: bool = F._glow != null and F._glow.multimesh.visible_instance_count > F.shots.size()
	glow_run = glow_run + 1 if lit else 0
	var g = F.gunship()
	if track and g != null and not gun_was.is_empty() and gun_was[0] == g:
		var dx: float = g.x - float(gun_was[1])
		var dy: float = g.y - float(gun_was[2])
		var dz: float = g.z - float(gun_was[3])
		var flew := sqrt(dx * dx + dy * dy + dz * dz) / STEP
		if flew > gun_fastest:
			gun_fastest = flew
			gun_fastest_in = g.state


## The spacing of 32-bit floats about x (> 0): a Vector3's place there is good to half of it, a component.
static func _ulp(x: float) -> float:
	return pow(2.0, floorf(log(maxf(x, 1.0)) / log(2.0)) - 23.0)


## One frame: the craft held still (or at `speed` along its road), the view stepped, a frame let pass.
func _frame(v, speed := 0.0) -> void:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in sim.bodies:
		b.vx = R.tx[i] * speed
		b.vy = R.ty[i] * speed
		b.vz = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	var gun_was := _gun_at(v)
	var t0 := Time.get_ticks_usec()
	v._process(STEP)
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_watch(v, gun_was)
	await process_frame


func _fly(v, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / STEP)):
		await _frame(v)


## One frame of the director alone: the craft's bodies where the test put them (the sim not stepped), no commuters (or,
## `keep_cars`, traffic's cars held where they are: commuters about, and a pack that stays put).
func _alone(v, keep_cars := false) -> void:
	if not keep_cars:
		v.traffic_net.cars.clear()
	var gun_was := _gun_at(v)
	v.raids.update(STEP)
	_watch(v, gun_was)


## The gunship's flight fields, to hold it where it is (_put_back) while its gun goes on as it would.
static func _keep(g) -> Array:
	return [g.state, g.dive_t, g.f, g.x, g.y, g.z, g.vx, g.vy, g.vz, g.v, g.hx, g.hy, g.face]


static func _put_back(F, g, kept: Array) -> void:
	g.state = kept[0]
	g.dive_t = kept[1]
	g.f = kept[2]
	g.x = kept[3]
	g.y = kept[4]
	g.z = kept[5]
	g.vx = kept[6]
	g.vy = kept[7]
	g.vz = kept[8]
	g.v = kept[9]
	g.hx = kept[10]
	g.hy = kept[11]
	g.face = kept[12]
	F._pose_ship(g)


## The raid's city: the first ground city that is not the start's.
func _city(v) -> int:
	var sim = v.sim
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## The craft still in the middle of city k's town zone, on its road; `settle` frames flown (traffic fills in).
func _in_zone(v, k: int, settle := 0) -> void:
	var zone: Dictionary = v.raids._zone(k)
	v.sim.respawn_on(int(zone.road), (int(zone.z.x) + int(zone.z.y)) / 2, 1)
	for i in settle:
		await _frame(v)


## The craft still `m` m short of city k's town zone on its road; `settle` frames flown.
func _off_zone(v, k: int, m: float, settle := 0) -> void:
	var zone: Dictionary = v.raids._zone(k)
	var Rd = v.sim.roads[int(zone.road)]
	v.sim.respawn_on(int(zone.road), clampi(int(zone.z.x) - roundi(m / float(Rd.len[int(zone.z.x)])), 2, Rd.N - 3), 1)
	for i in settle:
		await _frame(v)


## A raid called on city k and arrived (the director's own arrival puts the pack, the drones and the gunship down): the
## next frame. `gunship` true or false: this raid has it or not; null: the director's own cadence (gunship_from 3, every 2).
func _raid_on(v, k: int, gunship = null) -> void:
	var R = v.raids
	R.reset()
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	if gunship == null:
		R.gunship_from = 3
		R.gunship_every = 2
	else:
		R.gunship_from = 1 if gunship else 1 << 30
		R.gunship_every = 1
	R._alarm()
	R.city = k                   # (whichever it picked: this one)
	await _frame(v)


## (x, y, z) against city k's town zone: [m outside it (0 within), m above the road at the zone's sample nearest it, that
## sample].
static func _against_zone(v, x: float, y: float, z: float, k: int) -> Array:
	var sim = v.sim
	var zone: Dictionary = v.raids._zone(k)
	var road: int = zone.road
	var zz: Vector2i = zone.z
	var Rd = sim.roads[road]
	var near := zz.x
	var nd := INF
	for i in range(zz.x, zz.y + 1):
		var d := Vector2(Rd.px[i] - x, Rd.py[i] - y).length_squared()
		if d < nd:
			nd = d
			near = i
	return [sqrt(nd), z - sim.net_height(road, float(near)), near]


## Degrees gunship g is off the bore of a craft following `back` m behind it on the road: behind the zone road's sample
## i nearest it by its way along the road there, in the road's middle, its eye its ride height over the deck, its bore
## along the road there, with the road's climb.
static func _off_bore(v, g, road: int, i: int, back: float) -> float:
	var sim = v.sim
	var Rd = sim.roads[road]
	var way := 1 if g.vx * Rd.tx[i] + g.vy * Rd.ty[i] >= 0.0 else -1
	var j := clampi(i - way * roundi(back / float(Rd.len[i])), 1, Rd.N - 2)
	var deck: float = sim.net_height(road, float(j))
	var eye := Vector3(Rd.px[j], Rd.py[j], deck + float(sim.P.rideH))
	var bore := Vector3(Rd.tx[j] * way * Rd.len[j], Rd.ty[j] * way * Rd.len[j], sim.net_height(road, float(j + way)) - deck).normalized()
	return rad_to_deg(bore.angle_to(Vector3(g.x, g.y, g.z) - eye))


## The craft's three bodies moved together so the pod stands at (x, y), `dz` m over the deck height `deck` (plus its
## ride height), still.
static func _put_bodies(sim, x: float, y: float, deck: float, dz: float) -> void:
	var ox: float = x - sim.pod.x
	var oy: float = y - sim.pod.y
	for b in sim.bodies:
		b.x += ox
		b.y += oy
		b.z = deck + sim.P.rideH + dz
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0


## The craft's three bodies on by vel x dt, going vel.
static func _move_bodies(sim, vel: Vector3, dt: float) -> void:
	for b in sim.bodies:
		b.vx = vel.x
		b.vy = vel.y
		b.vz = vel.z
		b.x += vel.x * dt
		b.y += vel.y * dt
		b.z += vel.z * dt


## The dodger's way across (+1 or -1 along `across`): of the craft 30 m one way or the other, the one whose bodies would
## be farther from the lines of the shots in flight (each from where it is on, to its life's end); alike, back toward the
## middle (`mid`, on the road's middle line).
static func _dodge_side(sim, F, across: Vector3, mid: Vector3) -> float:
	var best := -INF
	var side := 1.0
	for way: float in [1.0, -1.0]:
		var clear := INF
		for b in sim.bodies:
			var q: Vector3 = Vector3(b.x, b.y, b.z) + across * way * 30.0
			for s in F.shots:
				var p: Vector3 = s.p
				var vel: Vector3 = s.v
				var t := clampf((q - p).dot(vel) / vel.length_squared(), 0.0, F.SHOT_LIFE - float(s.t))
				clear = minf(clear, (p + vel * t).distance_to(q))
		var inward: float = -(Vector3(sim.pod.x, sim.pod.y, 0.0) - mid).dot(across) * way      # (+: toward the middle)
		var score := minf(clear, 60.0) + (0.01 if inward > 0.0 else 0.0)
		if score > best:
			best = score
			side = way
	return side


## The gunship back on its station afresh: there, STATION_S to hold, and off its cool.
static func _fresh_station(g) -> void:
	g.state = "station"
	g.dive_t = 0.0
	g.cool = 0.0
	g.warn = -1.0
	g.hidden = 0.0
	g.f = g.f0
	g.x = g.ax
	g.y = g.ay
	g.z = g.az


## Sample `f` of `road`: [x, y, deck].
static func _road_point(sim, road: int, f: float) -> Vector3:
	var Rd = sim.roads[road]
	var i := clampi(int(f), 0, Rd.N - 1)
	return Vector3(Rd.px[i], Rd.py[i], sim.net_height(road, float(i)))


# --- the checks --------------------------------------------------------------------------------------------------

func check_off_builds_nothing() -> void:
	Raids.pinned = true
	Raids.enabled = false
	var v = await _cockpit()
	for i in 60:
		await _frame(v, 800.0)
	var node = v.find_child("raid_flyers", true, false)
	var cached := ResourceLoader.has_cached(Art.GUNSHIP_PATH)
	sections += 1
	_check("Raids off: no director (%s), no flyers node (%s), after 60 frames the gunship's model not loaded (cached %s)" % [v.raids, node, cached],
		v.raids == null and node == null and not cached)
	v.queue_free()
	await process_frame


func check_cadence(v) -> void:
	var R = v.raids
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	await _in_zone(v, k, 240)
	var says := []
	for n in range(1, 6):
		says.append(R.has_gunship(n))
	R._count = 0
	var ships := []
	var loaded := []
	var frames := []
	var F = R.flyers
	for raid in 3:
		await _raid_on(v, k)            # (the director's own cadence)
		ships.append(F.count("gunship"))
		loaded.append(ResourceLoader.has_cached(Art.GUNSHIP_PATH))
		frames.append(snappedf(last_ms, 0.01))
	var g = F.gunship()
	var hp: int = g.hp if g != null else -1
	var r: float = g.r if g != null else -1.0
	sections += 1
	_check("has_gunship(1..5) %s (want false, false, true, false, true); the director's own arrivals, raids 1 to 3: gunships %s (want 0, 0, 1), its model loaded after each %s; its HP %d (GUNSHIP_HP %d), pick radius %.0f m (GUNSHIP_R %.0f); the arrivals' frames %s ms (the third loads its model)" % [
			says, ships, loaded, hp, F.GUNSHIP_HP, r, F.GUNSHIP_R, frames],
		says == [false, false, true, false, true] and ships == [0, 0, 1] and loaded == [false, false, true] and hp == F.GUNSHIP_HP and r == F.GUNSHIP_R
			and R._count == 3)


func check_station_and_strafe(v) -> void:
	var R = v.raids
	var sim = v.sim
	var W = v.network_world
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	await _off_zone(v, k, 5000.0)
	await _raid_on(v, k, true)
	var F = R.flyers
	var g = F.gunship()
	var road: int = R._zone(k).road
	var cone: float = v.gunnery.mount.assist_deg() if v.gunnery != null else -1.0
	var hi := -INF
	var lo := INF
	var out := 0.0
	var run := 0
	var best_run := 0
	var low := 0
	var roof_gap := INF
	var states := {}
	var worst_low := 0.0
	var least_low := INF
	var t := 0.0
	while t < 60.0 and g != null and F.gunship() == g:
		await _frame(v)
		t += STEP
		var at := _against_zone(v, g.x, g.y, g.z, k)
		out = maxf(out, at[0])
		hi = maxf(hi, at[1])
		lo = minf(lo, at[1])
		states[g.state] = int(states.get(g.state, 0)) + 1
		if W != null and W.roofed(road, float(at[2])) > 0.0:
			roof_gap = minf(roof_gap, absf(float(at[1]) - W.HALL_H))
		if at[1] < 30.0:
			low += 1
			var off := _off_bore(v, g, road, at[2], 800.0)
			worst_low = maxf(worst_low, off)
			least_low = minf(least_low, off)
			run = run + 1 if off <= cone else 0
			best_run = maxi(best_run, run)
		else:
			run = 0
	sections += 1
	_check("the gunship alone for %.1f s (frames in each state %s): seen from %.0f to %.0f m over the road (above 150 and below 30 wanted); %.1f s below 30 m, %.2f to %.2f degrees off the bore of a craft 800 m behind it on the road's middle, within %.1f (the Phaethon's assist cone) %.2f s on end at the most (want 5); over a hall the nearest it came to the roof's height %.0f m (want over 5); the farthest from the zone's road %.0f m (within %.0f)" % [
			t, states, lo, hi, low * STEP, least_low, worst_low, cone, best_run * STEP, roof_gap, out, KEEP_M],
		t >= 60.0 - STEP and hi > 150.0 and lo < 30.0 and cone > 0.0 and best_run * STEP >= 5.0 and roof_gap > 5.0 and out <= KEEP_M)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)


func check_shot_hits_pilot(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	var hits := []
	var on_hit := func(source: String): hits.append(source)
	R.hit_taken.connect(on_hit)
	# A: a straight line at 300 m/s toward its station, from 2.2 km short of it along the road
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	var F = R.flyers
	var g = F.gunship()
	var road: int = g.road
	var Rd = sim.roads[road]
	_fresh_station(g)
	var per: float = Rd.len[int(g.f0)]
	var i0 := roundi(g.f0 - g.way * 2200.0 / per)
	var start := _road_point(sim, road, float(i0))
	_put_bodies(sim, start.x, start.y, start.z, 0.0)
	var line := Vector3(Rd.tx[i0], Rd.ty[i0], 0.0).normalized() * float(g.way) * 300.0
	var shot_at := 0
	var made: int = F.shots_made
	var t := 0.0
	while t < 30.0 and hits.is_empty():
		_move_bodies(sim, line, STEP)
		_alone(v)
		t += STEP
		for s in F.shots:
			if s.n > made and s.pilot:
				shot_at += 1
		made = F.shots_made
	var a_hits := hits.duplicate()
	var a_t := t
	var a_shots := shot_at
	# B: held 1.2 km short of its station, 30 m across the road after each shot at it, over 0.5 s (to the side away from
	# the shots still in flight: a dodger does not step back into one: _dodge_side)
	hits.clear()
	await _raid_on(v, k, true)
	g = F.gunship()
	_fresh_station(g)
	var i1 := roundi(g.f0 - g.way * 1200.0 / per)
	var spot := _road_point(sim, road, float(i1))
	_put_bodies(sim, spot.x, spot.y, spot.z, 0.0)
	var across := Vector3(Rd.nx[i1], Rd.ny[i1], 0.0).normalized()
	var side := 1.0
	var moving := 0.0
	var dodged := 0
	var stations := 0
	var was_state: String = g.state
	made = F.shots_made
	t = 0.0
	while t < 60.0 and F.gunship() == g:
		var vel := Vector3.ZERO
		if moving > 0.0:
			vel = across * side * 60.0
			moving -= STEP
		_move_bodies(sim, vel, STEP)
		_alone(v)
		t += STEP
		if g.state == "station" and was_state != "station":
			stations += 1
		was_state = g.state
		for s in F.shots:
			if s.n > made and s.pilot:
				dodged += 1
				side = _dodge_side(sim, F, across, Vector3(spot.x, spot.y, 0.0))
				moving = 0.5
		made = F.shots_made
	R.hit_taken.disconnect(on_hit)
	sections += 1
	_check("a pilot holding a straight line at 300 m/s toward the gunship's station from 2.2 km: %d shots at it, hit %s after %.1f s (want \"gunship\" within 30); one held 1.2 km short of the station, 30 m across the road after each shot at it: %d shots at it in %.1f s (its station again %d times), hits %s (want none)" % [
			a_shots, a_hits, a_t, dodged, t, stations, hits],
		a_hits == ["gunship"] and a_t <= 30.0 and dodged >= 6 and hits.is_empty() and t >= 60.0 - STEP)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)


func check_shot_kills_commuter(v) -> void:
	var R = v.raids
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	await _off_zone(v, k, 5000.0, 240)
	await _raid_on(v, k, true)
	var F = R.flyers
	var said := []
	var on_lost := func(x: float, y: float): said.append(Vector2(x, y))
	R.commuter_lost.connect(on_lost)
	var lost0: int = R.lost
	var made0: int = F.shots_made
	var at_pilot := 0
	var made := made0
	var t := 0.0
	while t < 40.0 and R.lost == lost0:
		await _frame(v)
		t += STEP
		for s in F.shots:
			if s.n > made and s.pilot:
				at_pilot += 1
		made = F.shots_made
	R.commuter_lost.disconnect(on_lost)
	var P = v.sim.pod
	var gap: float = Vector2(F.gunship().x - P.x, F.gunship().y - P.y).length() if F.gunship() != null else -1.0
	sections += 1
	_check("the gunship alone, the pilot 5 km short of the zone (%.1f km from the gunship): raids.lost %d -> %d after %.1f s, %d shots fired (%d at the pilot), commuter_lost %d times" % [
			gap / 1000.0, lost0, R.lost, t, F.shots_made - made0, at_pilot, said.size()],
		R.lost > lost0 and said.size() >= 1 and at_pilot == 0 and pack_free(R))
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)


## No raider and no drone in this raid (so a loss is the gunship's).
static func pack_free(R) -> bool:
	return R.pack.is_empty() and R.flyers.count("drone") == 0


## `frames` frames, through the view (`alone` false) or of the director alone: {at: shots at the pilot, others: shots at
## commuters, hits, frames}; stops at the first shot at the pilot when `until_shot`.
func _gun_watch(v, frames: int, alone: bool, until_shot: bool) -> Dictionary:
	var R = v.raids
	var F = R.flyers
	var hits := [0]
	var on_hit := func(_s: String): hits[0] += 1
	R.hit_taken.connect(on_hit)
	var at := 0
	var others := 0
	var made: int = F.shots_made
	var n := 0
	while n < frames:
		if alone:
			_alone(v)
		else:
			await _frame(v)
		n += 1
		for s in F.shots:
			if s.n > made:
				if s.pilot:
					at += 1
				else:
					others += 1
		made = F.shots_made
		if until_shot and at > 0:
			break
	R.hit_taken.disconnect(on_hit)
	return {"at": at, "others": others, "hits": hits[0], "frames": n}


func check_cover(v) -> void:
	var R = v.raids
	var sim = v.sim
	var W = v.network_world
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	await _in_zone(v, k, 120)
	await _raid_on(v, k, true)
	track = false                     # (the test moves the craft about, and puts the gunship back on its station)
	var F = R.flyers
	var g = F.gunship()
	var road: int = g.road
	var Rd = sim.roads[road]
	var hall: Array = W.halls.get(road, []) if W != null else []
	if hall.is_empty() or g == null:
		sections += 1
		_check("a hall on the zone's road (%s) and the gunship (%s)" % [hall, g], false)
		track = true
		return
	# A: the hall, 6 samples in from the mouth nearest the station; then the open road as far from the station the other way
	var mouth: int = hall[0] if absf(g.f0 - float(hall[0])) < absf(g.f0 - float(hall[1])) else hall[1]
	var inward := 1 if mouth == int(hall[0]) else -1
	var in_hall := mouth + 6 * inward
	sim.respawn_on(road, in_hall, 1)
	var roofed: float = W.roofed(road, float(in_hall))
	_fresh_station(g)
	var hall_m := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var a: Dictionary = await _gun_watch(v, 480, false, false)
	var open_f := clampi(roundi(2.0 * g.f0) - in_hall, 2, Rd.N - 3)
	sim.respawn_on(road, open_f, 1)
	_fresh_station(g)
	var open_m := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var a_open: Dictionary = await _gun_watch(v, 360, false, true)
	# B: a deck built: the craft 30 m under the zone road's deck 1 km short of the station; then on the deck there
	var bf := roundi(g.f0 - g.way * 1000.0 / float(Rd.len[int(g.f0)]))
	var spot := _road_point(sim, road, float(bf))
	_put_bodies(sim, spot.x, spot.y, spot.z, -30.0)
	_fresh_station(g)
	var b: Dictionary = await _gun_watch(v, 480, true, false)
	_put_bodies(sim, spot.x, spot.y, spot.z, 0.0)
	_fresh_station(g)
	var b_open: Dictionary = await _gun_watch(v, 360, true, true)
	# C: a shot that reaches the craft under the deck (the gun's own _shoot, laid on the craft where it is: its _fire holds
	# a shot at a pilot under cover, so the test makes this one), and the same at it on the deck
	var ends := []
	for drop in [true, false]:
		_put_bodies(sim, spot.x, spot.y, spot.z, -30.0 if drop else 0.0)
		_fresh_station(g)
		F.shots.clear()                # (none but this one: B's last may still be on its way to the deck)
		g.cool = 1.0e9                 # (no other shot)
		R._grace = 0.0
		var hit := [0]
		var on_hit := func(_s: String): hit[0] += 1
		R.hit_taken.connect(on_hit)
		g.at_pod = true
		g.prey = null
		g.lead = Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
		forced[F.shots_made + 1] = true
		F._shoot(g)
		var n: int = F.shots_made
		var nearest := INF
		var flown := 0
		while flown < roundi(F.SHOT_LIFE / STEP) + 2 and F.shots.any(func(s): return s.n == n):
			for s in F.shots:
				if s.n == n:
					for body in sim.bodies:
						nearest = minf(nearest, (s.p as Vector3).distance_to(Vector3(body.x, body.y, body.z)))
			_alone(v)
			flown += 1
		R.hit_taken.disconnect(on_hit)
		ends.append([hit[0], snappedf(nearest, 0.1), n == forced.keys().max()])
	# D: a line through the hall's roof: the craft in the open 9 samples past the hall's far end, the gunship held on a
	# station 200 m over the hall 41 samples back from that end (its line down to the craft crosses the roof's height
	# inside the hall); then held over the open road as far the other side of the craft
	F.shots.clear()
	var out_f := int(hall[1]) + 9
	var past := _road_point(sim, road, float(out_f))
	_put_bodies(sim, past.x, past.y, past.z, 0.0)
	var over := _road_point(sim, road, float(int(hall[1]) - 41))
	g.ax = over.x
	g.ay = over.y
	g.az = over.z + F.STATION_ALT
	g.f0 = float(int(hall[1]) - 41)
	_fresh_station(g)
	var roof_m := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var hid := 0.0
	var d := {"at": 0, "hits": 0, "frames": 0}
	for i in 4:
		var part: Dictionary = await _gun_watch(v, 120, true, false)
		d.at += part.at
		d.hits += part.hits
		d.frames += part.frames
		hid = maxf(hid, g.hidden)
	var clear_side := _road_point(sim, road, float(out_f + 41))
	g.ax = clear_side.x
	g.ay = clear_side.y
	g.az = clear_side.z + F.STATION_ALT
	g.f0 = float(out_f + 41)
	_fresh_station(g)
	var d_open: Dictionary = await _gun_watch(v, 360, true, true)
	_put_bodies(sim, spot.x, spot.y, spot.z, 0.0)
	R.reset()
	track = true
	sections += 1
	var line_said := "a line through the hall's roof (the craft %d samples past its end, the gunship over the hall %.0f m from it): %d shots at the pilot, %d hits in %d frames, the pilot left alone up to %.1f s; over the open road the other side: a shot at it after %d frame(s)" % [
		out_f - int(hall[1]), roof_m, d.at, d.hits, d.frames, hid, d_open.frames]
	_check(line_said, roof_m < F.SHOT_REACH and d.at == 0 and d.hits == 0 and d.frames == 480 and hid > 0.0 and d_open.at == 1 and d_open.frames <= 360)
	var reach: float = F.SHOT_HIT + F.SHOT_V * STEP      # (its nearest seen: on its last frame before it went, within a frame's flight of it)
	_check("the hall (samples %d..%d, roofed %.2f where the craft is, %.0f m from the gunship on station): %d shots at the pilot, %d at commuters, %d hits in %d frames; on the open road beyond its station (%.0f m from it): a shot at it after %d frame(s); a deck built, the craft 30 m under it: %d shots at the pilot, %d hits in %d frames; on the deck: a shot at it after %d frame(s); the gun's own shot laid on the craft under the deck: %s hit(s), its nearest seen %s m from the craft (within %.1f: SHOT_HIT and a frame's flight); on the deck: %s hit(s), its nearest seen %s m" % [
			hall[0], hall[1], roofed, hall_m, a.at, a.others, a.hits, a.frames, open_m, a_open.frames, b.at, b.hits, b.frames, b_open.frames,
			ends[0][0], ends[0][1], reach, ends[1][0], ends[1][1]],
		roofed > 0.0 and hall_m < F.SHOT_REACH and a.at == 0 and a.hits == 0 and a.frames == 480 and open_m < F.SHOT_REACH and a_open.at == 1 and a_open.frames <= 360
			and b.at == 0 and b.hits == 0 and b.frames == 480 and b_open.at == 1 and b_open.frames <= 360
			and ends[0][0] == 0 and ends[0][1] <= reach and ends[0][2] and ends[1][0] == 1 and ends[1][1] <= reach and ends[1][2])
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)


func check_takes_punishment(v) -> void:
	var R = v.raids
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(0, 0)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	var F = R.flyers
	var gun = v.gunnery
	var gs = F.gunship()
	if gun == null or gs == null or R.pack.is_empty():
		sections += 1
		_check("a fire control (%s), the gunship (%s) and a raider (%d)" % [gun, gs, R.pack.size()], false)
		return
	var early := 0
	for i in 119:
		early += int(gun.damage(gs, 1, Vector3(gs.x, gs.y, gs.z)))
	var kept: bool = F.has(gs)
	var hp_left: int = gs.hp
	var by0: int = int(R.kills_by.gunship)
	var killed: bool = gun.damage(gs, 1, Vector3(gs.x, gs.y, gs.z))
	var big := _last_fireball(gun)
	var raider = R.pack[0]
	var raider_killed: bool = gun.damage(raider, gun.HOSTILE_HP, Vector3(raider.x, raider.y, 0.0))
	var small := _last_fireball(gun)
	await _frame(v)
	sections += 1
	_check("the gunship's HP %d: 119 hits leave it (%d killed it early; still up %s, hp %d); the 120th kills it (%s): gone from the module (%s), kills_by.gunship %d -> %d, its model hidden (%s); its burst's fireball %.0f m against a raider's %.0f (%s; want three times)" % [
			gs.hp_max, early, kept, hp_left, killed, not F.has(gs), by0, R.kills_by.gunship, not F.ship.visible, big, small, raider_killed],
		gs.hp_max == F.GUNSHIP_HP and early == 0 and kept and hp_left == 1 and killed and not F.has(gs) and F.gunship() == null and by0 == 0
			and int(R.kills_by.gunship) == 1 and not F.ship.visible and raider_killed and small > 0.0 and absf(big / small - 3.0) < 1.0e-6)
	R.drones = Vector2i(6, 10)


## The size of the fire control's last fireball (its burst), or -1.
static func _last_fireball(gun) -> float:
	for k in range(gun._fx.size() - 1, -1, -1):
		if gun._fx[k].kind == "fireball":
			return float(gun._fx[k].size)
	return -1.0


func check_cleared_and_away(v) -> void:
	var R = v.raids
	var sim = v.sim
	var T = v.traffic_net
	var k := _city(v)
	# cleared: raiders and drones killed, the gunship left; then it
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	var F = R.flyers
	var gun = v.gunnery
	var raiders: Array = R.pack.duplicate()
	for c in raiders:
		R.on_kill(c)
		T.knock_out(c)
	var drones := 0
	for f in F.all().duplicate():
		if f.kind == "drone":
			drones += int(gun.damage(f, f.hp, Vector3(f.x, f.y, f.z)))
	await _frame(v)
	var still: bool = R.state == "on" and R.result == "" and R.pack.is_empty() and F.count("drone") == 0 and F.gunship() != null
	var line: String = R.text()
	var cleared0: int = int(R.tally.cleared)
	var gs = F.gunship()
	var last: bool = gs != null and gun.damage(gs, gs.hp, Vector3(gs.x, gs.y, gs.z))
	await _frame(v)
	var cleared: bool = R.result == "cleared" and int(R.tally.cleared) == cleared0 + 1 and F.all().is_empty() and F.shots.is_empty() \
		and int(R.kills_by.raider) == raiders.size() and int(R.kills_by.drone) == drones and int(R.kills_by.gunship) == 1
	var cleared_said := "every raider (%d) and drone (%d) killed, the gunship left: still on (%s), the dash \"%s\"; the gunship shot down (%s): \"%s\" (tally cleared %d -> %d), kills %s, none left (%d flyers, %d shots)" % [
		raiders.size(), drones, still, line, last, R.result, cleared0, R.tally.cleared, R.kills_by, F.all().size(), F.shots.size()]
	# away: the pilot far from the town, the gunship brought within R_KEEP of it (drones left in the zone: with the gunship
	# gone the raid is still on, and away)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(6, 10)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	R.away_t = 3.0
	track = false
	var e3 := [-1, -1]
	for r in sim.roads.size():
		if sim.roads[r].name == "E3":
			e3 = [r, 9000 / 24]
	sim.respawn_on(e3[0], e3[1], 1)
	var g = F.gunship()
	g.ax = sim.pod.x + 300.0
	g.ay = sim.pod.y
	g.az = sim.pod.z + 200.0
	_fresh_station(g)
	g.cool = 1.0e9                     # (it holds its fire: no jolts)
	for f in F.all():
		f.rest = 1.0e9                 # (the drones circle in the zone)
	var left_drones: int = F.count("drone")
	var far_km: float = R._gap(k) / 1000.0
	var t := 0.0
	var worst := 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
		worst = maxf(worst, R._away)
	var stayed: bool = R.state == "on"
	var near := Vector2(g.x - sim.pod.x, g.y - sim.pod.y).length()
	F.destroy(g)
	t = 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
	track = true
	sections += 1
	_check("%s; the pilot %.0f km from the zone (beyond R_KEEP %.0f) with the gunship %.0f m off for 4 s (%d drones in the zone): still on (%s), its away clock at most %.2f s; the gunship gone, %.2f s later: \"%s\" (%s; away_t %.1f)" % [
			cleared_said, far_km, Traffic.R_KEEP / 1000.0, near, left_drones, stayed, worst, t, R.result, R._why, R.away_t],
		raiders.size() > 0 and drones > 0 and still and line.contains("GUNSHIP") and not line.contains("0 RAIDERS") and not line.contains("0 DRONES") and last and cleared
			and far_km * 1000.0 > Traffic.R_KEEP and near < Traffic.R_KEEP and left_drones > 0 and stayed and worst == 0.0 and R.result == "lost" and R._why == "away"
			and t <= R.away_t + 0.25)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)


func check_reset_clears_flyers_and_shots(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	var F = R.flyers
	var g = F.gunship()
	var Rd = v.sim.roads[g.road]
	v.sim.respawn_on(g.road, roundi(g.f0 - g.way * 1200.0 / float(Rd.len[int(g.f0)])), 1)      # (in its reach: it fires on the pilot)
	_fresh_station(g)
	var t := 0.0
	while t < 10.0 and F.shots.size() < 2:
		await _frame(v)
		t += STEP
	var hits := []
	var on_hit := func(source: String): hits.append(source)
	R.hit_taken.connect(on_hit)
	var up := [F.count("drone"), F.count("gunship"), F.shots.size()]
	R.reset()
	var after := [F.all().size(), F.shots.size(), F.batch.multimesh.visible_instance_count, F._glow.multimesh.visible_instance_count, F.ship.visible]
	for i in 120:
		await _frame(v)
	R.hit_taken.disconnect(on_hit)
	sections += 1
	_check("drones, gunship and shots up %s (after %.1f s): a restart (reset) leaves, the same frame, %s flyers, %s shots, %s drones drawn, %s glows drawn, the model shown %s; 120 frames on: hits %s, traffic's floor \"%s\"" % [
			up, t, after[0], after[1], after[2], after[3], after[4], hits, T.race_state],
		up[0] > 0 and up[1] == 1 and up[2] >= 2 and after == [0, 0, 0, 0, false] and hits.is_empty() and T.race_state == "")


func check_cost(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	var said := []
	var means := []
	for drones in [0, 10]:
		R.pack_size = Vector2i(0, 0)
		R.drones = Vector2i(drones, drones)
		await _in_zone(v, k, 0)
		await _raid_on(v, k, true)
		var F = R.flyers
		var g = F.gunship()
		# the pilot 1.2 km short of its station on the open road: it fires on the pilot and, now and then, on commuters
		var Rd = sim.roads[g.road]
		sim.respawn_on(g.road, roundi(g.f0 - g.way * 1200.0 / float(Rd.len[int(g.f0)])), 1)
		for j in F.all().size():
			F.all()[j].rest = 0.2 * j      # (the drones off their first rest within 2 s)
		var ms := []
		var made: int = F.shots_made
		var shot_frames := []      # (the frames a shot was fired in: its line looked along for cover, at the pilot)
		for i in 600:
			var before: int = F.shots_made
			await _frame(v)
			ms.append(float(F.update_ms))
			if F.shots_made > before:
				shot_frames.append(snappedf(float(F.update_ms), 0.001))
		var mean := 0.0
		var worst := 0.0
		for x in ms:
			mean += x
			worst = maxf(worst, x)
		mean /= maxf(1.0, ms.size())
		var others := 0.0
		for i in ms.size():
			if not shot_frames.has(snappedf(ms[i], 0.001)):
				others = maxf(others, ms[i])
		means.append(mean)
		said.append("%d drones and the gunship (%s): %.4f ms a frame mean, the worst %.3f ms; the %d frames a shot was fired in %s ms, the worst of the rest %.3f ms" % [
			F.count("drone"), g.state, mean, worst, F.shots_made - made, shot_frames, others])
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)
	sections += 1
	_check("600 frames each, the module's update: %s (the gunship alone under %.2f, with ten drones under %.2f)" % ["; ".join(said), COST_MS, FLEET_MS],
		means.size() == 2 and means[0] < COST_MS and means[1] < FLEET_MS)


## `frames` frames of the director alone with commuters about (traffic held where it is), the craft put each frame by
## `place` (a Callable), the gunship held as `kept` says (_keep) while its gun goes on: {glows: glows begun, shots: shots
## made, drawn: frames its glow was drawn}.
func _hold_watch(v, frames: int, place: Callable, kept: Array) -> Dictionary:
	var F = v.raids.flyers
	var g = F.gunship()
	var glows := 0
	var drawn := 0
	var made0: int = F.shots_made
	for n in frames:
		place.call()
		var was: float = g.warn
		_alone(v, true)
		_put_back(F, g, kept)
		if g.warn >= 0.0 and was < 0.0:
			glows += 1
		if F._glow.multimesh.visible_instance_count > F.shots.size():
			drawn += 1
	return {"glows": glows, "shots": F.shots_made - made0, "drawn": drawn}


## Commuters about sample `at` of `road` (made here, as test_raid_flyers' check_speed_cap makes one): one 30 and one 60
## samples either side, each coming toward it at 200 m/s. -> them (the caller takes them out of traffic after).
static func _commuters_about(T, road: int, at: float) -> Array:
	var made := []
	for j in 4:
		var c = T.Car.new()
		c.id = 951000 + j
		c.kind = T.CAR
		c.road = road
		c.dir = 1 if j % 2 == 0 else -1
		c.f = at - float(c.dir) * (30.0 if j < 2 else 60.0)
		c.lane = 1
		c.lat = T._lane_lat(c, 1)
		c.turn_p = 0.0
		c.nsp_road = -1
		c.v = 200.0
		c.vdes = 200.0
		c.cruise = 200.0
		T._place(c)
		T.cars.append(c)
		made.append(c)
	return made


func check_hold_fire(v) -> void:
	var R = v.raids
	var sim = v.sim
	var T = v.traffic_net
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	track = false                    # (the test holds the gunship where it is)
	var F = R.flyers
	var g = F.gunship()
	var Rd = sim.roads[g.road]
	var about := _commuters_about(T, g.road, g.f0 - float(g.way) * 20.0)      # (what it would fire on: held where they are from here on)
	var zx: int = R._zone(k).z.x
	var far := _road_point(sim, g.road, float(clampi(zx - roundi(5000.0 / float(Rd.len[zx])), 2, Rd.N - 3)))
	var away := func(): _put_bodies(sim, far.x, far.y, far.z, 0.0)      # (the craft 5 km short of the zone: the control)
	# A: on its run in the open (on its run's line across the road), 40 samples short of its station; the craft 120 m
	# behind it on the road, going its way
	var sf: float = g.f0 - float(g.way) * 40.0
	g.state = "strafe"
	g.dive_t = 1.0
	F._place(g, sf, F.STRAFE_ALT, 1.0)
	var i := clampi(int(sf), 0, Rd.N - 1)
	F._moving(g, Rd.tx[i] * g.way * Traffic.SF_V, Rd.ty[i] * g.way * Traffic.SF_V, 0.0)
	g.face = atan2(-g.hx, g.hy)
	g.cool = 0.0
	g.warn = -1.0
	var kept_a := _keep(g)
	var deck: float = sim.net_height(g.road, sf)
	var back := sqrt(120.0 * 120.0 - pow(F.STRAFE_ALT - float(sim.P.rideH), 2.0))
	var behind := func():
		_put_bodies(sim, g.x - g.hx * back, g.y - g.hy * back, deck, 0.0)
		for b in sim.bodies:
			b.vx = g.vx
			b.vy = g.vy
	behind.call()
	var gap_a := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var held_a := _hold_watch(v, 480, behind, kept_a)
	g.cool = 0.0
	var a_ctrl := _hold_watch(v, 360, away, kept_a)
	# B: on station, the craft in the air 120 m under it
	_fresh_station(g)
	var kept_b := _keep(g)
	var under := func(): _put_bodies(sim, g.x, g.y, g.z - 120.0 - float(sim.P.rideH), 0.0)
	under.call()
	var gap_b := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var held_b := _hold_watch(v, 480, under, kept_b)
	g.cool = 0.0
	var b_ctrl := _hold_watch(v, 360, away, kept_b)
	# C: a glow at the craft begun 170 m under it, the craft come up to 140 m 0.2 s into it
	F.shots.clear()
	_fresh_station(g)
	var kept_c := _keep(g)
	var depth := [170.0]
	var hang := func(): _put_bodies(sim, g.x, g.y, g.z - float(depth[0]) - float(sim.P.rideH), 0.0)
	var n := 0
	while n < 240 and not (g.warn >= 0.2 and g.at_pod):
		hang.call()
		_alone(v, true)
		_put_back(F, g, kept_c)
		n += 1
	var glowed: bool = g.warn >= 0.2 and g.at_pod
	var made0: int = F.shots_made
	depth[0] = 140.0
	hang.call()
	_alone(v, true)
	_put_back(F, g, kept_c)
	var gap_c := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var out_at_once: bool = g.warn < 0.0 and F._glow.multimesh.visible_instance_count == F.shots.size()
	var held_c := _hold_watch(v, 120, hang, kept_c)
	var c_shots: int = F.shots_made - made0
	for c in about:
		T.cars.erase(c)
	R.reset()
	track = true
	sections += 1
	_check("ruling C: the craft %.0f m from the gunship held on its run in the open, commuters about: %d glows begun, %d shots, %d frames drawn in 4 s (the craft 5 km off instead: %d glows, %d shots in 3 s); %.0f m under it on station: %d glows, %d shots, %d frames drawn in 4 s (5 km off: %d glows, %d shots); a glow at the craft begun %s 170 m off, the craft come to %.0f m 0.2 s in: the glow out that frame %s, and in the second after %d shots, %d glows begun, %d frames drawn" % [
			gap_a, held_a.glows, held_a.shots, held_a.drawn, a_ctrl.glows, a_ctrl.shots, gap_b, held_b.glows, held_b.shots, held_b.drawn, b_ctrl.glows, b_ctrl.shots,
			"(seen)" if glowed else "(NOT seen)", gap_c, out_at_once, c_shots, held_c.glows, held_c.drawn],
		gap_a < F.HOLD_FIRE and held_a.glows == 0 and held_a.shots == 0 and held_a.drawn == 0 and a_ctrl.glows > 0
			and gap_b < F.HOLD_FIRE and held_b.glows == 0 and held_b.shots == 0 and held_b.drawn == 0 and b_ctrl.glows > 0
			and glowed and gap_c < F.HOLD_FIRE and out_at_once and c_shots == 0 and held_c.glows == 0 and held_c.drawn == 0)


func check_crash_ends_shots(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	await _in_zone(v, k, 0)
	await _raid_on(v, k, true)
	track = false
	var F = R.flyers
	var g = F.gunship()
	var Rd = sim.roads[g.road]
	var spot := _road_point(sim, g.road, float(roundi(g.f0 - g.way * 1000.0 / float(Rd.len[int(g.f0)]))))
	_put_bodies(sim, spot.x, spot.y, spot.z, 0.0)
	_fresh_station(g)
	g.cool = 1.0e9                    # (no shot but the test's)
	F.shots.clear()
	var crash0: float = sim.crash_t
	sim.crash_t = 30.0                # (the craft down; the sim, not stepped here, would count it out)
	R._grace = 0.0
	var hit := [0]
	var on_hit := func(_s: String): hit[0] += 1
	R.hit_taken.connect(on_hit)
	g.at_pod = true
	g.prey = null
	g.lead = Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
	forced[F.shots_made + 1] = true
	F._shoot(g)
	var n: int = F.shots_made
	var nearest := INF
	var last := INF
	var flown := 0
	while flown < roundi(F.SHOT_LIFE / STEP) + 2 and F.shots.any(func(s): return s.n == n):
		for s in F.shots:
			if s.n == n:
				last = INF
				for body in sim.bodies:
					last = minf(last, (s.p as Vector3).distance_to(Vector3(body.x, body.y, body.z)))
				nearest = minf(nearest, last)
		_alone(v)
		flown += 1
	R.hit_taken.disconnect(on_hit)
	sim.crash_t = crash0
	R._wrecked = false                # (no respawn to set the raid aside for: the test put the crash there)
	R.reset()
	track = true
	var reach: float = F.SHOT_HIT + F.SHOT_V * STEP
	sections += 1
	_check("a shot laid on the craft while it is down (crash_t): gone after %.2f s of %.0f, its nearest seen %.1f m from the craft and %.1f m the frame before it went (it ends at SHOT_HIT %.0f: within %.1f, never through it), hits %d" % [
			flown * STEP, F.SHOT_LIFE, nearest, last, F.SHOT_HIT, reach, hit[0]],
		flown < roundi(F.SHOT_LIFE / STEP) and nearest >= F.SHOT_HIT - 0.5 and last <= reach and hit[0] == 0)


func check_transit_keeps_to_road(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	R.pack_size = Vector2i(6, 6)
	R.drones = Vector2i(0, 0)
	await _off_zone(v, k, 5000.0, 120)      # (traffic about, held from here on; the craft out of its reach)
	await _raid_on(v, k, true)
	var F = R.flyers
	var g = F.gunship()
	var zone: Dictionary = R._zone(k)
	var Rd = sim.roads[int(zone.road)]
	var pack_way := 0
	for c in R.pack:
		pack_way += int(c.dir)
	var pack_n: int = R.pack.size()
	var ways := [g.way]
	var over := -INF              # m: the farthest it was from the road's middle, past the road's half width there
	var widest := 0.0             # ... and from its middle, m
	var widest_transit := 0.0
	var low_transit := INF        # m: its least height over the road in its flight between stations
	var transit_m := 0.0
	var harshest := 0.0           # m/s/s: the most its speed changed, in that flight (its start and its end too)
	var last_speed := -1.0
	var states := {}
	var t := 0.0
	var arrived := false
	while t < 75.0 and F.gunship() == g and not arrived:
		var was: String = g.state
		var x0: float = g.x
		var y0: float = g.y
		var z0: float = g.z
		_alone(v, true)
		t += STEP
		states[g.state] = int(states.get(g.state, 0)) + 1
		var dx: float = g.x - x0
		var dy: float = g.y - y0
		var dz: float = g.z - z0
		var step := sqrt(dx * dx + dy * dy + dz * dz)
		var at := _against_zone(v, g.x, g.y, g.z, k)
		var i: int = at[2]
		var lat := absf((g.x - Rd.px[i]) * Rd.nx[i] + (g.y - Rd.py[i]) * Rd.ny[i])
		widest = maxf(widest, lat)
		over = maxf(over, lat - float(Rd.w[i]) * 0.5)
		if was == "climb" and g.state == "transit":
			ways.append(g.way)
		if was == "transit" or g.state == "transit":
			transit_m += step
			widest_transit = maxf(widest_transit, lat)
			low_transit = minf(low_transit, float(at[1]))
			var speed := step / STEP
			if last_speed >= 0.0:
				harshest = maxf(harshest, absf(speed - last_speed) / STEP)
			last_speed = speed
		arrived = was == "transit" and g.state == "station"
	var ramp: float = Traffic.SF_V / F.UP_S
	R.reset()
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(6, 10)
	sections += 1
	_check("a pack of %d going way %d, the gunship's runs %s; in %.1f s (frames in each state %s) it flew %.1f km between stations %s, at least %.0f m over the road, its speed changing at most %.0f m/s/s (its run's ends: %.0f); the farthest from the road's middle %.0f m (in that flight %.0f), past the road's half width by %.1f m at the most (want 10 at most)" % [
			pack_n, signi(pack_way), ways, t, states, transit_m / 1000.0, "and arrived" if arrived else "and NOT arrived", low_transit, harshest, ramp,
			widest, widest_transit, over],
		pack_n == 6 and pack_way > 0 and ways.size() == 2 and ways[0] == ways[1] and ways[0] == signi(pack_way) and arrived and transit_m > 4000.0
			and low_transit >= F.STATION_ALT - 5.0 and harshest <= ramp * 1.05 and over <= 10.0)
