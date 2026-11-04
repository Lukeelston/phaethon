## Prescribed real road trajectories exercise the partner's actual frame updates.
extends SceneTree
const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
var failures := 0
var checks := 0
var view
var road := -1
const DT := 1.0 / 60.0

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	_run.call_deferred()

func pose(f: float, direction: int, speed := 1000.0) -> void:
	var s = view.sim
	var R = s.roads[road]
	var i := int(f)
	s.respawn_on(road, i, direction)
	s.pair_th = atan2(R.ty[i] * direction, R.tx[i] * direction)
	for b in s.bodies:
		b.x += R.tx[i] * (f - i) * 24.0
		b.y += R.ty[i] * (f - i) * 24.0
		b.vx = R.tx[i] * speed * direction
		b.vy = R.ty[i] * speed * direction
	view._follow_origin()

func scenario(direction: int, obstacle: bool) -> void:
	view.set_partner(false)
	pose(6000.0, direction)
	view.traffic_net.cars.clear()
	view.set_partner(true)
	var p = view.partner
	var maximum := -INF
	var minimum := INF
	var left := false
	var right := false
	var clearance := INF
	var max_relative_step := 0.0
	var previous := Vector2(p.x, p.y)
	var old_pod := Vector2(view.sim.pod.x, view.sim.pod.y)
	for frame in 3600:
		var f := 6000.0 + direction * frame * DT * 1000.0 / 24.0
		pose(f, direction)
		var s = view.sim
		var R = s.roads[road]
		if obstacle:
			var c = Traffic.Car.new()
			c.id = 900
			c.road = road
			c.dir = direction
			c.f = f + direction * 105.0 / 24.0
			c.lat = 60.0 * direction
			c.v = 1000.0
			view.traffic_net._place(c)
			view.traffic_net.cars.assign([c])
		p.update(DT)
		var fw := Vector2(R.tx[int(f)], R.ty[int(f)]) * direction
		var offset := Vector2(p.x - s.pod.x, p.y - s.pod.y)
		var ahead := offset.dot(fw)
		var lateral := offset.dot(Vector2(-fw.y, fw.x))
		maximum = maxf(maximum, ahead)
		if frame > 1800:
			minimum = minf(minimum, ahead)
		left = left or lateral > 35.0
		right = right or lateral < -35.0
		for b in s.bodies:
			clearance = minf(clearance, Vector2(p.x - b.x, p.y - b.y).length())
		if obstacle:
			var c = view.traffic_net.cars[0]
			clearance = minf(clearance, Vector2(p.x - c.x, p.y - c.y).length() - 24.0)
		var position := Vector2(p.x, p.y)
		var pod := Vector2(s.pod.x, s.pod.y)
		if frame > 0:
			max_relative_step = maxf(max_relative_step, (position - previous - (pod - old_pod)).length())
		previous = position
		old_pod = pod
	check("partner speeds well ahead %d obstacle=%s (%.1f m)" % [direction, obstacle, maximum], maximum > 180.0)
	check("partner returns close enough to be a reference (%.1f m)" % minimum, minimum < 60.0)
	check("partner goes around to both sides when clear", (left and right) or obstacle)
	check("player and traffic keep visible clearance %.2f m" % clearance, clearance > 18.0)
	check("ordinary maneuvers are continuous %.2f m/frame" % max_relative_step, max_relative_step < 8.0)

func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	for r in view.sim.roads.size():
		if view.sim.roads[r].name == "E2":
			road = r
	check("real wide road available", road >= 0)
	scenario(1, false)
	scenario(-1, false)
	scenario(1, true)
	pose(6000.0, 1)
	var p = view.partner
	view.traffic_net.cars.clear()
	var R = view.sim.roads[road]
	var half: float = R.w[6000] / 2.0
	for b in view.sim.bodies:
		b.x += R.nx[6000] * (half - 30.0)
		b.y += R.ny[6000] * (half - 30.0)
	var target: Vector2 = p._point(0.0, 72.0)
	var lat: float = (target.x - R.px[6000]) * R.nx[6000] + (target.y - R.py[6000]) * R.ny[6000]
	check("moving player cannot pull partner outside road edge", lat <= half - 25.0)
	pose(6000.0, 1)
	p._ahead = 14.0
	p._offset = 48.0
	var crossing = Traffic.Car.new()
	crossing.id = 901
	crossing.road = (road + 2) % view.sim.roads.size()
	crossing.f = 6000.0
	crossing.v = 1000.0
	crossing.hx = R.tx[6000]
	crossing.hy = R.ty[6000]
	crossing.x = view.sim.pod.x + R.tx[6000] * 100.0 + R.nx[6000] * 60.0
	crossing.y = view.sim.pod.y + R.ty[6000] * 100.0 + R.ny[6000] * 60.0
	var saved_height = view.sim._net_h.get(crossing.road, null)
	view.sim._net_h[crossing.road] = [[0, 0.0, 0.0], [view.sim.roads[crossing.road].N - 1, 0.0, 0.0]]
	view.traffic_net.cars.assign([crossing])
	check("same-level joining traffic blocks a pass", not p._target_clear(280.0, 72.0))
	view.sim._net_h[crossing.road] = [[0, 600.0, 0.0], [view.sim.roads[crossing.road].N - 1, 600.0, 0.0]]
	check("traffic on another deck does not block a pass", p._target_clear(280.0, 72.0))
	if saved_height == null:
		view.sim._net_h.erase(crossing.road)
	else:
		view.sim._net_h[crossing.road] = saved_height
	view.sim.pod.off_road = true
	check("partner suspends passing while airborne", not p._can_pass())
	view.sim.pod.off_road = false
	var saved_width: float = R.w[6012]
	R.w[6012] = 200.0
	check("partner suspends passing on narrow approach", not p._can_pass())
	R.w[6012] = saved_width
	view.free()
	View.track_override = ""
	View.job_override = ""
	print("PARTNER MANEUVERS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
