## The craft's attributes and powers, measured in the sim (sim/pilot_craft.gd TRAITS; Luke, 2026-11-24: "build the
## attributes and powers into the game"). Each attribute is measured twice on the same craft, as built and with
## that one attribute put back to 1 (sim.traits), so the ratio is the attribute's own whatever the chassis; and the
## top speeds against the Phaethon's. Each power is flown through what sets it off, and its effect measured:
##   attributes   top speed (thrustMax, engineCd), the grip limit (gripCapG: a sideslip's first step, both modes),
##                brake decel (brakes: SPEEDCRAFT at 2,500 mph, STARFIGHTER at 600), a wall's shove (wallShove: the
##                spring's push at a set depth, and the rebound off the circuit's wall), hang time (the Talon's lift)
##   powers       Slipstream's charge (6 s of drafting) and its thrust; Glide's hang time and steering in the air;
##                Kickdown's surge, its 0.3 s window and its 12 s recharge; Gyro Lock's grip and recharge; Ram
##                Plate's speed lost to a vehicle hit (and a smash made a shove, but not a pillar's); Ground
##                Effect's drag and what ends it; the Basilisk's turret drag
##   SAFE         nothing works with the switch at SAFE (no inp.power), and the Phaethon with none of the new
##                inputs flies exactly as it did (its multipliers 1, its lift 0)
## The Talon is flown as its row on the Phaethon's chassis (traitsOf) until it is merged; then as itself.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_traits.gd   Prints TRAITS PASS.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)


## A craft on the range's runway (or wherever `more` says), the Talon as its row until it is merged.
func _sim(craft: String, more := {}) -> Sim:
	var opts := {"vehicle": craft, "track": "range", "startY": -3000.0}
	if craft == "talon" and not Craft.NAMES.has("talon"):
		opts.vehicle = "phaethon"
		opts["traitsOf"] = "talon"
	opts.merge(more, true)
	return Sim.new(opts)


static func _go(sim: Sim, v: float, vy := 0.0) -> void:
	for b in sim.bodies:
		b.vx = v
		b.vy = vy


static func _inp(thr := 0.87, more := {}) -> Dictionary:
	var u := {"thrL": thr, "thrR": thr, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	u.merge(more, true)
	return u


## The craft's velocity, its centre of mass's.
static func _cm(sim: Sim) -> Vector2:
	var m := 0.0
	var v := Vector2.ZERO
	for b in sim.bodies:
		m += b.m
		v += Vector2(b.vx, b.vy) * b.m
	return v / m


static func _mass(sim: Sim) -> float:
	return sim.eL.m + sim.eR.m + sim.pod.m


static func _steps(sim: Sim, n: int, u: Dictionary) -> Array:
	var ev := []
	for i in n:
		sim.step(u, DT)
		for e: Dictionary in sim.events:
			if e.type == "power" or e.type == "bump" or e.type == "smash":
				ev.append(e.merged({"at": sim.time}))
		sim.events.clear()
	return ev


static func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol * absf(b)


# ---- the attributes --------------------------------------------------------------------------------------------

## Top speed on the levers (no burner), mph: from the Phaethon's own, 60 s.
func _top(craft: String, more := {}, inp_more := {}) -> float:
	var sim := _sim(craft, more)
	_go(sim, 1988.4)
	_steps(sim, 60 * 480, _inp(0.87, inp_more))
	return _cm(sim).length() * MPH


## The engines' grip limit, g: a sideslip of 50 m/s across the nose, its first step. Every force on the craft
## then is the grip's but for a little drag: take the pod's (its podCapG, saturated too) out of the whole.
func _grip_g(sim: Sim, inp_more := {}) -> float:
	sim.respawn()
	_go(sim, 0.0, 50.0)
	var before := _cm(sim).y
	_steps(sim, 1, _inp(0.0, inp_more))
	var a := (before - _cm(sim).y) / DT
	return (a * _mass(sim) / Sim.G - sim.pod.m * float(sim.P.podCapG)) / (2.0 * sim.eL.m)


## The brakes' own deceleration at speed v, m/s^2: with both brakes full less without, over 0.05 s.
func _brake_decel(sim: Sim, v: float) -> float:
	var d := []
	for brk in [1.0, 0.0]:
		sim.respawn()
		_go(sim, v)
		_steps(sim, 24, _inp(0.0, {"brkL": brk, "brkR": brk}))
		d.append((v - _cm(sim).x) / (24 * DT))
	return float(d[0]) - float(d[1])


## The coasting deceleration at speed v (the cruise drag's), m/s^2, over 0.05 s.
func _coast_decel(sim: Sim, v: float, inp_more := {}) -> float:
	_go(sim, v)
	var before := _cm(sim).x
	_steps(sim, 24, _inp(0.0, inp_more))
	return (before - _cm(sim).x) / (24 * DT)


## A wall's push on the pod's circle 0.2 m into the circuit's wall, standing still, N (this step's multipliers first).
func _wall_push(sim: Sim, inp_more := {}) -> float:
	sim._power_step(_inp(0.0, inp_more), DT)
	var i := 0
	var into: float = sim.tw[i] / 2.0 - 1.6 + 0.2
	sim.pod.x = sim.tpx[i] + sim.tnx[i] * into
	sim.pod.y = sim.tpy[i] + sim.tny[i] * into
	sim.pod.vx = 0.0
	sim.pod.vy = 0.0
	sim.pod.w = 0.0
	sim.pod.hint = i
	sim.pod.contact = [false, false]
	sim.pod.fx = 0.0
	sim.pod.fy = 0.0
	sim._collide_walls(sim.pod, [[sim.pod.x, sim.pod.y, 1.6]], DT)
	sim.events.clear()
	return Vector2(sim.pod.fx, sim.pod.fy).length()


## Into the circuit's wall: the craft set 12 m in from it on the start straight at 120 m/s and steered hard into it
## (a lever split of 0.57), for 3 s. -> (how far its outer engine went into the wall at the most, m: past where its
## circles first touch; how fast it came back off the wall, at the most, m/s across the road)
## (The way back off is mostly the craft's own grip and yaw, not the wall's spring: the depth is the spring's.)
func _into_wall(sim: Sim, inp_more := {}) -> Vector2:
	var n := Vector2(sim.tnx[0], sim.tny[0])
	var t := Vector2(sim.ttx[0], sim.tty[0])
	var p0 := Vector2(sim.tpx[0], sim.tpy[0])
	var shift: Vector2 = n * (sim.tw[0] / 2.0 - 12.0)
	for b in sim.bodies:
		b.x += shift.x
		b.y += shift.y
		b.vx = t.x * 120.0
		b.vy = t.y * 120.0
	var left := n.dot(Vector2(-t.y, t.x)) > 0.0      # (the wall on the craft's left: the right lever turns it in)
	var u := _inp(0.87, inp_more)
	if left:
		u.thrL = 0.3
	else:
		u.thrR = 0.3
	var deepest := -INF
	var out := 0.0
	for i in 3 * 480:
		sim.step(u, DT)
		sim.events.clear()
		for e in [sim.eL, sim.eR]:
			deepest = maxf(deepest, absf((Vector2(e.x, e.y) - p0).dot(n)) + 1.2 - sim.tw[0] / 2.0)
		out = maxf(out, -_cm(sim).dot(n))
	return Vector2(deepest, out)


## A jump off the range's 15 m kicker at 3,000 mph: the hang (s: the pod off the ground until it is down again)
## and how far its path turned in the air (degrees) with a lever split while it was up (`split`).
func _hang(sim: Sim, on: bool, split := 0.0) -> Vector2:
	_go(sim, 1341.12)
	var t_off := -1.0
	var hang := -1.0
	var path0 := 0.0
	var turned := 0.0
	for i in 16 * 480:
		var u := _inp(0.87, {"power": on})
		if t_off >= 0.0 and split > 0.0:
			u.thrL = 0.87 - split
		sim.step(u, DT)
		sim.events.clear()
		var clear: float = sim._pod_clear
		if t_off < 0.0 and clear < 1.0:
			t_off = sim.time
			path0 = atan2(sim.pod.vy, sim.pod.vx)
		elif t_off >= 0.0 and clear >= 1.0 and sim.time - t_off > 0.2:
			hang = sim.time - t_off
			turned = rad_to_deg(absf(angle_difference(path0, atan2(sim.pod.vy, sim.pod.vx))))
			break
	return Vector2(hang, turned)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	# ---- the table
	for id in Craft.ORDER + ["talon"]:
		var tr := Craft.traits(id)
		_check("%s has its row: %s, power %s" % [id, _row_text(tr), tr.power.get("name", "none")], not (tr.power as Dictionary).is_empty())
	var phaethon := _sim("phaethon")
	_check("the Phaethon's attributes are all 1 (lift 0): it flies as it did", phaethon.traits.thrustMax == 1.0 and phaethon.traits.engineCd == 1.0
		and phaethon.traits.gripCapG == 1.0 and phaethon.traits.brakes == 1.0 and phaethon.traits.wallShove == 1.0 and phaethon.traits.lift == 0.0)
	_steps(phaethon, 10, _inp(0.87, {"draft": true, "powerFire": true}))      # (no inp.power: SAFE)
	_check("at SAFE nothing works: drafting charges nothing and the button fires nothing (gauge %.2f, %s)" % [phaethon.power_gauge, phaethon.power_state],
		phaethon.power_gauge == 0.0 and phaethon.power_state == "charging" and phaethon.k_thrust == 1.0)

	# ---- top speeds, on the levers
	var top := {}
	for id in ["phaethon", "talon", "shrike", "orrery", "kiln", "vesper", "basilisk"]:
		top[id] = _top(id)
	top["basilisk gun out"] = _top("basilisk", {}, {"turretOut": true})
	var base: float = top.phaethon
	for id: String in top:
		var tr := Craft.traits(id.get_slice(" ", 0))
		var want := sqrt(float(tr.thrustMax) / (float(tr.engineCd) * (1.04 if id.ends_with("out") else 1.0)))
		_check("top speed, %s: %.0f mph, %+.2f%% on the Phaethon's %.0f (the table's %+.2f%%)" % [id, top[id], (top[id] / base - 1.0) * 100.0,
			base, (want - 1.0) * 100.0], _near(top[id] / base, want, 0.003))

	# ---- the grip limit (SPEEDCRAFT and STARFIGHTER) and Gyro Lock's
	for mode in ["speed", "starfighter"]:
		for id in ["talon", "shrike", "orrery", "vesper"]:
			var sim := _sim(id, {"handling": mode})
			var built := _grip_g(sim)
			sim.traits.gripCapG = 1.0
			var plain := _grip_g(sim)
			var want: float = Craft.traits(id).gripCapG
			_check("grip limit, %s, %s: %.2f g, x%.3f of %.2f g (the table's x%.2f)" % [id, mode, built, built / plain, plain, want], _near(built / plain, want, 0.01))

	# ---- brake decel (both modes)
	for mode in ["speed", "starfighter"]:
		var v := 1117.6 if mode == "speed" else 268.2
		for id in ["shrike", "kiln"]:
			var sim := _sim(id, {"handling": mode})
			var built := _brake_decel(sim, v)
			sim.traits.brakes = 1.0
			var plain := _brake_decel(sim, v)
			var want: float = Craft.traits(id).brakes
			_check("brake decel, %s, %s at %.0f mph: %.1f g, x%.3f (the table's x%.2f)" % [id, mode, v * MPH, built / Sim.G, built / plain, want], _near(built / plain, want, 0.01))

	# ---- a wall's shove: the Kiln's, and under its Ram Plate
	var kiln := _sim("kiln", {"track": "circuit"})
	var push_built := _wall_push(kiln)
	kiln.traits.wallShove = 1.0
	var push_plain := _wall_push(kiln)
	_check("wall shove, Kiln: %.0f kN at 0.2 m in, x%.3f (the table's x0.75)" % [push_built / 1000.0, push_built / push_plain], _near(push_built / push_plain, 0.75, 1e-6))
	var rb := {}
	for case in ["phaethon", "kiln", "kiln, its attribute 1", "kiln, Ram Plate"]:
		var s := _sim(case.get_slice(",", 0), {"track": "circuit"})
		if case.ends_with("1"):
			s.traits.wallShove = 1.0
		var more := {}
		if case.ends_with("Plate"):
			more = {"power": true}
			_steps(s, 1, _inp(0.0, {"power": true, "powerFire": true}))
			s.respawn()
		rb[case] = _into_wall(s, more)
	_check("steered into the circuit's wall at 270 mph, its outer engine leans in %.0f mm at the most (the Phaethon), %.0f mm (the Kiln; %.0f mm with its shove at 1), %.0f mm (the Kiln under Ram Plate)" % [
		rb.phaethon.x * 1000.0, rb.kiln.x * 1000.0, rb["kiln, its attribute 1"].x * 1000.0, rb["kiln, Ram Plate"].x * 1000.0],
		rb.kiln.x > rb["kiln, its attribute 1"].x and rb["kiln, Ram Plate"].x > rb.kiln.x and rb["kiln, its attribute 1"].x > 0.0)
	var ram_push := _sim("kiln", {"track": "circuit"})
	_steps(ram_push, 1, _inp(0.0, {"power": true, "powerFire": true}))
	var pushed := _wall_push(ram_push, {"power": true})
	_check("Ram Plate's wall shove: x%.3f of the Kiln's own (x0.5)" % (pushed / push_built), _near(pushed / push_built, 0.5, 1e-6))

	# ---- hang time: the Talon's lift, and Glide
	var plain_hang := _hang(_sim("phaethon", {"startX": 18000.0, "startY": 400.0}), false)
	var talon_safe := _hang(_sim("talon", {"startX": 18000.0, "startY": 400.0}), false)
	var talon_glide := _hang(_sim("talon", {"startX": 18000.0, "startY": 400.0}), true)
	_check("hang off the 15 m kicker at 3,000 mph: the Phaethon %.2f s, the Talon %.2f s at SAFE (x%.3f: its lift of 0.1 g), %.2f s gliding (x%.3f of its own)" % [
		plain_hang.x, talon_safe.x, talon_safe.x / plain_hang.x, talon_glide.x, talon_glide.x / talon_safe.x],
		plain_hang.x > 1.0 and talon_safe.x / plain_hang.x > 1.05 and talon_safe.x / plain_hang.x < 1.15 and talon_glide.x / talon_safe.x > 1.33 and talon_glide.x / talon_safe.x < 1.47)
	var steer_safe := _hang(_sim("talon", {"startX": 18000.0, "startY": 400.0}), false, 0.3)
	var steer_glide := _hang(_sim("talon", {"startX": 18000.0, "startY": 400.0}), true, 0.3)
	_check("the levers steer in the air: a split of 0.3 held aloft turns the Talon's path %.2f degrees gliding, %.2f at SAFE" % [steer_glide.y, steer_safe.y],
		steer_glide.y > 3.0 * maxf(steer_safe.y, 0.1))
	var flat := _sim("talon")
	_steps(flat, 480, _inp(0.87, {"power": true}))
	_check("no lift on the ground: the Talon armed runs the flat at ride height (%.4f m), its power not fired (%s)" % [flat.pod.z, flat.power_state],
		absf(flat.pod.z - float(flat.P.rideH)) < 0.001 and flat.power_state == "ready")

	# ---- Slipstream: its charge, its thrust
	var ph := _sim("phaethon")
	_go(ph, 447.04)
	var ev := _steps(ph, 3 * 480, _inp(0.87, {"power": true}))
	_check("Slipstream: no charge without a vehicle to draft (gauge %.2f after 3 s)" % ph.power_gauge, ph.power_gauge == 0.0 and ev.is_empty())
	ev = _steps(ph, 7 * 480, _inp(0.87, {"power": true, "draft": true}))
	var ready_at := -1.0
	for e: Dictionary in ev:
		if e.state == "ready":
			ready_at = float(e.at) - 3.0
	_check("Slipstream: full after %.3f s of drafting (6)" % ready_at, absf(ready_at - 6.0) <= 1.5 * DT and ph.power_state == "ready")
	var plain_ph := _sim("phaethon")
	for s in [ph, plain_ph]:
		s.respawn()
		_go(s, 447.04)
	ev = _steps(ph, 1, _inp(0.87, {"power": true, "powerFire": true}))
	var during := ph.k_thrust
	_steps(ph, 479, _inp(0.87, {"power": true}))
	_steps(plain_ph, 480, _inp(0.87))
	var gain := _cm(ph).x - 447.04
	var gain_plain := _cm(plain_ph).x - 447.04
	ev = _steps(ph, 4 * 480, _inp(0.87, {"power": true}))
	var ended_at := -1.0
	for e: Dictionary in ev:
		if e.state == "ended":
			ended_at = float(e.t)
	_check("Slipstream fired: thrust x%.3f (1.15) for %.3f s (4), %.1f mph gained in its first second against %.1f without (x%.3f), the gauge spent (%.2f)" % [
		during, ended_at, gain * MPH, gain_plain * MPH, gain / gain_plain, ph.power_gauge],
		is_equal_approx(during, 1.15) and absf(ended_at - 4.0) <= 1.5 * DT and gain / gain_plain > 1.12 and ph.power_gauge == 0.0)

	# ---- Kickdown: the surge, the window, the recharge
	var sh := _sim("shrike")
	_go(sh, 447.04)
	ev = _steps(sh, 240, _inp(0.0, {"power": true})) + _steps(sh, 1, _inp(0.87, {"power": true}))
	var kick_k := sh.k_thrust
	var fired_k := ev.filter(func(e): return e.state == "fired").size()
	ev = _steps(sh, 15 * 480, _inp(0.87, {"power": true}))
	var t_end := -1.0
	var t_ready := -1.0
	for e: Dictionary in ev:
		if e.state == "ended":
			t_end = float(e.at)
		if e.state == "ready":
			t_ready = float(e.at)
	_check("Kickdown: idle to full in a step fires it (%d), thrust x%.3f (1.35), %.3f s of it (1.5), ready again %.3f s after (12)" % [fired_k, kick_k,
		t_end - (0.5 + DT), t_ready - t_end], fired_k == 1 and is_equal_approx(kick_k, 1.35) and absf(t_end - (0.5 + DT) - 1.5) <= 1.5 * DT and absf(t_ready - t_end - 12.0) <= 1.5 * DT)
	for case in ["armed", "safe"]:
		var s := _sim("shrike")
		_go(s, 447.04)
		_steps(s, 240, _inp(0.0, {"power": case == "armed"}))
		_steps(s, 720, _inp(0.87, {"power": case == "armed"}))
		top[case] = _cm(s).x
	var surge_armed: float = top.armed - 447.04
	var surge_safe: float = top.safe - 447.04
	_check("Kickdown's surge: %.0f mph gained in the 1.5 s from the kick against %.0f at SAFE (x%.3f)" % [surge_armed * MPH, surge_safe * MPH, surge_armed / surge_safe],
		surge_armed / surge_safe > 1.25)
	var slow := _sim("shrike")
	_go(slow, 447.04)
	ev = _steps(slow, 240, _inp(0.0, {"power": true}))
	for i in 288:      # idle to full over 0.6 s
		ev += _steps(slow, 1, _inp(0.87 * float(i + 1) / 288.0, {"power": true}))
	ev += _steps(slow, 240, _inp(0.87, {"power": true}))
	_check("Kickdown: idle to full over 0.6 s does not fire it (%d events)" % ev.size(), ev.is_empty() and slow.power_state == "ready")

	# ---- Gyro Lock
	var orr := _sim("orrery")
	var g_before := _grip_g(orr)
	_steps(orr, 1, _inp(0.0, {"power": true, "powerFire": true}))
	var g_locked := _grip_g(orr, {"power": true})
	ev = _steps(orr, 20 * 480, _inp(0.0, {"power": true}))
	var gyro_end := -1.0
	var gyro_ready := -1.0
	for e: Dictionary in ev:
		if e.state == "ended":
			gyro_end = float(e.t)
		if e.state == "ready":
			gyro_ready = float(e.at)
	_check("Gyro Lock: the grip limit %.2f g -> %.2f g (x%.3f, 1.2) for %.2f s (4), ready again %.2f s after it ends (15)" % [g_before, g_locked, g_locked / g_before,
		gyro_end, gyro_ready - (2.0 * DT + 4.0)], _near(g_locked / g_before, 1.2, 0.01) and absf(gyro_end - 4.0) <= 2.0 * DT and absf(gyro_ready - (2.0 * DT + 4.0) - 15.0) <= 3.0 * DT)
	ev = _steps(_sim("orrery"), 1, _inp(0.0, {"powerFire": true}))
	_check("Gyro Lock's button at SAFE fires nothing (%d events)" % ev.size(), ev.is_empty())

	# ---- Ram Plate: a vehicle hit, a smash, a pillar
	var lost := {}
	for case in ["clear road", "hit", "hit, Ram Plate"]:
		var s := _sim("kiln")
		_go(s, 447.04)
		if case != "clear road":
			s.obstacles = [{"id": 1, "x": s.pod.x + 300.0, "y": s.pod.y, "vx": 200.0, "vy": 0.0, "r": 5.2}]
		_steps(s, 1, _inp(0.0, {"power": true, "powerFire": case.ends_with("Plate")}))
		ev = _steps(s, 3 * 480, _inp(0.0, {"power": true}))
		lost[case] = 447.04 - _cm(s).x
		lost[case + " bumps"] = ev.filter(func(e): return e.type == "bump").size()
	var by_hit: float = lost.hit - lost["clear road"]
	var by_ram: float = lost["hit, Ram Plate"] - lost["clear road"]
	_check("Ram Plate: a vehicle dead ahead at 1,000 mph closing 550 mph costs the Kiln %.1f mph (%d bumps), %.2f mph under the plate (%d shoves)" % [
		by_hit * MPH, lost["hit bumps"], by_ram * MPH, lost["hit, Ram Plate bumps"]], by_hit * MPH > 50.0 and absf(by_ram) * MPH < 1.0 and lost["hit, Ram Plate bumps"] > 0)
	var smash := {}
	for case in ["vehicle", "vehicle, Ram Plate", "pillar, Ram Plate"]:
		var s := _sim("kiln")
		_go(s, 1000.0)
		var o := {"id": 7, "x": s.pod.x + 300.0, "y": s.pod.y, "vx": 0.0, "vy": 0.0, "r": 5.2}
		if case.begins_with("pillar"):
			o["halfSize"] = 4.0
		s.obstacles = [o]
		_steps(s, 1, _inp(0.0, {"power": true, "powerFire": case.ends_with("Plate")}))
		ev = _steps(s, 480, _inp(0.0, {"power": true}))
		smash[case] = "smash" if ev.any(func(e): return e.type == "smash") else ("shove" if ev.any(func(e): return e.get("ram", false)) else "bump")
	_check("closing at 2,240 mph: a vehicle %s, under the plate %s; a pillar under the plate %s" % [smash.vehicle, smash["vehicle, Ram Plate"], smash["pillar, Ram Plate"]],
		smash.vehicle == "smash" and smash["vehicle, Ram Plate"] == "shove" and smash["pillar, Ram Plate"] == "smash")

	# ---- Ground Effect
	var ves := _sim("vesper")
	_go(ves, 1117.6)
	ev = _steps(ves, 300, _inp(0.87, {"power": true}))
	var engaged_at := -1.0
	for e: Dictionary in ev:
		if e.state == "fired":
			engaged_at = float(e.at)
	var drag_k := ves.k_drag
	var on_decel := _coast_decel(ves, 1117.6, {"power": true})
	var still_on := ves.power_state == "active"
	var plain_ves := _sim("vesper")
	var off_decel := _coast_decel(plain_ves, 1117.6)
	_check("Ground Effect: on at 2,500 mph after %.2f s straight (0.5); the cruise drag x%.3f of the Vesper's own (0.85), coasting %.2f g against %.2f (x%.3f)" % [
		engaged_at, drag_k / 0.88, on_decel / Sim.G, off_decel / Sim.G, on_decel / off_decel], absf(engaged_at - 0.5) <= 2.0 * DT and is_equal_approx(drag_k, 0.88 * 0.85)
		and still_on and _near(on_decel / off_decel, 0.85, 0.01))
	ev = _steps(ves, 24, _inp(0.87, {"power": true, "thrL": 0.72}))
	_check("... a split of 0.15 (turning hard) ends it (%s)" % ves.power_state, ves.power_state == "ready" and ev.any(func(e): return e.state == "ended"))
	var slowv := _sim("vesper")
	_go(slowv, 850.0)
	ev = _steps(slowv, 480, _inp(0.0, {"power": true}))
	_check("... and under 2,000 mph it never comes on (%d events at 1,900 mph)" % ev.size(), ev.is_empty())

	# ---- the Basilisk's turret
	var bas := _sim("basilisk")
	var in_decel := _coast_decel(bas, 1117.6)
	bas.respawn()
	var out_decel := _coast_decel(bas, 1117.6, {"turretOut": true})
	_check("the Basilisk's turret out: the cruise drag x%.3f (1.04)" % (out_decel / in_decel), _near(out_decel / in_decel, 1.04, 0.01))
	print("TRAITS took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("TRAITS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


static func _row_text(tr: Dictionary) -> String:
	var parts := []
	for k in Craft.TRAIT_DEFAULTS:
		if tr[k] != Craft.TRAIT_DEFAULTS[k]:
			parts.append("%s x%s" % [k, str(tr[k])] if k != "lift" else "lift %s g" % str(tr[k]))
	return "as the Phaethon" if parts.is_empty() else ", ".join(parts)
