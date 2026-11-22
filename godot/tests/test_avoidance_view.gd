## The avoidance field's eyes and its glue in the view (view/avoidance_field.gd, view/craft_view.gd;
## Luke, 2026-11-22: "Add a collision avoidance force field"), on the Network with real traffic:
##   eyes     a vehicle put in the craft's path: the push asked for is across the path, away from
##            it, 2 d / t^2; nothing with OBSTACLE COLLISIONS off, nothing for a vehicle on another
##            level; with the wall near on the side it would dodge to, it dodges the other way; boxed
##            in by a second vehicle and the wall, it asks for nothing
##   flown    the craft at 3,000 mph closing on a slow vehicle dead ahead (a smash's closing speed):
##            with the field off it is a smash and a crash; on, it is missed, with room to spare,
##            and nothing touched; the same with a pillar's worth of standing thing in the road
##   glue     switched on, the view hands the sims inp.avoid and the eyes' push each step; off, neither
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_avoidance_view.gd -- --mute
## Prints AVOIDANCE VIEW PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Eyes := preload("res://view/avoidance_field.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
var v
var failures := 0
var checks := 0
var road := 3            # N1
var at := 300            # a straight (tools/field_test.js)
var pool: Array = []     # the traffic's own vehicles, borrowed


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_avoidance_view_")
	View.avoid_on = false
	v = View.new()
	root.add_child(v)
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The craft on the straight, `lat` m left of the road's middle, flying up it at mph.
func _place(lat: float, mph: float) -> void:
	var sim = v.sim
	var R = sim.roads[road]
	sim.respawn_on(road, at, 1)
	for b in sim.bodies:
		b.x += R.nx[at] * lat
		b.y += R.ny[at] * lat
		b.vx = mph / MPH * R.tx[at]
		b.vy = mph / MPH * R.ty[at]
	sim.crash_t = 0.0
	sim.events.clear()


## The traffic emptied but for vehicles put `ahead` m up the road, `lat` m left of its middle, going the craft's
## way at `speed` m/s: [[ahead, lat, speed], ...].
func _put(T, things: Array) -> void:
	var R = v.sim.roads[road]
	var keep: Array = []
	for k in things.size():
		var c = pool[k]
		var f: float = at + float(things[k][0]) / 24.0
		var i := int(f)
		c.kind = T.CAR
		c.road = road
		c.f = f
		c.dir = 1
		c.lat = float(things[k][1])
		c.v = float(things[k][2])
		c.hx = R.tx[i]
		c.hy = R.ty[i]
		c.x = R.px[i] + R.tx[i] * (f - i) * R.len[i] + R.nx[i] * c.lat
		c.y = R.py[i] + R.ty[i] * (f - i) * R.len[i] + R.ny[i] * c.lat
		keep.append(c)
	T.cars.assign(keep)


## The craft flown at the vehicles as they stand, hands off the levers, for `secs`: the field `on` or off.
## -> {smash, bumps, nearest (m, pod to the nearest vehicle's middle), field_s, pushed (most asked, m/s^2), threat}
func _fly(T, on: bool, secs: float) -> Dictionary:
	var sim = v.sim
	var eyes = Eyes.new()
	var out := {"smash": false, "bumps": 0, "nearest": INF, "field_s": 0.0, "pushed": 0.0, "threat": "", "avoids": 0}
	for frame in int(secs * 60.0):
		T._feed()
		var push := eyes.look(sim, T, v.network_world) if on else Vector2.ZERO
		out.pushed = maxf(out.pushed, push.length())
		if eyes.threat != "":
			out.threat = eyes.threat
		for k in 8:
			var inp := {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
			if on:
				inp["avoid"] = true
				inp["avoidPush"] = [push.x, push.y]
			sim.step(inp, DT)
			for e in sim.events:
				if e.type == "smash":
					out.smash = true
				elif e.type == "bump":
					out.bumps += 1
				elif e.type == "avoid":
					out.avoids += 1
			sim.events.clear()
			if sim.avoid_a > 0.0:
				out.field_s += DT
		for c in T.cars:
			c.x += c.hx * c.v / 60.0
			c.y += c.hy * c.v / 60.0
			c.f += c.v / 60.0 / 24.0
			out.nearest = minf(out.nearest, Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length())
	return out


func _run() -> void:
	var until := Time.get_ticks_msec() + 5000      # the traffic spawns round the craft
	while Time.get_ticks_msec() < until:
		await process_frame
	v.set_process(false)
	var T = v.traffic_net
	var sim = v.sim
	var R = sim.roads[road]
	var cars_before: Array = T.cars.duplicate()
	pool = cars_before
	_check("there is traffic to borrow (%d vehicles), and the straight is 400 m wide" % T.cars.size(), T.cars.size() >= 3 and absf(float(R.w[at]) - 400.0) < 1.0)
	T.collide = true
	sim.P.obstacleCollisions = true
	var eyes = Eyes.new()
	var left := Vector2(R.nx[at], R.ny[at])
	# ---- the eyes ----
	_place(0.0, 3000.0)
	_put(T, [[1200.0, 2.0, 100.0]])            # dead ahead, 2 m to the left of the craft's line, going its way at 224 mph
	var push: Vector2 = eyes.look(sim, T, v.network_world)
	var closing := 3000.0 / MPH - 100.0
	var t_meet := 1200.0 / closing
	var want := 2.0 * (Eyes.CRAFT_HALF + 2.6 * 2.0 + Eyes.MARGIN - 2.0) / (t_meet * t_meet)
	_check("a vehicle 1,200 m ahead, 2 m left of the craft's line, closed on at %.0f m/s (%.2f s off): the eyes ask for %.1f m/s^2 to the right (2 d / t^2 is %.1f), across the path, and call it a %s" % [
		closing, t_meet, push.length(), want, eyes.threat],
		eyes.threat == "vehicle" and eyes.side == -1.0 and push.dot(left) < 0.0 and absf(push.length() - want) < 0.05 * want and absf(push.dot(Vector2(R.tx[at], R.ty[at]))) < 1e-6)
	sim.P.obstacleCollisions = false
	var blind: Vector2 = eyes.look(sim, T, v.network_world)
	sim.P.obstacleCollisions = true
	sim.pod.z += 60.0
	var other_level: Vector2 = eyes.look(sim, T, v.network_world)
	sim.pod.z -= 60.0
	_check("with OBSTACLE COLLISIONS off there is nothing to miss and nothing asked; nor for a vehicle 60 m below the craft's level", blind == Vector2.ZERO and other_level == Vector2.ZERO)
	_put(T, [[1200.0, 40.0, 100.0]])
	_check("a vehicle 40 m to the side of the craft's line is not in its way: nothing asked", eyes.look(sim, T, v.network_world) == Vector2.ZERO)
	_place(-(200.0 - Eyes.EDGE_KEEP - 4.0), 3000.0)      # 18 m from the right wall
	_put(T, [[1200.0, -(200.0 - Eyes.EDGE_KEEP - 4.0) + 2.0, 100.0]])
	push = eyes.look(sim, T, v.network_world)
	_check("the same vehicle met 18 m from the right wall (the dodge to the right would end %.0f m from it): it dodges left instead, the long way round (%.1f m/s^2)" % [18.0 - (Eyes.CRAFT_HALF + 5.2 + Eyes.MARGIN - 2.0), push.length()],
		eyes.side == 1.0 and push.dot(left) > 0.0 and push.length() > want)
	_put(T, [[1200.0, -(200.0 - Eyes.EDGE_KEEP - 4.0) + 2.0, 100.0], [1230.0, -(200.0 - Eyes.EDGE_KEEP - 4.0) + 20.0, 100.0]])
	push = eyes.look(sim, T, v.network_world)
	_check("boxed in, the wall on one side and a second vehicle where the other dodge would go: nothing is asked (it weighed %d)" % eyes.seen, push == Vector2.ZERO and eyes.seen == 2)
	# ---- flown ----
	var told := []
	var ok := true
	for case in [["a slow vehicle dead ahead", [[1500.0, 0.0, 60.0]]], ["one 3 m off the line", [[1500.0, -3.0, 60.0]]], ["a thing standing in the road", [[1500.0, 1.0, 0.0]]]]:
		_place(0.0, 3000.0)
		_put(T, case[1])
		var off := _fly(T, false, 2.0)
		_place(0.0, 3000.0)
		_put(T, case[1])
		var on := _fly(T, true, 2.0)
		told.append("%s: off, %s, nearest %.1f m; on, %s, nearest %.1f m (pushed %.0f m/s^2 at most, the field %.2f s)" % [case[0], "a smash" if off.smash else ("%d bumps" % off.bumps), off.nearest,
			"a smash" if on.smash else ("%d bumps" % on.bumps), on.nearest, on.pushed, on.field_s])
		ok = ok and off.smash and not on.smash and on.bumps == 0 and on.nearest > Eyes.CRAFT_HALF + 5.2 and on.pushed <= float(sim.P.avoidMaxA) and on.threat == "vehicle" and on.avoids <= 3
	_check("at 3,000 mph, hands off the levers' balance: " + "; ".join(told), ok)
	sim.crash_t = 0.0
	# ---- the glue ----
	_place(0.0, 3000.0)
	_put(T, [[1200.0, 2.0, 100.0]])
	View.avoid_on = true
	v._avoid_push = Vector2(3.0, -4.0)
	v.inp = {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	v._sim_step()
	var handed: bool = v.inp.get("avoid", false) == true and v.inp.get("avoidPush", []) == [3.0, -4.0] and sim.avoid_a > 0.0 and v.avoid_text() == "   FIELD"
	View.avoid_on = false
	v._sim_step()
	_check("switched on, the view hands the sims inp.avoid and the eyes' push each step and its readout says FIELD; off, neither, and the sim's field is at rest",
		handed and not v.inp.has("avoid") and not v.inp.has("avoidPush") and sim.avoid_a == 0.0 and v.avoid_text() == "")
	T.cars.assign(cars_before)
	T.collide = false
	sim.P.obstacleCollisions = false
	v.queue_free()
	await process_frame
	print("AVOIDANCE VIEW %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
