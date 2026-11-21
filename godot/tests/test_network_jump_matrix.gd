## Real GDScript traversal at below-minimum, minimum and high speed for every ascent.
## The speed controller moves throttle levers only. Geometry is never bypassed.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const MPH := 2.236936
const DT := 1.0 / 480.0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var sim = Sim.new({"track": "network", "handling": "speed"})
	var peaks := []
	for k in sim.jumps.size():
		var minimum := float(sim.jumps[k][2])
		for pair in [["low", minimum - 500.0], ["minimum", minimum], ["high", maxf(4200.0, minimum + 500.0)]]:
			var r := _traverse(sim, k, float(pair[1]))
			var low: bool = pair[0] == "low"
			var good: bool = r.air and not r.crash and (not r.caught and r.settled if low else r.caught and r.linked and (r.on_deck if k < 4 else r.home))
			failures += int(not good)
			print("%s J%d %s %.0f MPH: lip %.0f, catch %s, ground/lower road %s, peak %.0f m, returned %s" % ["PASS" if good else "FAIL", k, pair[0], pair[1], r.lip_speed, r.caught, r.settled, r.peak, r.home])
			if pair[0] == "minimum":
				peaks.append(r.peak)
	if sim.jumps.size() != 21 or peaks.max() - peaks.min() < 900.0:
		failures += 1
	print("NETWORK JUMP MATRIX %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _traverse(sim, k: int, mph: float) -> Dictionary:
	var launch := int(sim.jumps[k][0])
	var catcher := int(sim.jumps[k][1])
	var L = sim.roads[launch]
	var i: int = L.N - 301
	var target := mph / MPH
	sim.respawn_on(launch, i, 1)
	sim.events.clear()
	for body in sim.bodies:
		body.vx = target * L.tx[i]
		body.vy = target * L.ty[i]
	var r := {"air": false, "caught": false, "settled": false, "crash": false, "peak": 0.0, "home": false, "on_deck": false, "linked": false, "lip_speed": 0.0}
	var caught_at := -1.0
	var feed: float = sim.P.gate * (2.0 * sim.P.engineCd + sim.P.podCd) * target * target / (2.0 * sim.P.thrustMax)
	for frame in int(70.0 / DT):
		var speed := Vector2(sim.pod.vx, sim.pod.vy).length()
		var lever := clampf(feed + (target - speed) * 0.003, 0.0, 0.87)
		sim.step({"thrL": lever, "thrR": lever, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		r.peak = maxf(r.peak, sim.pod.z)
		r.crash = r.crash or sim.crash_t > 0.0
		for e in sim.events:
			if e.type == "airborne" and e.lip:
				r.air = true
				r.lip_speed = e.v * MPH
			elif e.type == "catch" and int(e.road) == catcher:
				r.caught = true
				caught_at = frame * DT
			elif e.type == "ground" or e.type == "onroad":
				r.settled = true
		sim.events.clear()
		r.home = r.caught and not sim.pod.off_road and sim.pod.path != catcher and sim.pod.path != launch
		r.on_deck = r.caught and not sim.pod.off_road and sim.pod.path == catcher
		r.linked = sim.bodies.all(func(body): return not body.off_road)
		# Complete turning-transfer routes are separately driven by network_jump_test.js.
		if k < 4 and caught_at >= 0.0 and frame * DT - caught_at >= 2.0:
			break
		if r.home or r.settled:
			break
	return r
