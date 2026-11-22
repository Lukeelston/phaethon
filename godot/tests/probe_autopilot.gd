## A look at one autopilot flight in the bare sim: the route, then a line every few seconds.
## -s res://tests/probe_autopilot.gd -- --road=N3 --at=400 --dir=1 --to=GLACIER --mph=2400 --secs=120 [--every=5]
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const Autopilot := preload("res://view/autopilot.gd")
const DT := 1.0 / 480.0
const SUB := 8
const MPH := 2.236936


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.get_slice("=", 1)
	return fallback


func _initialize() -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var road := -1
	for r in sim.roads.size():
		if String(sim.roads[r].name) == _arg("road", "N3"):
			road = r
	var city := -1
	for k in sim.cities.size():
		if String(sim.cities[k].name) == _arg("to", "GLACIER"):
			city = k
	var from_city := _arg("from", "")
	if from_city != "":
		for k in sim.cities.size():
			if String(sim.cities[k].name) == from_city:
				sim.respawn_on(int(sim.cities[k].road), int(sim.cities[k].i), int(_arg("dir", "1")))
	else:
		sim.respawn_on(road, int(_arg("at", "400")), int(_arg("dir", "1")))
	var a = Autopilot.new()
	var took: bool = a.engage(sim, city)
	if _arg("mph", "") != "":
		a.set_cruise(float(_arg("mph", "0")) / MPH)
	var names := []
	var last := -1
	for k in a.rpath.size():
		if a.rpath[k] != last:
			last = a.rpath[k]
			names.append("%s@%d" % [sim.roads[last].name, a.ri[k]])
	print("PROBE took %s (%s); route %d samples, %.0f km: %s; cruise %.0f mph" % [took, a.why_off, a.rx.size(), a.rs[a.rs.size() - 1] / 1000.0 if a.rs.size() else 0.0, " ".join(names), a.cruise * MPH])
	var secs := float(_arg("secs", "120"))
	var every := float(_arg("every", "5"))
	var next := 0.0
	var hits := 0
	var cars := []
	var cars_at := float(_arg("cars-at", "-1"))
	for f in int(secs / (SUB * DT)):
		var t := f * SUB * DT
		if cars_at >= 0.0 and t >= cars_at and cars.is_empty():
			var CR = sim.roads[sim.pod.path]
			var ci := clampi(int(sim.pod.hint) + int(_arg("cars-ahead", "300")) * Autopilot.way(sim), 0, int(CR.N) - 1)
			var w := float(Autopilot.way(sim))
			var span := int(_arg("cars-span", "0"))
			for k in range(-span, span + 1):
				cars.append({"x": CR.px[ci] + CR.nx[ci] * k * 22.0, "y": CR.py[ci] + CR.ny[ci] * k * 22.0, "v": 300.0 / MPH, "hx": CR.tx[ci] * w, "hy": CR.ty[ci] * w})
			print("PROBE   %d vehicles put on %s@%d, %.0f m ahead" % [cars.size(), CR.name, ci, Vector2(cars[0].x - sim.pod.x, cars[0].y - sim.pod.y).length()])
		for c in cars:
			c.x += c.v * c.hx * SUB * DT
			c.y += c.v * c.hy * SUB * DT
		var u: Dictionary = a.fly(sim, city, cars)
		if u.is_empty():
			print("PROBE given back at %.1f s: %s" % [t, a.why_off])
			break
		if t >= next:
			next += every
			var R = sim.roads[sim.pod.path]
			var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
			var off: float = (sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i]
			var gap := INF
			for c in cars:
				gap = minf(gap, Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length())
			print("PROBE %5.1f s  %5.0f mph (plan %5.0f) on %s@%d off %6.1f m | levers %.2f %.2f brakes %.2f %.2f %s | sim %s blend %.2f | at %d %s lane %.0f cap %.0f mph nearest %.0f m" % [
				t, Vector2(sim.pod.vx, sim.pod.vy).length() * MPH, a.vplan[a.at] * MPH, R.name, i, off, u.thrL, u.thrR, u.brkL, u.brkR, u.handling, sim.P.handling, sim.hblend, a.at, a.status, a.lane,
				minf(a.lane_cap * MPH, 99999.0), gap])
		var inp := {"thrL": u.thrL, "thrR": u.thrR, "brkL": u.brkL, "brkR": u.brkR, "repair": false, "reignite": true, "handling": u.handling}
		for k in SUB:
			sim.step(inp, DT)
			for e in sim.events:
				if e.type == "hit" or e.type == "scrape" or e.type == "smash":
					hits += 1
				elif e.type != "land":
					print("PROBE   event %s at %.1f s" % [e, t])
			sim.events.clear()
	print("PROBE done: %d wall contacts" % hits)
	quit(0)
