## Headless starfighter parity: GDScript CraftSim vs the JS reference through a 30 s slalom
## with one-sided and full braking (tools/record_handling.js; same input schedule below).
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_handling_parity.gd
## Prints HANDLING PARITY PASS only when every check passed.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0


static func _input(i: int) -> Dictionary:
	var s := i / 480
	var u := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	if s >= 5 and s < 25:
		if s % 2 == 0:
			u.thrL = 0.25
		else:
			u.thrR = 0.25
		if s == 12:
			u.brkL = 1.0
		if s == 20:
			u.brkL = 1.0
			u.brkR = 1.0
	return u


func _initialize() -> void:
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/handling_expected.json"))
	var sim = CraftSimScript.new({"track": "range", "startY": -3000.0, "handling": "starfighter"})
	var fails := 0
	var checks := 0
	fails += _check("starfighter preset applied (gripCapG %.0f, thrustMax %.0f)" % [sim.P.gripCapG, sim.P.thrustMax],
		sim.P.gripCapG == 50.0 and sim.P.thrustMax == 180000.0)
	checks += 1
	var k := 0
	for i in int(want.seconds) * 480:
		sim.step(_input(i), DT)
		sim.events.clear()
		if (i + 1) % 1200 == 0:
			var m: Array = want.marks[k]
			var dp := Vector2(sim.pod.x - float(m[0]), sim.pod.y - float(m[1])).length()
			var dth := absf(rad_to_deg(CraftSimScript.wrap_angle(sim.pod.th - float(m[2]))))
			fails += _check("t=%4.1f s  pod (%.1f, %.1f) vs (%.1f, %.1f): %.4f m, heading %.4f deg" % [
				(i + 1) * DT, sim.pod.x, sim.pod.y, m[0], m[1], dp, dth], dp <= 0.5 and dth <= 0.5)
			checks += 1
			k += 1
	var good: bool = fails == 0 and checks == want.marks.size() + 1
	print("HANDLING PARITY ", "PASS" if good else "FAIL (%d failed of %d)" % [fails, checks])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
