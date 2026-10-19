## Grand-prix parity: GDScript CraftSim replays the JS autopilot's GP lap (tools/record_gp.js) in
## STARFIGHTER and must match the track and the lap. Prints GP PARITY PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gp_parity.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8


func _initialize() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/gp_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/gp_inputs.json"))
	var fails := 0
	var checks := 0
	var sim = CraftSimScript.new({"track": "gp"})
	fails += _check("track samples %d == %d" % [sim.N, int(expected.track_samples)], sim.N == int(expected.track_samples))
	fails += _check("track length %.4f vs %.4f m" % [sim.track_length, expected.track_length], absf(sim.track_length - expected.track_length) < 0.01)
	fails += _check("starfighter by default on the GP (%s, thrustMax %.0f)" % [sim.P.handling, sim.P.thrustMax],
		sim.P.handling == "starfighter" and sim.P.thrustMax == 180000.0)
	var lap := -1.0
	var hits := 0
	var top := 0.0
	var frames := 0
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		frames += 1
		for k in SUB:
			sim.step(inp, DT)
			top = maxf(top, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936)
			for e in sim.events:
				if e.type == "lap" and lap < 0.0:
					lap = e.t
				elif e.type == "hit":
					hits += 1
			sim.events.clear()
			if lap >= 0.0:
				break   # stop on the substep the lap lands, as the JS recorder does
		if lap >= 0.0:
			break
	var ref: float = expected.lap_time
	var err := absf(lap - ref) / ref * 100.0 if lap > 0.0 else 100.0
	print("  godot lap %.4f s, js %.4f s (%.4f%%), top %.0f mph (js %.0f), wall hits %d (js %d)" % [lap, ref, err, top, expected.top_mph, hits, int(expected.hits)])
	var dp := Vector2(sim.pod.x - float(expected.final_pod[0]), sim.pod.y - float(expected.final_pod[1])).length()
	fails += _check("lap time within 0.5%% and the finish within 1 m (%.4f m)" % dp, lap > 0.0 and err <= 0.5 and dp <= 1.0)
	fails += _check("a ~1,000 mph circuit: top %.0f mph, average %.0f mph" % [top, sim.track_length / maxf(lap, 1.0) * 2.236936],
		top >= 950.0 and sim.track_length / maxf(lap, 1.0) * 2.236936 >= 750.0)
	print("GP PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
