## Real Network cell boundaries: one true nearest candidate per road. Mirrors network_query_test.js.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")

func _initialize() -> void:
	var sim = Sim.new({"track": "network", "handling": "speed"})
	var queries := 0
	var failures := 0
	for jump in sim.jumps:
		for r in [int(jump[0]), int(jump[1])]:
			var road = sim.roads[r]
			for at in [[0, -150.0], [0, 5.0], [road.N - 1, -10.0], [road.N - 1, 50.0]]:
				var i: int = at[0]
				var x: float = road.px[i] + road.tx[i] * float(at[1])
				var y: float = road.py[i] + road.ty[i] * float(at[1])
				var near: Array = sim.net_near(x, y)
				var seen := {}
				var own: Array = []
				for n in near:
					if seen.has(n[0]):
						failures += 1
					seen[n[0]] = true
					if int(n[0]) == r:
						own = n
				sim._nearest_on(r, x, y, road.N >> 1, road.N)
				var good: bool = not own.is_empty() and int(own[1]) == sim._n_i and bool(own[6]) == sim._n_off and absf(float(own[2]) - sim._n_lat) < 1e-7
				if not good:
					failures += 1
					print("FAIL query %s:%d:%.0f differs from exhaustive nearest" % [road.name, i, at[1]])
				queries += 1
	for enabled in [false, true]:
		var s = Sim.new({"track": "network", "handling": "speed", "obstacleCollisions": enabled})
		var catcher := int(s.jumps[0][1])
		var road = s.roads[catcher]
		var i := int(s._net_h[catcher][-1][0]) + 30
		s.respawn_on(catcher, i, 1)
		for body in s.bodies:
			body.x += road.nx[i] * (road.w[i] / 2.0 + 1.0)
			body.y += road.ny[i] * (road.w[i] / 2.0 + 1.0)
			body.off_road = true
			body.lock = false
			body.z = s.P.rideH
			body.vz = 0.0
			body.vx = -100.0 * road.nx[i]
			body.vy = -100.0 * road.ny[i]
		s.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}, 1.0 / 480.0)
		var inward: float = s.pod.vx * road.nx[i] + s.pod.vy * road.ny[i]
		if inward <= -50.0:
			failures += 1
			print("FAIL ground catch guardrail with obstacle collisions %s: %.3f m/s" % [enabled, inward])
	print("NETWORK QUERY %s (%d boundary queries, 2 ground-wall checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", queries, failures])
	quit(0 if failures == 0 else 1)
