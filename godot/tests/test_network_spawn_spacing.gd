## New traffic must enter a usable gap; cars in other lanes cannot hide a leader.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const Traffic := preload("res://view/network_traffic.gd")
var traffic
var road := -1
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func car(id: int, f: float, speed: float, direction := 1, lane := 3):
	var c = Traffic.Car.new()
	c.id = id
	c.road = road
	c.f = f
	c.v = speed
	c.vdes = speed
	c.dir = direction
	c.lane = lane
	c.lat = traffic._lane_lat(c, lane)
	c.turn_p = 0.0
	c.lc_cool = 10.0
	traffic._next_switch(c)
	traffic._place(c)
	return c

func _run() -> void:
	var sim = Sim.new({"track":"network"})
	var world = World.new()
	root.add_child(world)
	world.build(sim, null)
	traffic = Traffic.new()
	root.add_child(traffic)
	traffic.build(sim, {"org_x":0.0,"org_y":0.0}, world)
	for r in sim.roads.size():
		if sim.roads[r].name == "E2":
			road = r
	check("spawn admission checks exist", traffic.has_method("_spawn_clear"))
	for direction in [1, -1]:
		var subject = car(1, 6000.0, 1000.0, direction)
		var arr: Array = [subject]
		for k in 10:
			arr.append(car(20+k, 6000.0 + direction*(k+1), 1000.0, direction, 6))
		arr.append(car(2, 6000.0 + direction*15.0, 500.0, direction))
		traffic._drive(subject, arr, 0, 1.0/60.0)
		check("leader beyond ten other-lane cars still causes braking, dir%d" % direction, subject.v < 999.5)
		if not traffic.has_method("_spawn_clear"):
			continue
		subject = car(1, 6000.0, 1000.0, direction)
		traffic.cars.assign([car(2, 6000.0 + direction*0.5, 1000.0, direction)])
		check("cannot spawn overlapping another car", not traffic._spawn_clear(subject))
		traffic.cars.assign([car(2, 6000.0 + direction*20.0, 500.0, direction)])
		check("cannot spawn too fast behind slower traffic", not traffic._spawn_clear(subject))
		traffic.cars.assign([car(2, 6000.0 - direction*20.0, 1500.0, direction)])
		check("cannot spawn in front of a fast follower", not traffic._spawn_clear(subject))
		traffic.cars.assign([car(2, 6000.0, 1000.0, direction, 6)])
		check("another lane can still receive traffic", traffic._spawn_clear(subject))
		traffic.cars.assign([car(2, 6000.0 + direction*200.0, 1000.0, direction)])
		check("safe same-lane gap accepts traffic", traffic._spawn_clear(subject))
	print("NETWORK SPAWN SPACING ", "PASS" if failures == 0 else "FAIL", " (", checks, " checks)")
	world.queue_free()
	traffic.queue_free()
	quit(0 if failures == 0 else 1)
