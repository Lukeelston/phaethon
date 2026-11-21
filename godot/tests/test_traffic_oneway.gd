## Nothing comes at the pilot on a road it may be about to join (Luke, after the eleventh flight:
## "oncoming traffic appears until you're on their road, so they're still a collision risk";
## view/network_traffic.gd `oneway`):
##   ahead     under way on a highway, every road that highway hands on to ahead of the craft is one-way,
##             the way a craft joining it would go; a road behind the craft is not
##   cleared   traffic already on those roads going the other way is turned round (far off) or taken away (near)
##   kept      and none appears there the wrong way afterwards, through two minutes of driving and spawning
## Prints TRAFFIC ONE-WAY PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Outlook := preload("res://view/outlook.gd")
const Livery := preload("res://view/livery.gd")
const Chase := preload("res://view/network_chase.gd")
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_traffic_oneway_")
	Outlook.pinned = true
	Livery.pinned = true
	Chase.pinned = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _wrong(T) -> Array:
	var out := []
	for c in T.cars:
		if T.oneway.has(c.road) and c.dir != int(T.oneway[c.road]):
			out.append([c.road, int(c.f), c.dir])
	return out


func _run() -> void:
	var v = View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	var sim = v.sim
	var T = v.traffic_net
	var road: int = sim.pod.path
	var R = sim.roads[road]
	# under way: 1,000 m/s up the road
	for body in sim.bodies:
		body.vx = R.tx[sim.pod.hint] * 1000.0
		body.vy = R.ty[sim.pod.hint] * 1000.0
	# traffic going the wrong way on every road this one hands on to ahead, put there by hand
	var targets := {}
	var behind := {}
	for sp in T._switch[road]:
		if int(sp[1]) != 1:
			continue
		if float(sp[0]) > float(sim.pod.hint):
			if not targets.has(int(sp[2])):
				targets[int(sp[2])] = int(sp[4])
		elif not behind.has(int(sp[2])):
			behind[int(sp[2])] = int(sp[4])
	for key in targets:
		behind.erase(key)
	var planted := 0
	for to_road in targets:
		var Rt = sim.roads[to_road]
		for k in 6:
			var c = T.Car.new()
			c.id = 800000 + planted
			c.kind = T.CAR
			c.road = to_road
			c.dir = -int(targets[to_road])
			c.f = float(clampi(40 + k * 60, 2, Rt.N - 3))
			c.lane = k % T._lanes[to_road].size()
			c.lat = T._lane_lat(c, c.lane)
			c.v = 900.0
			c.vdes = 900.0
			c.cruise = 900.0
			T._place(c)
			T.cars.append(c)
			planted += 1
	var before: int = T.cars.size()
	T.update(1.0 / 120.0)
	var listed := true
	for to_road in targets:
		listed = listed and T.oneway.get(to_road, 0) == int(targets[to_road])
	var not_behind := true
	for to_road in behind:
		not_behind = not_behind and not T.oneway.has(to_road)
	_check("under way on %s: its own way %d, and the %d roads it hands on to ahead are one-way the way a craft joining would go (%s); the %d only behind it are left alone (%s)" % [
			R.name, int(T.oneway.get(road, 0)), targets.size(), listed, behind.size(), not_behind],
		int(T.oneway.get(road, 0)) == 1 and targets.size() >= 3 and listed and not_behind)
	var wrong := _wrong(T)
	_check("the %d vehicles put on those roads the wrong way are turned round or gone at once (%d of %d vehicles left, wrong way now: %s)" % [planted, T.cars.size(), before, wrong.slice(0, 4)],
		planted >= 18 and wrong.is_empty())
	# two minutes of traffic: spawning, driving, taking exits
	var worst := 0
	for frame in 14400:
		T.update(1.0 / 120.0)
		if frame % 40 == 0:
			worst = maxi(worst, _wrong(T).size())
	_check("through two minutes of traffic none appears on them the wrong way (most at once: %d; %d vehicles about)" % [worst, T.cars.size()], worst == 0 and T.cars.size() > 20)
	v.queue_free()
	print("TRAFFIC ONE-WAY %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
