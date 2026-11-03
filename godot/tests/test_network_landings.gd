## Receiving-deck contact through real fixed steps. Mirrors tools/network_landing_test.js.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936

func surface(sim, body, road: int) -> Dictionary:
	sim._nearest_on(road, body.x, body.y, body.hint, 12)
	var i: int = sim._n_i
	var lat: float = sim._n_lat
	var width: float = sim._n_w
	var inside: bool = not sim._n_off and absf(lat) < width / 2.0 - 2.0
	var r = sim.roads[road]
	var u := clampf(((body.x - r.px[i]) * r.tx[i] + (body.y - r.py[i]) * r.ty[i]) / r.len[i], 0.0, 1.0)
	return {"height": sim.net_height(road, i + u) + sim.net_edge(width, lat).x, "inside": inside}

func trial(sim, jump: int, yaw: float, offset: float, closing: float, mph: float, initial_clearance := 10.0) -> Dictionary:
	var road: int = sim.jumps[jump][1]
	var r = sim.roads[road]
	sim.respawn_on(road, 40, 1)
	var centre := Vector2(sim.pod.x, sim.pod.y)
	var angle := deg_to_rad(yaw)
	var heading: float = sim.pod.th + angle
	for b in sim.bodies:
		var position := (Vector2(b.x, b.y) - centre).rotated(angle) + centre + Vector2(r.nx[40], r.ny[40]) * offset
		b.x = position.x
		b.y = position.y
		b.th += angle
		b.vx = mph / MPH * cos(heading)
		b.vy = mph / MPH * sin(heading)
		var at := surface(sim, b, road)
		b.x += b.vx * DT
		b.y += b.vy * DT
		var next := surface(sim, b, road)
		b.x = position.x
		b.y = position.y
		b.z = at.height + sim.P.rideH + initial_clearance
		b.vz = (next.height - at.height) / DT - closing
		b.off_road = true
		b.lock = false
	var result := {"jump": jump, "yaw": yaw, "offset": offset, "closing": closing, "mph": mph,
		"initial_clearance": initial_clearance, "minimum": INF, "after_landing": -INF,
		"captured": [false, false, false], "touchdown": [false, false, false], "broken": false, "wall_ended": false}
	for step in 720:
		sim.step({"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		sim.events.clear()
		if sim.bodies.any(func(b): return b.contact[0] or b.contact[1]):
			result.wall_ended = true
			break
		result.broken = result.broken or sim.binder_broken
		for i in 3:
			var b = sim.bodies[i]
			if b.off_road or b.path != road:
				continue
			result.captured[i] = true
			var at := surface(sim, b, road)
			if not at.inside:
				continue
			var clearance: float = b.z - at.height
			result.minimum = minf(result.minimum, clearance)
			if clearance <= sim.P.rideH + 0.05:
				result.touchdown[i] = true
			if result.touchdown[i]:
				result.after_landing = maxf(result.after_landing, clearance)
	return result

func _initialize() -> void:
	var sim := Sim.new({"track": "network", "handling": "speed"})
	var failures := []
	var cases := 0
	for jump in sim.jumps.size():
		var minimum: float = sim.jumps[jump][2]
		var high := maxf(5000.0, minimum + 500.0)
		for args in [[0, 0, 30, minimum], [5, -140, 120, minimum], [-5, 140, 120, high], [15, -80, 120, high], [-15, 80, 120, minimum],
			[30, -100, 80, high], [-30, 100, 80, minimum], [0, 170, 120, minimum],
			[0, -170, 120, minimum], [0, 0, 240, high]]:
			var r := trial(sim, jump, args[0], args[1], args[2], args[3])
			cases += 1
			if not r.captured.all(func(x): return x) or r.minimum < sim.P.rideH - 1e-5 or r.after_landing > sim.P.rideH + 0.1 or r.broken or (r.closing >= 80 and not r.touchdown.all(func(x): return x)):
				failures.append(r)
	for jump in [0, 1, 8, 16]:
		for miss in ["below", "transverse"]:
			var r := trial(sim, jump, 90.0 if miss == "transverse" else 0.0, 0.0, 0.0, 3500.0, -70.0 if miss == "below" else 10.0)
			if r.captured.any(func(x): return x):
				r["negative"] = miss
				failures.append(r)
	print(JSON.stringify({"positive_cases": cases, "negative_cases": 8, "failures": failures.size(), "examples": failures.slice(0, 8)}))
	print("NETWORK LANDINGS ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
