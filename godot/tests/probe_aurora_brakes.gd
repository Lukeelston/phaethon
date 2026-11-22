## How far the craft takes to stop inside the Aurora tube on full air brakes with the levers shut:
## the table the line's takeoff and landing areas colour their distance rings by
## (view/aurora_stations.gd, STOP_KM). Run it again whenever the tube's air or the brakes change,
## and paste the line it prints over the constant (tests/test_aurora_stations.gd checks one row):
## --headless --xr-mode off --audio-driver Dummy -s res://tests/probe_aurora_brakes.gd
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 240.0
const SPEEDS := [200.0, 500.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 8000.0, 10000.0, 12000.0, 15000.0, 20000.0, 25000.0]   # (the line doubles a craft's speed: flat out it holds 10,800 mph, and in the top gear's overdrive it passes 18,000)


## [metres, seconds, the hardest deceleration in g, whether it went wrong] from a speed in mph.
func _stop(sim, mph: float) -> Array:
	var r := int(Sim.NET_PRESSURE[0])
	var road = sim.roads[r]
	var from := (int(Sim.NET_PRESSURE[1]) + int(Sim.NET_PRESSURE[2])) / 2
	sim.respawn_on(r, from, 1)
	var v := mph * 0.44704
	for b in sim.bodies:
		b.vx = road.tx[from] * v
		b.vy = road.ty[from] * v
	var start := Vector2(sim.pod.x, sim.pod.y)
	var inp := {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}
	var t := 0.0
	var hardest := 0.0
	var last := v
	while t < 400.0:
		sim.step(inp, DT)
		t += DT
		var s := sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		hardest = maxf(hardest, (last - s) / DT / 9.81)
		last = s
		if s < 0.9:
			break
	return [Vector2(sim.pod.x, sim.pod.y).distance_to(start), t, hardest, sim.crash_t > 0.0 or sim.pod.off_road or t >= 400.0]


func _initialize() -> void:
	var sim = Sim.new({"track": "network"})
	var rows := PackedStringArray(["[0.0, 0.0]"])
	var wrong := 0
	for mph: float in SPEEDS:
		var run := _stop(sim, mph)
		wrong += int(bool(run[3]))
		rows.append("[%.1f, %.2f]" % [mph, float(run[0]) / 1000.0])
		print("AURORA BRAKES from %5.0f mph: %.2f km in %.1f s, hardest %.0f g%s" % [mph, float(run[0]) / 1000.0, float(run[1]), float(run[2]), "  WENT WRONG" if run[3] else ""])
	print("const STOP_KM := [%s]" % ", ".join(rows))
	print("AURORA BRAKES %s" % ("PASS" if wrong == 0 else "FAIL (%d runs went wrong)" % wrong))
	quit(int(wrong > 0))
