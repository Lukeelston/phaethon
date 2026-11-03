## Fifth gear has logarithmic speed growth, with real brakes and no free thrust.
extends SceneTree
const S := preload("res://sim/craft_sim.gd")
const DT := 1.0 / 480.0
var failures := 0
var checks := 0

func _initialize() -> void:
	var gains := []
	for speed in [2000.0, 4000.0, 6000.0]:
		gains.append(_gain(speed, true, 0.87, 0.0))
	_check("full-throttle fifth still accelerates above the old top speed", gains.all(func(g): return g > 0.1))
	_check("equal time gains shrink progressively with speed", gains[0] > gains[1] * 1.5 and gains[1] > gains[2] * 1.5)
	_check("ordinary drive retains its terminal-speed behavior", _gain(4000.0, false, 0.87, 0.0) < 0.0)
	_check("throttle release slows fifth at high speed", _gain(4000.0, true, 0.0, 0.0) < 0.0)
	_check("brakes overcome full-throttle fifth", _gain(4000.0, true, 0.87, 1.0) < 0.0)
	_check("failed engines cannot sustain overdrive", _gain(4000.0, true, 0.87, 0.0, true) < 0.0)
	for handling in ["speed", "starfighter"]:
		var reference := 2000.0 if handling == "speed" else 443.0
		for boost in ["normal", "burner", "ramjet"]:
			var slow := _boost_gain(reference * 2.0, handling, boost)
			var fast := _boost_gain(reference * 3.0, handling, boost)
			_check(handling + " " + boost + " gains speed more slowly farther out", slow > fast and fast > 0.05)
	var sim = _sim(2000.0)
	var speeds := [2000.0]
	for frame in 480 * 120:
		sim.step(_input(true, 0.87, 0.0), DT)
		sim.events.clear()
		# Keep the infinite-drive test on the finite range, preserving the rigid-body state.
		if sim.pod.x > 50000.0:
			for body in sim.bodies:
				body.x -= 40000.0
		if (frame + 1) % (480 * 30) == 0:
			speeds.append(_speed(sim))
	var intervals := []
	for i in range(1, speeds.size()):
		intervals.append(speeds[i] - speeds[i - 1])
	_check("two minutes of fifth keep adding speed without a plateau", intervals.all(func(g): return g > 10.0) and sim.result.is_empty())
	_check("long-run increments taper rather than grow", intervals[0] > intervals[1] and intervals[1] > intervals[2] and intervals[2] > intervals[3])
	_check("straight high-speed flight stays finite and intact", is_finite(sim.pod.x) and is_finite(sim.pod.vy) and not sim.binder_broken and absf(sim.pod.y) < 10.0)
	print("OVERDRIVE METRICS: five-second gains m/s=", gains, " 30-second speeds m/s=", speeds)
	print("OVERDRIVE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func _sim(speed: float):
	var sim = S.new({"track": "range", "handling": "speed"})
	for body in sim.bodies:
		body.vx = speed * cos(sim.pair_th)
		body.vy = speed * sin(sim.pair_th)
	return sim

func _input(overdrive: bool, throttle: float, brake: float) -> Dictionary:
	return {"thrL": throttle, "thrR": throttle, "brkL": brake, "brkR": brake, "repair": false, "reignite": false, "gearOverdrive": overdrive}

func _boost_gain(speed: float, handling: String, boost: String) -> float:
	var sim = S.new({"track": "range", "handling": handling})
	for body in sim.bodies:
		body.vx = speed * cos(sim.pair_th)
		body.vy = speed * sin(sim.pair_th)
	sim.armed = boost == "ramjet"
	var inp := _input(true, 0.87, 0.0)
	inp.burner = boost != "normal"
	for frame in 480 * 2:
		sim.step(inp, DT)
		sim.events.clear()
	return _speed(sim) - speed

func _speed(sim) -> float:
	return sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)

func _gain(speed: float, overdrive: bool, throttle: float, brake: float, failed := false) -> float:
	var sim = _sim(speed)
	if failed:
		sim.eL.flameout = true
		sim.eR.flameout = true
	for frame in 480 * 5:
		sim.step(_input(overdrive, throttle, brake), DT)
		sim.events.clear()
	return _speed(sim) - speed

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
