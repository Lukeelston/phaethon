## The gears (input/quest_controls.gd, triggers; Luke: "experiment with giving the craft gears, using
## the right stick. That might eliminate the pingpong i keep getting, while keeping the
## responsiveness in the corners"; then "the gears should rise and fall like actual gears - not just
## operate at lower or higher frequencies"):
##   shifting    a flick of the right stick up shifts up once (held, no more), back under SHIFT_OFF
##               re-arms; down shifts down; 1 and 4 are the ends
##   box         a full pull is full lever in every gear, the burner only in top; at the same revs the
##               low gears pull harder (their ratios); no gearbox is exactly as before
##   sawtooth    full levers from a standstill on SPEEDCRAFT, shifting up at the redline: the revs climb
##               through each gear and drop at each shift (to the ratio of the redlines), to top speed;
##               the engine sound's spool follows them (it's what EngineAudio pitches its voices by)
##   limiter     held in first, the speed stops at first's redline (the revs on it)
##   grab        a shift: the clutch out (the pull dips), then the next gear grabs (a surge, once, a
##               grab signal for the cockpit's shudder and the hands' thump), settling to the gear's pull
##   overshoot   a pilot correcting like Luke's log (one trigger dropped whole, the nose seen 0.3 s
##               late) changing lanes at 3,000 mph on SPEEDCRAFT: top gear overshoots under half as
##               far as no gearbox (his flight's wag log: top gear 0.2-0.9 deg/s, first 3.5-8.9)
##   corners     top gear at 4,000 mph: a held drop still turns the path faster than the Network's
##               tightest highway bend needs (2.3 deg/s); the GP on STARFIGHTER in top gear (where its
##               revs put it) laps without a wall
## Prints GEARS PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_gears.gd
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const QC := preload("res://input/quest_controls.gd")
const DT := 1.0 / 72.0
const MPH := 2.236936
var fails := 0


func _initialize() -> void:
	# shifting
	var q = QC.new()
	q.scheme = "triggers"
	q.set_gear(0)
	var seen := []
	for y in [0.0, 0.9, 0.95, 0.9, 0.5, 0.2, 0.9, 0.1, 0.9, 0.1, 0.9, 0.1, 0.9, 0.1, -0.9, -0.9, 0.0, -0.9]:
		q.update(_c(0.5, 0.5, Vector2(0.0, y)), DT)
		seen.append(q.gear + 1)
	var want := [1, 2, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4, 3, 3, 3, 2]
	_check("shifting: right stick flicks %s -> gears %s" % ["up x5, down x2", seen], seen == want)
	# the box
	var levers := []
	var pulls := []
	var burner_low := false
	var burner_top := false
	for g in 4:
		var qg = _q(g)
		var o: Dictionary = {}
		var vg := 0.5 * float(QC.GEARS[g][2]) * QC.V_TOP_SPEED   # at half its revs
		for k in 300:
			o = qg.update(_c(1.0, 1.0, Vector2.ZERO, vg), DT)
		levers.append(snappedf(o.thrL, 0.001))
		pulls.append(snappedf(o.mul, 0.001))
		var cl := _c(1.0, 1.0, Vector2.ZERO, vg)   # the burner's flick (the left stick)
		cl.ls = Vector2(0.0, 1.0)
		o = qg.update(cl, DT)
		if g < 3 and (bool(o.burner) or maxf(o.thrL, o.thrR) >= QC.GATE):
			burner_low = true
		if g == 3:
			burner_top = bool(o.burner)
	var q0 = QC.new()
	q0.scheme = "triggers"
	var q1 = QC.new()
	q1.scheme = "triggers"
	q1.set_gear(-1)
	var same := true
	for k in 200:
		var cc := _c(0.5 + 0.4 * sin(k * 0.1), 0.5 + 0.4 * cos(k * 0.13), Vector2.ZERO, 300.0)
		var a: Dictionary = q0.update(cc, DT)
		var b: Dictionary = q1.update(cc, DT)
		same = same and a.thrL == b.thrL and a.thrR == b.thrR and float(a.get("mul", 1.0)) == 1.0
	_check("box: a full pull's lever by gear %s, the burner below top gear %s, in top %s; the pull at half revs %s; no gearbox as before %s" % [levers, burner_low, burner_top, pulls, same],
		levers.all(func(x): return absf(x - QC.FULL) < 0.01) and burner_top and not burner_low
		and pulls[0] > pulls[1] and pulls[1] > pulls[2] and pulls[2] > pulls[3] and same)
	# the sawtooth
	var saw := _sawtooth()
	_check("sawtooth: shifts at %s mph, the engine's spool before each %s and after %s; %.0f mph at the end (top gear)" % [saw[0], saw[1], saw[2], saw[3]],
		saw[0].size() == 3 and saw[1].all(func(x): return x >= 0.95) and saw[2].all(func(x): return x < 0.8) and saw[3] > 4000.0)
	var lim := _limited()
	_check("limiter: held in first at full levers, %.0f mph after 20 s (first's redline %.0f), the revs %.2f" % [lim[0], lim[1], lim[2]],
		absf(lim[0] - lim[1]) < lim[1] * 0.06 and lim[2] > 0.93 and lim[2] < 1.03)
	# the grab
	var qg = _q(0)
	var vg := 0.8 * float(QC.GEARS[1][2]) * QC.V_TOP_SPEED   # in second's band
	for k in 10:
		qg.update(_c(0.9, 0.9, Vector2.ZERO, vg), DT)
	qg.update(_c(0.9, 0.9, Vector2(0.0, 0.9), vg), DT)   # shift up
	var trace := []
	var grabs := []
	for k in 50:
		var o: Dictionary = qg.update(_c(0.9, 0.9, Vector2.ZERO, vg), DT)
		trace.append(o.mul)
		if o.grab > 0.0:
			grabs.append([k, o.grab])
	var base: float = trace[-1]
	var dip: float = trace.slice(0, 7).min()
	var surge: float = trace.slice(8, 20).max()
	_check("grab: the pull after a shift up dips to %.2f, surges to %.2f, settles at %.2f; grabs %s" % [dip, surge, base, grabs],
		dip < base * 0.4 and surge > base * 1.2 and grabs.size() == 1 and grabs[0][1] == 1.0 and absf(trace[-1] - trace[-2]) < 1e-6)
	# overshoot
	var none := _lanes(-1)
	var top := _lanes(3)
	_check("overshoot: changing lanes at 3,000 mph on SPEEDCRAFT, correcting all or nothing a beat late: %.1f m past the line in top gear, %.1f with no gearbox" % [top, none],
		top < none / 2.0)
	# corners
	var tr := _turn(3)
	var gp := _gp(3)
	_check("corners: top gear at 4,000 mph, a held drop turns the path %.2f deg/s (the highways' tightest bend: 2.28); the ideal pilot on the GP in top gear (STARFIGHTER): %d wall hits, %.1f km in 60 s" % [tr, gp[0], gp[1]],
		tr > 2.8 and gp[0] == 0 and gp[1] > 12.0)
	print("GEARS ", "PASS" if fails == 0 else "FAIL (%d failed)" % fails)
	quit(0 if fails == 0 else 1)


func _c(lt: float, rt: float, rs := Vector2.ZERO, v := -1.0, yaw := 0.0, sf := 0.0) -> Dictionary:
	var c := {"lt": lt, "rt": rt, "lg": 0.0, "rg": 0.0, "ls": Vector2.ZERO, "rs": rs, "lz": 0.0, "rz": 0.0}
	if v >= 0.0:
		c.speed = v
		c.yaw = yaw
		c.vtop = lerpf(QC.V_TOP_SPEED, QC.V_TOP_SF, sf)
		c.sf = sf
	return c


func _q(g: int):
	var q = QC.new()
	q.scheme = "triggers"
	q.set_gear(g)
	return q


## One frame of q driving sim: the levers, the gearbox's pull as thrMul. -> the output.
func _fly(sim, q, lt: float, rt: float) -> Dictionary:
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	var o: Dictionary = q.update(_c(lt, rt, Vector2.ZERO, v, (sim.eL.w + sim.eR.w) / 2.0, sim.hblend), DT)
	for k in 480 / 72:
		sim.step({"thrL": o.thrL, "thrR": o.thrR, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "thrMul": o.get("mul", 1.0)}, 1.0 / 480.0)
	sim.events.clear()
	return o


## From a standstill on the range (SPEEDCRAFT) at full levers (no burner), shifting up when the revs
## reach 0.95 (where the limiter starts): [mph at each shift, revs just before, revs just after, mph after 45 s].
func _sawtooth() -> Array:
	var sim = S.new({"track": "range", "handling": "speed"})
	var q = _q(0)
	var at := []
	var before := []
	var after := []
	var shifted := -1
	for f in int(45.0 / DT):
		_fly(sim, q, 0.95, 0.95)
		if shifted >= 0 and f == shifted + 1:
			after.append(snappedf(QC.engine_spool(q.rpm, 1.0), 0.01))
		if q.gear < 3 and q.rpm >= 0.95:
			at.append(roundi(sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * MPH))
			before.append(snappedf(QC.engine_spool(q.rpm, 1.0), 0.01))
			q.set_gear(q.gear + 1)
			shifted = f
	return [at, before, after, sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * MPH]


## Held in first at full levers on the range for 20 s: [mph, first's redline mph, revs].
func _limited() -> Array:
	var sim = S.new({"track": "range", "handling": "speed"})
	var q = _q(0)
	for f in int(20.0 / DT):
		_fly(sim, q, 0.95, 0.95)
	return [sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * MPH, float(QC.GEARS[0][2]) * QC.V_TOP_SPEED * MPH, q.rpm]


## Luke's corrections: both triggers near full; when the nose looks more than ~1 deg off the way
## to the line (seen 0.3 s late), drop the trigger on the far side whole, till it looks right. The
## line steps 150 m across every 5 s, at 3,000 mph on SPEEDCRAFT. Mean distance past the line after
## each step, m (2 seeds).
func _lanes(g: int) -> float:
	var total := 0.0
	for seed in [11, 12]:
		var sim = S.new({"track": "range", "handling": "speed"})
		var q = _q(g)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var th0: float = sim.pair_th
		var x0: float = sim.pod.x
		var y0: float = sim.pod.y
		for b in sim.bodies:
			b.vx = 3000.0 / MPH * cos(th0)
			b.vy = 3000.0 / MPH * sin(th0)
		var delay := int(rng.randf_range(0.25, 0.35) / DT)
		var thr := deg_to_rad(rng.randf_range(0.8, 1.2))
		var hist: Array[float] = []
		var corr := 0.0
		var target := 0.0
		var over := 0.0
		var steps := 0
		var peak := 0.0
		for f in int(22.0 / DT):
			if f % int(5.0 / DT) == 0:
				if f > 0:
					over += peak
					steps += 1
				peak = 0.0
				target = 150.0 * (1.0 if (f / int(5.0 / DT)) % 2 == 0 else -1.0) * rng.randf_range(0.8, 1.2)
			var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			var lat: float = -(sim.pod.x - x0) * sin(th0) + (sim.pod.y - y0) * cos(th0)
			var head := S.wrap_angle(sim.pair_th - th0)
			hist.append(atan2(target - lat, maxf(v, 50.0) * 2.0) - head)
			var seen: float = hist[maxi(0, hist.size() - 1 - delay)]
			if corr == 0.0:
				if absf(seen) > thr:
					corr = signf(seen)
			elif signf(seen) != corr or absf(seen) < deg_to_rad(0.2):
				corr = 0.0
			_fly(sim, q, 0.0 if corr < 0.0 else 0.95, 0.0 if corr > 0.0 else 0.95)
			if f * DT > 2.0:
				peak = maxf(peak, (lat - target) * signf(target))
		total += over / maxf(1.0, steps) / 2.0
	return total


## A held drop (left trigger let go, right full) for 6 s from 4,000 mph in gear g (SPEEDCRAFT): the
## path's turn rate over the last 3 s, deg/s.
func _turn(g: int) -> float:
	var sim = S.new({"track": "range", "handling": "speed"})
	var q = _q(g)
	var th0: float = sim.pair_th
	for b in sim.bodies:
		b.vx = 4000.0 / MPH * cos(th0)
		b.vy = 4000.0 / MPH * sin(th0)
	var a3 := 0.0
	for f in int(6.0 / DT):
		_fly(sim, q, 0.0, 0.95)
		if f == int(3.0 / DT):
			a3 = atan2(sim.pod.vy, sim.pod.vx)
	return absf(rad_to_deg(S.wrap_angle(atan2(sim.pod.vy, sim.pod.vx) - a3))) / 3.0


## The ideal pilot (tests/test_controls_flyable.gd's) on the GP (STARFIGHTER) in gear g for 60 s:
## [wall hits, km]. (With no gearbox it does 0 hits, 15.1 km.)
func _gp(g: int) -> Array:
	var sim = S.new({"track": "gp"})
	var q = _q(g)
	var hits := 0
	for f in int(60.0 / DT):
		var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var ahead: int = (sim.pod.hint + int((60.0 + v * 0.36) / 12.0)) % sim.N
		var mx: float = (sim.eL.x + sim.eR.x) / 2.0
		var my: float = (sim.eL.y + sim.eR.y) / 2.0
		var err: float = S.wrap_angle(atan2(sim.tpy[ahead] - my, sim.tpx[ahead] - mx) - sim.pair_th)
		var d := clampf(-err * 2.0, -1.0, 1.0)
		var c := 0.62 if v < 300.0 else 0.45   # (the flyability test's pilot)
		var o: Dictionary = q.update(_c(c - d / 2.0, c + d / 2.0, Vector2.ZERO, v, (sim.eL.w + sim.eR.w) / 2.0, sim.hblend), DT)
		for k in 480 / 72:
			sim.step({"thrL": o.thrL, "thrR": o.thrR, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "thrMul": o.get("mul", 1.0)}, 1.0 / 480.0)
			for e in sim.events:
				if e.type == "hit":
					hits += 1
			sim.events.clear()
	return [hits, sim.pod.hint * sim.track_length / sim.N / 1000.0]


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		fails += 1
