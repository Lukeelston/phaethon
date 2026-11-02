## Headless range parity: GDScript CraftSim vs the JS reference on the jump lane.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_range_parity.gd
## Prints RANGE PARITY PASS only when every check passed.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0


func _initialize() -> void:
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/range_expected.json"))
	var sim = CraftSimScript.new({"track": "range", "startY": 400.0})
	var apexes: Array = []
	var air := false
	var apex := 0.0
	for i in int(want.seconds / DT):
		sim.step({"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		sim.events.clear()
		if not air and sim.pod.grip < 0.5:
			air = true
			apex = sim.pod.z
		if air:
			apex = maxf(apex, sim.pod.z)
		if air and sim.pod.grip >= 0.99:
			air = false
			apexes.append(apex)
	var fails := 0
	fails += _check("ramp count %d == %d" % [sim.ramps.size(), int(want.ramps)], sim.ramps.size() == int(want.ramps))
	var dx := absf(sim.pod.x - float(want.final_pod[0])) / float(want.final_pod[0]) * 100.0
	fails += _check("final x %.1f vs %.1f (%.4f%%)" % [sim.pod.x, want.final_pod[0], dx], dx <= 0.5)
	fails += _check("jump count %d == %d" % [apexes.size(), want.apexes.size()], apexes.size() == want.apexes.size())
	for k in mini(apexes.size(), want.apexes.size()):
		var e := absf(apexes[k] - float(want.apexes[k])) / float(want.apexes[k]) * 100.0
		fails += _check("apex %d: %.2f vs %.2f m (%.3f%%)" % [k, apexes[k], want.apexes[k], e], e <= 2.0)
	print("RANGE PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
