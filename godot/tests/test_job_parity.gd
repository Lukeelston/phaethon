## Job parity (the emergency run): GDScript CraftSim replays tools/record_job.js's autopilot runs
## (replay/job_<route>_inputs.json) with the dawn as tuned (tools/tune_dawn.js), and must match JS:
## the same job events on the same frames, the margin within 0.05 s, the finish within 1 m. The
## open and shade runs make it home; the late run (6 s longer on the pad) is caught by the dawn on
## the same frame as in JS.
## Prints JOB PARITY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_job_parity.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8
const ASK := ["", "speed", "starfighter"]


func _initialize() -> void:
	var fails := 0
	for kind in ["open", "shade", "late"]:
		var ep := "res://tests/replay/job_%s_expected.json" % kind
		var ip := "res://tests/replay/job_%s_inputs.json" % kind
		if not FileAccess.file_exists(ep) or not FileAccess.file_exists(ip):
			fails += _check("%s: no replay (run tools/record_job.js)" % kind, false)
			continue
		var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ep))
		var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string(ip))
		var sim = CraftSimScript.new({"track": "eridanus", "job": "emergency"})
		var dawn_ok: bool = absf(sim.P.dawnDir - float(X.dawn[0])) < 1e-12 and absf(sim.P.dawnT0 - float(X.dawn[1])) < 1e-12
		var events := []
		var done := false
		for f in inputs.size():
			var u: Array = inputs[f]
			var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
			if int(u[4]) > 0:
				inp["handling"] = ASK[int(u[4])]
			for k in SUB:
				sim.step(inp, DT)
				for e in sim.events:
					if e.type == "job" or e.type == "dawn":
						events.append([f, e.type, e.get("stage", "")])
						if e.type == "job" and (e.stage == "done" or e.stage == "failed"):
							done = true
				sim.events.clear()
				if done:
					break
			if done:
				break
		var ev_ok: bool = events.size() == X.events.size()
		if ev_ok:
			for k in events.size():
				ev_ok = ev_ok and events[k][0] == int(X.events[k][0]) and events[k][1] == X.events[k][1] and events[k][2] == X.events[k][2]
		var dp := Vector2(sim.pod.x - float(X.final_pod[0]), sim.pod.y - float(X.final_pod[1])).length()
		var dm := absf(float(sim.job.margin) - float(X.margin))
		print("  %s: %s%s at %.3f s (js %s at %.3f s), route %s, margin %+.3f s (js %+.3f), finish %.4f m from js; events %s" % [
			kind, sim.job.stage, " (" + sim.job.reason + ")" if sim.job.reason != "" else "", sim.job.t, X.stage, X.t, sim.job.route, sim.job.margin, X.margin, dp, events])
		fails += _check("%s: the tuned dawn (%s), the same job events on the same frames, margin within 0.05 s, finish within 1 m" % [kind, dawn_ok],
			dawn_ok and ev_ok and dm <= 0.05 and dp <= 1.0)
		if kind == "late":
			fails += _check("late: caught by the dawn", sim.job.stage == "failed" and sim.job.reason == "dawn" and X.stage == "failed")
		else:
			fails += _check("%s: home ahead of the dawn on its route (%s, margin %+.2f s)" % [kind, sim.job.route, sim.job.margin],
				sim.job.stage == "done" and sim.job.route == kind and sim.job.margin > 0.0)
	print("JOB PARITY PASS" if fails == 0 else "JOB PARITY FAIL (%d)" % fails)
	quit(1 if fails else 0)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
