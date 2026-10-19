## Hard-braking gate, through the trigger scheme as flown (QuestControls) and CraftSim, starfighter
## at ~924 mph (Luke: "if i brake too hard, the pod flies forward and throws the engines off balance"):
##   one hand, full   the pod stays at its spot behind the engines (the stand-off), and the craft
##                    turns hard but doesn't spin round (the grip difference fades at speed)
##   both, uneven     a 0.15 mismatch between the grips brakes straight (the grips magnet)
##   slower           at ~400 mph a one-handed brake still pivots you hard (hairpins keep their tool)
##   proof            without the stand-off and the scaling, the old flung-pod spin comes back
## Prints BRAKES PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_brakes.gd
extends SceneTree

const QC := preload("res://input/quest_controls.gd")
const S := preload("res://sim/craft_sim.gd")
var fails := 0
var passed := 0


func _initialize() -> void:
	var one := _brake(0.8, [1.0, 0.0], true)
	var old := _brake(0.8, [1.0, 0.0], false)
	_check("one hand, full, from %.0f mph: the pod overruns its spot by %.2f m at most, heading %+.0f deg in 3 s, %.0f mph left (before: %.1f m, %+.0f deg)" % [
		one[3], one[0], one[1], one[2], old[0], old[1]], one[0] < 1.0 and absf(one[1]) < 60.0 and old[0] > 10.0 and absf(old[1]) > 120.0)
	var both := _brake(0.8, [1.0, 0.85], true)
	_check("both hands, 0.15 apart, from %.0f mph: straight (%+.1f deg in 3 s), pod overrun %.2f m" % [both[3], both[1], both[0]],
		absf(both[1]) < 10.0 and both[0] < 1.0)
	var slow := _brake(0.22, [1.0, 0.0], true)
	_check("one hand at %.0f mph still pivots you hard (%+.0f deg in 3 s)" % [slow[3], slow[1]], absf(slow[1]) > 60.0)
	var fast := _pull(0.2)
	var fast_old := _pull(0.1)
	_check("one hand at %.0f mph (SPEEDCRAFT) pulls a few degrees more: %+.1f deg in 3 s (the old 10%% floor: %+.1f), %.0f mph left" % [fast[3], fast[1], fast_old[1], fast[2]],
		absf(fast[1]) > absf(fast_old[1]) + 2.0 and absf(fast[1]) < 12.0)
	var good := fails == 0 and passed == 4
	print("BRAKES ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


## SPEEDCRAFT flat out (lever only) to 4,000 mph, then one grip full for 3 s with the floor the
## grip difference keeps at speed set to `floor_fast`: [0, heading change deg, mph at the end, at the start].
func _pull(floor_fast: float) -> Array:
	var q = QC.new()
	q.scheme = "triggers"
	q.brake_floor_fast = floor_fast
	var sim = S.new({"track": "range", "handling": "speed"})
	var t := 0.0
	while sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936 < 4000.0 and t < 60.0:
		sim.step({"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 480.0)
		sim.events.clear()
		t += 1.0 / 480.0
	var v0: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936
	var h0: float = atan2(sim.pod.vy, sim.pod.vx)
	for f in int(3.0 * 72):
		var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var o: Dictionary = q.update({"lt": 0.0, "rt": 0.0, "lg": 1.0, "rg": 0.0, "ls": Vector2.ZERO, "rs": Vector2.ZERO,
			"lz": 0.0, "rz": 0.0, "speed": v, "yaw": (sim.eL.w + sim.eR.w) / 2.0}, 1.0 / 72.0)
		for k in 480 / 72:
			sim.step({"thrL": o.thrL, "thrR": o.thrR, "brkL": o.brkL, "brkR": o.brkR, "repair": false, "reignite": true}, 1.0 / 480.0)
			sim.events.clear()
	var dh := rad_to_deg(wrapf(atan2(sim.pod.vy, sim.pod.vx) - h0, -PI, PI))
	return [0.0, dh, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936, v0]


## Cruise at `lev` for 8 s, then hold these grips for 3 s with the triggers let go.
## [max pod overrun m, heading change deg, mph at the end, mph at the start]
func _brake(lev: float, grips: Array, fixed: bool) -> Array:
	var q = QC.new()
	q.scheme = "triggers"
	var ov := {"track": "range", "handling": "starfighter"}
	if not fixed:
		ov["towLongK"] = 0.0
		q.brake_ref = 0.0
		q.magnet_w = 0.0
	var sim = S.new(ov)
	for i in int(8.0 * 480):
		sim.step({"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 480.0)
		sim.events.clear()
	var v0: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936
	var th0: float = sim.pair_th
	var back: float = sim.P.engineLen / 2.0 + sim.P.cableLen + sim.P.podLen / 2.0
	var over := 0.0
	for f in int(3.0 * 72):
		var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var o: Dictionary = q.update({"lt": 0.0, "rt": 0.0, "lg": grips[0], "rg": grips[1], "ls": Vector2.ZERO, "rs": Vector2.ZERO,
			"lz": 0.0, "rz": 0.0, "speed": v, "yaw": (sim.eL.w + sim.eR.w) / 2.0}, 1.0 / 72.0)
		for k in 480 / 72:
			sim.step({"thrL": o.thrL, "thrR": o.thrR, "brkL": o.brkL, "brkR": o.brkR, "repair": false, "reignite": true}, 1.0 / 480.0)
			sim.events.clear()
			var pf := cos(sim.pair_th)
			var ps := sin(sim.pair_th)
			var mx: float = (sim.eL.x + sim.eR.x) / 2.0
			var my: float = (sim.eL.y + sim.eR.y) / 2.0
			over = maxf(over, (sim.pod.x - (mx - pf * back)) * pf + (sim.pod.y - (my - ps * back)) * ps)
	return [over, rad_to_deg(S.wrap_angle(sim.pair_th - th0)), sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936, v0]


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
