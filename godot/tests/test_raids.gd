## Raids: the raid's lifecycle (view/network_raids.gd; the stage 1 plan, task 3). Raids pinned on, the
## director's tunables shortened:
##   waits      no alarm before first_after at speed on a public road; and none while another holds traffic's
##              floor (a chase's craft in the racer's slot)
##   alarm      after it: called, on the ground city nearest in a straight line that the pilot is not in; traffic's
##              floor held ("raid"), so a chase is not ready to begin
##   pick       an orbit entry nearer than any city is never picked; nor is the last raid's city, nor the city the
##              pilot is in
##   ticks      called and out of range, a commuter is lost every tick_every s; the floor still held
##   not reached  ... and at tick_cap, with the pilot not there, it is lost ("not reached"), the floor free; no more lost
##   arrive     an alarm with the pilot already in range: on the next frame, none lost, the pack (4, then one
##              more a raid, up to 6) hostile on the city's road in its town zone, spread over its lanes
##   cleared    every raider killed: cleared, tallied, the floor released; then the lull
##   away       out of R_KEEP of the city for away_t: lost, the pack taken out of traffic
##   time       time_limit after arriving: lost, the pack taken out of traffic
##   respawn    a restart mid-raid: no hostiles left, the floor free, no result
##   crash      a wreck mid-raid (the sim's own: its "wreck", then its respawn when crash_t runs out): the same
##   pause      the cockpit's FLIGHT HOLD menu (in the headset) and the desktop pause (the tree paused,
##              release/pause_overlay.gd) hold the raid's clocks; resumed, they run on
## Run with --fixed-fps 120 (see _fly). Prints RAIDS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const STEP := 1.0 / 120.0
const SPEED := 1000.0            # m/s along the road (2,237 mph): at speed from the first frame
var failures := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"       # open highway, well clear of a crossing, 170 km and more from every city
	View.best_dir = OS.get_user_data_dir().path_join("test_raids_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = "ember"
	Chase.pinned = true
	Chase.enabled = false
	Chase.craft = "racer"
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## Fly on with the levers up. Traffic and the raids run on the engine's own frame time, so this test is run at a
## fixed 120 frames a second and a frame is let pass for every step of the flight: the two clocks agree.
func _fly(v, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / STEP)):
		v.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
		v._process(STEP)
		await process_frame


## Fly frame by frame until the director's state is `want` (at most `limit` s): the seconds it took.
func _fly_until(v, want: String, limit: float) -> float:
	var t := 0.0
	while v.raids.state != want and t < limit:
		await _fly(v, STEP)
		t += STEP
	return t


## The craft on `road` at sample i, going `dir`, at SPEED.
func _put_pilot(v, road: int, i: int, dir: int) -> void:
	var sim = v.sim
	sim.respawn_on(road, i, dir)
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = R.tx[i] * dir * SPEED
		body.vy = R.ty[i] * dir * SPEED


## The craft on city k's road short of its town zone, heading in (3.6 km out: in range).
func _near_city(v, k: int) -> void:
	var z: Vector2i = v.raids._zone(k).z
	_put_pilot(v, int(v.sim.cities[k].road), z.x - 150, 1)


## Another holds traffic's floor: a craft in the racer's slot, as network_chase.gd's _begin puts its own.
func _holder(T):
	var pc = T._pod_as_car()
	var c = T.Car.new()
	c.id = 950999
	c.kind = T.RACER
	c.chase = "pursuer"
	c.road = pc.road
	c.dir = pc.dir
	c.f = pc.f - pc.dir * 2000.0 / 24.0
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.v = pc.v
	c.vdes = pc.v
	c.turn_p = 0.0
	c.nsp_road = -1
	T._place(c)
	T.cars.append(c)
	T.racer = c
	T.race_state = "chase"
	return c


## The raid's clocks: [waiting, since arrival, out of range, toward the next loss, lost].
func _snap(R) -> Array:
	return [R._clock, R._t, R._away, R._tick_t, R.lost]


func _cockpit():
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0           # (the levers are this test's: with cruise below zero the cockpit reads its own controllers each frame)
	return v


## m in a straight line from the pilot to city k's centre.
func _dist(v, k: int) -> float:
	var c: Dictionary = v.sim.cities[k]
	return Vector2(v.sim.pod.x, v.sim.pod.y).distance_to(Vector2(float(c.cx), float(c.cy)))


## The ground city nearest the pilot in a straight line that the director may pick: not `last` (the last raid's
## city), nor the one it is in (net.from, within arrive_r of its town). With exclude false, the nearest of all.
func _nearest(v, last: int, exclude := true) -> int:
	var sim = v.sim
	var best := -1
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) == "orbit":
			continue
		if exclude and (k == last or (k == int(sim.net.from) and v.raids._gap(k) <= v.raids.arrive_r)):
			continue
		if best < 0 or _dist(v, k) < _dist(v, best):
			best = k
	return best


## The director's last raid's city (-1 before the first; and on a director that does not keep one).
func _last(R) -> int:
	var l = R.get("_last_city")
	return -1 if l == null else int(l)


func _run() -> void:
	var v = await _cockpit()
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	if R == null:
		_check("raids pinned on: the cockpit has a director", false)
		print("RAIDS FAIL (%d failures)" % failures)
		quit(1)
		return
	T._hw_time = -1.0e9      # (no street racer drops in during this test: it would hold traffic's floor and the raids would wait)
	R.first_after = 3.0
	R.lull = Vector2(4.0, 6.0)
	R.time_limit = 8.0
	R.away_t = 3.0
	R.tick_every = 1.0
	R.tick_cap = 3
	var e3 := [int(sim.pod.path), int(sim.pod.hint), 1]
	_put_pilot(v, e3[0], e3[1], e3[2])

	# waits: not before first_after; not while another holds the floor
	await _fly(v, 2.5)
	var ran: float = R._clock
	var early: bool = R.state == ""
	var holder = _holder(T)
	await _fly(v, 2.0)
	var held_off: bool = R.state == "" and R._clock < ran
	var decayed: float = R._clock
	T.cars.erase(holder)
	T.racer = null
	T.race_state = ""
	_check("no alarm in %.1f s at %.0f mph on a public road (state \"%s\", its clock %.2f of %.1f); none in 2 s more with the floor held by another (\"%s\", clock down to %.2f)" % [
			2.5, Vector2(sim.pod.vx, sim.pod.vy).length() * 2.236936, R.state, ran, R.first_after, R.state, decayed],
		early and absf(ran - 2.5) < 0.05 and held_off)

	# alarm
	var chase = Chase.new()
	chase.traffic = T
	chase.sim = sim
	var chase_before: bool = chase._ready_for_one()
	var last_before := _last(R)
	var took: float = await _fly_until(v, "called", 4.0)
	var nearest := _nearest(v, last_before)
	var pc = T._pod_as_car()
	var ground: bool = R.city >= 0 and R.city < sim.cities.size() and String(sim.cities[R.city].get("kind", "")) != "orbit"
	var not_in: bool = R.city != int(sim.net.from) or R._gap(R.city) > R.arrive_r
	_check("%.2f s later the alarm: called (\"%s\") on %s (city %d; the nearest in a straight line %d), a ground city (%s) the pilot is not in (%s; it is %.0f km from its town); the floor \"%s\"; a chase was ready to begin (%s) and is not now (%s)" % [
			took, R.state, sim.cities[R.city].name if ground else "?", R.city, nearest, ground, not_in, R._gap(R.city) / 1000.0 if ground else -1.0, T.race_state, chase_before, chase._ready_for_one()],
		R.state == "called" and ground and not_in and R.city == nearest and T.race_state == "raid" and chase_before and not chase._ready_for_one())

	# pick (each asked without a frame flown): an orbit entry nearer than any city; the last raid's city (this raid's,
	# the nearest city); the city the pilot is in
	var P = sim.pod
	var road0: int = P.path
	var hint0: int = P.hint
	var dir0: int = pc.dir
	var Rr = sim.roads[road0]
	var at := clampi(hint0 + dir0 * 80, 1, Rr.N - 2)
	var last_city := _last(R)
	var last_nearest: bool = last_city == R.city and R.city == _nearest(v, -1, false)
	sim.cities.append({"name": "PORT", "kind": "orbit", "biome": "space", "cx": Rr.px[at], "cy": Rr.py[at], "road": road0, "i": at})
	var port: int = sim.cities.size() - 1
	var port_nearest := true
	for k in port:
		port_nearest = port_nearest and _dist(v, port) < _dist(v, k)
	var port_km := _dist(v, port) / 1000.0
	var t0 := Time.get_ticks_usec()
	var past_port: int = R._pick()
	var pick_ms := (Time.get_ticks_usec() - t0) / 1000.0
	sim.cities.pop_back()
	var want_far := _nearest(v, last_city)
	var home := int(sim.net.from)
	sim.respawn(home)                       # at its terminal: in it
	var home_nearest: bool = _nearest(v, -1, false) == home
	var want_home := _nearest(v, last_city)
	var past_home: int = R._pick()
	_put_pilot(v, road0, hint0, dir0)       # (back where it was: the raid called is untouched)
	_check("an orbit entry nearer than any city (%s, %.1f km) is passed over, and so is the last raid's city %s (%d; the nearest city %s): picked %d (want %d, in %.3f ms); in %s (%d), nearest of all (%s), it is passed over too: picked %d (want %d)" % [
			port_nearest, port_km, sim.cities[R.city].name, last_city, last_nearest, past_port, want_far, pick_ms, sim.cities[home].name, home, home_nearest, past_home, want_home],
		port_nearest and last_nearest and past_port >= 0 and past_port < port and past_port != last_city and past_port == want_far
			and home_nearest and past_home >= 0 and past_home != home and past_home != last_city and past_home == want_home and R.state == "called")

	# ticks: off-screen, a commuter lost a second, up to the cap
	var lost0: int = R.lost
	await _fly(v, 1.5)
	var l1: int = R.lost
	await _fly(v, 1.0)
	var l2: int = R.lost
	_check("called and %.0f km from its town: lost %d, then %d at 1.5 s, %d at 2.5 s; still called (\"%s\"), the floor still held (\"%s\")" % [
			R._gap(R.city) / 1000.0, lost0, l1, l2, R.state, T.race_state],
		R._gap(R.city) > R.arrive_r and lost0 == 0 and l1 == 1 and l2 == 2 and R.state == "called" and T.race_state == "raid")

	# not reached: at the cap, with the pilot nowhere near, it is lost
	await _fly(v, 1.0)
	var l3: int = R.lost
	var expired: bool = R.result == "lost" and R._why == "not reached" and int(R.tally.lost) == 1 and T.race_state == "" and R.state == "over"
	await _fly(v, 1.0)
	_check("at 3.5 s, %d lost (the cap %d) and not reached: \"%s\" (%s; tally %s), the floor free (\"%s\"), the lull (\"%s\"); a second on, still %d lost" % [
			l3, R.tick_cap, R.result, R._why, R.tally, T.race_state, R.state, R.lost],
		expired and l3 == R.tick_cap and R.lost == R.tick_cap and R.state == "over" and T.hostiles().is_empty())

	# arrive at once: the next is called with the pilot already near its city
	R.lull = Vector2(0.5, 0.5)
	R.reset()
	var aside: bool = R.state == "" and T.race_state == "" and T.hostiles().is_empty()
	var X := -1
	for k in sim.cities.size():
		if k != int(sim.net.from) and k != _last(R) and X < 0:
			X = k
	_near_city(v, X)
	var calls: int = R._count
	await _fly_until(v, "called", 2.0)
	var called_on: int = R.city
	var lost_at_call: int = R.lost
	await _fly(v, STEP)
	var n: int = R.pack.size()
	var croad := int(sim.cities[X].road)
	var CR = sim.roads[croad]
	var placed := n > 0
	var lanes := {}
	for c in R.pack:
		placed = placed and c.hostile and T.cars.has(c) and c.road == croad and CR.mode[clampi(int(c.f), 0, CR.N - 1)] == 0 and c.kind == T.DEMON and c.visual == R.RAIDER_VISUAL and c.id >= 960000
		lanes[c.lane] = true
	var want_n := mini(R.pack_size.x + calls, R.pack_size.y)       # (this is raid calls + 1)
	_check("set aside (%s); an alarm %.1f km from %s's town (city %d, called on %d): on the next frame (\"%s\"), none lost (%d, %d), a pack of %d (want %d, within %s), hostile in its town zone on its road (%s), over %d lanes; the floor \"%s\"" % [
			aside, R._gap(X) / 1000.0, sim.cities[X].name, X, called_on, R.state, lost_at_call, R.lost, n, want_n, R.pack_size, placed, lanes.size(), T.race_state],
		aside and called_on == X and R.state == "on" and lost_at_call == 0 and R.lost == 0 and n >= R.pack_size.x and n <= R.pack_size.y and n == want_n and placed and lanes.size() >= mini(2, n) and T.race_state == "raid")

	# cleared: every raider killed, then the lull
	R.lull = Vector2(4.0, 6.0)
	var raiders: Array = R.pack.duplicate()
	for c in raiders:
		R.on_kill(c)
		T.knock_out(c)
	await _fly(v, STEP)
	_check("every raider killed (%d of %d): \"%s\" (tally %s), the floor free (\"%s\"), no hostiles left (%d), the lull (\"%s\")" % [R.kills, raiders.size(), R.result, R.tally, T.race_state, T.hostiles().size(), R.state],
		R.result == "cleared" and int(R.tally.cleared) == 1 and int(R.tally.lost) == 1 and R.kills == raiders.size() and T.race_state == "" and T.hostiles().is_empty() and R.state == "over")
	await _fly(v, 3.5)
	var quiet: bool = R.state == "over"
	var more: float = await _fly_until(v, "called", 3.0)
	_check("the lull: quiet 3.5 s at speed (%s), the next alarm %.2f s after that (\"%s\", %s): %.1f s in all, within %s; not on %s, the last raid's, though the pilot is %.1f km from its town (city %d, picked %d)" % [
			quiet, more, R.state, sim.cities[R.city].name if R.city >= 0 else "?", 3.5 + more, R.lull, sim.cities[X].name, R._gap(X) / 1000.0, X, R.city],
		quiet and R.state == "called" and 3.5 + more >= R.lull.x - 0.05 and 3.5 + more <= R.lull.y + 0.05 and R.city != X)

	# away: in, then out of R_KEEP of it for away_t
	R.lull = Vector2(0.5, 0.5)
	_near_city(v, R.city)
	await _fly(v, STEP)
	var in_on: bool = R.state == "on"
	var pack: Array = R.pack.duplicate()
	_put_pilot(v, e3[0], e3[1], e3[2])
	await _fly(v, R.away_t + 0.25)
	var left := 0
	for c in pack:
		left += int(T.cars.has(c))
	_check("arrived (%s, %d raiders), then %.0f km out for %.2f s: \"%s\" (%s; tally %s), the pack out of traffic (%d left, %d hostiles), the floor free (\"%s\")" % [
			in_on, pack.size(), R._gap(R.city) / 1000.0, R.away_t + 0.25, R.result, R._why, R.tally, left, T.hostiles().size(), T.race_state],
		in_on and pack.size() > 0 and R.result == "lost" and R._why == "away" and int(R.tally.lost) == 2 and left == 0 and T.hostiles().is_empty() and T.race_state == "" and R.state == "over")

	# time: in range, the time limit runs out
	R.lull = Vector2(1.5, 1.5)           # (longer than the second flown past the limit: the next is not called within it)
	await _fly_until(v, "called", 2.0)
	_near_city(v, R.city)
	await _fly(v, STEP)
	in_on = R.state == "on"
	pack = R.pack.duplicate()
	await _fly(v, R.time_limit - 0.5)
	var still: bool = R.state == "on"
	await _fly(v, 1.0)
	left = 0
	for c in pack:
		left += int(T.cars.has(c))
	_check("arrived (%s), on still %.1f s later (%s, %.1f km from its town), then the time limit: \"%s\" (%s; tally %s), the pack out of traffic (%d left, %d hostiles), the floor free (\"%s\")" % [
			in_on, R.time_limit - 0.5, still, R._gap(R.city) / 1000.0, R.result, R._why, R.tally, left, T.hostiles().size(), T.race_state],
		in_on and still and R.result == "lost" and R._why == "time" and int(R.tally.lost) == 3 and left == 0 and T.hostiles().is_empty() and T.race_state == "")

	# respawn mid-raid
	await _fly_until(v, "called", 2.0)
	_near_city(v, R.city)
	await _fly(v, STEP)
	in_on = R.state == "on"
	var had: int = T.hostiles().size()
	var tally_before: Dictionary = R.tally.duplicate()
	v._respawn()
	_check("arrived (%s, %d hostiles), then a restart: none left (%d), the floor free (\"%s\"), no result (\"%s\") and nothing tallied (%s), waiting again (\"%s\")" % [
			in_on, had, T.hostiles().size(), T.race_state, R.result, R.tally, R.state],
		in_on and had > 0 and T.hostiles().is_empty() and T.race_state == "" and R.result == "" and R.tally == tally_before and R.state == "")

	# crash mid-raid: the pod's health gone, the sim's own wreck ("wreck", crash_t), and its respawn when that runs out
	_put_pilot(v, e3[0], e3[1], e3[2])
	await _fly_until(v, "called", 2.0)
	_near_city(v, R.city)
	await _fly(v, STEP)
	in_on = R.state == "on"
	had = T.hostiles().size()
	tally_before = R.tally.duplicate()
	var crash_at := Vector2(sim.pod.x, sim.pod.y)
	sim.pod.health = 0.0
	await _fly(v, 0.25)
	var down: bool = sim.crash_t > 0.0
	var stood: bool = R.state == "on"      # (the raid stands while the craft is down)
	await _fly(v, 1.6)
	var moved: float = Vector2(sim.pod.x, sim.pod.y).distance_to(crash_at)
	var back: bool = sim.crash_t <= 0.0 and sim.pod.health > 0.0 and moved > 2000.0
	_check("arrived (%s, %d hostiles), then wrecked (%s, the raid on meanwhile %s) and respawned by the sim %.1f km off (%s): none left (%d), the floor free (\"%s\"), no result (\"%s\") and nothing tallied (%s), waiting again (\"%s\")" % [
			in_on, had, down, stood, moved / 1000.0, back, T.hostiles().size(), T.race_state, R.result, R.tally, R.state],
		in_on and had > 0 and down and stood and back and T.hostiles().is_empty() and T.race_state == "" and R.result == "" and R.tally == tally_before and R.state == "")

	# pause: the cockpit's FLIGHT HOLD menu; the desktop pause
	_put_pilot(v, e3[0], e3[1], e3[2])
	await _fly_until(v, "called", 2.0)
	_near_city(v, R.city)
	await _fly(v, STEP)
	in_on = R.state == "on"
	R.time_limit = 60.0
	await _fly(v, 0.25)
	var before := _snap(R)
	var t_sim: float = sim.time
	v.menu_open(true)
	await _fly(v, 0.5)                   # (the view is still asked to step: its _process returns before the world)
	var held := _snap(R)
	var sim_held: bool = sim.time == t_sim
	v.menu_open(false)
	await _fly(v, 0.5)
	var ran_on := _snap(R)
	_check("on (%s); the FLIGHT HOLD menu open for 0.5 s of frames: the raid's clocks hold (%s; the flight waits too: %s); closed, they run on (%.2f s to %.2f)" % [in_on, held == before, sim_held, held[1], ran_on[1]],
		in_on and held == before and sim_held and ran_on[1] > held[1] + 0.45 and R.state == "on")
	# the desktop pause (release/pause_overlay.gd set_paused): the tree is paused, so the engine does not process the view at all
	v.set_process(true)                  # (the engine steps the view now, as in a flight)
	paused = true
	for i in 60:
		await process_frame
	var p_snap := _snap(R)
	var stopped: bool = not v.can_process() and not R.can_process()
	paused = false
	for i in 60:
		await process_frame
	var resumed := _snap(R)
	v.set_process(false)
	_check("the tree paused for 60 frames: the view and the director are not processed (%s), the clocks hold (%s); unpaused, they run on (%.2f s to %.2f)" % [stopped, p_snap == ran_on, p_snap[1], resumed[1]],
		stopped and p_snap == ran_on and resumed[1] > p_snap[1] + 0.4)

	chase.free()
	v.queue_free()
	await process_frame
	Raids.pinned = false
	Raids.enabled = false
	print("RAIDS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
