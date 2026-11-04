## Real driver updates catch missed offset followers and swept crossing cut-ins.
extends "res://tests/test_network_courtesy.gd"

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
	for direction in [1, -1]:
		var c = _car(31, 3, 6000.0, direction)
		var o = _follower(c)
		o.lat += 24.0 * direction
		var before: float = c.lat
		_advance(c, [o], 0.2)
		_check("offset approach has a natural notice delay %d" % direction, is_equal_approx(c.lat, before))
		_advance(c, [o], 3.4)
		_check("offset follower gets meaningful clearance in either direction %d" % direction, absf(c.lat - o.lat) > 60.0)
		_check("yielding never slows into fast follower %d" % direction, c.v > 999.0)
	var c = _car(31, 3)
	var early = _follower(c, 0, 16000.0, 2800.0)
	_advance(c, [early], 1.5)
	_check("high closing speed starts clearing corridor with time to spare", c.lane != 3)
	c = _car(31, 3)
	var crossing = _follower(c, 0, 30.0, 1300.0)
	crossing.lat = -10.0
	_check("lane change cannot sweep across close player to a clear endpoint", not traffic._clear([c, crossing], 0, c, 22.5))
	var R = sim.roads[road]
	sim.respawn_on(road, 5800, 1)
	# Swinging engine reaches beyond the pod's old point-only corridor.
	sim.eL.x += R.nx[5800] * 28.0
	sim.eL.y += R.ny[5800] * 28.0
	for b in sim.bodies:
		b.vx = 1800.0 * R.tx[5800]
		b.vy = 1800.0 * R.ty[5800]
	var player = traffic._pod_as_car()
	c = _car(31, 4, 5800.0 + 4000.0 / 24.0)
	_advance(c, [player], 3.4)
	_check("actual engine footprint is included in yielding", c.lane >= 5)
	world.free()
	traffic.free()
	print("TRAFFIC YIELD %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
