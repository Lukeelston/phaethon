## How many g does the craft pull along its length? Not a test: a table, to set the g-meter's scale
## (vr/gauge_cluster.gd). Full levers from rest, the burner, then both air brakes full out.
##   --headless -s res://tests/probe_g.gd
extends SceneTree
const Model := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0

func _initialize() -> void:
	var sim := Model.new({"track": "range", "startY": -3000.0})
	var inp := {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": true}
	var last := 0.0
	var t := 0.0
	print("t      mph     g along   mode")
	for phase in 2:
		var peak := 0.0
		for i in int((40.0 if phase == 0 else 20.0) / DT):
			if phase == 1:
				inp.thrL = 0.0
				inp.thrR = 0.0
				inp.brkL = 1.0
				inp.brkR = 1.0
				inp.burner = false
			sim.step(inp, DT)
			t += DT
			var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			if i % 240 == 239:
				var g: float = (v - last) / (240.0 * DT) / 9.81
				peak = maxf(peak, absf(g))
				print("%5.1f  %6.0f  %6.2f    %s" % [t, v * 2.23694, g, sim.mode])
				last = v
		print("phase %d peak %.1f g" % [phase, peak])
	quit()
