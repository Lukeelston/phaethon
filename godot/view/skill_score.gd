## Local skill chains. Simulation time, real contacts and swept passes drive rewards;
## UI/audio consume feedback and never decide whether a skill happened.
extends RefCounted

const MPH := 2.236936
var sim
var path := ""
var total := 0
var best := 0
var multiplier := 1.0
var award_text := ""
var feedback: Array = []
var time := 0.0
var chain := 0
var _chain_until := 0.0
var _notice_until := 0.0
var _bad_until := 0.0
var _speed_time := 0.0
var _speed_notice := 0.0
var _save_at := 10.0
var _saved_best := 0
var _previous := Vector2.ZERO
var _heading := 0.0
var _turn := 0.0
var _turn_time := 0.0
var _turn_peak := 0.0
var _air_since := -1.0
var _air_duration := 0.0
var _landing := false
var _settled := 0.0
var _cars := {}
var _paid := {}
var _previous_bodies: Array = []

func setup(s, best_path: String) -> void:
	sim = s
	path = best_path
	if path != "" and FileAccess.file_exists(path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary and (saved.get("best") is float or saved.get("best") is int):
			best = maxi(0, int(saved.best))
	_saved_best = best
	_previous = Vector2(sim.pod.x, sim.pod.y)
	_heading = sim.pod.th

func save_best() -> void:
	best = maxi(best, total)
	if path == "" or best <= _saved_best:
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"best": best}))
		_saved_best = best
	else:
		push_warning("Could not save skill best: " + path)

func reset_run() -> void:
	save_best()
	total = 0
	chain = 0
	multiplier = 1.0
	time = 0.0
	_chain_until = 0.0
	_bad_until = 0.0
	_notice_until = 0.0
	_speed_time = 0.0
	_speed_notice = 0.0
	_save_at = 10.0
	award_text = ""
	feedback.clear()
	_paid.clear()
	_clear_motion()

func _clear_motion() -> void:
	_previous = Vector2(sim.pod.x, sim.pod.y)
	_heading = sim.pod.th
	_turn = 0.0
	_turn_time = 0.0
	_turn_peak = 0.0
	_air_since = -1.0
	_landing = false
	_settled = 0.0
	_cars.clear()
	_previous_bodies.clear()

func _clean() -> bool:
	if time < _bad_until or sim.crash_t > 0.0 or sim.binder_broken:
		return false
	for body in sim.bodies:
		if body.off_road or body.contact.has(true) or not body.touch.is_empty():
			return false
	return true

func _award(kind: String, label: String, points: int, skill := true) -> void:
	if skill:
		chain += 1
		multiplier = minf(5.0, 1.0 + floorf(chain / 3.0) * 0.5)
		_chain_until = time + 7.0
	var earned := maxi(1, roundi(points * multiplier))
	total += earned
	best = maxi(best, total)
	if kind == "speed" and (time < _speed_notice or time < _notice_until):
		return
	if kind == "speed":
		_speed_notice = time + 8.0
	award_text = "%s  +%d" % [label, earned]
	_notice_until = time + 2.4
	feedback.append({"kind": kind, "points": earned, "multiplier": multiplier})
	if feedback.size() > 8:
		feedback.pop_front()

func on_event(event: Dictionary) -> void:
	var kind: String = event.type
	if kind in ["hit", "scrape", "bump", "smash", "crash", "ground"]:
		chain = 0
		multiplier = 1.0
		_bad_until = time + 2.0
		_turn = 0.0
		_landing = false
		_air_since = -1.0
		for entry in _cars.values():
			entry.blocked = true
	elif kind == "airborne" and event.get("lip", false) and _air_since < 0.0:
		_air_since = time
	elif kind == "catch" and _air_since >= 0.0:
		_air_duration = time - _air_since
		_landing = _air_duration >= 0.5
		_settled = 0.0
		_air_since = -1.0

func step(dt: float) -> void:
	if dt <= 0.0:
		return
	time += dt
	if time > _chain_until:
		chain = 0
		multiplier = 1.0
	if time > _notice_until:
		award_text = ""
	var P = sim.pod
	var pos := Vector2(P.x, P.y)
	var velocity := Vector2(P.vx, P.vy)
	var speed := velocity.length()
	var heading: float = velocity.angle() if speed > 1.0 else P.th
	var warped := pos.distance_to(_previous) > speed * dt * 1.5 + 40.0
	if warped:
		_clear_motion()
		_speed_time = 0.0
		chain = 0
		multiplier = 1.0
	var clean := _clean() and not warped
	var mph := speed * MPH
	if clean and mph >= 1000.0:
		_speed_time += dt
		if _speed_time >= 1.0:
			_speed_time -= 1.0
			_award("speed", "VELOCITY", mini(100, roundi(18.0 * log(1.0 + mph / 1000.0))), false)
	else:
		_speed_time = 0.0
	var turn := wrapf(heading - _heading, -PI, PI)
	var aligned := absf(wrapf(P.th - heading, -PI, PI)) < 0.12
	var steady := absf(turn / dt) > 0.003 and absf(turn / dt) < 0.7
	if clean and aligned and steady and mph > 800.0:
		if turn * _turn < 0.0:
			_turn = 0.0
			_turn_time = 0.0
			_turn_peak = speed
		_turn += turn
		_turn_time += dt
		_turn_peak = maxf(_turn_peak, speed)
		if absf(_turn) >= deg_to_rad(18.0) and _turn_time >= 1.0:
			if speed >= _turn_peak * 0.72:
				_award("turn", "CLEAN ARC" if mph < 3500.0 else "HIGH-SPEED PRECISION", mini(1200, roundi(150.0 + mph * 0.075)))
			_turn = 0.0
			_turn_time = 0.0
			_turn_peak = speed
	else:
		_turn = 0.0
		_turn_time = 0.0
		_turn_peak = speed
	if _landing:
		var supported := clean
		for body in sim.bodies:
			supported = supported and not body.lock
		_settled = _settled + dt if supported else 0.0
		if _settled >= 0.4:
			_award("jump", "STUCK THE LANDING", mini(1400, roundi(250.0 + _air_duration * 40.0 + mph * 0.06)))
			_landing = false
	_previous = pos
	_heading = heading
	if time >= _save_at:
		save_best()
		_save_at = time + 10.0

func _body_points() -> Array:
	var points := []
	for body in sim.bodies:
		var length: float = sim.P.podLen if body == sim.pod else sim.P.engineLen
		var forward := Vector2(cos(body.th), sin(body.th))
		for along in [-1.0, 0.0, 1.0]:
			points.append([Vector2(body.x, body.y) + forward * along * maxf(0.0, length / 2.0 - 1.2), body.z, 1.2])
	return points

static func _point_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var v := b - a
	var u := clampf((p - a).dot(v) / maxf(v.length_squared(), 1e-12), 0.0, 1.0)
	return p.distance_to(a + v * u)

static func _segment_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r := b - a
	var s := d - c
	var cross := r.cross(s)
	if absf(cross) > 1e-9:
		var u := (c - a).cross(r) / cross
		var t := (c - a).cross(s) / cross
		if u >= 0.0 and u <= 1.0 and t >= 0.0 and t <= 1.0:
			return 0.0
	return minf(minf(_point_distance(a, c, d), _point_distance(b, c, d)), minf(_point_distance(c, a, b), _point_distance(d, a, b)))

## Full body swept clearances prevent fast passes tunnelling between frame samples.
func observe_traffic(cars: Array, dt: float) -> void:
	var points := _body_points()
	var P = sim.pod
	var pos := Vector2(P.x, P.y)
	var speed := Vector2(P.vx, P.vy).length()
	var fw := Vector2(P.vx, P.vy).normalized()
	var usable := dt > 0.0 and dt <= 0.25 and _clean() and speed * MPH > 800.0 and _previous_bodies.size() == points.size()
	if usable and points[6][0].distance_to(_previous_bodies[6][0]) > speed * dt * 1.5 + 40.0:
		usable = false
		_cars.clear()
	for c in cars:
		var car_pos := Vector2(c.x, c.y)
		if pos.distance_squared_to(car_pos) > pow(1200.0 + speed * dt, 2.0):
			continue
		var along := (car_pos - pos).dot(fw)
		var entry: Dictionary = _cars.get(c.id, {"pos": car_pos, "along": along, "near": INF, "blocked": false, "approached": along > 60.0, "time": time})
		var h: float = sim.net_deck(c.road, c.f, c.lat)
		var valid: bool = usable and _cars.has(c.id) and time - entry.time <= 0.5 and car_pos.distance_to(entry.pos) <= c.v * dt * 1.5 + 40.0
		if valid:
			var heading := Vector2(c.hx, c.hy)
			var radius := 8.4 if c.kind == 3 else (6.4 if c.kind == 1 else 5.2)
			var front := 9.0 if c.kind == 3 else (8.0 if c.kind == 1 else 7.0)
			var rear := front + (266.0 if c.kind == 3 else 0.0)
			for i in points.size():
				if minf(points[i][1], _previous_bodies[i][1]) > h + 12.0 or maxf(points[i][1], _previous_bodies[i][1]) < h - 2.0:
					continue
				var clearance: float = _segment_distance(_previous_bodies[i][0] - entry.pos, points[i][0] - car_pos, -heading * rear, heading * front) - radius - points[i][2]
				entry.near = minf(entry.near, clearance)
				if clearance <= 0.0:
					entry.blocked = true
			var all_past := true
			for point in points:
				all_past = all_past and (car_pos - point[0]).dot(fw) < -30.0
			if entry.approached and all_past and speed - c.v > 50.0 and not _paid.has(c.id):
				if not entry.blocked and entry.near > 0.5 and entry.near < 25.0:
					_award("near", "THREAD THE NEEDLE" if entry.near < 8.0 else "CLOSE CALL", mini(1600, roundi(180.0 + speed * MPH * 0.07 + (25.0 - entry.near) * 12.0)))
				_paid[c.id] = time
		elif _cars.has(c.id):
			entry.blocked = true
		entry.pos = car_pos
		entry.along = along
		entry.time = time
		_cars[c.id] = entry
	for id in _cars.keys():
		if time - _cars[id].time > 2.0:
			_cars.erase(id)
	for id in _paid.keys():
		if time - _paid[id] > 120.0:
			_paid.erase(id)
	_previous_bodies = points

func readout() -> String:
	return "%d PTS   x%.1f   BEST %d\n%s" % [total, multiplier, best, award_text]
