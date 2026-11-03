## Obstacle toggle affects traffic/pillars, never guardrails or ground contact.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const IDLE := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
var failures := 0
var checks := 0

func check(label: String, passed: bool) -> void:
	checks += 1
	failures += int(not passed)
	print(("PASS " if passed else "FAIL ") + label)

func _initialize() -> void:
	var wall_velocity := Vector2.ZERO
	for enabled in [false, true]:
		var s = Sim.new({"track": "range", "obstacleCollisions": enabled})
		s.obstacles = [{"id": 1, "x": s.pod.x + 3.0, "y": s.pod.y, "vx": 0.0, "vy": 0.0, "r": 3.0}]
		s.step(IDLE, 1.0 / 480.0)
		check("traffic impact matches setting %s" % enabled, s.events.any(func(e): return e.type == "bump") == enabled)
		if not enabled:
			check("disabled traffic applies no push", absf(s.pod.vx) < 1e-10)
		var wall = Sim.new({"track": "gp", "obstacleCollisions": enabled})
		for b in wall.bodies:
			b.x += wall.tnx[0] * wall.tw[0]
			b.y += wall.tny[0] * wall.tw[0]
		wall.step(IDLE, 1.0 / 480.0)
		check("guardrails stay active with setting %s" % enabled, wall.events.any(func(e): return e.type in ["hit", "scrape"]))
		if not enabled:
			wall_velocity = Vector2(wall.pod.vx, wall.pod.vy)
		else:
			check("guardrail response is identical in both settings", wall_velocity == Vector2(wall.pod.vx, wall.pod.vy))
		var land = Sim.new({"track": "range", "obstacleCollisions": enabled})
		for b in land.bodies:
			b.z = 0.31
			b.vz = -30.0
		land.step(IDLE, 1.0 / 480.0)
		check("ground and landing stay active with setting %s" % enabled, land.events.any(func(e): return e.type == "land") and land.pod.z >= 0.3)
	for shape in [{"r": 3.0, "zMin": 0.0, "zMax": 4.0}, {"r": 0.0, "halfSize": 2.0, "zMin": 0.0, "zMax": 30.0}]:
		for height in [0.8, 100.0]:
			var s = Sim.new({"track": "range", "obstacleCollisions": true})
			s.pod.z = height
			var obstacle: Dictionary = {"id": 2, "x": s.pod.x + 3.0, "y": s.pod.y, "vx": 0.0, "vy": 0.0}
			obstacle.merge(shape)
			s.obstacles = [obstacle]
			s.step(IDLE, 1.0 / 480.0)
			check("bounded obstacle at height %.1f" % height, s.events.any(func(e): return e.type == "bump") == (height < 1.0))
	var network = Sim.new({"track": "network"})
	var world = World.new()
	world.sim = network
	var actual := {}
	for r in network.roads.size():
		for i in range(0, network.roads[r].N - 1, 6):
			var pillars: Array = world.pillar_specs(r, i)
			if not pillars.is_empty():
				actual = pillars[0]
				break
		if not actual.is_empty():
			break
	check("real bridge geometry supplies pillar collisions", not actual.is_empty())
	if not actual.is_empty():
		network.obstacles = world.obstacles_near(actual.x, actual.y)
		check("nearby pillar index contains actual visible support", network.obstacles.any(func(o): return o.id == actual.id))
		var body = network.pod
		body.x = actual.x + actual.halfSize + 1.0
		body.y = actual.y
		for enabled in [false, true]:
			network.P.obstacleCollisions = enabled
			body.z = 1.0
			body.fx = 0.0
			body.fy = 0.0
			network.events.clear()
			network._collide_obstacles(body, [[body.x, body.y, 1.6]])
			check("actual bridge pillar applies force only when enabled %s" % enabled, (body.fx > 0.0) == enabled)
		body.z = actual.zMax + 8.0
		body.fx = 0.0
		body.fy = 0.0
		network.events.clear()
		network._collide_obstacles(body, [[body.x, body.y, 1.6]])
		check("actual support cannot collide above its top", body.fx == 0.0 and body.fy == 0.0 and network.events.is_empty())
	world.free()
	print("OBSTACLE COLLISIONS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
