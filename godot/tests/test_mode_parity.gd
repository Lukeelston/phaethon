## Live handling switch parity: GDScript CraftSim replays the JS run (tools/record_modes.js) that
## flips between SPEEDCRAFT and STARFIGHTER on the range, and must match it: the same switches on
## the same steps (STARFIGHTER waits for 1,250 mph, SPEEDCRAFT takes at once), and the pod's
## state and the blend every second. Prints MODE PARITY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_mode_parity.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const ASK := ["", "speed", "starfighter"]


func _initialize() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/modes_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/modes_inputs.json"))
	var sim = CraftSimScript.new({"track": "range", "handling": "speed"})
	var events := []
	var trace := []
	for i in inputs.size():
		var u: Array = inputs[i]
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		sim.step(inp, DT)
		for e in sim.events:
			if e.type == "handling":
				events.append([i, e.mode])
		sim.events.clear()
		if i % 480 == 479:
			trace.append([i, sim.pod.x, sim.pod.y, sim.pod.vx, sim.pod.vy, sim.pod.th, sim.hblend, sim.P.thrustMax])
	var fails := 0
	var ev_ok: bool = events.size() == expected.events.size()
	if ev_ok:
		for k in events.size():
			ev_ok = ev_ok and int(events[k][0]) == int(expected.events[k][0]) and events[k][1] == expected.events[k][1]
	fails += _check("the same switches on the same steps: %s (js %s)" % [events, expected.events], ev_ok)
	var worst_p := 0.0
	var worst_v := 0.0
	var worst_b := 0.0
	var worst_at := -1
	var n: int = mini(trace.size(), expected.trace.size())
	for k in n:
		var a: Array = trace[k]
		var b: Array = expected.trace[k]
		var dp := Vector2(a[1] - b[1], a[2] - b[2]).length()
		if dp > worst_p:
			worst_p = dp
			worst_at = int(a[0])
		worst_v = maxf(worst_v, Vector2(a[3] - b[3], a[4] - b[4]).length())
		worst_b = maxf(worst_b, absf(a[6] - b[6]) + absf(a[7] - b[7]))
	fails += _check("pod and blend track the JS run over %d s: position within %.4f m (worst at step %d), velocity %.5f m/s, blend/handling %.6f" % [
		n, worst_p, worst_at, worst_v, worst_b], n == expected.trace.size() and n > 50 and worst_p < 1.0 and worst_v < 0.05 and worst_b < 1e-6)
	var last: Array = trace[trace.size() - 1]
	fails += _check("ends in STARFIGHTER (blend %.2f, thrustMax %.0f), engaged on the coast once below 1,250 mph" % [last[6], last[7]],
		last[6] > 0.0 and String(expected.events[expected.events.size() - 1][1]) == "starfighter")
	print("MODE PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
