## The avoidance field in the sim (sim/craft_sim.gd: inp.avoid, inp.avoidPush; Luke, 2026-11-22:
## "Add a collision avoidance force field"): scripted approaches to a wall, the field off against on.
##   walls     a Network highway's straight, the craft set down 150 m from its left wall and flown
##             at it at an angle, at a speed, the levers held: glancing approaches miss the wall
##             with the field on, squarer ones are softened or missed, none is made worse
##   along     set down along the wall, the field does nothing; leaning on a wall is still allowed
##   demand    inp.avoidPush moves the craft sideways as one, and is capped
##   energy    with the limits on it spends the battery, and is dead on a flat one
##   off       not asked for, a flight is step for step what it was
##   parity    three of the flights end where sim-core.js's do (node tools/field_test.js sim-core.js --figures)
## --headless -s res://tests/test_avoidance_field.gd      Prints AVOIDANCE FIELD PASS.
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
const START := 150.0
# tools/field_test.js --figures, 2026-11-22
const JS := [
	{"deg": 6, "mph": 2000, "road": 3, "i": 300, "x": 99889.294248, "y": 36555.558233, "vx": 53.185947, "vy": 1257.091448, "contacts": 0, "field_s": 1.5271, "peak": 51.0216},
	{"deg": 12, "mph": 500, "road": 3, "i": 300, "x": 99822.921130, "y": 34277.092349, "vx": 34.449569, "vy": 798.983559, "contacts": 0, "field_s": 1.5938, "peak": 60.3387},
	{"deg": 30, "mph": 4000, "road": 3, "i": 300, "x": 100045.134233, "y": 37743.810496, "vx": -93.468226, "vy": 1461.437996, "contacts": 4, "field_s": 1.0250, "peak": 300.0000},
]
var fails := 0
var checks := 0


func _check(label: String, ok: bool) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	fails += int(not ok)


## A craft on road 3 (N1) at sample 300, its pod `start` m from the left wall, turned `deg` toward that
## wall and flying the way it points at mph (tools/field_test.js setUp).
func _set_up(start: float, deg: float, mph: float, limits := false) -> S:
	var sim := S.new({"track": "network", "handling": "speed"})
	var R: S.TrackPath = sim.roads[3]
	var i := 300
	sim.respawn_on(3, i, 1)
	var th := deg_to_rad(deg)
	var c := cos(th)
	var s := sin(th)
	var v := mph / MPH
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var off: float = R.w[i] / 2.0 - start
	for b: S.Body in sim.bodies:
		var dx := b.x - px
		var dy := b.y - py
		b.x = px + dx * c - dy * s + R.nx[i] * off
		b.y = py + dx * s + dy * c + R.ny[i] * off
		b.th += th
		b.vx = v * (R.tx[i] * c + R.nx[i] * s)
		b.vy = v * (R.ty[i] * c + R.ny[i] * s)
	if limits:
		sim.set_limits(true)
	return sim


## A flight: {contacts, crashes, peak_g (sideways on the pod), kept, field_s, field_peak, avoids, low_battery, sim}.
func _fly(start: float, deg: float, mph: float, field, opts := {}) -> Dictionary:
	var sim := _set_up(start, deg, mph, bool(opts.get("limits", false)))
	if opts.get("drained", false):
		sim.battery = 0.0
	var R: S.TrackPath = sim.roads[3]
	var nx: float = R.nx[300]
	var ny: float = R.ny[300]
	var lev: float = opts.get("lev", 0.6)
	var out := {"contacts": 0, "crashes": 0, "peak_g": 0.0, "field_s": 0.0, "field_peak": 0.0, "avoids": 0, "low_battery": 1.0, "sim": sim}
	var v0 := sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var push: Array = opts.get("push", [])
	for k in int(round(float(opts.get("secs", 4.0)) / DT)):
		var inp := {"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		if field != null:
			inp["avoid"] = field
		if not push.is_empty():
			inp["avoidPush"] = [nx * float(push[0]), ny * float(push[0])] if k < int(push[1]) else [0.0, 0.0]
		var l0: float = sim.pod.vx * nx + sim.pod.vy * ny
		sim.step(inp, DT)
		out.peak_g = maxf(out.peak_g, absf(sim.pod.vx * nx + sim.pod.vy * ny - l0) / DT / 9.81)
		for e in sim.events:
			if e.type == "hit" or e.type == "scrape":
				out.contacts += 1
			elif e.type == "crash" or e.type == "smash":
				out.crashes += 1
			elif e.type == "avoid":
				out.avoids += 1
		sim.events.clear()
		out.field_peak = maxf(out.field_peak, sim.avoid_a)
		if sim.avoid_a > 0.0:
			out.field_s += DT
		out.low_battery = minf(out.low_battery, sim.battery)
	out.kept = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) / v0
	out.lat = (sim.pod.x - R.px[300]) * nx + (sim.pod.y - R.py[300]) * ny
	return out


func _initialize() -> void:
	# ---- walls ----
	var glancing := []
	var square := []
	for mph in [500.0, 2000.0, 4000.0]:
		for deg in [3.0, 6.0, 12.0, 30.0]:
			var off := _fly(START, deg, mph, null)
			var on := _fly(START, deg, mph, true)
			(glancing if deg <= 6.0 else square).append([off, on, "%d deg at %d mph: %d -> %d contacts, %.0f -> %.0f g" % [deg, mph, off.contacts, on.contacts, off.peak_g, on.peak_g]])
	var told := []
	var touch_off := 0
	var clean := true
	for row in glancing:
		told.append(row[2])
		touch_off += int(row[0].contacts > 0)
		clean = clean and row[1].contacts == 0 and row[1].peak_g < 40.0
	_check("glancing approaches from %d m out, the field off -> on (%s): none touches the wall with it on, and none is turned harder than 40 g" % [START, "; ".join(told)], clean and touch_off >= 3)
	told = []
	var never_worse := true
	var missed := 0
	var softened := 0
	for row in square:
		told.append(row[2])
		never_worse = never_worse and row[1].contacts <= row[0].contacts and row[1].peak_g <= row[0].peak_g * 1.02 + 1.0 and row[1].crashes <= row[0].crashes
		missed += int(row[1].contacts == 0)
		softened += int(row[1].peak_g < 0.8 * row[0].peak_g)
	_check("squarer ones (%s): missed where there is time (%d of 6), else softened (%d of 6 under four fifths of the blow), never worse" % ["; ".join(told), missed, softened],
		never_worse and missed >= 2 and softened >= 4)
	var speed_ok := true
	var spam_ok := true
	for row in glancing + square:
		speed_ok = speed_ok and row[1].kept >= row[0].kept - 0.02
		spam_ok = spam_ok and row[1].avoids <= 6
	_check("it never costs speed worth the name (within 2% of the flight without it, every one), and it reports a save once, not once a step", speed_ok and spam_ok)
	# ---- along the wall ----
	var hug := _fly(12.0, 0.0, 2000.0, true, {"secs": 2.0})
	var hug_off := _fly(12.0, 0.0, 2000.0, null, {"secs": 2.0})
	_check("set down along the wall 12 m off it at 2,000 mph, 2 s: the field does nothing (%.2f s working) and the flight is the one without it" % hug.field_s,
		hug.field_s == 0.0 and hug.sim.pod.x == hug_off.sim.pod.x and hug.sim.pod.y == hug_off.sim.pod.y and hug.sim.pod.vx == hug_off.sim.pod.vx)
	var lean := _fly(6.0, 0.25, 2000.0, true, {"secs": 1.2})
	_check("leaning on a wall is still allowed: closing on it at %.1f m/s from 6 m the field stays out of it (%.2f s working)" % [2000.0 / MPH * sin(deg_to_rad(0.25)), lean.field_s], lean.field_s == 0.0)
	# ---- the view's demand ----
	var plain := _fly(200.0, 0.0, 2000.0, null, {"secs": 1.0})
	var pushed := _fly(200.0, 0.0, 2000.0, true, {"secs": 1.0, "push": [98.1, 240]})
	var over := _fly(200.0, 0.0, 2000.0, true, {"secs": 1.0, "push": [900.0, 240]})
	var moved: float = pushed.lat - plain.lat
	_check("a demand of 10 g to the left for half a second in the road's middle: the craft is %.1f m further left a second on (a t^2 / 2 and the coast after: 36.8 m), its speed %.2f%% of the flight without; a demand of 92 g is given as %.1f g" % [
		moved, pushed.kept / plain.kept * 100.0, over.field_peak / 9.81],
		moved > 22.0 and moved < 52.0 and absf(pushed.kept / plain.kept - 1.0) < 0.01 and absf(over.field_peak - 300.0) < 1e-6)
	# ---- energy ----
	var paid := _fly(START, 6.0, 2000.0, true, {"limits": true})
	var flat := _fly(START, 6.0, 2000.0, true, {"limits": true, "drained": true, "lev": 1.0})   # (the burner held on a flat battery: it does not charge)
	_check("with the heat and energy on a save costs battery (the 6 deg approach at 2,000 mph: %.1f%% of it); flat, with the burner held so that it stays flat, the field is dead and the wall is met as before (%d contacts, %.2f s working)" % [
		(1.0 - paid.low_battery) * 100.0, flat.contacts, flat.field_s],
		paid.low_battery < 0.99 and paid.low_battery > 0.7 and paid.contacts == 0 and flat.field_s == 0.0 and flat.contacts > 0)
	# ---- off ----
	var never := _fly(START, 6.0, 2000.0, null)
	var no := _fly(START, 6.0, 2000.0, false)
	_check("not asked for, or asked not to: the same flight to the last bit, and nothing of the field in the sim's state",
		never.sim.pod.x == no.sim.pod.x and never.sim.pod.y == no.sim.pod.y and never.sim.pod.vx == no.sim.pod.vx and never.sim.eL.th == no.sim.eL.th
		and never.field_peak == 0.0 and no.field_peak == 0.0 and never.avoids + no.avoids == 0 and never.sim.avoid_src == "")
	# ---- parity with sim-core.js ----
	var worst := 0.0
	var same := true
	for j in JS:
		var o := _fly(START, float(j.deg), float(j.mph), true)
		var p: S.Body = o.sim.pod
		worst = maxf(worst, maxf(maxf(absf(p.x - float(j.x)), absf(p.y - float(j.y))), maxf(absf(p.vx - float(j.vx)), absf(p.vy - float(j.vy)))))
		same = same and o.contacts == int(j.contacts) and absf(o.field_s - float(j.field_s)) < 0.01 and absf(o.field_peak - float(j.peak)) < 0.01
	_check("three of the flights (6 deg at 2,000 mph, 12 at 500, 30 at 4,000), field on, end where sim-core.js's do: the pod within %.6f m and m/s after 4 s, the same contacts, the field working as long and as hard" % worst, worst < 1e-3 and same)
	print("AVOIDANCE FIELD %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)
