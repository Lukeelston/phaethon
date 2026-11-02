## Course parity (Eridanus, the dual-purpose course): GDScript CraftSim replays the JS autopilot's
## lap (tools/record_course.js), handling switches and all, and must match the track and the lap:
## the same samples, length, widths and banks, the same switches on the same frames (SPEEDCRAFT out of each town,
## STARFIGHTER into each, engaging below 1,250 mph), the lap time and the finish.
## Prints COURSE PARITY PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_course_parity.gd
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const SUB := 8
const ASK := ["", "speed", "starfighter"]
const COURSE := "eridanus"


func _initialize() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/%s_expected.json" % COURSE))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/%s_inputs.json" % COURSE))
	var fails := 0
	var sim = CraftSimScript.new({"track": COURSE})
	fails += _check("track samples %d == %d, length %.4f vs %.4f m" % [sim.N, int(expected.track_samples), sim.track_length, expected.track_length],
		sim.N == int(expected.track_samples) and absf(sim.track_length - expected.track_length) < 0.01)
	var sf := 0
	var sp := 0
	for i in sim.N:
		if sim.tmode[i] == 0:
			sf += 1
		else:
			sp += 1
	var C: Dictionary = CraftSimScript.COURSES[COURSE]
	var core := _share_at(sim, 0, C.widths.sf)
	fails += _check("two kinds of track: %.1f km of towns (%.0f%% exactly %.0f m wide, easing to the loop's width at their ends), %.1f km of speed loop (widest %.0f); STARFIGHTER at the start (%s)" % [
		sf * 12.0 / 1000.0, core * 100.0, C.widths.sf, sp * 12.0 / 1000.0, _widest(sim, 1), sim.P.handling],
		sf > 0 and sp > sf * 4 and core > 0.6 and absf(_widest(sim, 1) - C.widths.sp) < 0.5 and sim.P.handling == "starfighter")
	# banked both kinds of track: the towns to their bank, the loop's sweepers just a little
	var bk_sf := 0.0
	var bk_sp := 0.0
	for i in sim.N:
		var w := rad_to_deg(absf(sim.tb[i]))
		if sim.tmode[i] == 0:
			bk_sf = maxf(bk_sf, w)
		elif absf(sim.tw[i] - C.widths.sp) < 0.5:   # the loop proper, past the width easing
			bk_sp = maxf(bk_sp, w)
	fails += _check("banked: the towns up to %.1f deg (want %.0f), the loop's sweepers up to %.1f deg (want %.0f)" % [bk_sf, C.banks.sf, bk_sp, C.banks.sp],
		absf(bk_sf - C.banks.sf) < 0.05 and absf(bk_sp - C.banks.sp) < 0.05)
	var lap := -1.0
	var hits := 0
	var top := 0.0
	var switches := []
	var frames := 0
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(inp, DT)
			var v := sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			top = maxf(top, v * 2.236936)
			for e in sim.events:
				if e.type == "lap" and lap < 0.0:
					lap = e.t
				elif e.type == "hit":
					hits += 1
				elif e.type == "handling":
					switches.append([frames, e.mode, roundi(v * 2.236936)])
			sim.events.clear()
			if lap >= 0.0:
				break
		frames += 1
		if lap >= 0.0:
			break
	var ref: float = expected.lap_time
	var err := absf(lap - ref) / ref * 100.0 if lap > 0.0 else 100.0
	print("  godot lap %.4f s, js %.4f s (%.4f%%), top %.0f mph (js %.0f), wall hits %d (js %d)" % [lap, ref, err, top, expected.top_mph, hits, int(expected.hits)])
	var sw_ok: bool = switches.size() == expected.switches.size()
	if sw_ok:
		for k in switches.size():
			sw_ok = sw_ok and int(switches[k][0]) == int(expected.switches[k][0]) and switches[k][1] == expected.switches[k][1]
	fails += _check("the same switches on the same frames: %s (js %s)" % [switches, expected.switches], sw_ok and switches.size() == 4)
	var dp := Vector2(sim.pod.x - float(expected.final_pod[0]), sim.pod.y - float(expected.final_pod[1])).length()
	fails += _check("lap time within 0.5%% and the finish within 1 m (%.4f m); hits match" % dp, lap > 0.0 and err <= 0.5 and dp <= 1.0 and hits == int(expected.hits))
	fails += _check("both modes flown flat out: top %.0f mph, average %.0f mph" % [top, sim.track_length / maxf(lap, 1.0) * 2.236936],
		top >= 4000.0 and sim.track_length / maxf(lap, 1.0) * 2.236936 >= 2000.0)
	print("COURSE PARITY ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _share_at(sim, mode: int, w: float) -> float:
	var n := 0
	var at := 0
	for i in sim.N:
		if sim.tmode[i] == mode:
			n += 1
			if absf(sim.tw[i] - w) < 0.01:
				at += 1
	return float(at) / maxf(n, 1)


func _widest(sim, mode: int) -> float:
	var w := 0.0
	for i in sim.N:
		if sim.tmode[i] == mode:
			w = maxf(w, sim.tw[i])
	return w


func _check(label: String, ok: bool) -> int:
	print(("  ok   " if ok else "  FAIL ") + label)
	return 0 if ok else 1
