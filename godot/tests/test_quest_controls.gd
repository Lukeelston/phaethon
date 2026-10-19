## Quest control schemes gate: drives QuestControls with synthetic controller snapshots.
## Prints QUEST CONTROLS PASS when every check passes.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_quest_controls.gd
extends SceneTree

const QC := preload("res://input/quest_controls.gd")
const DT := 1.0 / 72.0
var fails := 0
var passed := 0


static func snap(o := {}) -> Dictionary:
	var c := {"lt": 0.0, "rt": 0.0, "lg": 0.0, "rg": 0.0, "ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0}
	c.merge(o, true)
	return c


func run(q, c: Dictionary, secs: float) -> Dictionary:
	var out := {}
	for i in int(secs / DT):
		out = q.update(c, DT)
	return out


func _initialize() -> void:
	var q = QC.new()
	# triggers: throttle (both together) + shaped, ramped steering (the difference); crossed
	q.scheme = "triggers"
	var o := run(q, snap({"lt": 0.5, "rt": 0.5}), 2.0)
	var linear := 0.87 * 0.5 / 0.9
	_check("triggers: both at half = pure throttle, no steer, ~20%% softer than straight-through (%.3f / %.3f vs %.3f)" % [o.thrL, o.thrR, linear],
		absf(o.thrL - QC.trigger_lever(0.5)) < 1e-6 and o.thrL == o.thrR and o.thrL < linear * 0.85 and o.thrL > linear * 0.7)
	var mean_cut := 0.0
	for k in 9:
		var x := 0.1 * (k + 1)
		mean_cut += 1.0 - QC.trigger_lever(x) / maxf(0.87 * minf(x / 0.9, 1.0), 1e-6)
	mean_cut /= 9.0
	_check("triggers: ~25%% less lever per bit of pull on average (%.0f%%), and still full at a full pull (%.2f)" % [mean_cut * 100.0, QC.trigger_lever(0.95)],
		mean_cut > 0.18 and mean_cut < 0.32 and is_equal_approx(QC.trigger_lever(0.95), 0.87) and QC.trigger_lever(1.0) == 1.0)
	# the magnet: nearly-together fingers fly straight, a real split still turns hard
	var raw = QC.new()
	raw.scheme = "triggers"
	raw.magnet_w = 0.0
	var split_at := func(qq, l: float, r: float) -> float:
		var oo: Dictionary = run(qq, snap({"lt": l, "rt": r}), 2.0)
		return oo.thrL - oo.thrR
	var w2: float = split_at.call(q, 0.5, 0.52)
	var w2_raw: float = split_at.call(raw, 0.5, 0.52)
	_check("triggers: a 2%% wobble barely steers (split %.4f, %.0f%% of unmagnetised %.4f)" % [w2, 100.0 * w2 / w2_raw, w2_raw],
		w2 >= 0.0 and w2 <= 0.06 * w2_raw)
	var m7: float = split_at.call(q, 0.4, 0.47)
	var m7_raw: float = split_at.call(raw, 0.4, 0.47)
	_check("triggers: fingers 0.07 apart (Luke's median) steer %.0f%% as hard as unmagnetised (< 25%%)" % (100.0 * m7 / m7_raw),
		m7 > 0.0 and m7 < 0.25 * m7_raw)
	var big: float = split_at.call(q, 0.3, 0.7)
	var big_raw: float = split_at.call(raw, 0.3, 0.7)
	_check("triggers: a real split (0.4) still steers %.0f%% as hard (> 70%%)" % (100.0 * big / big_raw), big > 0.7 * big_raw)
	var mono := true
	var max_slope := 0.0
	var prev_m := QC.magnetise(-1.0, QC.MAGNET)
	for i in range(1, 2001):
		var d := -1.0 + i * 0.001
		var mm := QC.magnetise(d, QC.MAGNET)
		mono = mono and mm >= prev_m
		max_slope = maxf(max_slope, (mm - prev_m) / 0.001)
		prev_m = mm
	_check("triggers: the magnet is smooth: monotonic, full at the stops (%.3f), no snap (max slope %.2f)" % [QC.magnetise(1.0, QC.MAGNET), max_slope],
		mono and is_equal_approx(QC.magnetise(1.0, QC.MAGNET), 1.0) and is_equal_approx(QC.magnetise(-1.0, QC.MAGNET), -1.0) and max_slope < 1.25)
	run(q, snap(), 1.0)
	o = q.update(snap({"rt": 1.0}), DT)
	var first_l: float = o.thrL
	var far_max: float = o.thrR
	for f in int(0.4 / DT) - 1:
		o = q.update(snap({"rt": 1.0}), DT)
		far_max = maxf(far_max, o.thrR)
	_check("triggers: a full right squeeze from idle ramps the left engine (%.3f after one frame, %.2f after 0.4 s) and never stirs the right (max %.3f)" % [first_l, o.thrL, far_max],
		first_l > 0.0 and first_l < 0.05 and o.thrL > 0.45 and o.thrL < 0.75 and far_max == 0.0)
	# Luke's GP wreck: pumping one trigger hard drove him straight on (both engines ~0.15)
	var qp = QC.new()
	qp.scheme = "triggers"
	var near_sum := 0.0
	var far_pump := 0.0
	var nf := int(2.0 / DT)
	for f in nf:
		var pulled := fmod(f * DT, 0.2) < 0.12
		var op: Dictionary = qp.update(snap({"rt": 1.0 if pulled else 0.0, "speed": 250.0, "yaw": 0.3}), DT)
		near_sum += op.thrL / nf
		far_pump = maxf(far_pump, op.thrR)
	_check("triggers: pumping the right trigger turns right, never drives straight on (left engine mean %.2f, right engine max %.3f)" % [near_sum, far_pump],
		near_sum > 0.05 and far_pump == 0.0)
	o = run(q, snap({"rt": 1.0}), 1.5)
	_check("triggers: ... and still reaches the full split (left engine %.2f, right %.2f)" % [o.thrL, o.thrR], o.thrL == 1.0 and o.thrR == 0.0)
	o = run(q, snap({"lt": 0.6, "rt": 0.6}), 0.5)
	_check("triggers: evening up straightens within 0.5 s (split %.3f)" % (o.thrL - o.thrR), absf(o.thrL - o.thrR) < 0.01)
	o = run(q, snap({"lt": 1.0, "rt": 1.0}), 0.6)
	_check("triggers: full pull = burner (%.2f, %.2f)" % [o.thrL, o.thrR], o.thrL == 1.0 and o.thrR == 1.0)
	o = run(q, snap(), DT)
	_check("triggers: letting off is instant (%.2f / %.2f one frame later)" % [o.thrL, o.thrR], o.thrL == 0.0 and o.thrR == 0.0)
	var r1: Dictionary = run(q, snap({"lt": 1.0, "rt": 1.0}), 0.1)
	var r2: Dictionary = run(q, snap({"lt": 1.0, "rt": 1.0}), 0.6)
	_check("triggers: idle to full ramps over ~0.6 s (%.2f at 0.1 s, %.2f at 0.7 s)" % [r1.thrL, r2.thrL],
		r1.thrL > 0.1 and r1.thrL < 0.2 and r1.thrL == r1.thrR and r2.thrL == 1.0)
	# a finger landing 60 ms early can't spin you off the line
	var peak := 0.0
	var peak_raw := 0.0
	var qr = QC.new()
	qr.scheme = "triggers"
	qr.ramp_up = 0.0
	qr.magnet_w = 0.0
	run(q, snap(), 1.0)
	for f in int(0.4 / DT):
		var t := f * DT
		var cc := snap({"rt": clampf(t / 0.1, 0.0, 1.0), "lt": 0.92 * clampf((t - 0.06) / 0.1, 0.0, 1.0)})
		var cq := cc.duplicate()
		cq["speed"] = 0.0   # on the line, as the cockpit feeds it
		var oa: Dictionary = q.update(cq, DT)
		var ob: Dictionary = qr.update(cc, DT)
		peak = maxf(peak, absf(oa.thrL - oa.thrR))
		peak_raw = maxf(peak_raw, absf(ob.thrL - ob.thrR))
	_check("triggers: one finger 60 ms early off the line: peak split %.2f (without the ramp %.2f)" % [peak, peak_raw], peak < 0.05 and peak_raw > 0.2)
	# steering authority grows with speed; with the triggers together the craft holds itself straight
	var at_speed := func(v: float) -> float:
		var qq = QC.new()
		qq.scheme = "triggers"
		qq.hold_k = 0.0
		var oo: Dictionary = run(qq, snap({"lt": 0.3, "rt": 0.7, "speed": v}), 2.0)
		return oo.thrL - oo.thrR
	var s_full: float = at_speed.call(300.0)
	var s_slow: float = at_speed.call(100.0)
	var s_crawl: float = at_speed.call(10.0)
	_check("triggers: steering authority by speed: full from 500 mph (%.3f at 671 mph), %.0f%% at 224 mph, floor %.0f%% at a crawl" % [
		s_full, 100.0 * s_slow / s_full, 100.0 * s_crawl / s_full],
		is_equal_approx(s_full, at_speed.call(QC.SPEED_REF)) and absf(s_slow / s_full - pow(100.0 / QC.SPEED_REF, 1.5)) < 0.01 and absf(s_crawl / s_full - QC.SPEED_FLOOR) < 0.01)
	var qh = QC.new()
	qh.scheme = "triggers"
	var hold_on: Dictionary = run(qh, snap({"lt": 0.5, "rt": 0.5, "speed": 200.0, "yaw": -0.2}), 1.0)   # yawing right, fingers level
	var hold_off: Dictionary = run(qh, snap({"lt": 0.3, "rt": 0.6, "speed": 200.0, "yaw": -0.2}), 1.0)  # turning right on purpose
	var hold_none: Dictionary = run(QC.new(), snap({"lt": 0.3, "rt": 0.6, "speed": 200.0, "yaw": 0.0}), 1.0)
	var qb = QC.new()
	qb.scheme = "triggers"
	var burner: Dictionary = run(qb, snap({"lt": 1.0, "rt": 1.0, "speed": 400.0, "yaw": -0.2}), 1.0)
	_check("triggers: straight-hold: fingers level and yawing right, it pushes left (split %.3f); turning on purpose it stays out (%.3f vs %.3f); never on the burner (%.2f / %.2f)" % [
		hold_on.thrL - hold_on.thrR, hold_off.thrL - hold_off.thrR, hold_none.thrL - hold_none.thrR, burner.thrL, burner.thrR],
		hold_on.thrL - hold_on.thrR < -0.1 and absf((hold_off.thrL - hold_off.thrR) - (hold_none.thrL - hold_none.thrR)) < 1e-6 and burner.thrL == 1.0 and burner.thrR == 1.0)
	# the air brakes never fire an engine: triggers let go, one grip squeezed, the pod yawing hard
	var worst := 0.0
	for yaw in [-0.6, -0.2, 0.2, 0.6]:
		for grips in [[1.0, 0.0], [0.0, 1.0], [0.5, 0.0], [1.0, 1.0]]:
			var qq = QC.new()
			qq.scheme = "triggers"
			var ob: Dictionary = run(qq, snap({"lg": grips[0], "rg": grips[1], "speed": 250.0, "yaw": yaw}), 0.5)
			worst = maxf(worst, maxf(ob.thrL, ob.thrR))
	var qi = QC.new()
	qi.scheme = "triggers"
	var idle_yaw: Dictionary = run(qi, snap({"speed": 250.0, "yaw": 0.5}), 0.5)
	_check("triggers: braking (or coasting) with the triggers let go never fires an engine, however the pod yaws (worst lever %.3f; coasting %.3f / %.3f)" % [
		worst, idle_yaw.thrL, idle_yaw.thrR], worst == 0.0 and idle_yaw.thrL == 0.0 and idle_yaw.thrR == 0.0)
	o = run(q, snap({"lg": 1.0}), 0.1)
	_check("triggers: let go = idle, left grip = left brake only (thr %.2f/%.2f brk %.2f/%.2f)" % [o.thrL, o.thrR, o.brkL, o.brkR],
		o.thrL == 0.0 and o.thrR == 0.0 and o.brkL == 1.0 and o.brkR == 0.0)
	# mixed: held collective, spring steering
	q.scheme = "mixed"
	o = run(q, snap({"ls": Vector2(0, 1)}), 0.5)
	var held: float = q.collective
	o = run(q, snap(), 1.0)
	_check("mixed: collective holds after the stick returns (%.2f -> %.2f)" % [held, q.collective], held > 0.3 and q.collective == held)
	o = run(q, snap({"rs": Vector2(1, 0)}), 0.1)
	_check("mixed: full right steer eases the right engine (%.2f / %.2f)" % [o.thrL, o.thrR], o.thrR == 0.0 and o.thrL > 0.3)
	o = run(q, snap(), 0.1)
	_check("mixed: steering springs back (%.2f / %.2f)" % [o.thrL, o.thrR], o.thrL == o.thrR and o.thrL > 0.3)
	run(q, snap({"ls": Vector2(0, 1)}), 2.0)
	o = run(q, snap({"rs": Vector2(-0.6, 0)}), 0.1)
	_check("mixed: on the burner, left steer feathers the left brake, burner stays (thr %.2f/%.2f brk %.2f/%.2f)" % [o.thrL, o.thrR, o.brkL, o.brkR],
		o.thrL == 1.0 and o.thrR == 1.0 and o.brkL > 0.1 and o.brkR == 0.0)
	# grab: grip + push moves that lever, holds on release
	q.scheme = "grab"
	q.thr_l = 0.0
	q.thr_r = 0.0
	run(q, snap({"lg": 1.0, "lz": 0.0}), 0.05)
	o = run(q, snap({"lg": 1.0, "lz": -0.11}), 0.05)
	_check("grab: left hand 11 cm forward = half lever (%.2f), right untouched (%.2f)" % [o.thrL, o.thrR], absf(o.thrL - 0.5) < 1e-6 and o.thrR == 0.0)
	o = run(q, snap({"lg": 0.0, "lz": 0.3}), 0.1)
	_check("grab: let go and the lever stays (%.2f)" % o.thrL, absf(o.thrL - 0.5) < 1e-6)
	run(q, snap({"rg": 1.0, "rz": 0.2}), 0.05)
	o = run(q, snap({"rg": 1.0, "rz": 0.2 - 0.5}), 0.05)
	_check("grab: shoving past the end clamps at 1.0 (%.2f)" % o.thrR, o.thrR == 1.0)
	# gate ticks fire once per crossing
	q.scheme = "triggers"
	run(q, snap(), 0.5)
	var ticks := [0, 0]
	var same_frame := false
	for f in int(1.0 / DT):
		var tk: Dictionary = q.update(snap({"lt": 1.0, "rt": 1.0}), DT)
		ticks[0] += int(tk.tickL)
		ticks[1] += int(tk.tickR)
		same_frame = same_frame or (tk.tickL and tk.tickR)
	_check("both hands tick once as the levers cross the burner gate (%d / %d ticks, same frame %s)" % [ticks[0], ticks[1], same_frame],
		ticks[0] == 1 and ticks[1] == 1 and same_frame)
	# through the sim: each control must turn the craft the way the hand says
	_turn_check("triggers", snap({"lt": 0.55, "rt": 0.85}), -1.0, "right trigger harder")
	_turn_check("triggers", snap({"lt": 0.8, "rt": 0.8, "lg": 1.0}), 1.0, "left grip (brake)")
	_turn_check("mixed", snap({"rs": Vector2(0.8, 0)}), -1.0, "right stick right")
	# sticks: the original behaviour
	q.scheme = "sticks"
	q.thr_l = 0.0
	q.thr_r = 0.0
	run(q, snap({"ls": Vector2(0, 1), "rs": Vector2(0, 1)}), 0.5)
	o = run(q, snap({"rs": Vector2(0, -1)}), 0.2)
	var before := [o.thrL, o.thrR]
	o = run(q, snap({"lg": 1.0, "rg": 1.0}), 0.05)
	_check("sticks: both grips level to the lower (%.2f/%.2f -> %.2f/%.2f)" % [before[0], before[1], o.thrL, o.thrR],
		o.thrL == o.thrR and o.thrL == minf(before[0], before[1]))
	# cycling
	var seen := []
	for i in 4:
		seen.append(q.next_scheme())
	_check("menu cycles all four schemes %s" % [seen], seen.size() == 4 and seen[3] == "sticks" and seen.has("grab"))
	var good: bool = fails == 0 and passed == 31
	print("QUEST CONTROLS ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


## Fly CraftSim straight at ~0.6 lever for 3 s, then hold this control snapshot for 2 s (with live
## speed and yaw, so the straight-hold is in the loop) and check the heading turned the expected
## way (+1 left / counter-clockwise, -1 right).
func _turn_check(scheme: String, c: Dictionary, want: float, label: String) -> void:
	var q = QC.new()
	q.scheme = scheme
	q.collective = 0.6
	var sim = CraftSim.new({"track": "range", "startY": -3000.0})
	var cruise := {"thrL": 0.6, "thrR": 0.6, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	for i in 3 * 480:
		sim.step(cruise, 1.0 / 480.0)
	var th0: float = sim.pair_th
	for f in int(2.0 / DT):
		var live := c.duplicate()   # as the cockpit feeds it: speed and the engines' yaw rate, every frame
		live["speed"] = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		live["yaw"] = (sim.eL.w + sim.eR.w) / 2.0
		var o: Dictionary = q.update(live, DT)
		var u := {"thrL": o.thrL, "thrR": o.thrR, "brkL": o.brkL, "brkR": o.brkR, "repair": false, "reignite": true}
		for i in 480 / 72:
			sim.step(u, 1.0 / 480.0)
	var turned: float = rad_to_deg(CraftSim.wrap_angle(sim.pair_th - th0))
	_check("%s: %s turns %s (%.1f deg in 2 s)" % [scheme, label, "left" if want > 0.0 else "right", turned],
		signf(turned) == want and absf(turned) > 2.0)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
