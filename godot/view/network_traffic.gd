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
##   kinds      cars (2,000-3,000 mph, 30% faster on express decks), slow pods (1,000-1,500),
##              speed demons (4,000-4,800, 10% faster on express decks, weaving), transport pods
##              (a tractor hauling seven freight cars, ~1,600 mph, the outside lane). Higher roads have
##              more hot rods and racers; lower roads have more shuttles and freight.
##   driving    each keeps a headway to the one ahead in its lane (the craft counts) or changes lane
##              when it can; slows for curves (its own grip) and the cities' STARFIGHTER zones; at a
##              junction it may take the other road (where the two coincide, the way a road can be
##              entered); toward a highway's end it takes the turnaround. Ordinary traffic makes
##              one safe, gradual move for a persistent faster follower, whoever is driving it.
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

const Simulation := preload("res://sim/craft_sim.gd")
const RoadWorld := preload("res://view/network_world.gd")
const Batch := preload("res://view/traffic_batch.gd")
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
const BRAKE_AT := [250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0, 12000.0, 16000.0, 22000.0, 30000.0, 40000.0, 50000.0]   # straight highways let demons reach speeds that need >30 km to brake
const BRAKE_BY := [0.0, 250.0, 500.0, 1000.0, 2000.0, 3000.0, 4500.0, 6000.0, 8000.0, 10000.0, 12000.0, 16000.0, 22000.0, 30000.0, 40000.0]   # ... and where it's slowed for each: the reading
	# before it (a limit read at 500 m may start at 251: braked for at 500 they crossed a zone's edge 70 mph over)
const AFTER := [0.0, 1000.0, 2000.0, 3500.0, 5000.0, 7000.0, 9000.0, 11000.0, 13000.0, 15000.0, 20000.0, 28000.0, 38000.0, 50000.0]   # m along a road it'll take: where its limits are read
enum { CAR, SLOW, DEMON, TRANSPORT, RACER }
const TRACTOR := 5 # Render slot for the lead unit of a transport.
const FLEET := [
	preload("res://art/traffic/commuter.glb"), preload("res://art/traffic/shuttle.glb"),
	preload("res://art/traffic/demon.glb"), preload("res://art/traffic/cargo.glb"),
	preload("res://art/traffic/racer.glb"), preload("res://art/traffic/tractor.glb"),
]
const NUMBER_BOARDS := {"VEGA": 0.0, "KESTREL": 1.0/3.0, "MARROW": 2.0/3.0, "TALLOW": 1.0}
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
	var sort_entry := [0.0, 0]
	var kind := 0
	var road := 0
	var f := 0.0          # fractional sample along its road
	var dir := 1          # 1 up the samples, -1 down
	var lane := 0
	var lat := 0.0        # m left of the centreline
	var left_width := 7.0
	var right_width := 7.0
	var front := 24.0
	var rear := 24.0
	var v := 0.0          # m/s
	var vdes := 0.0
	var cruise := 0.0     # the vehicle's own lower-deck cruise; express roads scale cars/hot rods
	var cruise_goal := 0.0 # road-dependent target, approached gradually across a level change
	var a_up := 1.5 * 9.81
	var a_lat := 9.0 * 9.81
	var headway := 1.2
	var turn_p := 0.3
	var x := 0.0
	var y := 0.0
	var hx := 1.0         # the way it's going (unit)
	var hy := 0.0
	var lc_cool := 0.0
	var flow_clock := 0.0  # staggered rearward glance, not a scan of every car every frame
	var flow_source := -1 # the same approaching road user must persist before a move
	var flow_notice := 0.0
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


var sim: Simulation
var view
var world: RoadWorld
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
var grade := true         # vehicles follow the road's grade (off: level at the lead's height, as v0.3.2, for comparisons)
var collide := false      # traffic's forcefields in the sims (off: the craft passes through; the tests turn them on)
var proad := -1           # the pilot's road and the way it's going on it: the way all traffic there goes
var pdir := 0
var _warm := 3            # frames: every kind drawn once under the ground, so its shaders compile at the start, not on first sight


func build(s, v, w) -> void:
	sim = s
	view = v
	world = w
	collide = bool(sim.P.obstacleCollisions)
	_rng.seed = 20261019
	for k in BRAKE_AT.size():
		_brake_at_s.append(float(BRAKE_AT[k]) / 24.0)
		_brake_by.append(float(BRAKE_BY[k]))
	for r in sim.roads.size():
		var R := sim.roads[r]
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
		var C := sim.roads[int(J[3])]
		if not _public_road(C):
			continue
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
				var R := sim.roads[r]
				var to_end: int = (R.N - 1 - at) if d > 0 else at
				var after := []   # the road beyond: [m on, its limit there (the vlim code)]
				var Q := sim.roads[q]
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
		if c != racer and Vector2(c.x - px, c.y - py).length_squared() > R_KEEP * R_KEEP:
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
			if Vector2(c.x - px, c.y - py).length_squared() > FLIP_FAR * FLIP_FAR:
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
		var group: Array = buckets[key]
		if group.size() < 2:
			continue
		# Native sort compares exact double positions. The original index breaks
		# ties on eight-lane grids and retrieves the original car after sorting.
		var order: Array = []
		order.resize(group.size())
		var previous := -INF
		var sorted := true
		for i in group.size():
			var car: Car = group[i]
			var along := car.f * car.dir
			sorted = sorted and along >= previous
			previous = along
			car.sort_entry[0] = along
			car.sort_entry[1] = i
			order[i] = car.sort_entry
		if not sorted:
			order.sort()
			var input := group.duplicate()
			for i in order.size():
				group[i] = input[order[i][1]]
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
	var P := sim.pod
	var R := sim.roads[P.path]
	var i: int = clampi(P.hint, 0, R.N - 1)
	var along: float = P.vx * R.tx[i] + P.vy * R.ty[i]
	var c := Car.new()
	c.id = 0
	c.road = P.path
	c.dir = 1 if along >= 0.0 else -1
	c.f = float(i)
	c.v = absf(along)
	c.lat = (P.x - R.px[i]) * R.nx[i] + (P.y - R.py[i]) * R.ny[i]
	# The engines can swing wider and run well ahead of the pod. Other drivers
	# reserve that physical corridor, not just the cockpit's centre point.
	for body in sim.bodies:
		var dx: float = body.x - P.x
		var dy: float = body.y - P.y
		var across: float = dx * R.nx[i] + dy * R.ny[i]
		var ahead: float = (dx * R.tx[i] + dy * R.ty[i]) * c.dir
		c.left_width = maxf(c.left_width, across + 3.0)
		c.right_width = maxf(c.right_width, -across + 3.0)
		c.front = maxf(c.front, ahead + 5.0)
		c.rear = maxf(c.rear, -ahead + 5.0)
	return c


static func _public_road(road: Simulation.TrackPath) -> bool:
	return road.role == "" and road.name != "SAurora" and not RoadWorld.STUNT_ROADS.has(road.name)


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
	var R := sim.roads[r]
	if not _public_road(R):
		return
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
	var express := _traffic_tier(r, c.f)
	var car_cut := lerpf(0.58, 0.48, express)
	var slow_cut := car_cut + lerpf(0.22, 0.05, express)
	var demon_cut := slow_cut + lerpf(0.06, 0.39, express)
	c.kind = CAR if roll < car_cut else (SLOW if roll < slow_cut else (DEMON if roll < demon_cut else TRANSPORT))
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
			c.col = [Color(0.82, 0.77, 0.62), Color(0.38, 0.61, 0.65), Color(0.78, 0.48, 0.25), Color(0.57, 0.62, 0.69)][_rng.randi() % 4]
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
			c.col = [Color(0.9, 0.55, 0.15), Color(0.65, 0.22, 0.16), Color(0.33, 0.49, 0.61), Color(0.43, 0.52, 0.29)][_rng.randi() % 4]
			c.a_up = 0.5 * G
			c.a_lat = 6.0 * G
			c.headway = 2.0
	c.cruise = c.vdes
	c.cruise_goal = _cruise_for(c, express)
	c.vdes = c.cruise_goal
	c.turn_p = 0.35 if c.kind != TRANSPORT else 0.15
	c.lat = _lane_lat(c, c.lane)
	# A car can spawn beside an exit. Choose its route before its initial speed,
	# so it is already able to brake for that road's curves and city zone.
	_next_switch(c)
	_decide(c)
	c.v = _speed_cap(c, 0.0)
	if not _spawn_clear(c):
		return
	_place(c)
	cars.append(c)
	spawned += 1


## Admission happens in the haze: never insert a car into a gap that already
## needs impossible braking. Include approaching followers and freight tails.
func _spawn_clear(c: Car) -> bool:
	var nearby: Array = cars.duplicate()
	var pod := _pod_as_car()
	if pod:
		nearby.append(pod)
	for o: Car in nearby:
		if o.road != c.road or o.dir != c.dir:
			continue
		var committed := o.lat if o.id == 0 else _lane_lat(o, o.lane)
		if c.lat < minf(o.lat, committed) - 25.0 or c.lat > maxf(o.lat, committed) + 25.0:
			continue
		var gap := (o.f - c.f) * c.dir * 24.0
		var leader: Car = o if gap >= 0.0 else c
		var follower: Car = c if gap >= 0.0 else o
		var closing := maxf(0.0, follower.v - leader.v)
		var tail := (TRAIN - 1) * TRAIN_GAP if leader.kind == TRANSPORT else 0.0
		var space := 40.0 + tail + maxf(100.0, follower.v * follower.headway * 0.5)
		space += closing * closing / (2.0 * BRAKE)
		if absf(gap) < space:
			return false
	return true


## The speed it can hold here: its grip in the curve, a city's STARFIGHTER cap.
func _limit(c: Car) -> float:
	var l: float = _vlim[c.road][clampi(int(c.f), 0, _vlim[c.road].size() - 1)]
	if l < 0.0:
		return -l
	return l * sqrt(c.a_lat / G)


## A gradual express fraction along the actual ramps. A shaft's climb is not another
## traffic tier: keep its entrance altitude, also for a carried recovery twist.
func _traffic_tier(road: int, f: float) -> float:
	var at := f
	if world.shaft.maps.has(road):
		var span: Dictionary = world.shaft.maps[road]
		if f >= float(span.i0) and f <= float(span.i1):
			at = float(span.i0)
	return smoothstep(120.0, 500.0, sim.net_height(road, at))


func _cruise_for(c: Car, express: float) -> float:
	var boost := 0.30 if c.kind == CAR else (0.10 if c.kind == DEMON else 0.0)
	return c.cruise * (1.0 + boost * express)


func _drive(c: Car, arr: Array, idx: int, delta: float) -> void:
	var R := sim.roads[c.road]
	var nl: int = _lanes[c.road].size()
	c.lc_cool = maxf(0.0, c.lc_cool - delta)
	c.flow_clock = maxf(0.0, c.flow_clock - delta)
	if c.nsp_road != c.road or c.nsp_dir != c.dir:
		_next_switch(c)
	# the speed it wants: its own, the curve's, and slow enough to brake (at BRAKE) for every limit up
	# to 50 km ahead (demons can reach full speed on the straight highways), and for the road
	# beyond the exit it's taking. Read every CAP_EVERY frames, as if from where it'll be by the next.
	if c.kind != RACER:
		_decide(c)
		if c.cruise > 0.0:
			if c.vcap_road != c.road or (_tick + c.id) % CAP_EVERY == 0:
				c.cruise_goal = _cruise_for(c, _traffic_tier(c.road, c.f))
			c.vdes = move_toward(c.vdes, c.cruise_goal, BRAKE * delta)
	if c.vcap_road != c.road or (_tick + c.id) % CAP_EVERY == 0:
		c.vcap = _speed_cap(c, CAP_EVERY * c.v * delta)
		c.vcap_road = c.road
	var vt := minf(c.vcap, c.vdes)
	if c.kind == RACER and race_state == "tail":
		vt = _tail_speed(c)
	# the one ahead in its lane
	var lead: Car = null
	var gap := INF
	# A busy adjacent lane must not hide the actual leader beyond nine entries.
	for k in range(idx + 1, arr.size()):
		var o: Car = arr[k]
		if o.road != c.road or o.dir != c.dir or (o.f - c.f) * c.dir <= 0.0:
			continue
		if absf(o.lat - c.lat) < 22.0:
			lead = o
			gap = (o.f - c.f) * c.dir * 24.0 - 20.0 * SCALE
			break
	if lead and gap < c.v * c.headway:
		c.flow_source = -1
		c.flow_notice = 0.0
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
			# A blocked gap does not improve sixty times a second. Keep braking at full
			# rate, but stagger another gap search; full safety scans stay inexpensive.
			if c.lc_cool <= 0.0:
				c.lc_cool = (0.22 if c.kind == DEMON or c.kind == RACER else 0.40) + float(c.id % 5) * 0.03
			vt = minf(vt, lead.v + (gap - c.v * c.headway * 0.5) / maxf(c.headway, 0.3))
	elif _courtesy(c, arr, idx):
		pass
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


## The fastest it can go here and still brake (at BRAKE) for every limit on its road up to 50 km on
## (down to each by the reading before it), each `margin` m nearer than it is.
func _brake_for(c: Car, margin := 0.0) -> float:
	var R := sim.roads[c.road]
	var vl: PackedFloat32Array = _vlim[c.road]   # (as an Array it would be converted: a copy every call)
	var vt := minf(c.vdes, _limit(c))
	var gs := sqrt(c.a_lat / G)   # (the same sums as before, with the constants out of the loop: ~200
	var n1: int = R.N - 1         # cars, a third of them a frame, fifteen readings each)
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


## Is the complete merge clear? A chosen destination is occupied before the body arrives.
## Full road bucket: eight cars in other lanes must not hide a fast ninth follower.
func _clear(arr: Array, idx: int, c: Car, lat_n: float) -> bool:
	var duration := absf(lat_n - c.lat) / (60.0 if c.kind == DEMON or c.kind == RACER else 30.0) + 0.6
	var swept_lo := minf(c.lat, lat_n) - c.right_width
	var swept_hi := maxf(c.lat, lat_n) + c.left_width
	var front_gap := c.v * c.headway * 1.3 + c.front
	var rear_gap := c.rear + 12.0
	var n := arr.size()
	for step in range(1, n):
		var offset := (step + 1) >> 1
		var k := idx + (offset if step % 2 == 1 else -offset)
		k = posmod(k, n)
		var o: Car = arr[k]
		if o.road != c.road or o.dir != c.dir:
			continue # a road switch or a direction normalization can leave a stale bucket entry
		var g: float = (o.f - c.f) * c.dir * 24.0
		var future := g + (o.v - c.v) * duration
		var tail := (TRAIN - 1) * TRAIN_GAP if o.kind == TRANSPORT else 0.0
		var unsafe_gap := minf(g, future) < front_gap + o.rear + tail if g > 0.0 else maxf(g, future) > -(rear_gap + o.front)
		if not unsafe_gap:
			continue
		var committed := o.lat if o.id == 0 else _lane_lat(o, o.lane)
		if swept_hi >= minf(o.lat, committed) - o.right_width - 10.0 and swept_lo <= maxf(o.lat, committed) + o.left_width + 10.0:
			return false
	return true


## Ordinary road manners: a persistent faster follower gets room if an adjacent gap exists.
## No player-specific steering, speed concession or last-second rescue. Racers and freight
## keep their established behavior; all of them can still be the approaching road user.
func _courtesy(c: Car, arr: Array, idx: int) -> bool:
	if c.kind == RACER or c.kind == TRANSPORT:
		return false
	if c.lc_cool > 0.0 or absf(c.lat - _lane_lat(c, c.lane)) > 1.0:
		c.flow_source = -1
		c.flow_notice = 0.0
		return false
	if c.flow_clock > 0.0:
		return false
	var glance := 0.30 + float(c.id % 3) * 0.021
	c.flow_clock = glance
	var lateral_speed := 60.0 if c.kind == DEMON else 30.0
	var maneuver := (45.0 if _lanes[c.road].size() == 8 else 50.0) / lateral_speed
	var protected_distance := c.v * (maneuver + 0.9) + 300.0
	var route_clear := true
	if c.nsp != null and (float(c.nsp[0]) - c.f) * c.dir * 24.0 < protected_distance:
		route_clear = false
	if world.shaft.maps.has(c.road):
		var sh: Dictionary = world.shaft.maps[c.road]
		var to_f := c.f + c.dir * protected_distance / 24.0
		if maxf(c.f, to_f) >= float(sh.i0) and minf(c.f, to_f) <= float(sh.i1):
			route_clear = false
	var follower: Car = null
	if route_clear:
		for k in range(idx - 1, -1, -1):
			var o: Car = arr[k]
			if o.road != c.road or o.dir != c.dir:
				continue
			var behind := (c.f - o.f) * c.dir * 24.0
			if behind > R_SPAWN.y:
				break
			var corridor_lo := o.lat - o.right_width - c.left_width - 18.0
			var corridor_hi := o.lat + o.left_width + c.right_width + 18.0
			if behind <= 0.0 or c.lat < corridor_lo or c.lat > corridor_hi:
				continue
			# The nearest vehicle in this corridor is the one actually approaching us.
			var closing := o.v - c.v
			if closing > 120.0:
				var catch_time := behind / closing
				if catch_time > maneuver + 0.9 and catch_time < 11.0:
					follower = o
			break
	if follower == null:
		c.flow_source = -1
		c.flow_notice = 0.0
		return false
	if c.flow_source != follower.id:
		c.flow_source = follower.id
		c.flow_notice = 0.0
		return false
	c.flow_notice += glance
	if c.flow_notice < 0.30 + float(c.id % 7) * 0.055:
		return false
	# Prefer the move that opens the largest gap, keeping right on a tie.
	# Commit once; do not mirror steering or repeatedly chase the follower's lane.
	var chosen := -1
	var clearance := 0.0
	for dl in [-1, 1]:
		var lane: int = c.lane + dl
		if lane < 0 or lane >= _lanes[c.road].size():
			continue
		var target := _lane_lat(c, lane)
		var gap := maxf(target - follower.lat - follower.left_width - c.right_width, follower.lat - target - follower.right_width - c.left_width)
		if gap > clearance and _clear(arr, idx, c, target):
			chosen = lane
			clearance = gap
	if chosen >= 0:
		c.lane = chosen
		c.lc_cool = 5.0 + float(c.id % 7) * 0.45
		c.flow_source = -1
		c.flow_notice = 0.0
		return true
	return false


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
	var R := sim.roads[c.road]
	var i := clampi(int(c.f), 0, R.N - 1)
	c.lat = (c.x - R.px[i]) * R.nx[i] + (c.y - R.py[i]) * R.ny[i]   # where it is across the new road
	c.lane = mini(c.lane, _lanes[c.road].size() - 1)
	c.plan = null
	c.decided = -1
	c.nsp_road = -1
	c.lc_cool = maxf(c.lc_cool, 3.0)
	c.flow_source = -1
	c.flow_notice = 0.0
	switched += 1


func _place(c: Car) -> void:
	var R := sim.roads[c.road]
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
		var R := sim.roads[cur.x]
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
	var P := sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var behind := _gap_to_pod(c)   # m the craft is ahead
	return clampf(pv + (behind - 160.0) * 0.6, 0.0, 6500.0 / MPH)


## How far ahead of the racer the craft is, along the racer's way (straight line projected).
func _gap_to_pod(c: Car) -> float:
	return (sim.pod.x - c.x) * c.hx + (sim.pod.y - c.y) * c.hy


func _race(delta: float, pod_car: Car) -> void:
	var P := sim.pod
	var pv := Vector2(P.vx, P.vy).length()
	var on_hwy: bool = sim.roads[P.path].w[0] >= 300.0 and _public_road(sim.roads[P.path])
	if race_state == "":
		if on_hwy and pv > 2000.0 / MPH:
			_hw_time += delta * lerpf(0.85, 1.30, _traffic_tier(P.path, float(P.hint)))
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
	var R := sim.roads[c.road]
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
	var bounds := AABB(Vector3(-40000, -100, -40000), Vector3(80000, 20000, 80000))
	for kind in FLEET.size():
		var batch := Batch.new()
		batch.name = "traffic_tractor" if kind == TRACTOR else "traffic_%d" % kind
		var slots := TARGET * (TRAIN - 1) if kind == TRANSPORT else TARGET + 8
		batch.configure(FLEET[kind], slots, 500.0, bounds, true, kind == RACER)
		add_child(batch)
		_mm[kind] = batch
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
	_beams.custom_aabb = AABB(Vector3(-40000, -100, -40000), Vector3(80000, 20000, 80000))
	add_child(_beams)


func _render() -> void:
	var ox: float = view.org_x
	var oy: float = view.org_y
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else Vector3.ZERO
	var nb := 0
	var bmm: MultiMesh = _beams.multimesh
	var pod_v := Vector2(sim.pod.vx, sim.pod.vy)
	for c in cars:
		var batch: Batch = _mm[c.kind]
		var h := 1.0 + sim.net_height(c.road, c.f) if sim._net_h.has(c.road) else 1.0
		var shaft_on: bool = sim.roads[c.road].shaft and world.shaft.on(c.road, c.f)
		# A road with a height profile (a hill, a ramp, a deck's approach): every body sits at its
		# own height and noses up or down with the grade. They used to stay level at the lead's
		# height, so a transport's train floated off a climb or sank into it (Luke: "busses look
		# hilarious half sticking out going up hills"). A level road costs nothing more.
		var graded: bool = grade and not shaft_on and sim._net_h.has(c.road)
		var last: float = sim.roads[c.road].N - 1.0
		var step: float = c.dir * TRAIN_GAP / 24.0   # samples from one body's centre to the next
		var h_ahead := h
		var h_here := h
		if graded:
			h_ahead = sim.net_height(c.road, clampf(c.f + step, 0.0, last)) + 1.0
		var cx: float = c.x + c.hx * c.v * c.owed   # where it is now (a far one not driven this frame: on along its way)
		var cy: float = c.y + c.hy * c.v * c.owed
		var yaw := atan2(-c.hx, c.hy)   # +z (the model's back) against the way it's going
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SCALE)
		if shaft_on:
			b = world.shaft.carry(c.road, c.f) * b
		var cnt := TRAIN if c.kind == TRANSPORT else 1
		var board: float = NUMBER_BOARDS.get(c.name, 0.0) if c.kind == RACER else 0.0
		for k in cnt:
			var back := k * TRAIN_GAP
			var p := Vector3(cx - c.hx * back - ox, h, -(cy - c.hy * back - oy))
			var body_basis := b
			if graded:
				# the grade under this body: from a body length ahead of it to one behind
				var h_behind: float = sim.net_height(c.road, clampf(c.f - step * (k + 1), 0.0, last)) + 1.0
				p.y = h_here
				body_basis = (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, atan((h_ahead - h_behind) / (2.0 * TRAIN_GAP)))).scaled(Vector3.ONE * SCALE)
				h_ahead = h_here
				h_here = h_behind
			if shaft_on:
				var f: float = c.f - c.dir * back / 24.0
				p = world.shaft.point(c.road, f, c.lat, 1.0, ox, oy)
				body_basis = world.shaft.frame(c.road, f) * Basis(Vector3.UP, PI if c.dir < 0 else 0.0)
				body_basis = body_basis.scaled(Vector3.ONE * SCALE)
			var unit: Batch = _mm[TRACTOR] if c.kind == TRANSPORT and k == 0 else batch
			unit.put(Transform3D(body_basis, p), eye, c.col, board)
		if nb < bmm.instance_count:
			# the light you see: its tail if it's going your way, its head lamps if it's coming at you
			var coming: bool = c.hx * pod_v.x + c.hy * pod_v.y < 0.0
			var off := -6.5 * SCALE if coming else 6.5 * SCALE + (cnt - 1) * TRAIN_GAP
			var lp := Vector3(cx - c.hx * off - ox, h + 1.2 * SCALE, -(cy - c.hy * off - oy))
			if graded:   # the lamp rides at its own end's height
				lp.y = sim.net_height(c.road, clampf(c.f - c.dir * off / 24.0, 0.0, last)) + 1.0 + 1.2 * SCALE
			if shaft_on:
				lp = world.shaft.point(c.road, c.f - c.dir * off / 24.0, c.lat, 1.0 + 1.2 * SCALE, ox, oy)
			bmm.set_instance_transform(nb, Transform3D(Basis(), lp))
			var lc := Color(1.0, 0.95, 0.85) if coming else (Color(1.0, 0.3, 0.9) if c.kind == RACER else Color(1.0, 0.15, 0.08))
			bmm.set_instance_color(nb, lc)
			nb += 1
	for kind in _mm:
		(_mm[kind] as Batch).finish_frame(_warm > 0)
	if _warm > 0:
		_warm -= 1
		if nb == 0:
			bmm.set_instance_transform(0, Transform3D(Basis(), Vector3(0.0, -60.0, -40.0)))
			nb = 1
	bmm.visible_instance_count = nb


## The near vehicles as the sims' obstacles: circles along each body (a train's cars each), with
## its velocity (the sim moves them between frames).
func _feed() -> void:
	if not collide or not sim.P.obstacleCollisions:
		sim.obstacles = []
		return
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var obs: Array = world.obstacles_near(px, py)
	for c in cars:
		if Vector2(c.x - px, c.y - py).length_squared() > R_FIELD * R_FIELD:
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
			var x: float = c.x - c.hx * back
			var y: float = c.y - c.hy * back
			var h: float = sim.net_height(c.road, c.f)
			# A level road's train is rigid at the lead's height. A shaft carries each car at its
			# own sample: project the collision footprint to that same sample in the flat sim. On a
			# graded road each part stands at its own height, as it is drawn (below).
			if world.shaft.on(c.road, c.f):
				var center_back := floorf(float(q) / 2.0) * TRAIN_GAP if c.kind == TRANSPORT else 0.0
				var f: float = c.f - c.dir * center_back / 24.0
				var R := sim.roads[c.road]
				var i := clampi(int(f), 0, R.N - 2)
				var t := clampf(f - i, 0.0, 1.0)
				var tangent := Vector2(lerpf(R.tx[i], R.tx[i + 1], t), lerpf(R.ty[i], R.ty[i + 1], t)).normalized()
				x = R.px[i] + R.tx[i] * R.len[i] * t - tangent.y * c.lat - tangent.x * c.dir * (back - center_back)
				y = R.py[i] + R.ty[i] * R.len[i] * t + tangent.x * c.lat - tangent.y * c.dir * (back - center_back)
				h = sim.net_height(c.road, f)
			elif grade and sim._net_h.has(c.road):
				h = sim.net_height(c.road, clampf(c.f - c.dir * back / 24.0, 0.0, sim.roads[c.road].N - 1.0))
			obs.append({"id": c.id * 32 + q, "r": parts[q][1], "x": x, "y": y,
				"vx": vx, "vy": vy, "zMin": h, "zMax": h + (9.6 if c.kind == TRANSPORT else 6.0)})
	sim.obstacles = obs


## The vehicles on the map: [[x, y, kind], ...] within r of (x, y).
func marks(x: float, y: float, r: float) -> Array:
	var out := []
	for c in cars:
		if absf(c.x - x) < r and absf(c.y - y) < r:
			out.append([c.x, c.y, c.kind])
	return out
