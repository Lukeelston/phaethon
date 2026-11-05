## Actual Quest controls through the three-body sim: high-speed braking, steering and stability.
## Every trial runs exactly 3 s braking + 1 s released, at 480 Hz with 60 Hz controller updates.
## Optional user argument: JSON configuration file for measured tuning comparisons.
extends SceneTree

const S := preload("res://sim/craft_sim.gd")
const QC := preload("res://input/quest_controls.gd")
const DT := 1.0 / 480.0
const MPH := 2.2369362920544
var config := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		config = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var records := []
	for mph in [2000.0, 3000.0, 4000.0, 6000.0]:
		for controls in [["single", 0.0, 0.0, 1.0, 0.0], ["dual", 0.0, 0.0, 1.0, 1.0], ["uneven", 0.0, 0.0, 1.0, 0.85], ["steer", 1.0, 0.0, 0.0, 0.0], ["steer_brake", 1.0, 0.0, 1.0, 0.0], ["held_single", 1.0, 1.0, 1.0, 0.0], ["held_dual", 1.0, 1.0, 1.0, 1.0], ["right", 0.0, 0.0, 0.0, 1.0], ["half", 0.0, 0.0, 0.5, 0.0], ["feather", 0.0, 0.0, 0.2, 0.0], ["coast", 0.0, 0.0, 0.0, 0.0]]:
			records.append(trial(mph, 4, controls))
	for gear in [1, 2, 3, 4]:
		records.append(trial(1500.0, gear, ["gear_steer", 1.0, 0.0, 0.0, 0.0]))
		if gear != 4:
			records.append(trial(3000.0, gear, ["gear_brake", 0.0, 0.0, 1.0, 0.0]))
	for mph in [2000.0, 4000.0, 6000.0]:
		records.append(trial(mph, 4, ["held_release", 1.0, 1.0, 1.0, 0.0, true]))
	print(JSON.stringify(records))
	var fails := 0
	if config.get("verify", true):
		for r in records:
			var m: Dictionary = r.marks[2]
			if r.case == "single":
				var enough: bool = m.path_deg > (15.0 if r.mph == 6000.0 else 20.0)
				if not enough:
					push_error("Full one-hand brake at %.0f mph only bends the velocity %.2f degrees in 3 s" % [r.mph, m.path_deg])
					fails += 1
				if absf(m.nose_deg - m.path_deg) > 6.0 or r.sway > 3.0 or r.overrun > 1.0 or r.broken:
					push_error("Brake turn loses craft stability: " + JSON.stringify(r))
					fails += 1
			if r.case == "dual" and (absf(m.path_deg) > 0.01 or m.mph > r.mph * 0.7):
				push_error("Both brakes must slow down in a straight line: " + JSON.stringify(r))
				fails += 1
			if r.case in ["held_single", "held_dual"] and m.mph > r.mph * (0.95 if r.case == "held_single" else 0.85):
				push_error("Air brakes must also slow the craft with the triggers already held: " + JSON.stringify(r))
				fails += 1
			if r.sway > 3.0 or r.overrun > 1.0 or r.broken or absf(r.marks[3].path_deg - m.path_deg) > 2.0 or absf(r.marks[3].yaw_dps) > 0.5:
				push_error("Turn or release loses stability: " + JSON.stringify(r))
				fails += 1
			if r.case == "uneven" and absf(m.path_deg) > 7.0:
				push_error("Nearly equal brake grips must remain nearly straight: " + JSON.stringify(r))
				fails += 1
			if r.case == "right":
				for left in records:
					if left.mph == r.mph and left.case == "single":
						if absf(left.marks[2].path_deg + m.path_deg) > 0.01 or absf(left.marks[2].mph - m.mph) > 0.01:
							push_error("Left/right brakes must mirror each other")
							fails += 1
			if r.energy_rises > 0:
				push_error("Braking or coasting must not create kinetic energy: " + JSON.stringify(r))
				fails += 1
			if r.case == "half" or r.case == "feather":
				for full in records:
					if full.mph == r.mph and full.case == ("single" if r.case == "half" else "half"):
						if m.path_deg < 0.0 or m.path_deg >= full.marks[2].path_deg or m.mph <= full.marks[2].mph:
							push_error("Partial grip must produce gentler turn and deceleration")
							fails += 1
		var legacy := {"frontBrakeCd": 0.05, "frontBrakeV0": 670.6, "frontBrakeV1": 1117.6, "frontBrakeMaxG": 0.0, "brakeTurnG": 0.0}
		for mph in [400.0, 1000.0, 1240.0, 2000.0, 6000.0]:
			var controls := ["unchanged", 0.0, 0.0, 1.0 if mph < 1250.0 else 0.0, 0.0]
			var current := trial(mph, 4, controls)
			var prior := trial(mph, 4, controls, legacy)
			if absf(current.marks[2].path_deg - prior.marks[2].path_deg) > 0.0001 or absf(current.marks[2].mph - prior.marks[2].mph) > 0.0001:
				push_error("Low-speed brakes and unbraked coasting must retain original handling")
				fails += 1
		print("SPEED BRAKES ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)

func trial(mph: float, gear: int, controls: Array, overrides := {}) -> Dictionary:
	var ov := {"track": "range", "handling": "speed", "startY": -3000.0}
	ov.merge(config.get("physics", {}), true)
	ov.merge(overrides, true)
	var sim = S.new(ov)
	for b in sim.bodies:
		b.vx = mph / MPH
		b.vy = 0.0
	var q = QC.new()
	q.set_gear(gear)
	for key in config.get("controls", {}):
		q.set(key, config.controls[key])
	# Begin with the triggers already held, rather than letting the throttle ramp mask braking.
	for frame in 120:
		q.update({"lt": controls[1], "rt": controls[2], "lg": 0.0, "rg": 0.0,
			"ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0,
			"speed": mph / MPH, "yaw": 0.0, "sf": sim.hblend}, 1.0 / 60.0)
	var r := {"mph": mph, "gear": gear, "case": controls[0], "marks": [], "sway": 0.0, "overrun": 0.0, "binder": 0.0, "release_yaw": 0.0, "broken": false, "energy_rises": 0}
	var last_energy := energy(sim)
	var h0 := atan2(sim.pod.vy, sim.pod.vx)
	var n0: float = sim.pair_th
	var pod_n0: float = sim.pod.th
	var dist := 0.0
	var path := 0.0
	var prev_h := h0
	var out := {}
	var hold_throttle: bool = controls.size() > 5 and controls[5]
	for i in 4 * 480:
		if i % 8 == 0:
			var active := i < 3 * 480
			out = q.update({"lt": controls[1] if active or hold_throttle else 0.0, "rt": controls[2] if active or hold_throttle else 0.0,
				"lg": controls[3] if active else 0.0, "rg": controls[4] if active else 0.0,
				"ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0,
				"speed": hypot(sim.pod.vx, sim.pod.vy), "yaw": (sim.eL.w + sim.eR.w) / 2.0, "sf": sim.hblend}, 1.0 / 60.0)
			r["brakes"] = [out.brkL, out.brkR] if i == 0 else r.brakes
			r["pull"] = out.mul if i == 0 else r.pull
		var inp := {"thrL": out.thrL, "thrR": out.thrR, "brkL": out.brkL, "brkR": out.brkR, "thrMul": out.mul,
			"gearOverdrive": out.overdrive, "burner": out.burner, "repair": false, "reignite": true}
		sim.step(inp, DT)
		sim.events.clear()
		var h := atan2(sim.pod.vy, sim.pod.vx)
		path += wrapf(h - prev_h, -PI, PI)
		prev_h = h
		dist += hypot(sim.pod.vx, sim.pod.vy) * DT
		var pf := cos(sim.pair_th)
		var ps := sin(sim.pair_th)
		var mx: float = (sim.eL.x + sim.eR.x) / 2.0
		var my: float = (sim.eL.y + sim.eR.y) / 2.0
		var back: float = sim.P.engineLen / 2.0 + sim.P.cableLen + sim.P.podLen / 2.0
		r.overrun = maxf(r.overrun, (sim.pod.x - (mx - pf * back)) * pf + (sim.pod.y - (my - ps * back)) * ps)
		r.sway = maxf(r.sway, absf(rad_to_deg(wrapf(atan2(my - sim.pod.y, mx - sim.pod.x) - sim.pair_th, -PI, PI))))
		r.binder = maxf(r.binder, absf(sim.binder_stretch))
		r.broken = r.broken or sim.binder_broken
		if i >= 3 * 480:
			r.release_yaw = maxf(r.release_yaw, absf(rad_to_deg((sim.eL.w + sim.eR.w) / 2.0)))
		if i + 1 in [240, 480, 1440, 1920]:
			var t := (i + 1) * DT
			r.marks.append({"t": t, "path_deg": rad_to_deg(path), "nose_deg": rad_to_deg(wrapf(sim.pair_th - n0, -PI, PI)),
				"pod_nose_deg":rad_to_deg(wrapf(sim.pod.th-pod_n0,-PI,PI)),
				"mph": hypot(sim.pod.vx, sim.pod.vy) * MPH, "radius_m": dist / maxf(absf(path), 1e-9), "distance_m": dist,
				"decel_g": (mph / MPH - hypot(sim.pod.vx, sim.pod.vy)) / t / 9.81,
				"yaw_dps": rad_to_deg((sim.eL.w + sim.eR.w) / 2.0)})
		if (i + 1) % 240 == 0:
			var now_energy := energy(sim)
			if (controls[1] == 0.0 and controls[2] == 0.0 or (i >= 3 * 480 and not hold_throttle)) and now_energy > last_energy * 1.001 + 100.0:
				r.energy_rises += 1
			last_energy = now_energy
	return r

func energy(sim) -> float:
	var e := 0.0
	for b in sim.bodies:
		e += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy) + 0.5 * b.inertia * b.w * b.w
	return e

func hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)
