## Headless sprint parity: replay the JS reference sprint and require the same outcome.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_sprint_parity.gd
## Prints SPRINT PARITY PASS only when every check passed.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8


func _initialize() -> void:
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/sprint_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/sprint_inputs.json"))
	var sim = CraftSimScript.new({"track": "range"})
	for u in inputs:
		if not sim.result.is_empty():
			break
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		for k in SUB:
			if not sim.result.is_empty():
				break
			sim.step(inp, DT)
			sim.events.clear()
	var fails := 0
	var got_type: String = sim.result.get("type", "none")
	fails += _check("result %s == %s" % [got_type, want.result.type], got_type == want.result.type)
	if got_type == "finish" and want.result.type == "finish":
		var e := absf(float(sim.result.t) - float(want.result.t))
		fails += _check("time %.3f vs %.3f s (diff %.3f s)" % [sim.result.t, want.result.t, e], e <= 0.05)
		fails += _check("stop offset %.2f vs %.2f m" % [sim.pod.x - CraftSimScript.BOX_X, want.dx],
			absf((sim.pod.x - CraftSimScript.BOX_X) - float(want.dx)) <= 0.5)
	print("SPRINT PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
