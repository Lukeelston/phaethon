## Traffic keeps, marks and lists hostile cars (Raids, task 2; view/network_traffic.gd `Car.hostile`):
##   far       a hostile car 25 km off is still kept after two seconds; a plain car there is gone (R_KEEP)
##   flip      a hostile oncoming on the pilot's road inside FLIP_FAR keeps its way and its place after a regroup
##   marks     marks() gives it HOSTILE_MARK, and every other car its own kind
##   pick      ray_pick from 600 m behind along its road hits it
##   list      hostiles() is exactly the hostile cars
##   lamp      its lamp is HOSTILE_LAMP
## With none about, traffic is as it was (the parity tests).
## Prints RAID TRAFFIC PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Outlook := preload("res://view/outlook.gd")
const Livery := preload("res://view/livery.gd")
const Chase := preload("res://view/network_chase.gd")
const STEP := 1.0 / 120.0
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_raid_traffic_")
	Outlook.pinned = true
	Livery.pinned = true
	Chase.pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## A car of its own on `road` at sample `f`, going `dir`, in the lane it is given, at speed.
func _car(T, id: int, road: int, f: float, dir: int, lane: int, hostile: bool):
	var c = T.Car.new()
	c.id = id
	c.kind = T.CAR
	c.road = road
	c.dir = dir
	c.f = f
	c.lane = clampi(lane, 0, T._lanes[road].size() - 1)
	c.lat = T._lane_lat(c, c.lane)
	c.v = 900.0
	c.vdes = 900.0
	c.cruise = 900.0
	c.hostile = hostile
	T._place(c)
	return c


## A public road with a sample about `away` m from (px, py): [road, sample], or [].
func _far_spot(sim, T, px: float, py: float, away: float, skip: int) -> Array:
	for r in sim.roads.size():
		var R = sim.roads[r]
		if r == skip or not T._public_road(R) or R.shaft:
			continue
		for i in range(2, R.N - 2, 8):
			var d := Vector2(R.px[i] - px, R.py[i] - py).length()
			if absf(d - away) < 300.0:
				return [r, i]
	return []


func _run() -> void:
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	var T = v.traffic_net
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var hint: int = sim.pod.hint
	# under way: 1,000 m/s up the road, so the pilot's road is one-way (the flip's case)
	for body in sim.bodies:
		body.vx = R.tx[hint] * 1000.0
		body.vy = R.ty[hint] * 1000.0
	T.cars.clear()
	T.update(STEP)
	var px: float = sim.pod.x
	var py: float = sim.pod.y

	# far: 25 km off, a hostile stays, a plain car goes
	var spot := _far_spot(sim, T, px, py, 25000.0, road)
	var far_h = null
	var far_p = null
	if spot.size() == 2:
		far_h = _car(T, 900001, spot[0], float(spot[1]), 1, 0, true)
		far_p = _car(T, 900002, spot[0], float(spot[1] + 4), 1, 1, false)
		T.cars.append(far_h)
		T.cars.append(far_p)
	for k in 240:
		T.update(STEP)
	var dist := Vector2(far_h.x - px, far_h.y - py).length() if far_h else 0.0
	_check("a hostile %.1f km off is kept after 2 s (%s); the plain car there is gone (%s)" % [dist / 1000.0, T.cars.has(far_h), not T.cars.has(far_p)],
		far_h != null and dist > T.R_KEEP and T.cars.has(far_h) and not T.cars.has(far_p))
	T.cars.erase(far_h)

	# flip: oncoming on the pilot's road, inside FLIP_FAR
	var ahead := hint + int(1500.0 / 24.0)
	var way: int = int(T.oneway.get(road, 1))
	var onc = _car(T, 900003, road, float(ahead), -way, 2, true)
	var plain_onc = _car(T, 900004, road, float(ahead + 6), -way, 3, false)
	T.cars.append(onc)
	T.cars.append(plain_onc)
	T.cars.append(_car(T, 900005, road, float(ahead + 40), way, 4, false))     # (the count changes: a regroup)
	for k in 5:
		T.update(STEP)
	_check("a hostile oncoming 1.5 km ahead on the pilot's road keeps its way (%d, was %d) and stays (%s); the plain one is cleared (%s)" % [onc.dir, -way, T.cars.has(onc), not T.cars.has(plain_onc)],
		T.cars.has(onc) and onc.dir == -way and not T.cars.has(plain_onc))

	# marks
	var marks: Array = T.marks(px, py, 40000.0)
	var hostile_marks := 0
	var plain_ok := true
	for m in marks:
		if int(m[2]) == T.HOSTILE_MARK:
			hostile_marks += 1
	for c in T.cars:
		if c.hostile:
			continue
		var found := false
		for m in marks:
			if is_equal_approx(m[0], c.x) and is_equal_approx(m[1], c.y) and int(m[2]) == c.kind:
				found = true
		plain_ok = plain_ok and found
	_check("marks() gives HOSTILE_MARK (%d) for the hostile (%d of them) and the plain kind for the others (%s)" % [T.HOSTILE_MARK, hostile_marks, plain_ok],
		hostile_marks == 1 and plain_ok and T.HOSTILE_MARK == 9)

	# pick: nothing else on the road to be in the way
	T.cars.clear()
	var target = _car(T, 900006, road, float(hint + 80), way, 3, true)
	T.cars.append(target)
	var lone = _car(T, 900007, road, float(hint + 200), way, 3, false)
	T.cars.append(lone)
	T.update(STEP)
	var o := Vector3(target.x - target.hx * 600.0, target.y - target.hy * 600.0, T._drawing.height(target.road, target.f) + 3.0)
	var hit: Dictionary = T.ray_pick(o, Vector3(target.hx, target.hy, 0.0), 2000.0)
	_check("ray_pick from 600 m behind along its road hits the hostile (%s, t %.0f)" % [hit.get("car") == target, float(hit.get("t", -1.0))],
		not hit.is_empty() and hit["car"] == target and float(hit["t"]) > 400.0)

	# list
	var listed: Array = T.hostiles()
	var second = _car(T, 900008, road, float(hint + 120), way, 2, true)
	T.cars.append(second)
	var listed2: Array = T.hostiles()
	_check("hostiles() is exactly the hostile cars (%d, then %d with another)" % [listed.size(), listed2.size()],
		listed.size() == 1 and listed[0] == target and listed2.size() == 2 and listed2.has(target) and listed2.has(second) and not listed2.has(lone))

	# the lamp: a hostile's own colour
	T.update(STEP)
	v._process(STEP)
	await process_frame
	_check("a hostile car's lamp is HOSTILE_LAMP (%s), a plain one's is not (%s)" % [target.lamp_color, lone.lamp_color],
		target.lamp_color.is_equal_approx(T.HOSTILE_LAMP) and not lone.lamp_color.is_equal_approx(T.HOSTILE_LAMP))
	v.queue_free()
	print("RAID TRAFFIC %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
