## The autopilot (view/autopilot.gd; Luke: "Add autopilot."), in the sim alone and then in a view.
##   the port     its route finder, speed plan and pilot are tools/net_route.js's: from Eridanus to
##                Glacier with no cruise cap it must give the recorded drive's own inputs, frame for
##                frame (replay/network_inputs.json), and so the recorded arrival
##   routes       there is a drive between every pair of cities, none through a shaft, a deck road,
##                a jump or the Aurora Line
##   holds        engaged at 2,400 and at 1,200 mph on a highway it holds that speed and the road's
##                middle for three minutes, hands off, and touches no wall
##   a route      engaged standing in Eridanus it flies to the city the dash points at, takes the
##                exits on the way and arrives, then carries on toward the next
##   traffic      a slow vehicle in its lane: it moves over and passes; a wall of them: it slows
##   the view     in a CraftView: engaged, it has the levers; a lever moved gives the craft back;
##                off, the frame's inputs are the pilot's own
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_autopilot.gd -- --mute
## Prints AUTOPILOT PASS.
extends SceneTree

const CraftSimScript := preload("res://sim/craft_sim.gd")
const Autopilot := preload("res://view/autopilot.gd")
const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 480.0
const SUB := 8
const MPH := 2.236936
const ASK := ["", "speed", "starfighter"]
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_autopilot_")
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _city(sim, name: String) -> int:
	for k in sim.cities.size():
		if String(sim.cities[k].name) == name:
			return k
	return -1


## Fly `sim` under `a` for `seconds`, the pilot asked every SUB steps as the recorder asks it.
## -> {hits, scrapes, arrivals: [[city, t]], mph: [least, most] once `settle` s have passed,
## off: the most the pod was from its road's middle (m), given_back}
func _fly(sim, a, seconds: float, city: int, cars: Array = [], settle := 30.0) -> Dictionary:
	var out := {"hits": 0, "scrapes": 0, "arrivals": [], "mph": [INF, 0.0], "off": 0.0, "given_back": false, "smash": 0}
	var frames := int(seconds / (SUB * DT))
	for f in frames:
		var u: Dictionary = a.fly(sim, city, cars)
		if u.is_empty():
			out.given_back = true
			break
		var inp := {"thrL": u.thrL, "thrR": u.thrR, "brkL": u.brkL, "brkR": u.brkR, "repair": false, "reignite": true, "handling": u.handling}
		for k in SUB:
			sim.step(inp, DT)
			for e in sim.events:
				match String(e.type):
					"hit":
						out.hits += 1
					"scrape":
						out.scrapes += 1
					"smash":
						out.smash += 1
					"arrive":
						out.arrivals.append([int(e.city), float(e.t)])
						city = _next_city(sim, int(e.city))
			sim.events.clear()
		if f * SUB * DT >= settle:
			var mph := Vector2(sim.pod.vx, sim.pod.vy).length() * MPH
			out.mph = [minf(out.mph[0], mph), maxf(out.mph[1], mph)]
			var R = sim.roads[sim.pod.path]
			var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
			out.off = maxf(out.off, absf((sim.pod.x - R.px[i]) * R.nx[i] + (sim.pod.y - R.py[i]) * R.ny[i]))
	out.city = city
	return out


## The dash's rule, near enough: the nearest other city.
func _next_city(sim, from: int) -> int:
	var best := -1
	var bd := INF
	for k in sim.cities.size():
		if k == from:
			continue
		var d := Vector2(sim.cities[k].cx - sim.pod.x, sim.cities[k].cy - sim.pod.y).length()
		if d < bd:
			bd = d
			best = k
	return best


func _port() -> void:
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_expected.json"))
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/network_inputs.json"))
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var e: Dictionary = sim.cities[_city(sim, "ERIDANUS")]
	var g: Dictionary = sim.cities[_city(sim, "GLACIER")]
	var a = Autopilot.new()
	var legs: Array = Autopilot.legs_to(sim, {"road": int(e.road), "i": int(e.i), "dir": 0}, {"road": int(g.road), "i": int(g.i)}, false)
	var plain: Array = Autopilot.legs_to(sim, {"road": int(e.road), "i": int(e.i), "dir": 0}, {"road": int(g.road), "i": int(g.i)}, true)
	var names := []
	for L in legs:
		names.append(String(sim.roads[int(L.road)].name))
	_check("the drive from Eridanus to Glacier: %d legs (%s), the same with the special roads left out" % [legs.size(), " ".join(names)], legs.size() >= 4 and str(legs) == str(plain))
	var last: Dictionary = legs[legs.size() - 1]
	last.i1 = clampi(int(last.i1) + int(last.dir) * Autopilot.PAST_GOAL, 0, int(sim.roads[int(last.road)].N) - 1)
	a.cruise = Autopilot.SP_TOP
	a.like_recorded = true
	a.set_route(sim, legs)
	var st: Array = X.start
	sim.respawn_on(int(st[0]), int(st[1]), int(st[2]))
	var differ := 0
	var worst := 0.0
	var first := -1
	var arrivals := []
	var hits := 0
	var ended := -1
	for f in inputs.size():
		var want: Array = inputs[f]
		var u: Array = a.pilot(sim)
		if u.is_empty():
			ended = f
			break
		var d := 0.0
		for q in 4:
			d = maxf(d, absf(float(u[q]) - float(want[q])))
		if d > 1.5e-4 or int(u[4]) != int(want[4]):
			differ += 1
			if first < 0:
				first = f
		worst = maxf(worst, d)
		var inp := {"thrL": float(u[0]), "thrR": float(u[1]), "brkL": float(u[2]), "brkR": float(u[3]), "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp["handling"] = ASK[int(u[4])]
		for k in SUB:
			sim.step(inp, DT)
			for ev in sim.events:
				if ev.type == "hit" or ev.type == "scrape":
					hits += 1
				elif ev.type == "arrive":
					arrivals.append([f, int(ev.city), float(ev.t)])
			sim.events.clear()
	# (not every frame: flat out the pilot chatters between two levers at its limit, 4,291 mph against 4,300, and at a
	# brake's threshold; the two sims agree to a micron, not to the last bit, and which frame the chatter falls on differs)
	_check("its own inputs over that drive are the recorded pilot's on %.1f%% of %d frames (the first other at %d: its chatter at a threshold, the most by %.2f); the route ended at frame %d" % [
		100.0 * (inputs.size() - differ) / inputs.size(), inputs.size(), first, worst, ended],
		differ * 10 < inputs.size() and (ended < 0 or ended >= inputs.size() - 2))
	var xa: Array = X.arrivals[0]
	_check("and so its arrival is the recorded one: %s (recorded frame %d, %.2f s), %d wall contacts" % [arrivals, int(xa[0]), float(xa[3]), hits],
		arrivals.size() == 1 and int(arrivals[0][0]) == int(xa[0]) and absf(float(arrivals[0][2]) - float(xa[3])) < 0.01 and hits == 0)


func _routes() -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var none := []
	var odd := []
	var longest := 0
	for a in sim.cities.size():
		for b in sim.cities.size():
			if a == b:
				continue
			var from: Dictionary = sim.cities[a]
			var to: Dictionary = sim.cities[b]
			for dir in [1, -1]:
				var legs: Array = Autopilot.legs_to(sim, {"road": int(from.road), "i": int(from.i), "dir": dir}, {"road": int(to.road), "i": int(to.i)})
				if legs.is_empty():
					none.append("%s>%s %d" % [from.name, to.name, dir])
					continue
				longest = maxi(longest, legs.size())
				for k in range(1, legs.size() - 1):
					if Autopilot.special(sim, int(legs[k].road)):
						odd.append("%s>%s by %s" % [from.name, to.name, sim.roads[int(legs[k].road)].name])
	# (leaving a city the wrong way there may be nothing but the highway's end and its shaft: then the shaft it is)
	var stuck := []
	for row in none:
		var parts: PackedStringArray = String(row).split(" ")
		var names: PackedStringArray = parts[0].split(">")
		var from: Dictionary = sim.cities[_city(sim, names[0])]
		var to: Dictionary = sim.cities[_city(sim, names[1])]
		if Autopilot.legs_to(sim, {"road": int(from.road), "i": int(from.i), "dir": int(parts[1])}, {"road": int(to.road), "i": int(to.i)}, false).is_empty():
			stuck.append(row)
	_check("a drive from every city to every other, leaving either way (%d cities), the longest %d legs, none through a shaft, a deck road, a jump or the Aurora Line (%s) but %d that have no other way out (%s), and none with no way at all (%s)" % [
		sim.cities.size(), longest, odd, none.size(), none, stuck], stuck.is_empty() and odd.is_empty() and longest >= 3 and none.size() <= 8)


func _road(sim, name: String) -> int:
	for r in sim.roads.size():
		if String(sim.roads[r].name) == name:
			return r
	return -1


func _holds() -> void:
	for mph in [2400.0, 1200.0]:
		var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
		var road := _road(sim, "N3")
		sim.respawn_on(road, 400, 1)
		var a = Autopilot.new()
		var city := _city(sim, "GLACIER")
		var took: bool = a.engage(sim, city)
		a.set_cruise(mph / MPH)
		var out := _fly(sim, a, 180.0, city, [], 45.0)
		_check("engaged on N3 for %d mph, three minutes hands off: it flew %.0f to %.0f mph once up to speed, never more than %.1f m from its road's middle, %d wall contacts, the craft still its own (%s)" % [
			int(mph), out.mph[0], out.mph[1], out.off, out.hits + out.scrapes, a.status],
			took and not out.given_back and float(out.mph[1]) <= mph + 40.0 and float(out.mph[0]) >= 250.0 and float(out.off) < 40.0 and out.hits + out.scrapes == 0)


func _route() -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var e: Dictionary = sim.cities[_city(sim, "ERIDANUS")]
	sim.respawn_on(int(e.road), int(e.i), 1)
	var a = Autopilot.new()
	var city := _city(sim, "BASALT")
	var took: bool = a.engage(sim, city)
	var page: String = a.message()
	var roads := {}
	for k in a.rpath:
		roads[String(sim.roads[k].name)] = true
	for k in 7:
		a.nudge(1)
	var out := _fly(sim, a, 420.0, city, [], 0.0)
	var names := []
	for row in out.arrivals:
		names.append("%s at %.0f s" % [sim.cities[int(row[0])].name, float(row[1])])
	_check("engaged standing in Eridanus for Basalt (its page \"%s\"), then nudged up seven steps to %d mph: by %s it arrived (%s) and carried on for %s, %d wall contacts in seven minutes" % [
		page.replace("\n", " / "), roundi(a.cruise * MPH), " ".join(roads.keys()), names, sim.cities[int(out.city)].name if int(out.city) >= 0 else "nowhere", out.hits + out.scrapes],
		took and page.begins_with("AUTOPILOT  2,500 MPH") and roundi(a.cruise * MPH) == 4250 and out.arrivals.size() >= 1 and int(out.arrivals[0][0]) == city and not out.given_back
		and out.hits + out.scrapes == 0 and int(out.city) != city)


func _traffic() -> void:
	# one slow vehicle in its lane, then a wall of them
	for wall in [false, true]:
		var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
		var road := _road(sim, "N3")
		sim.respawn_on(road, 400, 1)
		var a = Autopilot.new()
		var city := _city(sim, "GLACIER")
		a.engage(sim, city)
		a.set_cruise((2000.0 if wall else 2400.0) / MPH)
		_fly(sim, a, 40.0, city, [], 0.0)             # up to speed, nothing about
		var R = sim.roads[sim.pod.path]
		var i := clampi(int(sim.pod.hint) + (600 if wall else 220), 0, int(R.N) - 1)      # (14 km off, and 5: the traffic is kept 19 km out)
		var way := 1.0 if sim.pod.vx * R.tx[i] + sim.pod.vy * R.ty[i] >= 0.0 else -1.0
		var cars := []
		var slow := 300.0 / MPH
		var lanes: Array = range(-8, 9) if wall else [0]
		for k in lanes:
			cars.append({"x": R.px[i] + R.nx[i] * k * 22.0, "y": R.py[i] + R.ny[i] * k * 22.0, "v": slow, "hx": R.tx[i] * way, "hy": R.ty[i] * way})
		var nearest := INF          # the least the pod came to a vehicle
		var passed := false
		var moved := 0.0
		var least_mph := INF
		for f in int((90.0 if wall else 40.0) / (SUB * DT)):
			var u: Dictionary = a.fly(sim, city, cars)
			if u.is_empty():
				break
			var inp := {"thrL": u.thrL, "thrR": u.thrR, "brkL": u.brkL, "brkR": u.brkR, "repair": false, "reignite": true, "handling": u.handling}
			for s in SUB:
				sim.step(inp, DT)
			sim.events.clear()
			for c in cars:
				c.x += c.v * c.hx * SUB * DT
				c.y += c.v * c.hy * SUB * DT
				nearest = minf(nearest, Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length())
			var ahead: float = (cars[0].x - sim.pod.x) * cars[0].hx + (cars[0].y - sim.pod.y) * cars[0].hy
			passed = passed or ahead < -50.0
			moved = maxf(moved, absf(a.lane))
			least_mph = minf(least_mph, Vector2(sim.pod.vx, sim.pod.vy).length() * MPH)
		if wall:
			var end_mph := Vector2(sim.pod.vx, sim.pod.vy).length() * MPH
			_check("a wall of vehicles at 300 mph across its road, 14 km off, at 2,000: it slows in time and is settling behind them, at %.0f mph after a minute and a half (\"%s\"), never nearer than %.0f m, and does not go through" % [end_mph, a.status, nearest],
				not passed and end_mph < 450.0 and end_mph > 250.0 and nearest > 60.0 and a.status == "TRAFFIC")
		else:
			_check("a vehicle at 300 mph on its line, at 2,400: it moves over (%.0f m: the next gap between lanes) and passes, never nearer than %.0f m, never under %.0f mph, and comes back to the middle (%.0f m)" % [moved, nearest, least_mph, a.lane],
				passed and is_equal_approx(moved, 45.0) and nearest > 30.0 and least_mph > 2300.0 and absf(a.lane) < 0.5)


## Leaving Dunes the wrong way the only road on is the highway's end and its shaft: up it, over and back.
func _shaft() -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var d: Dictionary = sim.cities[_city(sim, "DUNES")]
	sim.respawn_on(int(d.road), int(d.i), -1)
	var a = Autopilot.new()
	var city := _city(sim, "ERIDANUS")
	var took: bool = a.engage(sim, city)
	var through := []
	for k in a.rpath:
		var name := String(sim.roads[k].name)
		if through.is_empty() or through[through.size() - 1] != name:
			through.append(name)
	var shaft := ""
	for name in through:
		if sim.roads[_road(sim, name)].shaft:
			shaft = name
	var on_shaft := false
	var after := ""
	var contacts := 0
	var top := 0.0
	for f in int(150.0 / (SUB * DT)):
		var u: Dictionary = a.fly(sim, city, [])
		if u.is_empty():
			break
		var inp := {"thrL": u.thrL, "thrR": u.thrR, "brkL": u.brkL, "brkR": u.brkR, "repair": false, "reignite": true, "handling": u.handling}
		for s in SUB:
			sim.step(inp, DT)
			for e in sim.events:
				if e.type == "hit" or e.type == "scrape":
					contacts += 1
			sim.events.clear()
		var here := String(sim.roads[sim.pod.path].name)
		if here == shaft:
			on_shaft = true
			top = maxf(top, float(sim.pod.z))
		elif on_shaft:
			after = here
	_check("taken in Dunes facing the highway's end, for Eridanus: the only drive is over the shaft (%s); it flew %s, %.0f m up at the top, and came off it onto %s with %d wall contacts, still flying (%s)" % [
		" ".join(through), shaft, top, after, contacts, a.on], took and shaft != "" and on_shaft and after != "" and after != shaft and contacts == 0 and a.on and top > 300.0)


## What a frame of it costs, among a city's traffic: 220 vehicles within 19 km, half of them on its road.
func _cost() -> void:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var road := _road(sim, "N3")
	sim.respawn_on(road, 2000, 1)
	var a = Autopilot.new()
	var city := _city(sim, "GLACIER")
	a.engage(sim, city)
	var plan_ms := 0.0
	for k in 3:
		var t0 := Time.get_ticks_usec()
		a.plan_to(sim, city)
		plan_ms = maxf(plan_ms, (Time.get_ticks_usec() - t0) / 1000.0)
	_fly(sim, a, 20.0, city, [], 0.0)
	var R = sim.roads[sim.pod.path]
	var i0 := int(sim.pod.hint)
	var cars := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 220:
		var i := clampi(i0 + rng.randi_range(-700, 700), 0, int(R.N) - 1)
		var lat: float = ([-157.5, -112.5, -67.5, -22.5, 22.5, 67.5, 112.5, 157.5][rng.randi_range(0, 7)]) + (3000.0 if k % 2 == 1 else 0.0)
		cars.append({"x": R.px[i] + R.nx[i] * lat, "y": R.py[i] + R.ny[i] * lat, "v": 2380.0 / MPH, "hx": R.tx[i], "hy": R.ty[i]})
	var best := INF
	for rep in 5:
		var t := Time.get_ticks_usec()
		for k in 300:
			a.fly(sim, city, cars)
		best = minf(best, float(Time.get_ticks_usec() - t) / 300.0)
	_check("a frame of it among 220 vehicles costs %.0f us (nothing in the sim's steps); planning a %d km drive, once, %.1f ms" % [best, roundi(a.rs[a.rs.size() - 1] / 1000.0), plan_ms],
		best < 600.0 and plan_ms < 120.0 and a.on)


## A controllers' snapshot for the cockpit's scheme (vr/vr_cockpit.gd _read_input's `c`).
func _snap(c, o := {}) -> Dictionary:
	var v := Vector2(c.sim.pod.vx, c.sim.pod.vy).length()
	var s := {"lt": 0.0, "rt": 0.0, "lg": 0.0, "rg": 0.0, "ls": Vector2.ZERO, "rs": Vector2.ZERO, "lz": 0.0, "rz": 0.0,
		"speed": v, "yaw": 0.0, "airspeed": v, "sf": c.sim.hblend}
	for k in o:
		s[k] = o[k]
	return s


func _views() -> void:
	# ---- a bare view, at a desk ----
	var v = View.new()
	root.add_child(v)
	await process_frame
	await process_frame
	v.set_process(false)
	for k in 5:
		v._process(1.0 / 60.0)
	var own: Dictionary = v.inp.duplicate()
	var took: bool = v.set_autopilot(true)
	v._autopilot_hands(0.6, 0.0)           # a lever still held as it is taken
	var held_on: bool = v.autopilot.on
	for k in 30:
		v._process(1.0 / 60.0)             # (the view's own levers are at rest: the hands have let go)
	var flown: Dictionary = v.inp.duplicate()
	_check("a view: left alone the levers are the pilot's own (%.2f, %.2f); the autopilot taken (P), they are its (%.2f, %.2f) and the flash says where to (\"%s\")" % [
		own.thrL, own.thrR, flown.thrL, flown.thrR, v.flash_msg],
		took and v.autopilot.on and float(own.thrL) == 0.0 and float(flown.thrL) > 0.5 and float(flown.thrR) > 0.5 and String(v.flash_msg).begins_with("AUTOPILOT  /  TO "))
	var gave: bool = v._autopilot_hands(0.0, 0.5)
	for k in 5:
		v._process(1.0 / 60.0)
	_check("a lever still held as it was taken does not take her back (%s); let go, then a brake squeezed past %.2f, does (%s, \"%s\"), and the levers are the pilot's again (%.2f)" % [
		held_on, View.AUTOPILOT_TAKE, gave, v.flash_msg, v.inp.thrL],
		held_on and gave and not v.autopilot.on and String(v.flash_msg) == "AUTOPILOT OFF  /  YOU HAVE HER" and float(v.inp.thrL) == 0.0)
	v.queue_free()
	await process_frame
	# ---- the cockpit ----
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit.cold_on_entry = false
	var c = Cockpit.new()
	root.add_child(c)
	await process_frame
	c.set_process(false)
	var dt := 1.0 / 90.0
	var across := _snap(c, {"ls": Vector2(1.0, 0.1)})
	c._autopilot_controls(across, null, null, dt)
	var on_flick: bool = c.autopilot.on
	c._autopilot_controls(_snap(c, {"ls": Vector2(1.0, 0.0)}), null, null, dt)      # still held across: one flick, one switch
	var still: bool = c.autopilot.on
	c._autopilot_controls(_snap(c), null, null, dt)
	c._autopilot_controls(_snap(c, {"ls": Vector2(-1.0, 0.0)}), null, null, dt)
	var off_flick: bool = not c.autopilot.on
	c._autopilot_controls(_snap(c), null, null, dt)
	c._autopilot_controls(_snap(c, {"ls": Vector2(0.6, 0.9)}), null, null, dt)        # the burner's flick, a little across
	_check("the cockpit: the left stick flicked across takes it (%s), held there it stays taken (%s), flicked again it gives her back (%s); the burner's flick up does nothing to it (%s)" % [
		on_flick, still, off_flick, not c.autopilot.on], on_flick and still and off_flick and not c.autopilot.on)
	# taken with the triggers still in, as it will be in flight
	c._autopilot_controls(_snap(c), null, null, dt)
	var holding := _snap(c, {"lt": 1.0, "rt": 1.0, "ls": Vector2(1.0, 0.0)})
	c._autopilot_controls(holding, null, null, dt)
	var kept: bool = c.autopilot.on and float(holding.lt) == 0.0 and holding.ls == Vector2.ZERO
	c._autopilot_controls(_snap(c, {"lt": 1.0, "rt": 0.9}), null, null, dt)
	var kept2: bool = c.autopilot.on
	c._autopilot_controls(_snap(c), null, null, dt)                                   # the hands let go
	var cruise0: float = c.autopilot.cruise
	c._autopilot_controls(_snap(c, {"rs": Vector2(0.0, 1.0)}), null, null, dt)        # the right stick up: faster
	c._autopilot_controls(_snap(c), null, null, dt)
	var page: String = ""
	c._hud_progress(true)
	if c.approach_display:
		page = c.approach_display.message
	var strip: String = c._hud_progress(true)
	c._autopilot_controls(_snap(c, {"rg": 0.4}), null, null, dt)                      # a grip: hers again
	_check("taken with both triggers in it keeps her while they are held (%s, %s) and the scheme is given none of them; the right stick up nudges its speed %d mph; the glass reads \"%s\" (the strip \"%s\"); the hands let go, a grip squeezed gives her back (%s)" % [
		kept, kept2, roundi((c.autopilot.cruise - cruise0) * MPH), page.replace("\n", " / "), strip.replace("\n", " / "), not c.autopilot.on],
		kept and kept2 and roundi((c.autopilot.cruise - cruise0) * MPH) == 250 and page.begins_with("AUTOPILOT  ") and page.contains("A TRIGGER OR A GRIP TAKES HER BACK")
		and strip.begins_with("AUTOPILOT") and not c.autopilot.on)
	# the OPTIONS page's line
	c._menu_page = "options"
	var keys := []
	for item in c._menu_items():
		keys.append(item.key)
	c.menu.items = c._menu_items()
	c.menu.open = true
	c.menu.at = keys.find("autopilot")
	c.menu_choose()
	var by_menu: bool = c.autopilot.on and String(c.menu.items[keys.find("autopilot")].value) == "ON"
	c.menu.open = false
	c._menu_page = ""
	# it shifts for itself
	c.quest.set_gear(1)
	c.quest.rpm = 0.95
	var up: float = c._autopilot_shift(300.0, dt)
	var wait: float = c._autopilot_shift(300.0, dt)
	c.quest.set_gear(3)
	c.quest.rpm = 0.3
	c._auto_shift_t = 0.0
	var down: float = c._autopilot_shift(200.0, dt)
	# holding 2,400 mph in second (87% of its revs): third would turn at 64%, so up; in fourth (54%) it stays
	c.autopilot.status = "HOLDING"
	c.quest.set_gear(2)
	c.quest.rpm = 0.87
	c._auto_shift_t = 0.0
	var cruise_up: float = c._autopilot_shift(2400.0 / MPH, dt)
	c.quest.set_gear(4)
	c.quest.rpm = 0.54
	c._auto_shift_t = 0.0
	var cruise_stay: float = c._autopilot_shift(2400.0 / MPH, dt)
	_check("the quick menu's OPTIONS page has AUTOPILOT (%s) and it takes it (%s); it shifts as a pilot does: up at the revs' top (%.0f, then nothing for a moment: %.0f), down when the revs sag (%.0f); holding 2,400 mph it goes up out of second (%.0f) and stays in fourth (%.0f)" % [
		keys, by_menu, up, wait, down, cruise_up, cruise_stay], keys.has("autopilot") and by_menu and up == 1.0 and wait == 0.0 and down == -1.0 and cruise_up == 1.0 and cruise_stay == 0.0)
	# flown for real: whole frames, hands off
	c.quest.set_gear(1)
	c._auto_shift_t = 0.0
	var gears := {}
	for k in int(20.0 / dt):
		c._process(dt)
		gears[c.quest.gear] = true
	var mph := Vector2(c.sim.pod.vx, c.sim.pod.vy).length() * MPH
	_check("twenty seconds of whole frames with nobody's hands on her: she is at %.0f mph, the autopilot still has her (%s), it has been through gears %s, the gearbox's pull is in the sim's input (%s)" % [
		mph, c.autopilot.status, gears.keys(), c.inp.has("thrMul")], c.autopilot.on and mph > 600.0 and gears.size() >= 2 and c.inp.has("thrMul"))
	c.startup.flick("park", 1)
	c._autopilot_controls(_snap(c), null, null, dt)
	_check("the parking brake set under it: the craft is given back (\"%s\")" % c.flash_msg, not c.autopilot.on and String(c.flash_msg).contains("PARKED"))
	c.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()


func _run() -> void:
	_port()
	_routes()
	_holds()
	_route()
	_traffic()
	_shaft()
	_cost()
	await _views()
	print("AUTOPILOT %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
