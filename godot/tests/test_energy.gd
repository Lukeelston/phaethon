## Energy gate: with no thrust and no brakes the craft must never gain energy. The one-way tow
## bar (the pod follows the engines without yawing them back) used to create it: the pod whirled
## round a pivoting pair, or swung by a spinning one after wall hits, gained speed from nothing
## and the craft pinballed (a pod went 159 -> 495 km/h coasting; total energy x11 in a second).
## CraftSim's tow-bar energy audit (P.towAudit) takes that back out.
##   40 coasting trials on the GP: fly 2-6 s on a random lever and split, then cut everything for
##   8 s and let it hit the walls. Counted each second: total energy (speed + spin) rising by more
##   than 2% and 20 kJ, the pod's worst speed gain, wrecks. Audit on: none, none, none. Audit off:
##   the same trials must still show the bug, so this test can see it.
##   Handling untouched: yaw response to a 0.05 split at ~490 mph and coast-down from ~950 mph
##   match the audit-off sim.
## Prints ENERGY PASS. Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_energy.gd
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
var fails := 0
var passed := 0


func _initialize() -> void:
	# the tow-bar audit on its own: banking off (a banked corner trades height for speed, which
	# this 2D sim can't see as height; that gets its own bound below)
	var on := _coast({"bank": 0.0})
	var off := _coast({"towAudit": false, "bank": 0.0})
	var banked := _coast({})
	_check("audit on: coasting into the walls, energy never rises (%d of %d s, biggest %.0f kJ), the pod never gains more than 100 km/h (worst %.0f), no wrecks (%d s), no blow-ups (%d)" % [
		on.rises, on.seconds, on.big_kj, on.worst_kmh, on.wreck_s, on.blowups],
		on.rises == 0 and on.worst_kmh < 100.0 and on.wreck_s == 0 and on.blowups == 0)
	_check("audit off: the same trials still show the bug (%d s gaining energy, up to %.0f kJ in one; pod up to +%.0f km/h; %d s wrecked)" % [
		off.rises, off.big_kj, off.worst_kmh, off.wreck_s], off.rises >= 10 and off.worst_kmh > 100.0)
	_check("on the banked GP: coasting gains only what sliding down a bank can give (biggest %.0f kJ in a second, pod at most +%.0f km/h), no wrecks (%d s), no blow-ups (%d)" % [
		banked.big_kj, banked.worst_kmh, banked.wreck_s, banked.blowups],
		banked.big_kj < 200.0 and banked.worst_kmh < 100.0 and banked.wreck_s == 0 and banked.blowups == 0)
	var y_on := _yaw({})
	var y_off := _yaw({"towAudit": false})
	_check("steering untouched: 0.05 split at %.0f mph yaws %.2f deg/s with the audit, %.2f without" % [y_on[1], y_on[0], y_off[0]],
		absf(y_on[0] - y_off[0]) < 0.2 and y_off[0] > 5.0)
	var c_on := _coast_down({})
	var c_off := _coast_down({"towAudit": false})
	_check("coast-down untouched: %.0f mph after 8 s with the audit, %.0f without" % [c_on, c_off], absf(c_on - c_off) < c_off * 0.03)
	var good := fails == 0 and passed == 5
	print("ENERGY ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


func _energy(sim) -> float:
	var e := 0.0
	for b in [sim.pod, sim.eL, sim.eR]:
		e += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy) + 0.5 * b.inertia * b.w * b.w
	return e


func _coast(ov: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var r := {"rises": 0, "seconds": 0, "big_kj": 0.0, "worst_kmh": 0.0, "wreck_s": 0, "blowups": 0}
	for trial in 40:
		var o := {"track": "gp"}
		o.merge(ov, true)
		var sim = S.new(o)
		var lev := rng.randf_range(0.3, 0.87)
		var split := rng.randf_range(-0.4, 0.4)
		var t_drive := rng.randf_range(2.0, 6.0)
		var t := 0.0
		while t < t_drive:
			sim.step({"thrL": clampf(lev + split / 2.0, 0.0, 1.0), "thrR": clampf(lev - split / 2.0, 0.0, 1.0), "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
			sim.events.clear()
			t += DT
		var prev_v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var prev_e := _energy(sim)
		var blew := false
		for s in 8:
			var wrecked := false
			for k in 480:
				sim.step({"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
				sim.events.clear()
				if sim.crash_t > 0.0:
					wrecked = true
				for b in [sim.pod, sim.eL, sim.eR]:
					if b.vx * b.vx + b.vy * b.vy > 450.0 * 450.0:   # ~1,000 mph out of a coast
						blew = true
			var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
			var en := _energy(sim)
			if wrecked:   # a wreck respawns the craft: not a physics second
				r.wreck_s += 1
			else:
				r.seconds += 1
				if en > prev_e * 1.02 and en - prev_e > 20000.0:
					r.rises += 1
					r.big_kj = maxf(r.big_kj, (en - prev_e) / 1000.0)
				r.worst_kmh = maxf(r.worst_kmh, (v - prev_v) * 3.6)
			prev_v = v
			prev_e = en
		if blew:
			r.blowups += 1
	return r


## Yaw rate 2 s after a 0.05 thrust split at a steady ~490 mph (starfighter, open range).
func _yaw(ov: Dictionary) -> Array:
	var o := {"track": "range", "handling": "starfighter"}
	o.merge(ov, true)
	var sim = S.new(o)
	for k in 480 * 12:
		sim.step({"thrL": 0.25, "thrR": 0.25, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
	sim.events.clear()
	var mph: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936
	for k in 480 * 2:
		sim.step({"thrL": 0.275, "thrR": 0.225, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
	sim.events.clear()
	return [absf(rad_to_deg((sim.eL.w + sim.eR.w) / 2.0)), mph]


## Pod speed after 8 s coasting (with a gentle weave, so the pod swings) from full lever.
func _coast_down(ov: Dictionary) -> float:
	var o := {"track": "range", "handling": "starfighter"}
	o.merge(ov, true)
	var sim = S.new(o)
	for k in 480 * 12:
		sim.step({"thrL": 0.8, "thrR": 0.8, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
	for k in 480 * 8:
		var w := 0.08 * sin(TAU * 0.5 * k * DT)
		sim.step({"thrL": maxf(0.0, w), "thrR": maxf(0.0, -w), "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
	sim.events.clear()
	return sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy) * 2.236936


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
