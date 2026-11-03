## Focused physical check: guide stopping distances against actual full-brake runs.
## Covers the flap deployment band, force-limited high speed, fourth gear and Starfighter.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const Guide := preload("res://view/speed_guide.gd")
const MPH := 2.2369362920544
const DT := 1.0 / 480.0

func _initialize() -> void:
	var fails := 0
	for c in [["speed", 2000.0, 1250.0, false], ["speed", 4000.0, 1250.0, false], ["speed", 6000.0, 1250.0, false], ["speed", 6000.0, 1250.0, true], ["starfighter", 1200.0, 400.0, false],
		["speed", 4000.0, 1250.0, false, {"frontBrakeMaxG": 0.0}], ["speed", 2000.0, 1250.0, false, {"frontBrakeCd": 0.0}],
		["speed", 4000.0, 1250.0, false, {"frontBrakeMaxG": 20.0}], ["speed", 4000.0, 1250.0, false, {"podMass": 1500.0, "forceScale": 3900.0 / 2900.0}]]:
		var options := {"track": "range", "handling": c[0], "startY": -3000.0}
		if c.size() > 4:
			options.merge(c[4], true)
		var sim = Sim.new(options)
		var g = Guide.new()
		g.setup(sim)
		for b in sim.bodies:
			b.vx = c[1] / MPH
			b.vy = 0.0
		var predicted: float = g.stop_distance(c[1] / MPH, c[2] / MPH, g.brake_model(), g.brake_model("starfighter"))
		var x0: float = sim.pod.x
		var steps := 0
		while sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) > c[2] / MPH and steps < 480 * 60:
			sim.step({"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "gearOverdrive": c[3], "repair": false, "reignite": true}, DT)
			sim.events.clear()
			steps += 1
		var actual: float = sim.pod.x - x0
		var error := absf(predicted - actual) / actual
		var ok: bool = steps < 480 * 60 and error < 0.08
		print("%s %s %.0f->%.0f mph, fourth=%s, overrides=%s: guide %.1f m, sim %.1f m, error %.2f%%" % ["PASS" if ok else "FAIL", c[0], c[1], c[2], c[3], c[4] if c.size() > 4 else {}, predicted, actual, error * 100.0])
		if not ok:
			fails += 1
	print("SPEED GUIDE BRAKING ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)
