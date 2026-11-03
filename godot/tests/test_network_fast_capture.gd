## Full real-step ballistic arrivals through the crest; mirrors the JS fast capture matrix.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936

func trial(sim, jump: int, mph: float) -> Dictionary:
	var launch: int = sim.jumps[jump][0]
	var catcher: int = sim.jumps[jump][1]
	var road = sim.roads[launch]
	var index: int = road.N - 101
	sim.respawn_on(launch, index, 1)
	for b in sim.bodies:
		b.vx = mph / MPH * road.tx[index]
		b.vy = mph / MPH * road.ty[index]
	var result := {"jump": jump, "mph": mph, "airborne": false, "caught": [false, false, false], "settled": [false, false, false], "max_gap": 0.0, "min_gap": INF}
	var at := [-1.0, -1.0, -1.0]
	var end := -1.0
	for frame in int(15.0 / DT):
		sim.step({"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "burner": mph >= 5000, "gearOverdrive": true, "thrMul": 1.0, "reignite": true}, DT)
		for event in sim.events:
			if event.type == "airborne" and event.lip:
				result.airborne = true
		sim.events.clear()
		for k in 3:
			var b = sim.bodies[k]
			if b.off_road or b.path != catcher:
				continue
			if at[k] < 0:
				at[k] = frame * DT
				result.caught[k] = true
				end = maxf(end, at[k] + 3.0)
			sim._nearest_on(catcher, b.x, b.y, b.hint, 12)
			if sim._n_off or absf(sim._n_lat) >= sim._n_w / 2.0 - 2.0:
				continue
			var i: int = sim._n_i
			var r = sim.roads[catcher]
			var u := clampf(((b.x - r.px[i]) * r.tx[i] + (b.y - r.py[i]) * r.ty[i]) / r.len[i], 0.0, 1.0)
			var gap: float = b.z - sim.net_height(catcher, i + u) - sim.net_edge(sim._n_w, sim._n_lat).x - sim.P.rideH
			result.max_gap = maxf(result.max_gap, gap)
			result.min_gap = minf(result.min_gap, gap)
			if gap < 0.05 and not b.lock:
				result.settled[k] = true
		if end >= 0 and frame * DT >= end:
			break
	return result

func _initialize() -> void:
	var sim := Sim.new({"track": "network", "handling": "speed"})
	var failures := []
	var maximum := 0.0
	var count := 0
	for jump in 20:
		for mph in [float(sim.jumps[jump][2]), 5000.0, 7000.0, 9000.0]:
			var r := trial(sim, jump, mph)
			count += 1
			maximum = maxf(maximum, r.max_gap)
			if not r.airborne or not r.caught.all(func(x): return x) or not r.settled.all(func(x): return x) or r.max_gap > 45.0 or r.min_gap < -1e-5:
				failures.append(r)
	print(JSON.stringify({"cases": count, "failures": failures.size(), "max_gap": maximum, "examples": failures.slice(0, 6)}))
	print("NETWORK FAST CAPTURE ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
