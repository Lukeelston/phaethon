## Same raw brake inputs through GD and JS, including held throttle and unlimited fourth gear.
extends SceneTree
const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.2369362920544

func _initialize() -> void:
	var records: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/speed_brakes_expected.json"))
	var fails := 0
	var checks := 0
	for r in records:
		var sim = S.new({"track": "range", "handling": "speed", "startY": -3000.0})
		for b in sim.bodies:
			b.vx = r.mph / MPH
			b.vy = 0.0
		var k := 0
		for i in 4 * 480:
			var active := i < 3 * 480
			sim.step({"thrL": r.throttle if active else 0.0, "thrR": r.throttle if active else 0.0,
				"brkL": 0.65 if active else 0.0, "brkR": 0.35 if active else 0.0,
				"gearOverdrive": r.overdrive, "thrMul": 1.0, "burner": false, "repair": false, "reignite": true}, DT)
			sim.events.clear()
			if i + 1 == int(r.marks[k].step):
				var m: Dictionary = r.marks[k]
				var dp := Vector2(sim.pod.x - m.x, sim.pod.y - m.y).length()
				var dv := Vector2(sim.pod.vx - m.vx, sim.pod.vy - m.vy).length()
				var dh := absf(rad_to_deg(S.wrap_angle(sim.pair_th - m.pair)))
				checks += 1
				if dp > 0.01 or dv > 0.01 or dh > 0.01:
					push_error("Brake parity %.0f mph, overdrive=%s throttle=%.2f t=%.1f: %.5f m, %.5f m/s, %.5f deg" % [r.mph, r.overdrive, r.throttle, (i + 1) * DT, dp, dv, dh])
					fails += 1
				k += 1
				if k == r.marks.size():
					break
	print("SPEED BRAKES PARITY ", "PASS" if fails == 0 and checks == 64 else "FAIL", " (%d checks, %d failures)" % [checks, fails])
	quit(0 if fails == 0 and checks == 64 else 1)
