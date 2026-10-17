## Headless parity gate: GDScript CraftSim vs the JS reference.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_parity.gd
## Exit code 0 = pass. Lap time must match the JS replay within 1%.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8


func _initialize() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/lap_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/lap_inputs.json"))
	var fails := 0
	fails += _check("rng first 5 match JS", _rng_matches(expected.rng_first5))
	var sim = CraftSimScript.new()
	fails += _check("track samples %d == %d" % [sim.N, int(expected.track_samples)], sim.N == int(expected.track_samples))
	fails += _check("track length %.4f vs %.4f" % [sim.track_length, expected.track_length],
		absf(sim.track_length - expected.track_length) < 0.01)
	fails += _check("wrap_angle(+-PI) stays in [-PI, PI]",
		absf(CraftSimScript.wrap_angle(PI)) <= PI + 1e-12 and absf(CraftSimScript.wrap_angle(-PI)) <= PI + 1e-12
		and absf(CraftSimScript.wrap_angle(3.0 * PI) - PI) < 1e-9)
	fails += _check("posmod index wrap below zero", posmod(-3, 672) == 669)

	var t0 := Time.get_ticks_msec()
	var lap_time := -1.0
	var frames := 0
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		frames += 1
		for k in SUB:
			sim.step(inp, DT)
			for e in sim.events:
				if e.type == "lap" and lap_time < 0.0:
					lap_time = e.t
			sim.events.clear()
		if lap_time >= 0.0:
			break
	var ms := Time.get_ticks_msec() - t0
	var ref: float = expected.lap_time
	var err := absf(lap_time - ref) / ref * 100.0 if lap_time > 0.0 else 100.0
	print("replay: godot lap %.4f s, js lap %.4f s, error %.4f%%, frames %d/%d, %d ms wall" %
		[lap_time, ref, err, frames, int(expected.frames), ms])
	print("final pod: godot (%.3f, %.3f) js (%.3f, %.3f)" %
		[sim.pod.x, sim.pod.y, expected.final_pod[0], expected.final_pod[1]])
	fails += _check("lap time within 1%", lap_time > 0.0 and err <= 1.0)

	print("PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _rng_matches(want: Array) -> bool:
	var sim = CraftSimScript.new()
	for v in want:
		var got: float = sim.rand()
		if absf(got - float(v)) > 1e-15:
			print("  rng got %.17f want %.17f" % [got, v])
			return false
	return true


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
