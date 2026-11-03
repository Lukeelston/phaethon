## The Network's road ends: run into a highway's dead end and nothing may come from nowhere.
## A highway's ends are closed (a turnaround's junction holds them), so its end is a wall across the
## road. A body's collision circle that ran just past the end used to read "no road here" (INF)
## and take the junction's other road instead, the turnaround loop, whose centreline is ~300 m off
## to the side there: 210 m of "wall penetration" and a 1.3e9 N kick in one 1/480 s step (375 ->
## 7,833 km/h, the binder torn: Luke's breaks at mile ~340-346 and 0-5, speeds jumping to 10,000-
## 63,000 km/h).
##   Every highway, both ends, from ~2 s short of the end: full brakes from 2,500 km/h and a coast
##   from 8,000 km/h (no thrust: the craft's energy, speed + climb + spin, may never rise above its
##   start), and the ramjet at ~8,000 km/h (no body may go past 1.25x its start). The binder must
##   hold, and every run must reach the end (and be stopped by it).
## Prints ROAD ENDS PASS. Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_road_ends.gd -- --mute
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
var fails := 0
var passed := 0


func _energy(sim) -> float:
	var e := 0.0
	for b in [sim.pod, sim.eL, sim.eR]:
		e += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) + 0.5 * b.inertia * b.w * b.w
	return e


## [peak energy / start energy, fastest body / start speed, binder broke, reached the end]
## mode: "brakes" (2,500 km/h, starfighter), "coast" (8,000 km/h, speed: less drag, so it gets
## there), "ramjet" (8,000 km/h)
func _run(road: int, end: int, mode: String) -> Array:
	var kmh := 2500.0 if mode == "brakes" else 8000.0
	var handling := "speed" if mode == "coast" else "starfighter"
	var sim = S.new({"track": "network", "handling": handling})
	var R = sim.roads[road]
	var back := int(round(kmh / 3.6 * 2.0 / 24.0))
	var i: int = R.N - 1 - back if end == 1 else back
	var dir := 1 if end == 1 else -1
	sim.respawn_on(road, i, dir)
	var v := kmh / 3.6
	for b in [sim.pod, sim.eL, sim.eR]:
		b.vx = v * R.tx[i] * dir
		b.vy = v * R.ty[i] * dir
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0 if mode == "brakes" else 0.0, "brkR": 1.0 if mode == "brakes" else 0.0,
		"repair": false, "reignite": true, "handling": handling}
	if mode == "ramjet":
		sim.armed = true
		inp = {"thrL": 0.87, "thrR": 0.87, "burner": true, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": handling}
	var e0 := _energy(sim)
	var peak := e0
	var fastest := 0.0
	var broke := false
	var reached := false
	for k in 6 * 480:
		sim.step(inp, DT)
		peak = maxf(peak, _energy(sim))
		for b in [sim.pod, sim.eL, sim.eR]:
			fastest = maxf(fastest, sqrt(b.vx * b.vx + b.vy * b.vy))
			if not b.off_road and b.path == road and ((end == 1 and b.hint >= R.N - 2) or (end == 0 and b.hint <= 1)):
				reached = true
		for ev in sim.events:
			if ev.type == "binder":
				broke = true
		sim.events.clear()
		if broke:
			break
	return [peak / e0, fastest / v, broke, reached]


func _initialize() -> void:
	var probe = S.new({"track": "network"})
	var worst_gain := 0.0
	var gain_at := ""
	var worst_fast := 0.0
	var breaks := 0
	var reached := 0
	var runs := 0
	for name in ["N1", "N2", "N3", "E1", "E2", "E3"]:
		var road := -1
		for r in probe.roads.size():
			if probe.roads[r].name == name:
				road = r
		for end in [1, 0]:
			for mode in ["brakes", "coast", "ramjet"]:
				var res := _run(road, end, mode)
				runs += 1
				if mode != "ramjet" and res[0] > worst_gain:
					worst_gain = res[0]
					gain_at = "%s end %d %s" % [name, end, mode]
				if mode == "ramjet":
					worst_fast = maxf(worst_fast, res[1])
				breaks += int(res[2])
				reached += int(res[3])
	_check("all %d runs reach the highway's end (%d did)" % [runs, reached], reached == runs)
	_check("with no thrust the craft never ends up with more energy than it came in with (peak %.3fx its start, %s)" % [worst_gain, gain_at], worst_gain <= 1.01)
	_check("on the ramjet no body ever passes 1.25x its start (fastest %.2fx)" % worst_fast, worst_fast < 1.25)
	_check("the binder holds (%d of %d tore)" % [breaks, runs], breaks == 0)
	var good := fails == 0 and passed == 4
	print("ROAD ENDS ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
