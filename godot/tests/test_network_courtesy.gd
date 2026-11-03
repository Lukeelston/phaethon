## Deterministic road-user scenarios: delayed courtesy, safe merge reservations and exceptions.
## Uses the real Network, traffic driver and road limits; never opens the player view or preferences.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const Traffic := preload("res://view/network_traffic.gd")
const DT := 1.0 / 60.0
var sim
var world
var traffic
var road := -1
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)


func _car(id: int, lane: int, f := 6000.0, direction := 1, kind := Traffic.CAR):
	var c = Traffic.Car.new()
	c.id = id
	c.kind = kind
	c.road = road
	c.dir = direction
	c.f = f
	c.lane = lane
	c.lat = traffic._lane_lat(c, lane)
	c.v = 1000.0
	c.vdes = 1000.0
	c.turn_p = 0.0
	traffic._next_switch(c)
	traffic._place(c)
	return c


func _follower(c, id := 0, gap := 4000.0, velocity := 1800.0):
	var o = _car(id, c.lane, c.f - c.dir * gap / 24.0, c.dir)
	o.v = velocity
	o.vdes = velocity
	return o


## Advance the subject with real driving. Other road users keep their prescribed test trajectories.
func _advance(c, others: Array, seconds: float) -> void:
	for frame in roundi(seconds / DT):
		var arr: Array = others.duplicate()
		arr.append(c)
		arr.sort_custom(func(a, b): return a.f * a.dir < b.f * b.dir)
		traffic._tick += 1
		traffic._drive(c, arr, arr.find(c), DT)
		for o in others:
			o.f += o.dir * o.v * DT / 24.0
			traffic._place(o)


func _approach(direction: int, follower_id: int) -> void:
	var c = _car(31, 3, 6000.0, direction)
	var follower = _follower(c, follower_id)
	var start: float = c.lat
	_advance(c, [follower], 0.2)
	_check("no instant dodge, direction %d follower %d" % [direction, follower_id], c.lane == 3 and is_equal_approx(c.lat, start))
	_advance(c, [follower], 1.2)
	_check("persistent faster follower gets one gradual adjacent move, direction %d follower %d" % [direction, follower_id], absi(c.lane - 3) == 1 and absf(c.lat - start) > 1.0 and absf(c.lat - start) < 44.0)
	var chosen: int = c.lane
	_advance(c, [follower], 2.2)
	_check("move completes without changing lane again", c.lane == chosen and absf(c.lat - start) > 44.0 and c.v >= 999.0)


func _run() -> void:
	sim = Sim.new({"track": "network", "obstacleCollisions": false})
	world = World.new()
	root.add_child(world)
	world.build(sim, null)
	traffic = Traffic.new()
	root.add_child(traffic)
	traffic.build(sim, {"org_x": 0.0, "org_y": 0.0}, world)
	for r in sim.roads.size():
		if sim.roads[r].name == "E2":
			road = r
	_check("real E2 fixture exists", road >= 0)
	_approach(1, 0)
	_approach(1, 72)
	_approach(-1, 0)
	var c = _car(31, 3)
	_advance(c, [_follower(c, 0, 16000.0, 5500.0)], 1.4)
	_check("very fast distant follower is noticed while a gradual move is still possible", absi(c.lane - 3) == 1)
	c = _car(31, 3)
	_advance(c, [_follower(c, 0, 900.0)], 0.6)
	_check("late closer does not provoke a last-second dodge or brake", c.lane == 3 and c.v >= 999.0)
	c = _car(31, 3)
	_advance(c, [_follower(c), _car(2, 2, 6001.0), _car(3, 4, 6001.0)], 1.4)
	_check("occupied adjacent lanes keep the car in its lane", c.lane == 3 and c.v >= 999.0)
	c = _car(31, 3)
	var claim = _car(2, 1, 6001.0)
	claim.lane = 2 # physically in lane 1, already committed to lane 2
	_check("committed destination reserves its gap before the body reaches it", not traffic._clear([c, claim], 0, c, traffic._lane_lat(c, 2)))
	var fast = _follower(c, 80, 1400.0, 2600.0)
	fast.lane = 2
	fast.lat = traffic._lane_lat(fast, 2)
	var arr: Array = [fast]
	for i in 10:
		arr.append(_car(100 + i, 6, c.f - (1200.0 - i * 100.0) / 24.0))
	arr.append(c)
	_check("fast destination follower beyond eight neighbors prevents a cut-in", not traffic._clear(arr, arr.size() - 1, c, traffic._lane_lat(c, 2)))
	for kind in [Traffic.RACER, Traffic.TRANSPORT]:
		c = _car(31, 3, 6000.0, 1, kind)
		_advance(c, [_follower(c)], 1.4)
		_check("racers race and freight keeps its established lane: kind %d" % kind, c.lane == 3)
	c = _car(31, 3)
	var receding = _follower(c, 0, 4000.0, 900.0)
	_advance(c, [receding], 1.4)
	_check("slower follower does not request a move", c.lane == 3)
	var regular_road := road
	var sh: Array = sim.shafts[0]
	road = int(sh[0])
	c = _car(31, 3, lerpf(sh[1], sh[2], 0.5))
	_advance(c, [_follower(c)], 1.4)
	_check("no discretionary move on a carried shaft", c.lane == 3)
	road = regular_road
	for sp in traffic._switch[road]:
		if int(sp[1]) == 1 and not sp[5]:
			c = _car(31, 3, float(sp[0]) - 1700.0 / 24.0)
			_advance(c, [_follower(c)], 1.0)
			_check("junction approach retains its lane", c.lane == 3)
			break
	_tiers()
	_dense_cost()
	print("NETWORK COURTESY %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


## Sample the actual lower E2 and elevated N2 through the same spawn pipeline.
func _sample_tier() -> Dictionary:
	traffic.cars.clear()
	traffic._rng.seed = 81031
	traffic.proad = road
	traffic.pdir = 1
	var R = sim.roads[road]
	for attempt in 5000:
		traffic._spawn(R.px[6500], R.py[6500], true)
		if traffic.cars.size() >= 400:
			break
	var count := [0, 0, 0, 0, 0]
	var cruise := 0.0
	for c in traffic.cars:
		count[c.kind] += 1
		if c.kind == Traffic.CAR:
			cruise += c.vdes
	return {"count": count, "cruise": cruise / maxf(1, count[Traffic.CAR])}


func _tiers() -> void:
	var lower_road := road
	var low := _sample_tier()
	for r in sim.roads.size():
		if sim.roads[r].name == "N2":
			road = r
	var saved: Array = sim._net_h.get(road, [])
	_check("tier fixture uses an actual elevated N2 road", sim.net_height(road, 6500.0) > 550.0 and sim.net_height(lower_road, 6500.0) < 120.0)
	var upper := _sample_tier()
	_check("upper express deck attracts more hot rods than the lower deck: %s vs %s" % [upper.count, low.count], upper.count[Traffic.DEMON] > low.count[Traffic.DEMON] * 2)
	_check("lower deck has more shuttles and freight", low.count[Traffic.SLOW] + low.count[Traffic.TRANSPORT] > upper.count[Traffic.SLOW] + upper.count[Traffic.TRANSPORT])
	_check("express commuters have higher cruising speed", upper.cruise > low.cruise * 1.2)
	var commuter = null
	for c in traffic.cars:
		if c.kind == Traffic.CAR and c.road == road:
			commuter = c
			break
	_check("express sample includes a commuter on N2 itself", commuter != null)
	if commuter != null:
		var initial: float = commuter.vdes
		var actual: float = commuter.v
		sim._net_h[road] = [[0, 0.0, 0.0], [sim.roads[road].N - 1, 0.0, 0.0]]
		_advance(commuter, [], DT)
		_check("leaving express deck cannot teleport actual or desired speed", absf(commuter.v - actual) < 1.1 and absf(commuter.vdes - initial) < 1.1)
		_advance(commuter, [], 10.0)
		_check("express commuter gradually settles into lower-deck cruise: %.1f to %.1f m/s" % [initial, commuter.vdes], commuter.vdes < initial * 0.85)
	sim._net_h[road] = saved
	road = lower_road
	traffic.cars.clear()


func _dense_cost() -> void:
	traffic.cars.clear()
	traffic._warm = 0
	traffic._hw_time = -1000.0
	var R = sim.roads[road]
	# Deliberately dense, high-speed express traffic, with many faster followers.
	for i in 220:
		var c = _car(1000 + i, i % 8, 6000.0 + float(i / 8) * 1100.0 / 24.0)
		c.v = 1000.0 if i % 3 else 1800.0
		c.vdes = c.v
		c.cruise = c.v
		c.cruise_goal = c.v
		traffic.cars.append(c)
	var total := 0.0
	var count := 0
	for frame in 180:
		var f := 6500.0 + float(frame) * 2000.0 * DT / 24.0
		var at := int(f)
		sim.respawn_on(road, at, 1)
		for b in sim.bodies:
			b.vx = 2000.0 * R.tx[at]
			b.vy = 2000.0 * R.ty[at]
		traffic.view.org_x = sim.pod.x
		traffic.view.org_y = sim.pod.y
		traffic.update(DT)
		if frame >= 60:
			total += traffic.update_ms
			count += 1
	var mean := total / count
	_check("dense fast traffic stays below 2.5 ms: %.3f ms, %d vehicles" % [mean, traffic.cars.size()], mean < 2.5 and traffic.cars.size() >= 100)
