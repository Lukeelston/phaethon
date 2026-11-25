## Raiders on the scene of a raid (view/network_raids.gd; the final review's I1 and I2): they keep to the raid's
## town zone, and they run commuters down at the Network's speeds. A cockpit on the Network, Raids pinned on, the
## raid's city the first ground city that is not the start's, its pack put down by the director's own arrival:
##   bounce      the pilot still in the middle of the zone, off the roads' one-way rule (the city's road is not the
##               pilot's): 120 s with live commuters; every raider stays on the zone's road within the zone +-1 km,
##               turning round short of its ends; the raid still on, never "away"
##   hold        the pilot on the city's road, its way the road's (traffic's one-way rule): 60 s; no raider is ever
##               turned against the pilot's way; each stays within the zone +-1 km (held at its far end)
##   away        the safety net: the pilot beyond R_KEEP of the zone but beside a raider is not away; with that one
##               gone, the clock runs and the raid is lost ("away")
## Run with --fixed-fps 120 (traffic and the director run on the engine's frame time; a frame is let pass for every
## step). Prints RAID HUNT PASS.
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const MPH := 2.236936
const KEEP_M := 1000.0           # m: a raider stays within the zone by this
var failures := 0
var sections := 0                # (a section that dies on a script error never counts itself: the verdict then fails)
var _ids := 0


func _initialize() -> void:
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.spot_override = "E3@9000"
	Cockpit.best_dir = OS.get_user_data_dir().path_join("test_raid_hunt_")
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
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


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
	v._process(STEP)
	await process_frame


## The raid's city: the first ground city that is not the start's.
func _city(v) -> int:
	var sim = v.sim
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## A raid called on city k and arrived (the director's own arrival puts the pack down): the next frame.
func _raid_on(v, k: int) -> void:
	var R = v.raids
	R.reset()
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R._alarm()
	R.city = k                   # (whichever it picked: this one)
	await _frame(v)


## How far raider c is outside city k's town zone, m along its road (0 inside); INF off the zone's road.
func _outside(R, c, k: int) -> float:
	var zone: Dictionary = R._zone(k)
	if c.road != int(zone.road):
		return INF
	var z: Vector2i = zone.z
	return maxf(maxf(float(z.x) - c.f, c.f - float(z.y)), 0.0) * 24.0


## A car of the test's on `road` at sample f going dir, in `lane`, at v m/s: a raider (as the director makes them) or a
## commuter. Held in traffic's cars.
func _car(T, road: int, f: float, dir: int, lane: int, v: float, raider: bool):
	var c = T.Car.new()
	_ids += 1
	c.id = (960700 if raider else 950700) + _ids
	c.road = road
	c.dir = dir
	c.f = f
	c.v = v
	c.vdes = v
	c.turn_p = 0.0
	c.nsp_road = -1
	c.lane = lane
	c.lat = T._lane_lat(c, lane)
	if raider:
		c.kind = T.DEMON
		c.visual = T.DEMON
		c.hostile = true
		c.name = "RAIDER"
		c.a_up = 3.0 * T.G
		c.a_lat = 11.0 * T.G
		c.headway = 0.45
		c.col = T.HOSTILE_COL
	else:
		c.kind = T.CAR
		c.a_up = 1.5 * T.G
		c.a_lat = 9.0 * T.G
		c.headway = 1.2
	T._place(c)
	T.cars.append(c)
	return c


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var R = v.raids
	if R == null:
		_check("raids pinned on: the cockpit has a director", false)
	else:
		v.traffic_net._hw_time = -1.0e9      # (no street racer drops in: it would hold traffic's floor)
		await _bounce(v)
		await _hold_far_end(v)
		await _away_net(v)
	_check("every section ran to its end (%d of 3)" % sections, sections == 3)
	v.queue_free()
	await process_frame
	Raids.pinned = false
	Raids.enabled = false
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID HUNT %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


## The pilot still in the middle of the zone, the city's road not its own: the pack turns round short of the zone's ends.
func _bounce(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	var k := _city(v)
	var zone: Dictionary = R._zone(k)
	var road: int = zone.road
	var z: Vector2i = zone.z
	sim.respawn_on(road, (z.x + z.y) / 2, 1)
	for i in 240:                 # (traffic fills in round the craft)
		await _frame(v)
	var free_way: bool = not T.oneway.has(road)
	await _raid_on(v, k)
	var pack: Array = R.pack.duplicate()
	var worst := 0.0
	var turned := {}
	var dirs := {}
	for c in pack:
		dirs[c] = c.dir
	var commuters := 0
	var t := 0.0
	while t < 120.0 and R.state == "on":
		await _frame(v)
		t += STEP
		for c in pack:
			if not T.cars.has(c):
				continue
			worst = maxf(worst, _outside(R, c, k))
			if c.dir != dirs[c]:
				dirs[c] = c.dir
				turned[c] = int(turned.get(c, 0)) + 1
		if int(t / STEP) % 1200 == 0:
			var near := 0
			for c in T.cars:
				if not c.hostile and c.road == road:
					near += 1
			commuters = maxi(commuters, near)
	var kept := 0
	for c in pack:
		kept += int(T.cars.has(c))
	sections += 1
	_check("bounce: the pilot still in %s's zone (%.1f km of road, samples %d..%d; the road not one-way: %s), %d raiders over %.0f s with up to %d commuters on its road: the farthest out of the zone %.0f m (want within %.0f), turned round %d times in all by %d of them, the raid %s, %d still in traffic, %d lost" % [
			sim.cities[k].name, (z.y - z.x) * 0.024, z.x, z.y, free_way, pack.size(), t, commuters, worst, KEEP_M, _sum(turned), turned.size(), R.state, kept, R.lost],
		free_way and pack.size() >= 4 and t >= 120.0 - STEP and R.state == "on" and worst <= KEEP_M and turned.size() >= 1 and kept == pack.size())
	R.reset()


## The pilot on the city's road going its way (traffic's one-way rule there): no raider is turned against it.
func _hold_far_end(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	var k := _city(v)
	var zone: Dictionary = R._zone(k)
	var road: int = zone.road
	var z: Vector2i = zone.z
	sim.respawn_on(road, z.x + 60, 1)
	for i in 30:                  # (moving: the road is the pilot's, its way the road's)
		await _frame(v, 600.0)
	for i in 120:
		await _frame(v)
	var way: int = int(T.oneway.get(road, 0))
	await _raid_on(v, k)
	var pack: Array = R.pack.duplicate()
	var worst := 0.0
	var against := 0
	var t := 0.0
	while t < 60.0 and R.state == "on":
		await _frame(v)
		t += STEP
		for c in pack:
			if not T.cars.has(c):
				continue
			worst = maxf(worst, _outside(R, c, k))
			if c.road == road and c.dir != way:
				against += 1
	var far := 0
	for c in pack:
		if T.cars.has(c) and c.road == road and (c.f - float(z.y)) * way > -KEEP_M / 24.0 - 2.0:
			far += 1
	sections += 1
	_check("hold: the pilot on %s's road going its way (one-way %+d), %d raiders over %.0f s: none ever turned against it (%d raider-frames against), the farthest out of the zone %.0f m (want within %.0f), %d held at its far end; the raid %s" % [
			sim.cities[k].name, way, pack.size(), t, against, worst, KEEP_M, far, R.state],
		way == 1 and pack.size() >= 4 and t >= 60.0 - STEP and R.state == "on" and against == 0 and worst <= KEEP_M and far >= 1)
	R.reset()


## The away clock's safety net: measured from the nearest live raider as well as the zone.
func _away_net(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	var k := _city(v)
	var e3 := [-1, -1]
	for r in sim.roads.size():
		if sim.roads[r].name == "E3":
			e3 = [r, 9000 / 24]
	if e3[0] < 0:
		e3 = [int(sim.pod.path), int(sim.pod.hint)]
	sim.respawn_on(e3[0], e3[1], 1)
	R.reset()
	T.cars.clear()
	R.state = "on"
	R.city = k
	T.race_state = "raid"
	R.time_limit = 1.0e9
	R.away_t = 3.0
	var zone: Dictionary = R._zone(k)
	var near = _car(T, e3[0], float(e3[1]) + 20.0, 1, 0, 0.0, true)
	var there = _car(T, int(zone.road), float(zone.z.x + 100), 1, 0, 0.0, true)
	R.pack = [near, there]
	var far_km: float = R._gap(k) / 1000.0
	var t := 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
		for c in T.cars.duplicate():
			if c != near and c != there:
				T.cars.erase(c)
		near.v = 0.0
		there.v = 0.0
	var stayed: bool = R.state == "on"
	var clock_near: float = R._away
	T.cars.erase(near)
	t = 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
		for c in T.cars.duplicate():
			if c != there:
				T.cars.erase(c)
		there.v = 0.0
	sections += 1
	_check("away: the pilot %.0f km from the zone beside a raider for 4 s: still on (%s, its away clock %.2f s of %.1f); that raider gone, %.2f s later: \"%s\" (%s)" % [
			far_km, stayed, clock_near, R.away_t, t, R.result, R._why],
		far_km * 1000.0 > T.R_KEEP and stayed and clock_near == 0.0 and R.result == "lost" and R._why == "away" and t <= R.away_t + 0.25)
	R.reset()
	T.cars.clear()


static func _sum(d: Dictionary) -> int:
	var n := 0
	for x in d.values():
		n += int(x)
	return n
