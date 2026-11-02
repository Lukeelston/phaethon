## Flyability gate: an ideal pilot (no reaction delay, proportional on the heading to a point
## ahead) steers the GP's first 40 s through the trigger-throttle scheme exactly as a player does
## (QuestControls, crossed triggers) and must hold the track: no wall hits, a tight line, real
## progress. The squared-curve + slow-ramp mapping failed this (10 hits, a 16 m weave, stuck at
## 2.5 km: Luke's "skippy"); direct levers pass it (0 hits, 1.7 m).
## Then human fingers, against the unassisted mapping (no magnet, ramp, speed scaling or hold):
##   straight hold  both fingers aimed level at ~1,000 mph, each wandering on its own (sigma 0.05
##                  of travel, the size of Luke's measured mismatch): how far off line in 8 s?
##   launch mash    six "0 to 100" launches with one finger 60-100 ms late and/or a little short
##                  (absolute bars; the unassisted figures are printed for reference):
##                  how far does the heading swing (Luke: "sends me into a whirlwind")?
##   stroke pilot   accelerating from the line, correcting the way Luke's log shows (a 0.3 squeeze
##                  of one side whenever the heading is 1.5 deg off, 0.25 s late): how far does it
##                  swing (Luke: "the acceleration is still really hard to get into a straight line")?
## Prints CONTROLS FLYABLE PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_controls_flyable.gd
extends SceneTree

const QC := preload("res://input/quest_controls.gd")
const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 72.0
const SECONDS := 40.0
const LAUNCHES := [[0.06, 0.92, 1.0], [-0.06, 0.92, 1.0], [0.06, 1.0, 0.92], [-0.06, 1.0, 0.92], [0.03, 1.0, 1.0], [0.1, 0.85, 0.95]]


func _initialize() -> void:
	var fails := 0
	var q = _qc(true)
	var sim = S.new({"track": "gp"})
	var hits := 0
	var sq := 0.0
	var n := 0
	for f in int(SECONDS / DT):
		var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var ahead: int = (sim.pod.hint + int((60.0 + v * 0.36) / 12.0)) % sim.N
		var mx: float = (sim.eL.x + sim.eR.x) / 2.0
		var my: float = (sim.eL.y + sim.eR.y) / 2.0
		var err: float = S.wrap_angle(atan2(sim.tpy[ahead] - my, sim.tpx[ahead] - mx) - sim.pair_th)
		var d := clampf(-err * 2.0, -1.0, 1.0)   # right turn wanted (err < 0): squeeze right harder
		var c := 0.62 if v < 300.0 else 0.45
		hits += _step(sim, q, c - d / 2.0, c + d / 2.0)
		sim._nearest(sim.pod.x, sim.pod.y, sim.pod.hint, 40)
		sq += sim._n_lat * sim._n_lat
		n += 1
	var rms := sqrt(sq / n)
	var km: float = sim.pod.hint * sim.track_length / sim.N / 1000.0
	var ok := hits == 0 and rms < 8.0 and km > 8.0
	fails += int(not ok)
	print("  %s  ideal pilot on triggers, %d s of the GP: %d wall hits, line %.1f m RMS, %.1f km covered" % ["ok  " if ok else "FAIL", SECONDS, hits, rms, km])

	var st := _straight(true)
	var st_old := _straight(false)
	ok = st[0] < 50.0 and st[0] < st_old[0] / 2.5 and st[1] < 2.5
	fails += int(not ok)
	print("  %s  straight hold, jittery fingers at ~1,000 mph: %.0f m off line, %.1f deg in 8 s (old mapping %.0f m, %.1f deg)" % [
		"ok  " if ok else "FAIL", st[0], st[1], st_old[0], st_old[1]])

	var la := _launches(true)
	var la_old := _launches(false)
	# Absolute bars. (It used to be measured against the unassisted mapping too, but much of
	# that one's launch whirlwind was the tow bar creating energy; since CraftSim's energy
	# audit it barely spins out, and with no throttle ramp it is faster at 3 s by design.) The speed
	# bar is against a clean full pull through the same mapping: the burner's off the triggers now
	# (its detent lit it on one of these launches, and the bar was 900 km/h with that in it).
	var clean: float = _launches(true, [[0.0, 1.0, 1.0]])[3]
	ok = la[0] < 1.5 and la[1] < 5.0 and la[2] <= 2 and la[3] >= 0.9 * clean
	fails += int(not ok)
	print("  %s  launch mash x6: heading swing mean %.1f / worst %.1f deg, %d wall hits, %.0f km/h at 3 s, a clean full pull %.0f (old: %.1f / %.1f deg, %d hits, %.0f km/h)" % [
		"ok  " if ok else "FAIL", la[0], la[1], la[2], la[3], clean, la_old[0], la_old[1], la_old[2], la_old[3]])
	var sk := _stroke(true)
	var sk_old := _stroke(false)
	ok = sk[1] < 9.0 and sk[1] < sk_old[1] / 2.0 and sk[0] < sk_old[0] / 2.0 and sk[2] < sk_old[2]
	fails += int(not ok)
	print("  %s  stroke pilot accelerating straight: heading swings to %.1f deg, %.1f m off line, %.1f reversals in 10 s (unassisted %.1f deg, %.1f m, %.1f)" % [
		"ok  " if ok else "FAIL", sk[1], sk[0], sk[2], sk_old[1], sk_old[0], sk_old[2]])
	print("CONTROLS FLYABLE ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)


## The trigger scheme as shipped, or unassisted (no magnet, ramp, speed scaling or hold).
func _qc(shipped: bool):
	var q = QC.new()
	q.scheme = "triggers"
	if not shipped:
		q.magnet_w = 0.0
		q.ramp_up = 0.0
		q.speed_ref = 0.0
		q.hold_k = 0.0
	return q


func _step(sim, q, lt: float, rt: float) -> int:
	var o: Dictionary = q.update({"lt": clampf(lt, 0.0, 1.0), "rt": clampf(rt, 0.0, 1.0), "lg": 0.0, "rg": 0.0,
		"ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0,
		"speed": sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy), "yaw": (sim.eL.w + sim.eR.w) / 2.0}, DT)
	var inp := {"thrL": o.thrL, "thrR": o.thrR, "brkL": o.brkL, "brkR": o.brkR, "repair": false, "reignite": true}
	var hits := 0
	for k in 480 / 72:
		sim.step(inp, 1.0 / 480.0)
		for e in sim.events:
			if e.type == "hit":
				hits += 1
		sim.events.clear()
	return hits


## From the line on the range, both triggers to 0.7 over 0.3 s (one finger up to 0.12 s late,
## both jittering), holding the start line for 10 s with stroke corrections. Four seeds:
## [lateral RMS m, max heading swing deg, steering reversals].
func _stroke(shipped: bool) -> Array:
	var out := [0.0, 0.0, 0.0]
	for seed in [3, 4, 5, 6]:
		var q = _qc(shipped)
		var sim = S.new({"track": "range", "handling": "starfighter"})
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var x0: float = sim.pod.x
		var y0: float = sim.pod.y
		var th0: float = sim.pair_th
		var hist: Array[float] = []
		var nl := 0.0
		var nr := 0.0
		var sq := 0.0
		var hmax := 0.0
		var rev := 0
		var last := 0.0
		var lag := rng.randf_range(-0.12, 0.12)
		var n := int(10.0 / DT)
		for f in n:
			var t := f * DT
			var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			var lat: float = -(sim.pod.x - x0) * sin(th0) + (sim.pod.y - y0) * cos(th0)
			var head := S.wrap_angle(sim.pair_th - th0)
			hist.append(atan2(-lat, 30.0 + v) - head)   # aim 1 s down the start line
			var seen: float = hist[maxi(0, hist.size() - 1 - 18)]   # 0.25 s late
			var d := -0.3 * signf(seen) if absf(seen) > deg_to_rad(1.5) else 0.0   # squeeze the side to turn toward
			nl += -nl / 0.25 * DT + 0.05 * sqrt(2.0 * DT / 0.25) * rng.randfn()
			nr += -nr / 0.25 * DT + 0.05 * sqrt(2.0 * DT / 0.25) * rng.randfn()
			var pl := 0.7 * clampf((t - maxf(0.0, lag)) / 0.3, 0.0, 1.0)
			var pr := 0.7 * clampf((t - maxf(0.0, -lag)) / 0.3, 0.0, 1.0)
			_step(sim, q, pl - d / 2.0 + nl, pr + d / 2.0 + nr)
			if absf(d) > 0.0:   # a reversal: the pilot's squeeze switches side
				if last != 0.0 and signf(d) != last:
					rev += 1
				last = signf(d)
			sq += lat * lat
			hmax = maxf(hmax, absf(rad_to_deg(head)))
		out[0] += sqrt(sq / n) / 4.0
		out[1] += hmax / 4.0
		out[2] += rev / 4.0
	return out


## Mean distance off line and heading change after 8 s, four jitter seeds.
func _straight(shipped: bool) -> Array:
	var lat := 0.0
	var head := 0.0
	for seed in [5, 6, 7, 8]:
		var q = _qc(shipped)
		var sim = S.new({"track": "range", "handling": "starfighter"})
		for f in int(10.0 / DT):   # up to speed, fingers perfect
			_step(sim, q, 0.8, 0.8)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var nl := 0.0
		var nr := 0.0
		var y0: float = sim.pod.y
		var th0: float = sim.pair_th
		for f in int(8.0 / DT):   # each finger wanders on its own (Ornstein-Uhlenbeck, tau 0.25 s)
			nl += -nl / 0.25 * DT + 0.05 * sqrt(2.0 * DT / 0.25) * rng.randfn()
			nr += -nr / 0.25 * DT + 0.05 * sqrt(2.0 * DT / 0.25) * rng.randfn()
			_step(sim, q, 0.8 + nl, 0.8 + nr)
		lat += absf(sim.pod.y - y0) / 4.0
		head += absf(rad_to_deg(S.wrap_angle(sim.pair_th - th0))) / 4.0
	return [lat, head]


## [mean heading swing, worst, wall hits, mean km/h at 3 s] over the launch set. Each launch:
## [lag (s, + = left finger late), final left pull, final right pull], both reached in 0.1 s.
func _launches(shipped: bool, pats: Array = LAUNCHES) -> Array:
	var mean := 0.0
	var worst := 0.0
	var hits := 0
	var v3 := 0.0
	for pat in pats:
		var q = _qc(shipped)
		var sim = S.new({"track": "gp"})
		var th0: float = sim.pair_th
		for f in int(3.0 / DT):
			var t := f * DT
			var rt: float = pat[2] * clampf((t - maxf(0.0, -pat[0])) / 0.1, 0.0, 1.0)
			var lt: float = pat[1] * clampf((t - maxf(0.0, pat[0])) / 0.1, 0.0, 1.0)
			hits += _step(sim, q, lt, rt)
		var swing := absf(rad_to_deg(S.wrap_angle(sim.pair_th - th0)))
		mean += swing / pats.size()
		worst = maxf(worst, swing)
		v3 += sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 3.6 / pats.size()
	return [mean, worst, hits, v3]
