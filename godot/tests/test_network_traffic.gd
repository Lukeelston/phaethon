## The Network's traffic and racers (view/network_traffic.gd), the craft carried kinematically along
## a highway (the traffic driven by hand, 1/60 s a frame):
##   spawn       a full road of traffic at once round the craft; cars, slow pods, demons and transport
##               trains all on it
##   lanes       one way, the pilot's: every vehicle on the pilot's road goes its way; 85%+ in a lane (the
##               rest changing lanes); none off its road
##   junctions   vehicles take ramps and bypasses (road changes) as they go
##   headway     nobody inside another in its lane (30 m), but for a merge or two (a car joining from a
##               ramp doesn't see the road it joins until it's on it)
##   speeds      demons quicker than cars, cars than slow pods; in a city's STARFIGHTER zone none over
##               1,200 mph
##   density     thicker round a city than mid-country
##   zones       20 s by Eridanus with traffic flowing in off the highway: none over 1,200 mph in its
##               STARFIGHTER zone (they decide on an exit 40 km out and slow for it)
##   obstacles   off by default (Luke: "please turn off collision"); on, the vehicles near the craft are the sim's obstacles, moving at their speed; one put
##               in the craft's path is a bump
##   cost        the traffic's fastest frame under COST_MS, a city's crowd round it (100+). The fastest, not the
##               average: that rides on whatever else the machine is doing (the same pass averages 1.6-2.5 ms)
##   racers      after a while on a highway a racer shadows you ("RACER BEHIND"); the ramjet starts the race;
##               faster than it you win (the tally saved), slower you lose, and ignored it peels off
## Prints NETWORK TRAFFIC PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_network_traffic.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const MPH := 2.236936
const CHECKS := 12
const COST_MS := 1.8   # the fastest frame: 1.55-1.65 as it is; 1.94-2.02 with every car reading its road ahead every frame (CAP_EVERY 1)
const COST_FRAMES := 360   # timed: enough that dozens run clear of the machine's other work (of 120, as few as one did)
var fails := 0
var passed := 0
var v
var T
var frames := 0
var road := -1
var fi := 0.0
var speed := 0.0


func _initialize() -> void:
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_network_traffic_")
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	v = ViewScript.new()
	root.add_child(v)


func _road(name: String) -> int:
	for r in v.sim.roads.size():
		if v.sim.roads[r].name == name:
			return r
	return -1


## The craft at road r's sample f, going up it at `speed`.
func _carry() -> void:
	var sim = v.sim
	var R = sim.roads[road]
	var i := clampi(int(fi), 0, R.N - 1)
	sim.respawn_on(road, i, 1)
	for b in sim.bodies:
		b.vx = speed * R.tx[i]
		b.vy = speed * R.ty[i]
	v._follow_origin()


func _run(secs: float) -> void:
	var dt := 1.0 / 60.0
	for k in int(secs * 60.0):
		fi += speed * dt / 24.0
		_carry()
		T.update(dt)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	if frames > 3:
		return false
	var sim = v.sim
	T = v.traffic_net
	v.traffic_net = null   # driven by hand here
	road = _road("E2")
	fi = 4000.0
	speed = 2500.0 / MPH
	_carry()
	T.update(1.0 / 60.0)
	var kinds := {}
	for c in T.cars:
		kinds[c.kind] = true
	_run(20.0)
	for c in T.cars:
		kinds[c.kind] = true
	_check("spawn: %d spawned so far, %d round the craft after 20 s; kinds seen %s" % [T.spawned, T.cars.size(), kinds.keys()],
		T.cars.size() >= 60 and kinds.has(0) and kinds.has(1) and kinds.has(2) and kinds.has(3))
	# lanes
	var in_lane := 0
	var on_mine := 0
	var against := 0
	var off_road := 0
	for c in T.cars:
		var R = sim.roads[c.road]
		var hw: float = R.w[clampi(int(c.f), 0, R.N - 1)] / 2.0
		if absf(c.lat - T._lane_lat(c, c.lane)) < 5.0:
			in_lane += 1
		if c.road == road:
			on_mine += 1
			if c.dir != 1:
				against += 1
		if absf(c.lat) > hw - 2.0:
			off_road += 1
	var n: int = T.cars.size()
	_check("lanes: %d of %d in a lane; on the craft's road %d, going against it %d; %d off the road" % [in_lane, n, on_mine, against, off_road],
		in_lane >= n * 0.85 and on_mine > 5 and against == 0 and off_road == 0)
	# junctions: through the centre interchange and past Eridanus' bypass
	var R0 = sim.roads[road]
	var bd := INF
	for i in range(0, R0.N, 4):
		var d := Vector2(R0.px[i] - 265000.0, R0.py[i] - 300000.0).length()
		if d < bd:
			bd = d
			fi = float(i)
	_carry()
	var sw0: int = T.switched
	_run(40.0)
	_check("junctions: %d road changes in 40 s through the centre interchange (ramps, the bypass)" % (T.switched - sw0), T.switched - sw0 >= 5)
	# headway
	var close := 0
	var by := {}
	for c in T.cars:
		var key := "%d:%d:%d" % [c.road, c.dir, c.lane]
		if not by.has(key):
			by[key] = []
		by[key].append(c)
	for key in by:
		var arr: Array = by[key]
		arr.sort_custom(func(a, b): return a.f < b.f)
		for k in arr.size() - 1:
			var a = arr[k]
			var b = arr[k + 1]
			if absf(a.lat - b.lat) < 15.0 and (b.f - a.f) * 24.0 < 30.0:
				close += 1
	_check("headway: %d pairs inside 30 m in their lane (a merge from a ramp can land beside one: at most 2)" % close, close <= 2)
	# speeds by kind, and the cities' zones
	var mean := {0: [0.0, 0], 1: [0.0, 0], 2: [0.0, 0]}
	var zone_fast := 0
	var in_zone := 0
	for c in T.cars:
		if mean.has(c.kind):
			mean[c.kind][0] += c.v
			mean[c.kind][1] += 1
		var R = sim.roads[c.road]
		if R.mode[clampi(int(c.f), 0, R.N - 1)] == 0:
			in_zone += 1
			if c.v > 1200.0 / MPH:
				zone_fast += 1
				var zs := int(c.f)
				while zs > 0 and zs < R.N - 1 and R.mode[zs] == 0:
					zs -= c.dir
				print("    fast in a zone: %s kind %d f %.0f dir %d v %.0f mph vdes %.0f, %d samples into the zone, lim %.0f" % [R.name, c.kind, c.f, c.dir, c.v * MPH, c.vdes * MPH, absi(int(c.f) - zs), T._limit(c) * MPH])
	var mv := {}
	for kk in mean:
		mv[kk] = mean[kk][0] / maxf(1.0, mean[kk][1]) * MPH
	_check("speeds: demons %.0f mph, cars %.0f, slow pods %.0f; %d in a city's zone, %d over 1,200 mph there" % [mv[2], mv[0], mv[1], in_zone, zone_fast],
		mv[2] > mv[0] and mv[0] > mv[1] and zone_fast == 0)
	# density: round Eridanus vs mid-country
	var near_city := _count_near(sim.cities[0].cx, sim.cities[0].cy)
	road = _road("E2")
	fi = 6000.0   # ~150 km from any city
	_carry()
	T.cars.clear()
	T.spawned = 0
	_run(10.0)
	var mid := _count_near(sim.pod.x, sim.pod.y)
	road = _road("Eridanus")
	fi = float(sim.cities[0].i)
	_carry()
	T.cars.clear()
	T.spawned = 0
	_run(10.0)
	near_city = _count_near(sim.pod.x, sim.pod.y)
	_check("density: %d vehicles within 15 km of Eridanus' terminal, %d mid-country" % [near_city, mid], near_city > mid)
	# the zones: 20 s by Eridanus' terminal, traffic flowing in off the highway (the speeds check is one moment)
	speed = 1000.0 / MPH
	var zn := 0
	var zfast := 0
	var ztop := 0.0
	for k in 20:
		_run(1.0)
		for c in T.cars:
			var Rz = sim.roads[c.road]
			if Rz.mode[clampi(int(c.f), 0, Rz.N - 1)] == 0:
				zn += 1
				ztop = maxf(ztop, c.v)
				if c.v > 1200.0 / MPH:
					zfast += 1
					var zs2 := int(c.f)
					while zs2 > 0 and zs2 < Rz.N - 1 and Rz.mode[zs2] == 0:
						zs2 -= c.dir
					print("    fast in a zone: %s kind %d f %.0f dir %d v %.0f mph, %d samples into the zone, lim here %.0f, its cap %.0f, plan %s" % [Rz.name, c.kind, c.f, c.dir, c.v * MPH, absi(int(c.f) - zs2), T._limit(c) * MPH, c.vcap * MPH, c.plan != null])
	_check("zones: %d vehicle-samples in Eridanus' STARFIGHTER zone over 20 s, the fastest %.0f mph, %d over 1,200" % [zn, ztop * MPH, zfast],
		zn >= 50 and zfast == 0)
	# obstacles (off in the game: Luke, "please turn off collision"; on here, so the forcefields stay tested)
	var no_feed: bool = (func():
		T._feed()
		return sim.obstacles.is_empty()).call()
	T.collide = true
	road = _road("E2")
	fi = 6000.0
	speed = 2000.0 / MPH
	_carry()
	_run(1.0)
	# one in the craft's path, slower: the sim feels it
	var R2 = sim.roads[road]
	var i0: int = int(fi)
	var c0 = T.cars[0]
	c0.kind = T.TRANSPORT   # a road train: it never changes lane
	c0.road = road
	c0.dir = 1
	c0.f = fi + 400.0 / 24.0
	c0.lane = 0
	c0.lat = T._lane_lat(c0, 0)
	for b in sim.bodies:   # the craft in lane 0 too
		b.x += R2.nx[i0] * c0.lat
		b.y += R2.ny[i0] * c0.lat
	c0.v = 1000.0 / MPH
	c0.vdes = c0.v
	T._place(c0)
	T._feed()
	var ok_obs: bool = not sim.obstacles.is_empty()
	var sps := []
	for o in sim.obstacles:
		var sp: float = Vector2(o.vx, o.vy).length()
		sps.append(roundi(sp * MPH))
		if sp > 5000.0 / MPH:
			ok_obs = false
	var bumped := false
	for f in 240:
		for k in 8:
			sim.step({"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 480.0)
		for e in sim.events:
			if e.type == "bump" or e.type == "smash":
				bumped = true
		sim.events.clear()
		v._follow_origin()
		T.update(1.0 / 60.0)
		if bumped:
			break
	_check("obstacles: off by default, none fed (%s); on, %d near vehicles fed to the sim at their speeds %s mph; one in the craft's path bumped it (%s)" % [no_feed, sim.obstacles.size(), sps, bumped], no_feed and ok_obs and bumped)
	T.collide = false
	# the cost: the fastest of the frames (their work is much the same; the slow ones are the machine)
	var tot := 0.0
	var fastest := INF
	road = _road("Eridanus")   # through Eridanus: a city's crowd
	fi = float(sim.cities[0].i) - 400.0
	speed = 1100.0 / MPH
	_carry()
	T.cars.clear()
	T.spawned = 0
	_run(10.0)   # filled in round it first (just arrived, it's a handful: that measured nothing)
	for k in COST_FRAMES:
		fi += speed / 60.0 / 24.0
		_carry()
		T.update(1.0 / 60.0)
		tot += T.update_ms
		fastest = minf(fastest, T.update_ms)
	print("    cost: %.2f ms per 100 vehicles" % (tot / COST_FRAMES / maxf(1.0, T.cars.size()) * 100.0))
	_check("cost: the traffic's fastest frame %.2f ms, %.2f on average (%d vehicles)" % [fastest, tot / COST_FRAMES, T.cars.size()], fastest < COST_MS and T.cars.size() >= 100)
	# racers: shadowed, then a race won
	_reset_racers()
	sim.mode = "normal"
	speed = 3000.0 / MPH
	_run(6.0)
	for k in 40:   # until it's right behind
		if T.racer and T._gap_to_pod(T.racer) < T.RACE_CLOSE:
			break
		_run(0.5)
	var tail_text: String = T.race_text()
	var ok_tail: bool = T.race_state == "tail" and tail_text.begins_with("RACER BEHIND")
	var who: String = T.race_name
	speed = 7000.0 / MPH
	sim.mode = "ramjet"
	_run(0.5)
	var raced: bool = T.race_state == "race"
	var race_line: String = T.race_text()
	_run(30.0)
	var won: String = T.race_result
	v.traffic_net = T
	if won != "":
		v._net_race_result()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(ViewScript.best_dir + "network.json")) if FileAccess.file_exists(ViewScript.best_dir + "network.json") else {}
	v.traffic_net = null
	_check("racers: \"%s\" (%s), then on the ramjet \"%s\"; at 7,000 mph %s; the tally %s" % [tail_text, who, race_line, won, saved.get("beaten", {}) if saved is Dictionary else {}],
		ok_tail and raced and race_line.begins_with("RACE  ") and won == "won" and saved is Dictionary and int(saved.get("beaten", {}).get(who, 0)) == 1)
	# lost: slower than the next one
	_reset_racers()
	sim.mode = "normal"
	speed = 3000.0 / MPH
	_run(6.0)
	for k in 40:
		if T.racer and T._gap_to_pod(T.racer) < T.RACE_CLOSE:
			break
		_run(0.5)
	var tail2: bool = T.race_state == "tail"
	sim.mode = "ramjet"
	speed = 2600.0 / MPH
	_run(60.0)
	var lost: String = T.race_result
	T.race_result = ""
	_check("racers: shadowed again (%s); at 2,600 mph against %s: %s" % [tail2, T.race_name, lost], tail2 and lost == "lost")
	# peeled: the next one ignored
	_reset_racers()
	sim.mode = "normal"
	speed = 3000.0 / MPH
	_run(6.0)
	for k in 40:
		if T.racer and T._gap_to_pod(T.racer) < T.RACE_CLOSE:
			break
		_run(0.5)
	var tail3: bool = T.race_state == "tail"
	_run(50.0)
	var peeled: String = T.race_result
	_check("racers: shadowed (%s), ignored: %s" % [tail3, peeled], tail3 and peeled == "peeled")
	var good: bool = fails == 0 and passed == CHECKS
	print("NETWORK TRAFFIC ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return false


## A clean slate for the next racer: none about, the clock to its first.
func _reset_racers() -> void:
	if T.racer:
		T.cars.erase(T.racer)
	T.racer = null
	T.race_state = ""
	T.race_result = ""
	T._hw_time = T.RACER_EVERY - 4.0   # the next racer 4 s on
	road = _road("E2")
	fi = 3000.0
	_carry()


func _count_near(x: float, y: float) -> int:
	var n := 0
	for c in T.cars:
		if Vector2(c.x - x, c.y - y).length() < 15000.0:
			n += 1
	return n


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
