## The Network's traffic and racers (docs/superpowers/specs/2026-10-19-network-design.md, phase 2):
## regular traffic at speed, driven here, outside the sims; the sims see the vehicles near the craft
## as moving forcefield obstacles (sim.obstacles: a shove, a 'bump'; a catastrophic closing speed is a
## 'smash').
##   one way    traffic always goes the way the pilot is going (Luke: "oncoming traffic cuts the
##              available road in half"): on the pilot's road every vehicle goes the pilot's way, across
##              the whole width: eight lanes on a highway (45 m apart), four on a ramp, a bypass or a
##              turnaround. Nothing merges onto it against you; when you come back the other way (a
##              turnaround) the far ones turn with you and the near ones are cleared. Lanes counted from
##              the right: slow pods and trains keep right, demons left
##   kinds      cars (2,000-3,000 mph), slow pods (1,000-1,500), speed demons (4,000-4,800, weaving),
##              transport pods (road trains of 8 freight cars, ~1,600 mph, the outside lane)
##   driving    each keeps a headway to the one ahead in its lane (the craft counts) or changes lane
##              when it can; slows for curves (its own grip) and the cities' STARFIGHTER zones; at a
##              junction it may take the other road (where the two coincide, the way a road can be
##              entered); toward a highway's end it takes the turnaround
##   density    kept round the craft: thicker near the cities and the interchanges; spawned out in
##              the haze (14-28 km), dropped past 30 km
##   racers     now and then a racer drops in behind you on a highway and shadows you; light your
##              ramjet and it's on: first a mile ahead wins (distance driven since the start); ignore
##              it and it peels off. Names and styles; the tally in network.json (the view saves it)
## Rendering: a MultiMesh per kind (the craft's floating origin), and a beacon per vehicle so its
## tail (or head) light reads from miles away.
##   var t := NetworkTraffic.new(); add_child(t); t.build(sim, view, world)
##   t.update(delta)     every frame, after the sim's steps (sets sim.obstacles for the next ones)
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const MPH := 2.236936
const G := 9.81
const LANES_HWY := [-157.5, -112.5, -67.5, -22.5, 22.5, 67.5, 112.5, 157.5]   # m left of the centreline
const LANES_RAMP := [-75.0, -25.0, 25.0, 75.0]
const FLIP_FAR := 5000.0         # m: an oncoming vehicle on the pilot's road this far off turns round (nearer: cleared)
const R_KEEP := 19000.0          # vehicles kept within this of the craft
const R_SPAWN := Vector2(11000.0, 18000.0)   # spawned this far out (in the haze)
const TARGET := 220              # the most vehicles round the craft (near a city); mid-country fewer (_target)
const SCALE := 2.0               # the vehicles' size: big enough to read at these speeds (a car 24 m, a freight car 34 m)
const R_FIELD := 2500.0          # vehicles within this are the sims' obstacles
const TRAIN := 8                 # cars in a transport pod's train
const TRAIN_GAP := 38.0          # m between their centres
const SF_V := 1150.0 / MPH       # through a city's STARFIGHTER zone
const BRAKE := 4.0 * 9.81        # m/s^2: how hard they plan to brake for what's ahead (6 g at most when they must)
const PLAN_AHEAD := 40000.0      # m: a vehicle decides on a junction this far before it (and slows for the road beyond)
const CAP_EVERY := 3            # frames between a car's readings of its road ahead (staggered: a third of them a frame)
const NEAR := 6000.0             # m (either way): nearer vehicles are driven every frame; farther, every other
                                 # (half of them a frame, for both frames' time) and drawn where they'll be.
                                 # The sims' obstacles (R_FIELD) are all near. Round a city ~70% are far
const BRAKE_AT := [250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0, 12000.0]   # m ahead: where a car reads its road's limits
const BRAKE_BY := [0.0, 250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0]   # ... and where it's slowed for each: the reading
	# before it (a limit read at 500 m may start at 251: braked for at 500 they crossed a zone's edge 70 mph over)
const AFTER := [0.0, 1000.0, 2000.0, 3500.0, 5000.0, 7000.0, 9000.0, 11000.0, 13000.0, 15000.0]   # m along a road it'll take: where its limits are read
enum { CAR, SLOW, DEMON, TRANSPORT, RACER }
# [top mph, lateral grip g, headway s, colour]: a racer's style
const RACERS := {
	"VEGA": [6300.0, 7.0, 0.5, Color(1.0, 0.25, 0.65)],      # a straight-line monster, soft in the bends
	"KESTREL": [5900.0, 10.0, 0.25, Color(0.25, 1.0, 0.55)],  # fearless in traffic
	"MARROW": [6050.0, 9.0, 0.4, Color(1.0, 0.55, 0.1)],      # all-round
	"TALLOW": [5800.0, 12.0, 0.45, Color(0.4, 0.75, 1.0)],    # the corner king
}
const RACER_FIRST := 40.0        # s on a highway before the first racer
const RACER_EVERY := 90.0        # s between racers
const RACER_PATIENCE := 45.0     # s it shadows you before it peels off
const RACE_WIN := 1609.344       # a mile


class Car:
	var id := 0
	var kind := 0
	var road := 0
	var f := 0.0          # fractional sample along its road
	var dir := 1          # 1 up the samples, -1 down
	var lane := 0
	var lat := 0.0        # m left of the centreline
	var v := 0.0          # m/s
	var vdes := 0.0
	var a_up := 1.5 * 9.81
	var a_lat := 9.0 * 9.81
	var headway := 1.2
	var turn_p := 0.3
	var x := 0.0
	var y := 0.0
	var hx := 1.0         # the way it's going (unit)
	var hy := 0.0
	var lc_cool := 0.0
	var col := Color.WHITE
	var name := ""
	var plan = null       # the switch it's decided on ahead (it slows for that road beforehand), or null
	var decided := -1     # the sample of the last switch it decided about (taken or not)
	var nsp = null        # the next switch ahead on its road its way (null: none), found once, not every frame
	var nsp_road := -1    # ... found for this road and way (-1: find it again)
	var nsp_dir := 0
	var vcap := 0.0       # the most it may go for what's ahead (its road's limits and its exit's), read every CAP_EVERY frames
	var vcap_road := -1   # ... read on this road (-1: read it now)
	var owed := 0.0       # s since it was last driven (a far one is driven every other frame)


var sim
var view
var world
var cars: Array[Car] = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _vlim := []           # per road: the speed limit at each sample (curvature, STARFIGHTER zones)
var _switch := []         # per road: [at sample, need dir, to road, to sample, to dir, forced]
var _lanes := []          # per road: its lane offsets
var _mm := {}             # kind -> MultiMeshInstance3D
var _beams: MultiMeshInstance3D
var spawned := 0          # tests read these
var switched := 0
var illegal := 0
var update_ms := 0.0
var _tick := 0
var _brake_at_s := PackedFloat64Array()   # BRAKE_AT in samples (m / 24), BRAKE_BY, for _brake_for
var _brake_by := PackedFloat64Array()
# the racer
var racer: Car = null
var race_state := ""      # "" | "tail" | "race" | "done"
var race_t := 0.0         # s in this state
var race_gap := 0.0       # m: + the craft ahead
var race_result := ""     # "won" | "lost" | "peeled", once, for the view to take
var race_name := ""       # who: the racer's name (kept after it's gone)
const RACE_CLOSE := 600.0        # m: it's shadowing you this close behind (the ramjet then starts the race)
var _hw_time := 0.0       # s on a highway since the last racer
var _racer_count := 0
var _p_switches := []     # the craft's road changes: [from road, from sample, to road, to sample, to dir]
var _pod_prev := Vector2i(-1, -1)
var collide := false      # traffic's forcefields in the sims (off: the craft passes through; the tests turn them on)
var proad := -1           # the pilot's road and the way it's going on it: the way all traffic there goes
var pdir := 0
var _warm := 3            # frames: every kind drawn once under the ground, so its shaders compile at the start, not on first sight


func build(s, v, w) -> void:
	sim = s
	view = v
	world = w
	_rng.seed = 20261019
	for k in BRAKE_AT.size():
		_brake_at_s.append(float(BRAKE_AT[k]) / 24.0)
		_brake_by.append(float(BRAKE_BY[k]))
	for r in sim.roads.size():
		var R = sim.roads[r]
		var lim := PackedFloat32Array()
		lim.resize(R.N)
		var kap := PackedFloat32Array()   # each sample's turn per metre (the cross product of its tangents)
		kap.resize(R.N)
		for j in R.N - 1:
			kap[j] = absf(R.tx[j] * R.ty[j + 1] - R.ty[j] * R.tx[j + 1]) / R.len[j]
		for i in R.N:
			var k := 0.0
			for j in range(maxi(0, i - 6), mini(R.N - 2, i + 6)):
				k = maxf(k, kap[j])
			lim[i] = 1e9 if k < 1e-7 else sqrt(G / k)   # per g of grip: times sqrt(grip) for each vehicle
			if R.mode[i] == 0:
				lim[i] = -SF_V   # a STARFIGHTER zone: a fixed cap (negative marks it)
			if R.shaft and world.shaft.on(r, float(i)):
				lim[i] = 1e9     # a shaft's bulb is the plan's, not a bend: it carries them round
		_vlim.append(lim)
		_lanes.append(LANES_HWY if R.w[0] >= 300.0 else LANES_RAMP)
		_switch.append([])
	for J in sim.junctions:
		var C = sim.roads[int(J[3])]
		if C.role != "":
			continue   # the jumps and the on-ramps from the open ground: not traffic's
		var cb: int = 0 if int(J[4]) == 0 else C.N - 1
		var ca: int = world._map(J, cb)
		for side in 2:   # from the parent onto the joining road, and back
			var r: int = int(J[0]) if side == 0 else int(J[3])
			var q: int = int(J[3]) if side == 0 else int(J[0])
			var at: int = ca if side == 0 else cb
			var iq: int = cb if side == 0 else ca
			for d in [1, -1]:
				var dq: int = d * int(J[6])
				var qz0: int = int(J[4]) if side == 0 else int(J[1])
				var qz1: int = int(J[5]) if side == 0 else int(J[2])
				if qz0 == 0 and dq < 0:
					continue
				if qz1 == sim.roads[q].N - 1 and dq > 0:
					continue
				var R = sim.roads[r]
				var to_end: int = (R.N - 1 - at) if d > 0 else at
				var after := []   # the road beyond: [m on, its limit there (the vlim code)]
				var Q = sim.roads[q]
				for dd in AFTER:
					var qi := clampi(iq + dq * int(dd / 24.0), 0, Q.N - 1)
					after.append([dd, _vlim[q][qi]])
				_switch[r].append([at, d, q, iq, dq, to_end < 260, after])
	_build_meshes()


## Every frame: spawn and drop round the craft, drive, follow the craft's racer, render, and hand the
## near ones to the sim as obstacles.
func update(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick += 1
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	_track_pod()
	# drop the far ones, spawn round the edge
	for k in range(cars.size() - 1, -1, -1):
		var c := cars[k]
		if c != racer and Vector2(c.x - px, c.y - py).length() > R_KEEP:
			cars.remove_at(k)
	var tries := 0
	var want := _target(px, py)
	while cars.size() < want and tries < 12:
		tries += 1
		_spawn(px, py, spawned < want)   # at the start: anywhere from 2 km out, so there's traffic at once
	# who's ahead of whom, in each road and direction (the craft too)
	var buckets := {}
	for c in cars:
		var key: int = c.road * 2 + (1 if c.dir > 0 else 0)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(c)
	var pod_car := _pod_as_car()
	if pod_car and pod_car.v > 20.0:
		proad = pod_car.road
		pdir = pod_car.dir
	if proad >= 0:   # nothing comes at you on your road: far ones turn round, near ones go
		for k in range(cars.size() - 1, -1, -1):
			var c := cars[k]
			if c.road != proad or c.dir == pdir or c == racer:
				continue
			if Vector2(c.x - px, c.y - py).length() > FLIP_FAR:
				c.lane = _lanes[c.road].size() - 1 - c.lane   # the same place across, the other way
				c.dir = pdir
				_place(c)
			else:
				cars.remove_at(k)
	if pod_car:
		var key: int = pod_car.road * 2 + (1 if pod_car.dir > 0 else 0)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(pod_car)
	for key in buckets:
		(buckets[key] as Array).sort_custom(func(a, b): return a.f * a.dir < b.f * b.dir)
	for key in buckets:
		var arr: Array = buckets[key]
		for idx in arr.size():
			var c: Car = arr[idx]
			if c == pod_car:
				continue
			c.owed += delta
			if c != racer and (absf(c.x - px) > NEAR or absf(c.y - py) > NEAR) and (_tick + c.id) % 2 != 0:
				continue
			_drive(c, arr, idx, c.owed)
			c.owed = 0.0
	_race(delta, pod_car)
	_render()
	_feed()
	update_ms = (Time.get_ticks_usec() - t0) / 1000.0


## How many vehicles to keep round (x, y): 60 mid-country, up to TARGET round a city.
func _target(x: float, y: float) -> int:
	var w := 0.0
	for city in sim.cities:
		w = maxf(w, exp(-pow(Vector2(x - city.cx, y - city.cy).length() / 40000.0, 2.0)))
	return int(90.0 + (TARGET - 90.0) * w)


## Lane `lane` counted from the right (the way the car goes): its place across the road.
func _lane_lat(c: Car, lane: int) -> float:
	var L: Array = _lanes[c.road]
	var k := mini(lane, L.size() - 1)
	return L[k] if c.dir > 0 else L[L.size() - 1 - k]


## The craft as a vehicle (for the others' headways): its road, its way, its place across.
func _pod_as_car() -> Car:
	var P = sim.pod
	var R = sim.roads[P.path]
	var i: int = clampi(P.hint, 0, R.N - 1)
	var along: float = P.vx * R.tx[i] + P.vy * R.ty[i]
	var c := Car.new()
	c.id = 0
	c.road = P.path
	c.dir = 1 if along >= 0.0 else -1
	c.f = float(i)
	c.v = absf(along)
	c.lat = (P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]
	return c


func _spawn(px: float, py: float, first: bool) -> void:
	# a random chunk round the craft, a random sample in it
	var gc := Vector2i(int(floor(px / world.CELL)), int(floor(py / world.CELL)))
	var rc := int(ceil(R_SPAWN.y / world.CELL))
	var cell := gc + Vector2i(_rng.randi_range(-rc, rc), _rng.randi_range(-rc, rc))
	var entries: Array = world.grid.get(cell, [])
	if entries.is_empty():
		return
	var e: Array = entries[_rng.randi() % entries.size()]
	var r: int = e[0]
	var R = sim.roads[r]
	if R.role != "":
		return   # (nor spawns on them)
	var i: int = clampi(e[1] * world.CH + _rng.randi_range(0, world.CH - 1), 1, R.N - 2)
	var d := Vector2(R.px[i] - px, R.py[i] - py).length()
	if d > R_SPAWN.y or d < (2000.0 if first else R_SPAWN.x):
		return
	# thicker near the cities and the interchanges
	var w := 0.35
	for city in sim.cities:
		w += 1.2 * exp(-pow(Vector2(R.px[i] - city.cx, R.py[i] - city.cy).length() / 25000.0, 2.0))
	if R.w[0] < 300.0:
		w += 0.6   # ramps and bypasses: at the interchanges
	if _rng.randf() * 1.6 > w:
		return
	var c := Car.new()
	c.id = _next_id
	_next_id += 1
	c.road = r
	c.f = float(i)
	c.dir = 1 if _rng.randf() < 0.5 else -1
	if r == proad and pdir != 0:
		c.dir = pdir
	var roll := _rng.randf()
	c.kind = CAR if roll < 0.55 else (SLOW if roll < 0.70 else (DEMON if roll < 0.85 else TRANSPORT))
	var nl: int = _lanes[r].size()
	match c.kind:
		CAR:
			c.vdes = _rng.randf_range(2000.0, 3000.0) / MPH
			c.lane = _rng.randi_range(0, nl - 1)
			c.col = [Color(0.85, 0.86, 0.9), Color(0.2, 0.35, 0.8), Color(0.75, 0.12, 0.1), Color(0.95, 0.75, 0.2), Color(0.15, 0.16, 0.18), Color(0.3, 0.6, 0.45)][_rng.randi() % 6]
			c.a_up = 1.5 * G
			c.a_lat = 9.0 * G
			c.headway = 1.2
		SLOW:
			c.vdes = _rng.randf_range(1000.0, 1500.0) / MPH
			c.lane = 0 if _rng.randf() < 0.6 else 1
			c.col = Color(0.62, 0.6, 0.55)
			c.a_up = 0.8 * G
			c.a_lat = 7.0 * G
			c.headway = 1.6
		DEMON:
			c.vdes = _rng.randf_range(4000.0, 4800.0) / MPH
			c.lane = nl - 1
			c.col = [Color(0.9, 0.1, 0.6), Color(0.1, 0.9, 0.9), Color(0.6, 0.1, 0.95)][_rng.randi() % 3]
			c.a_up = 3.0 * G
			c.a_lat = 11.0 * G
			c.headway = 0.45
		TRANSPORT:
			c.vdes = _rng.randf_range(1450.0, 1750.0) / MPH
			c.lane = 0
			c.col = Color(0.9, 0.55, 0.15)
			c.a_up = 0.5 * G
			c.a_lat = 6.0 * G
			c.headway = 2.0
	c.turn_p = 0.35 if c.kind != TRANSPORT else 0.15
	c.lat = _lane_lat(c, c.lane)
	c.v = _brake_for(c)   # already slow enough for what's ahead (a city's zone a few km on)
	_place(c)
	cars.append(c)
	spawned += 1


## The speed it can hold here: its grip in the curve, a city's STARFIGHTER cap.
func _limit(c: Car) -> float:
	var l: float = _vlim[c.road][clampi(int(c.f), 0, _vlim[c.road].size() - 1)]
	if l < 0.0:
		return -l
	return l * sqrt(c.a_lat / G)


func _drive(c: Car, arr: Array, idx: int, delta: float) -> void:
	var R = sim.roads[c.road]
	var nl: int = _lanes[c.road].size()
	c.lc_cool = maxf(0.0, c.lc_cool - delta)
	if c.nsp_road != c.road or c.nsp_dir != c.dir:
		_next_switch(c)
	# the speed it wants: its own, the curve's, and slow enough to brake (at BRAKE) for every limit up
	# to 12 km ahead (a city's STARFIGHTER zone from 2,400 mph is 7.5 km of braking), and for the road
	# beyond the exit it's taking. Read every CAP_EVERY frames, as if from where it'll be by the next.
	if c.kind != RACER:
		_decide(c)
	if c.vcap_road != c.road or (_tick + c.id) % CAP_EVERY == 0:
		c.vcap = _speed_cap(c, CAP_EVERY * c.v * delta)
		c.vcap_road = c.road
	var vt := c.vcap
	if c.kind == RACER and race_state == "tail":
		vt = _tail_speed(c)
	# the one ahead in its lane
	var lead: Car = null
	var gap := INF
	for k in range(idx + 1, mini(idx + 10, arr.size())):
		var o: Car = arr[k]
		if absf(o.lat - c.lat) < 22.0:
			lead = o
			gap = (o.f - c.f) * c.dir * 24.0 - 20.0 * SCALE
			break
	if lead and gap < c.v * c.headway:
		var moved := false
		if c.lc_cool <= 0.0 and c.kind != TRANSPORT:
			for dl in ([-1, 1] if _rng.randf() < 0.5 else [1, -1]):
				var ln: int = c.lane + dl
				if ln < 0 or ln >= nl:
					continue
				var lat_n := _lane_lat(c, ln)
				if _clear(arr, idx, c, lat_n):
					c.lane = ln
					c.lc_cool = 1.0 if c.kind == DEMON or c.kind == RACER else 3.0
					moved = true
					break
		if not moved:
			vt = minf(vt, lead.v + (gap - c.v * c.headway * 0.5) / maxf(c.headway, 0.3))
	elif c.kind == DEMON and c.lc_cool <= 0.0 and _rng.randf() < 0.004:
		var ln2 := clampi(c.lane + (1 if _rng.randf() < 0.5 else -1), 0, nl - 1)   # weaving for the joy of it
		if _clear(arr, idx, c, _lane_lat(c, ln2)):
			c.lane = ln2
			c.lc_cool = 1.0
	# speed and place
	var dv := vt - c.v
	c.v += clampf(dv, -6.0 * G * delta, c.a_up * delta)
	c.v = maxf(c.v, 0.0)
	var lt := _lane_lat(c, c.lane)
	c.lat = move_toward(c.lat, lt, (60.0 if c.kind == DEMON or c.kind == RACER else 30.0) * delta)
	var f0 := c.f
	c.f += c.dir * c.v * delta / R.len[clampi(int(c.f), 0, R.N - 1)]
	# a junction it's passing: take the other road? (nothing to pass before its next switch)
	if c.nsp != null and (float(c.nsp[0]) - c.f) * c.dir <= 0.0:
		for sp in _switch[c.road]:
			if int(sp[1]) != c.dir:
				continue
			var at := float(sp[0])
			if (at - f0) * c.dir > 0.0 and (at - c.f) * c.dir <= 0.0:
				var take: bool = sp[5] or (c.plan != null and c.plan == sp)
				if c.kind == RACER:
					take = _racer_takes(c, sp)
				if take and int(sp[2]) == proad and int(sp[4]) != pdir and c != racer:
					if sp[5]:
						c.v = -1.0   # its road ends here and the only way on is against the pilot: gone
					take = false
				if take:
					_switch_to(c, sp)
					break
		c.nsp_road = -1   # passed it: find the next
	var R2 = sim.roads[c.road]
	if c.f < 0.5 or c.f > R2.N - 1.5:   # off an end it couldn't leave: gone (or a racer: kept on the road)
		if c == racer:
			c.f = clampf(c.f, 0.5, R2.N - 1.5)
			c.v = 0.0
			c.nsp_road = -1
		else:
			c.v = -1.0
	_place(c)
	if c.v < 0.0:
		cars.erase(c)


## The fastest it can go here and still brake (at BRAKE) for every limit on its road up to 12 km on
## (down to each by the reading before it), each `margin` m nearer than it is.
func _brake_for(c: Car, margin := 0.0) -> float:
	var R = sim.roads[c.road]
	var vl: PackedFloat32Array = _vlim[c.road]   # (as an Array it would be converted: a copy every call)
	var vt := minf(c.vdes, _limit(c))
	var gs := sqrt(c.a_lat / G)   # (the same sums as before, with the constants out of the loop: ~200
	var n1: int = R.N - 1         # cars, a third of them a frame, ten readings each)
	for k in _brake_at_s.size():
		var ai := clampi(int(c.f + c.dir * _brake_at_s[k]), 0, n1)
		var la: float = vl[ai]
		var lv: float = -la if la < 0.0 else la * gs
		vt = minf(vt, sqrt(lv * lv + 2.0 * BRAKE * maxf(0.0, _brake_by[k] - margin)))
	return vt


## _brake_for, and slow enough for the road beyond the exit it's decided on.
func _speed_cap(c: Car, margin: float) -> float:
	var vt := _brake_for(c, margin)
	if c.plan != null:
		var ds: float = (float(c.plan[0]) - c.f) * c.dir * 24.0
		if ds > 0.0:   # (not passed it yet)
			ds = maxf(0.0, ds - margin)
			var by := 0.0   # down to each by the reading before it, as in _brake_for
			for pr in c.plan[6]:
				var la2: float = pr[1]
				var lv2: float = -la2 if la2 < 0.0 else la2 * sqrt(c.a_lat / G)
				vt = minf(vt, sqrt(lv2 * lv2 + 2.0 * BRAKE * (ds + by)))
				by = float(pr[0])
	return vt


## Is the lane at lat clear: nobody within a headway ahead, nor closing from behind?
func _clear(arr: Array, idx: int, c: Car, lat_n: float) -> bool:
	for k in range(maxi(0, idx - 8), mini(arr.size(), idx + 9)):
		if k == idx:
			continue
		var o: Car = arr[k]
		if absf(o.lat - lat_n) > 25.0:
			continue
		var g: float = (o.f - c.f) * c.dir * 24.0
		if g > 0.0 and g < c.v * c.headway * 1.3 + 40.0:
			return false
		if g <= 0.0 and -g < maxf(0.0, o.v - c.v) * 1.5 + 60.0:
			return false
	return true


## The next junction ahead within PLAN_AHEAD: decided once, whether it takes it (forced ones always;
## never onto the pilot's road against the pilot).
func _decide(c: Car) -> void:
	var best = c.nsp
	if best == null:
		return
	var bd: float = (float(best[0]) - c.f) * c.dir * 24.0
	if best == null or bd > PLAN_AHEAD or int(best[0]) == c.decided:
		return
	c.decided = int(best[0])
	c.vcap_road = -1   # read the road ahead again now (it may be slowing for this exit)
	var take: bool = best[5] or _rng.randf() < c.turn_p
	if int(best[2]) == proad and int(best[4]) != pdir and not best[5]:
		take = false
	c.plan = best if take else null


## The nearest switch strictly ahead on its road its way (the first listed, of several at one sample).
func _next_switch(c: Car) -> void:
	c.nsp = null
	c.nsp_road = c.road
	c.nsp_dir = c.dir
	var bd := INF
	for sp in _switch[c.road]:
		if int(sp[1]) != c.dir:
			continue
		var ds: float = (float(sp[0]) - c.f) * c.dir
		if ds > 0.0 and ds < bd:
			bd = ds
			c.nsp = sp


func _switch_to(c: Car, sp: Array) -> void:
	var over: float = (c.f - float(sp[0])) * c.dir   # samples past the switch
	c.road = sp[2]
	c.dir = sp[4]
	c.f = float(sp[3]) + over * c.dir
	var R = sim.roads[c.road]
	var i := clampi(int(c.f), 0, R.N - 1)
	c.lat = (c.x - R.px[i]) * R.nx[i] + (c.y - R.py[i]) * R.ny[i]   # where it is across the new road
	c.lane = mini(c.lane, _lanes[c.road].size() - 1)
	c.plan = null
	c.decided = -1
	c.nsp_road = -1
	switched += 1


func _place(c: Car) -> void:
	var R = sim.roads[c.road]
	var i := clampi(int(c.f), 0, R.N - 2)
	var t := clampf(c.f - i, 0.0, 1.0)
	var tx: float = lerpf(R.tx[i], R.tx[i + 1], t)
	var ty: float = lerpf(R.ty[i], R.ty[i + 1], t)
	var l := sqrt(tx * tx + ty * ty)
	tx /= l
	ty /= l
	c.x = R.px[i] + R.tx[i] * R.len[i] * t - ty * c.lat
	c.y = R.py[i] + R.ty[i] * R.len[i] * t + tx * c.lat
	c.hx = tx * c.dir
	c.hy = ty * c.dir


# --- the racer -----------------------------------------------------------------------------------

## The craft's road changes, so a racer behind it can follow.
func _track_pod() -> void:
	var cur := Vector2i(sim.pod.path, sim.pod.hint)
	if _pod_prev.x >= 0 and cur.x != _pod_prev.x:
		var R = sim.roads[cur.x]
		var along: float = sim.pod.vx * R.tx[cur.y] + sim.pod.vy * R.ty[cur.y]
		_p_switches.append([_pod_prev.x, _pod_prev.y, cur.x, cur.y, 1 if along >= 0.0 else -1])
		if _p_switches.size() > 12:
			_p_switches.pop_front()
	_pod_prev = cur


func _racer_takes(c: Car, sp: Array) -> bool:
	for s in _p_switches:   # where the craft went from this road
		if int(s[0]) == c.road and int(s[2]) == int(sp[2]) and absi(int(s[1]) - int(sp[0])) < 200:
			return true
	return sp[5]


func _tail_speed(c: Car) -> float:
	var P = sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var behind := _gap_to_pod(c)   # m the craft is ahead
	return clampf(pv + (behind - 160.0) * 0.6, 0.0, 6500.0 / MPH)


## How far ahead of the racer the craft is, along the racer's way (straight line projected).
func _gap_to_pod(c: Car) -> float:
	return (sim.pod.x - c.x) * c.hx + (sim.pod.y - c.y) * c.hy


func _race(delta: float, pod_car: Car) -> void:
	var P = sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var on_hwy: bool = sim.roads[P.path].w[0] >= 300.0
	if race_state == "":
		if on_hwy and pv > 2000.0 / MPH:
			_hw_time += delta
		if _hw_time >= (RACER_FIRST if _racer_count == 0 else RACER_EVERY) and pod_car and on_hwy and pv > 2000.0 / MPH:
			_spawn_racer(pod_car)
		return
	race_t += delta
	if racer == null or not cars.has(racer):
		race_state = ""
		racer = null
		return
	match race_state:
		"tail":
			var gp := _gap_to_pod(racer)
			if sim.mode == "ramjet" and gp > -50.0 and gp < RACE_CLOSE:
				race_state = "race"
				race_t = 0.0
				race_gap = _gap_to_pod(racer)
				var st: Array = RACERS[racer.name]
				racer.vdes = st[0] / MPH
				racer.a_up = 3.5 * G
			elif race_t > RACER_PATIENCE or _gap_to_pod(racer) > 6000.0:
				_end_race("peeled")
		"race":
			race_gap += (pv - racer.v) * delta
			if race_gap >= RACE_WIN:
				_end_race("won")
			elif race_gap <= -RACE_WIN:
				_end_race("lost")
		"done":
			if race_t > 20.0 or Vector2(racer.x - P.x, racer.y - P.y).length() > 20000.0:
				cars.erase(racer)
				racer = null
				race_state = ""


func _spawn_racer(pc: Car) -> void:
	var names := RACERS.keys()
	var nm: String = names[_racer_count % names.size()]
	var st: Array = RACERS[nm]
	var c := Car.new()
	c.id = 900000 + _racer_count
	c.kind = RACER
	c.name = nm
	c.road = pc.road
	c.dir = pc.dir
	c.f = pc.f - pc.dir * 2500.0 / 24.0
	c.nsp_road = -1
	var R = sim.roads[c.road]
	if c.f < 2.0 or c.f > R.N - 3.0:
		return
	c.v = pc.v + 300.0 / MPH
	c.vdes = c.v
	c.a_up = 3.0 * G
	c.a_lat = st[1] * G
	c.headway = st[2]
	c.col = st[3]
	var nl: int = _lanes[c.road].size()
	var plane := 0
	var best := INF
	for k in nl:
		var d := absf(_lane_lat(c, k) - pc.lat)
		if d < best:
			best = d
			plane = k
	c.lane = clampi(plane + (1 if plane < nl - 1 else -1), 0, nl - 1)
	c.lat = _lane_lat(c, c.lane)
	c.turn_p = 0.0
	_place(c)
	cars.append(c)
	racer = c
	race_name = nm
	race_state = "tail"
	race_t = 0.0
	_racer_count += 1
	_hw_time = 0.0


func _end_race(result: String) -> void:
	race_state = "done"
	race_t = 0.0
	race_result = result
	if racer:
		racer.vdes = 2200.0 / MPH   # off the gas: it drops back and leaves


## The dash's line while a racer is about ("" when none).
func race_text() -> String:
	if racer == null or race_state == "" or race_state == "done":
		return ""
	if race_state == "tail":
		var gp := _gap_to_pod(racer)
		if gp > RACE_CLOSE:
			return "RACER CLOSING  %s  %.1f mi back" % [racer.name, gp / 1609.344]
		return "RACER BEHIND  %s   light the ramjet to race" % racer.name
	var mi := race_gap / 1609.344
	var bar := ""
	var k := clampi(roundi((race_gap / RACE_WIN + 1.0) * 5.0), 0, 10)
	for q in 11:
		bar += "|" if q == 5 else ("=" if (q < 5 and q >= k) or (q > 5 and q <= k) else ".")
	return "RACE  %s  YOU %s%.2f mi  [%s]" % [racer.name, "+" if mi >= 0.0 else "-", absf(mi), bar]


# --- rendering and the sims' obstacles ---------------------------------------------------------

func _build_meshes() -> void:
	var body := Kit.vertex_colors()
	var lights := Kit.vertex_colors(true)
	lights.albedo_color = Color(2.2, 2.2, 2.2)
	var shapes := {
		CAR: [[Kit.box(Vector3(4.0, 1.6, 12.0)), Transform3D(Basis(), Vector3(0, 1.0, 0)), Color.WHITE], [Kit.box(Vector3(2.6, 1.0, 5.0)), Transform3D(Basis(), Vector3(0, 2.2, 1.0)), Color(0.15, 0.2, 0.28)]],
		SLOW: [[Kit.box(Vector3(5.0, 3.2, 14.0)), Transform3D(Basis(), Vector3(0, 1.8, 0)), Color.WHITE]],
		DEMON: [[Kit.box(Vector3(3.4, 1.1, 13.0)), Transform3D(Basis(), Vector3(0, 0.8, 0)), Color.WHITE], [Kit.box(Vector3(5.5, 0.3, 2.0)), Transform3D(Basis(), Vector3(0, 1.3, 5.6)), Color(0.08, 0.08, 0.1)]],
		TRANSPORT: [[Kit.box(Vector3(5.5, 4.4, 17.0)), Transform3D(Basis(), Vector3(0, 2.4, 0)), Color.WHITE], [Kit.box(Vector3(5.6, 0.5, 17.2)), Transform3D(Basis(), Vector3(0, 4.7, 0)), Color(0.2, 0.2, 0.22)]],
		RACER: [[Kit.box(Vector3(3.6, 1.2, 14.0)), Transform3D(Basis(), Vector3(0, 0.9, 0)), Color.WHITE], [Kit.box(Vector3(6.0, 0.35, 2.4)), Transform3D(Basis(), Vector3(0, 1.5, 6.0)), Color(0.05, 0.05, 0.06)]],
	}
	var glows := {   # a tail strip (+z is the back) and two head lamps
		CAR: [[Kit.box(Vector3(3.6, 0.3, 0.2)), Transform3D(Basis(), Vector3(0, 1.2, 6.05)), Color(1.0, 0.1, 0.05)], [Kit.box(Vector3(0.6, 0.3, 0.2)), Transform3D(Basis(), Vector3(1.4, 1.1, -6.05)), Color(1, 1, 0.92)], [Kit.box(Vector3(0.6, 0.3, 0.2)), Transform3D(Basis(), Vector3(-1.4, 1.1, -6.05)), Color(1, 1, 0.92)]],
		SLOW: [[Kit.box(Vector3(4.6, 0.4, 0.2)), Transform3D(Basis(), Vector3(0, 1.0, 7.05)), Color(1.0, 0.45, 0.05)]],
		DEMON: [[Kit.box(Vector3(3.2, 0.25, 13.2)), Transform3D(Basis(), Vector3(0, 0.25, 0)), Color.WHITE], [Kit.box(Vector3(3.0, 0.3, 0.2)), Transform3D(Basis(), Vector3(0, 1.0, 6.55)), Color(1.0, 0.1, 0.05)]],
		TRANSPORT: [[Kit.box(Vector3(5.6, 0.35, 0.2)), Transform3D(Basis(), Vector3(0, 0.8, 8.55)), Color(1.0, 0.6, 0.1)], [Kit.box(Vector3(0.2, 0.35, 16.0)), Transform3D(Basis(), Vector3(2.8, 4.2, 0)), Color(1.0, 0.6, 0.1)], [Kit.box(Vector3(0.2, 0.35, 16.0)), Transform3D(Basis(), Vector3(-2.8, 4.2, 0)), Color(1.0, 0.6, 0.1)]],
		RACER: [[Kit.box(Vector3(3.4, 0.3, 14.2)), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color.WHITE], [Kit.box(Vector3(3.2, 0.5, 0.2)), Transform3D(Basis(), Vector3(0, 1.1, 7.05)), Color(1.0, 0.3, 0.9)]],
	}
	for kind in shapes:
		var mesh := Kit.compound(shapes[kind])
		Kit.compound(glows[kind], mesh)
		mesh.surface_set_material(0, body)
		mesh.surface_set_material(1, lights)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = TARGET * TRAIN if kind == TRANSPORT else TARGET + 8
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.name = "traffic_%d" % kind
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-40000, -100, -40000), Vector3(80000, 400, 80000))
		add_child(mi)
		_mm[kind] = mi
	# a beacon per vehicle: its tail (or head) light, a few pixels from miles away
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_color(Color.WHITE)
		st.set_uv(uv)
		st.set_uv2(Vector2(0.0, 1e6))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3.ZERO)
	var bmm := MultiMesh.new()
	bmm.transform_format = MultiMesh.TRANSFORM_3D
	bmm.use_colors = true
	bmm.mesh = st.commit()
	bmm.instance_count = TARGET + 12
	bmm.visible_instance_count = 0
	_beams = MultiMeshInstance3D.new()
	_beams.name = "traffic_lights"
	_beams.multimesh = bmm
	var bm := ShaderMaterial.new()
	bm.shader = preload("res://view/beacon.gdshader")
	bm.set_shader_parameter("size", 0.9)
	bm.set_shader_parameter("min_ang", 0.0022)
	bm.set_shader_parameter("far_dim", 0.25)
	bm.set_shader_parameter("energy", 2.0)
	_beams.material_override = bm
	_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beams.custom_aabb = AABB(Vector3(-40000, -100, -40000), Vector3(80000, 400, 80000))
	add_child(_beams)


func _render() -> void:
	var ox: float = view.org_x
	var oy: float = view.org_y
	var n := {}
	for kind in _mm:
		n[kind] = 0
	var nb := 0
	var bmm: MultiMesh = _beams.multimesh
	var pod_v := Vector2(sim.pod.vx, sim.pod.vy)
	for c in cars:
		var mm: MultiMesh = (_mm[c.kind] as MultiMeshInstance3D).multimesh
		var h: float = sim.net_height(c.road, c.f) + 1.0
		var shaft_on: bool = sim.roads[c.road].shaft and world.shaft.on(c.road, c.f)
		var cx: float = c.x + c.hx * c.v * c.owed   # where it is now (a far one not driven this frame: on along its way)
		var cy: float = c.y + c.hy * c.v * c.owed
		var yaw := atan2(-c.hx, c.hy)   # +z (the model's back) against the way it's going
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SCALE)
		if shaft_on:
			b = world.shaft.carry(c.road, c.f) * b
		var cnt := TRAIN if c.kind == TRANSPORT else 1
		for k in cnt:
			if n[c.kind] >= mm.instance_count:
				break
			var back := k * TRAIN_GAP
			var p := Vector3(cx - c.hx * back - ox, h, -(cy - c.hy * back - oy))
			if shaft_on:
				p = world.shaft.point(c.road, c.f - c.dir * back / 24.0, c.lat, 1.0, ox, oy)
			mm.set_instance_transform(n[c.kind], Transform3D(b, p))
			mm.set_instance_color(n[c.kind], c.col)
			n[c.kind] += 1
		if nb < bmm.instance_count:
			# the light you see: its tail if it's going your way, its head lamps if it's coming at you
			var coming: bool = c.hx * pod_v.x + c.hy * pod_v.y < 0.0
			var off := -6.5 * SCALE if coming else 6.5 * SCALE + (cnt - 1) * TRAIN_GAP
			var lp := Vector3(cx - c.hx * off - ox, h + 1.2 * SCALE, -(cy - c.hy * off - oy))
			if shaft_on:
				lp = world.shaft.point(c.road, c.f - c.dir * off / 24.0, c.lat, 1.0 + 1.2 * SCALE, ox, oy)
			bmm.set_instance_transform(nb, Transform3D(Basis(), lp))
			var lc := Color(1.0, 0.95, 0.85) if coming else (Color(1.0, 0.3, 0.9) if c.kind == RACER else Color(1.0, 0.15, 0.08))
			bmm.set_instance_color(nb, lc)
			nb += 1
	if _warm > 0:
		_warm -= 1
		for kind in _mm:
			var wm: MultiMesh = (_mm[kind] as MultiMeshInstance3D).multimesh
			if n[kind] == 0:
				wm.set_instance_transform(0, Transform3D(Basis(), Vector3(0.0, -60.0, -40.0)))
				n[kind] = 1
		if nb == 0:
			bmm.set_instance_transform(0, Transform3D(Basis(), Vector3(0.0, -60.0, -40.0)))
			nb = 1
	for kind in _mm:
		(_mm[kind] as MultiMeshInstance3D).multimesh.visible_instance_count = n[kind]
	bmm.visible_instance_count = nb


## The near vehicles as the sims' obstacles: circles along each body (a train's cars each), with
## its velocity (the sim moves them between frames).
func _feed() -> void:
	if not collide:   # (Luke, 2026-10-20: "please turn off collision": nine smashes in a flight)
		sim.obstacles = []
		return
	var obs: Array = []
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	for c in cars:
		if Vector2(c.x - px, c.y - py).length() > R_FIELD:
			continue
		var vx := c.hx * c.v
		var vy := c.hy * c.v
		var parts: Array = []
		match c.kind:
			TRANSPORT:
				for k in TRAIN:
					parts.append([k * TRAIN_GAP + 4.5 * SCALE, 4.2 * SCALE])
					parts.append([k * TRAIN_GAP - 4.5 * SCALE, 4.2 * SCALE])
			SLOW:
				parts = [[4.0 * SCALE, 3.2 * SCALE], [-4.0 * SCALE, 3.2 * SCALE]]
			_:
				parts = [[3.5 * SCALE, 2.6 * SCALE], [-3.5 * SCALE, 2.6 * SCALE]]
		for q in parts.size():
			var back: float = parts[q][0]
			obs.append({"id": c.id * 32 + q, "r": parts[q][1], "x": c.x - c.hx * back, "y": c.y - c.hy * back, "vx": vx, "vy": vy})
	sim.obstacles = obs


## The vehicles on the map: [[x, y, kind], ...] within r of (x, y).
func marks(x: float, y: float, r: float) -> Array:
	var out := []
	for c in cars:
		if absf(c.x - x) < r and absf(c.y - y) < r:
			out.append([c.x, c.y, c.kind])
	return out
