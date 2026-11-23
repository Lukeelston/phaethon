## Mount Hyperion's leaps (Luke, 2026-11-22: "add the ultimate jump at the bottom of each side of Hyperion's
## access roads? Such that you could start at the peak, rocket towards the bottom, and hit a jump at 9-11k mph,
## and literally jet for some odd tens of miles."; tools/design_network.py add_hyperion_leaps, CraftSim.NET_LEAPS):
##   designed   two leaps, each a launch lane beside SHyperion's centreline (inside its 800 m deck) whose far end is
##              a lip 200 m up at half a degree, and a landing field (a catch deck) that begins under the lip; the
##              mountain's own road is where it was
##   summit     from a standing start on the summit, flat out in top gear with the ramjet armed, in the lane and
##              hands off the steering: the craft is at each lip inside 9,000 to 11,000 mph with the boost held
##              and without it, flies tens of miles and is caught whole by its field, on the field's middle
##   speeds     pinned to 9,000, 10,000 and 11,000 mph at the lip (flat out through the flight): the angle, the
##              seconds in the air, the peak, the miles; caught at the top of the field's reach every time (a
##              craft covers 9 to 10 m a step: nothing is tunnelled through); longer the faster
##   slow       at 150, 1,500 and 4,000 mph the craft drops off the lip onto the field's first stretch, whole
##   climbing   a craft driving up the approach to the ramp's foot, down its middle or over the lane's own ground,
##              is never off the level and never in the air; nor is one that comes up the far straight to climb the
##              cliff
##   plain      a craft that keeps to the middle off the summit, flat out, goes each way on SHyperion alone
##   astray     a craft half a degree off the line at the lip still lands on the field; one three degrees off
##              misses it and comes down on the open ground, whole
##   marked     the views: boards before each lane, on it and on its field; each lip on the map; the lanes' amber
##              rails down the mountain
##   one deck   where the views draw the cliff's field and the far straight under it as one plain road (the field's;
##              the far straight's chunks are left empty), the sims' two roads are one surface: wherever a body is
##              on the far straight its deck is at the field's own height there, edge ramp and all, and everywhere
##              else across the far straight the field is the deeper road (the body is on the field)
## Prints HYPERION LEAPS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Hyperion := preload("res://view/hyperion.gd")
const Outlook := preload("res://view/outlook.gd")
const DT := 1.0 / 480.0
const MPH := 2.236936
const MILE := 1609.344
# The designer's account of the mountain's road (tests/test_hyperion.gd holds these):
const AT := {"ramp": 1874, "wall": 4754, "crest": 4824, "summit": 5016, "centre": 5116, "lip": 5216, "drop": 5235, "runout": 6580, "end": 7604}
const LANE := 280.0             # a lane's centre, m off SHyperion's centreline (LEAP_LANE)
const WINDOW := [9000.0, 11000.0]
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _road(sim, road_name: String) -> int:
	for k in sim.roads.size():
		if String(sim.roads[k].name) == road_name:
			return k
	return -1


func _speed(s) -> float:
	return Vector2(s.pod.vx, s.pod.vy).length() * MPH


## The pod's place across road r: m to the left of its centreline (the way its samples run).
func _lat(s, r: int) -> float:
	var R = s.roads[r]
	var i: int = clampi(int(s.pod.hint), 0, R.N - 1)
	return (s.pod.x - R.px[i]) * R.nx[i] + (s.pod.y - R.py[i]) * R.ny[i]


func _stats() -> Dictionary:
	return {"t": 0.0, "air": -1.0, "lip": false, "lip_mph": 0.0, "lip_vz": 0.0, "lip_at": Vector2.ZERO, "lip_road": "", "peak": 0.0, "caught": -1.0, "kind": "",
		"field": "", "sample": -1, "closing": 0.0, "dz": 0.0, "arrive_mph": 0.0, "m": 0.0, "off_line": 0.0, "crash": false, "ground": false, "hits": 0, "roads": [], "high": 0.0}


## After each step of a flight: what happened, into st.
func _after(s, st: Dictionary) -> void:
	st.t += DT
	st.crash = st.crash or s.crash_t > 0.0 or s.binder_broken
	for e in s.events:
		match String(e.type):
			"airborne":
				if st.air < 0.0:
					st.air = st.t
					st.lip = bool(e.lip)
					st.lip_mph = float(e.v) * MPH
					st.lip_vz = float(e.vz)
					st.lip_at = Vector2(s.pod.x, s.pod.y)
					st.lip_road = String(s.roads[int(e.road)].name)
			"catch", "onroad":
				if st.caught < 0.0 and st.air >= 0.0:
					st.caught = st.t
					st.kind = String(e.type)
					st.field = String(s.roads[int(e.road)].name)
					st.sample = int(s.pod.hint)
					st.closing = float(e.v)
					st.dz = float(e.dz)
					st.arrive_mph = _speed(s)
					st.m = Vector2(s.pod.x, s.pod.y).distance_to(st.lip_at)
					st.off_line = _lat(s, int(e.road))
			"ground":
				st.ground = true
			"hit", "scrape":
				st.hits += 1
	s.events.clear()
	if s.pod.off_road:
		st.peak = maxf(st.peak, s.pod.z)
	else:
		st.high = maxf(st.high, s.pod.z)
		var on := String(s.roads[int(s.pod.path)].name)
		if (st.roads as Array).is_empty() or String(st.roads[-1]) != on:
			st.roads.append(on)


## The gearbox's pull in `gear` (1 to 4) at v m/s, as input/quest_controls.gd's _gearbox has it.
func _pull(gear: int, v: float) -> float:
	var g: Array = QuestControls.GEARS[gear]
	var x := v / (float(g[2]) * QuestControls.V_TOP_SPEED)
	var top := gear == QuestControls.GEARS.size() - 1
	return float(g[0]) * (0.8 + 0.2 * smoothstep(0.0, 0.4, x)) * (1.0 if top else 1.0 - smoothstep(QuestControls.LIMIT_X, 1.0, x))


## From a standing start on SHyperion's sample `from`, facing `way` along it and `right` m to the right of its
## centre line: the triggers pulled all the way and never eased, each gear taken at its redline, the burner lit in
## top gear with the ramjet armed (and the boost held with it, or not), nothing steered. Until the craft has been
## `after` s on what caught it, or passes sample `until` of SHyperion, or `seconds` are up.
func _from_summit(s, from: int, way: int, right: float, boost: bool, after: float, until := -1, seconds := 130.0) -> Dictionary:
	var hy := _road(s, "SHyperion")
	s.respawn_on(hy, from, way, right)
	s.armed = true
	var st := _stats()
	var gear := 1
	var lever := 0.0
	var shifted := INF
	var top: int = QuestControls.GEARS.size() - 1
	while st.t < seconds:
		var v := Vector2(s.pod.vx, s.pod.vy).length()
		if gear < top and shifted == INF and v / (float(QuestControls.GEARS[gear][2]) * QuestControls.V_TOP_SPEED) >= 0.955:
			gear += 1
			shifted = 0.0
		var pull := _pull(gear, v)
		if shifted != INF:      # the clutch's dip and its grab
			shifted += DT
			if shifted < QuestControls.CLUTCH_T:
				pull *= QuestControls.CLUTCH_DIP
			elif shifted < QuestControls.CLUTCH_T + QuestControls.GRAB_T:
				pull *= 1.0 + QuestControls.GRAB_SURGE * (1.0 - (shifted - QuestControls.CLUTCH_T) / QuestControls.GRAB_T)
			else:
				shifted = INF
		lever = minf(QuestControls.FULL, lever + QuestControls.FULL * QuestControls.RAMP_UP * DT)
		var inp := {"thrL": lever, "thrR": lever, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed",
			"thrMul": pull, "gearOverdrive": gear == top, "burner": gear == top}
		if boost:
			inp["boost"] = gear == top
		s.step(inp, DT)
		_after(s, st)
		if st.crash or (st.caught >= 0.0 and st.t - float(st.caught) >= after):
			break
		if until >= 0 and not s.pod.off_road and int(s.pod.path) == hy and (int(s.pod.hint) - until) * way >= 0:
			break
		if st.ground and st.caught < 0.0 and s.pod.z < 3.0:
			break
	return st


## Put down on launch lane `lane` 250 samples short of its lip at mph, `yaw` degrees to the left of its line.
## Flat out as he would be from 5,000 mph up (top gear, the ramjet lit, held through the flight), the speed
## pinned to the figure while the pod is on the lane; slower, a lever that holds the speed.
func _held(s, lane: int, mph: float, yaw := 0.0, after := 1.5, seconds := 200.0) -> Dictionary:
	var R = s.roads[lane]
	var from: int = R.N - 251
	var v := mph / MPH
	s.respawn_on(lane, from, 1)
	var a := deg_to_rad(yaw)
	var dir := Vector2(R.tx[from], R.ty[from]).rotated(a)
	var centre := Vector2(s.pod.x, s.pod.y)
	for b in s.bodies:
		var p := (Vector2(b.x, b.y) - centre).rotated(a) + centre
		b.x = p.x
		b.y = p.y
		b.th += a
		b.vx = v * dir.x
		b.vy = v * dir.y
	var flat := mph >= 5000.0
	s.armed = flat
	var feed: float = float(s.P.gate) * (2.0 * float(s.P.engineCd) + float(s.P.podCd)) * v * v / (2.0 * float(s.P.thrustMax))
	var st := _stats()
	while st.t < seconds:
		var now := Vector2(s.pod.vx, s.pod.vy).length()
		var lever := 0.87 if flat else clampf(feed + (v - now) * 0.003, 0.0, 0.87)
		var inp := {"thrL": lever, "thrR": lever, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
		if flat:
			inp["burner"] = true
			inp["gearOverdrive"] = true
			inp["thrMul"] = 1.0
		s.step(inp, DT)
		if flat and yaw == 0.0 and not s.pod.off_road and int(s.pod.path) == lane:
			var k := v / maxf(1.0, Vector2(s.pod.vx, s.pod.vy).length())
			for b in s.bodies:
				b.vx *= k
				b.vy *= k
		_after(s, st)
		if st.crash or (st.caught >= 0.0 and st.t - float(st.caught) >= after):
			break
		if st.ground and st.caught < 0.0 and s.pod.z < 3.0 and st.t - float(st.air) > 1.0:
			break
	return st


## Every body of the craft on road r, down on its deck.
func _whole_on(s, r: int) -> bool:
	for b in s.bodies:
		if b.off_road or int(b.path) != r or b.lock:
			return false
	return not s.binder_broken and s.crash_t <= 0.0


func _told(st: Dictionary) -> String:
	if st.air < 0.0:
		return "never left a lip (on %s)" % [st.roads]
	var out := "off %s at %.0f mph, %.2f deg up" % [st.lip_road, st.lip_mph, rad_to_deg(atan2(float(st.lip_vz), float(st.lip_mph) / MPH))]
	if st.caught < 0.0:
		return out + (", down on the open ground" if st.ground else ", not caught")
	return out + ", %.2f s in the air, peak %.0f m, %.1f km (%.1f miles) to %s sample %d, %.0f m off its middle, arriving %.0f mph, closing %.0f m/s from %.1f m over it" % [
		float(st.caught) - float(st.air), st.peak, float(st.m) / 1000.0, float(st.m) / MILE, st.field, st.sample, st.off_line, st.arrive_mph, st.closing, st.dz]


func _run() -> void:
	var s = Sim.new({"track": "network", "handling": "speed"})
	var hy := _road(s, "SHyperion")
	var Y = s.roads[hy]
	var step: float = s.NET_STEP
	var rise: float = s.P.rideH

	# designed
	var named := []
	var shaped: bool = s.leaps.size() == 2 and hy >= 0
	for lp in s.leaps:
		var J = s.roads[int(lp[0])]
		var K = s.roads[int(lp[1])]
		var lip_h: float = s.net_height(int(lp[0]), float(J.N - 1))
		var lip_deg := rad_to_deg(atan(s.net_slope(int(lp[0]), float(J.N - 1) - 0.001) / step))
		# the lane beside the mountain's road: its first and last samples' distance from SHyperion's centre line
		s._nearest_on(hy, J.px[0], J.py[0], 0, Y.N)
		var off0: float = absf(s._n_lat)
		var deck0: float = s._n_w
		var straight := true
		for i in J.N:
			straight = straight and absf(J.tx[i] - J.tx[0]) + absf(J.ty[i] - J.ty[0]) < 1e-9
		var gap := Vector2(K.px[0] - J.px[J.N - 1], K.py[0] - J.py[J.N - 1])
		var in_line: float = absf(gap.x * J.nx[J.N - 1] + gap.y * J.ny[J.N - 1])
		var drop: float = lip_h - s.net_height(int(lp[1]), 0.0)
		var widest := 0.0
		for i in K.N:
			widest = maxf(widest, K.w[i])
		named.append("%s (%.1f km, %.0f m wide, %.0f m off SHyperion's centre line inside its %.0f m deck, dead straight %s; lip %.1f m up at %.2f deg) to %s (%.1f km, up to %.0f m wide; begins %.0f m past the lip, %.1f m off its line, %.0f m under it)" % [
			J.name, float(J.N - 1) * step / 1000.0, J.w[0], off0, deck0, straight, lip_h, lip_deg, K.name, float(K.N - 1) * step / 1000.0, widest, gap.length(), in_line, drop])
		shaped = shaped and String(J.role) == "launch" and String(K.role) == "catch" and absf(off0 - LANE) < 0.5 and deck0 >= 800.0 and off0 + J.w[0] / 2.0 <= deck0 / 2.0 + 0.5 and straight
		shaped = shaped and absf(lip_h - float(lp[3])) < 0.01 and absf(lip_h - 200.0) < 0.5 and absf(lip_deg - 0.5) < 0.01 and absf(tan(deg_to_rad(lip_deg)) - float(lp[4])) < 1e-5
		shaped = shaped and gap.length() > 100.0 and gap.length() < 300.0 and in_line < 0.5 and drop > 100.0 and widest >= 1200.0 and J.open1 and K.open0 and not K.open1
	var top := 0.0
	for i in range(AT.summit, AT.lip + 1):
		top = maxf(top, s.net_height(hy, float(i)))
	var mountain_w := INF
	for i in range(AT.ramp, AT.end + 1):
		mountain_w = minf(mountain_w, Y.w[i])
	_check("two leaps: %s; SHyperion has its %d samples, its summit %.0f m up, its deck %.0f m wide all over the mountain (samples %d to %d); the interchanges' %d ascents are as they were" % [
			"; ".join(named), Y.N, top, mountain_w, AT.ramp, AT.end, s.jumps.size()],
		shaped and Y.N == 12890 and absf(top - 48000.0) < 0.01 and mountain_w >= 800.0 and s.jumps.size() == 21 and bool(Y.deck))
	if s.leaps.size() != 2:
		print("HYPERION LEAPS FAIL (%d failures)" % failures)
		quit(1)
		return
	var cliff: Array = s.leaps[0]
	var ramp: Array = s.leaps[1]

	# summit: the cliff's from the summit's start point (sample 5200, facing the cliff), the ramp's from the summit's middle facing back
	var flown := []
	var summit_ok := true
	var lip_speeds := []
	for run in [["the cliff's", cliff, AT.lip - 16, 1, LANE, false], ["the cliff's, boost held", cliff, AT.lip - 16, 1, LANE, true],
			["the ramp's", ramp, AT.centre, -1, -LANE, false], ["the ramp's, boost held", ramp, AT.centre, -1, -LANE, true]]:
		var st := _from_summit(s, int(run[2]), int(run[3]), float(run[4]), bool(run[5]), 1.5)
		var lane_name := String(s.roads[int(run[1][0])].name)
		var field := int(run[1][1])
		flown.append("%s: at the lip %.1f s from the start; %s; %s" % [run[0], st.air, _told(st), "whole on the field 1.5 s on" if _whole_on(s, field) else "NOT WHOLE ON ITS FIELD"])
		lip_speeds.append(roundi(float(st.lip_mph)))
		summit_ok = summit_ok and st.lip and String(st.lip_road) == lane_name and float(st.lip_mph) >= float(WINDOW[0]) and float(st.lip_mph) <= float(WINDOW[1])
		summit_ok = summit_ok and String(st.kind) == "catch" and String(st.field) == String(s.roads[field].name) and float(st.m) >= 25.0 * MILE and absf(float(st.off_line)) < 60.0
		summit_ok = summit_ok and not st.crash and not st.ground and int(st.hits) == 0 and _whole_on(s, field) and st.roads == ["SHyperion", lane_name, String(s.roads[field].name)]
	_check("from a standing start on the summit, flat out in the lane, nothing steered (lip speeds %s mph, the window %d to %d): %s" % [lip_speeds, int(WINDOW[0]), int(WINDOW[1]), "; ".join(flown)], summit_ok)

	# speeds
	for lp in [cliff, ramp]:
		var lane := int(lp[0])
		var field := int(lp[1])
		var rows := []
		var ok := true
		var miles_was := 0.0
		for mph in [9000.0, 10000.0, 11000.0]:
			var st := _held(s, lane, mph)
			var miles: float = float(st.m) / MILE
			var deg := rad_to_deg(atan2(float(st.lip_vz), float(st.lip_mph) / MPH))
			rows.append("%d mph: %s" % [int(mph), _told(st)])
			ok = ok and st.lip and absf(float(st.lip_mph) - mph) < 30.0 and absf(deg - 0.5) < 0.06 and String(st.kind) == "catch" and String(st.field) == String(s.roads[field].name)
			ok = ok and miles > miles_was + 2.0 and miles >= 25.0 and miles <= 60.0 and float(st.dz) > 30.0 and float(st.dz) <= float(s.JC_REACH) + 0.01 and float(st.closing) < 90.0
			ok = ok and float(st.peak) > 240.0 and float(st.peak) < 340.0 and absf(float(st.off_line)) < 5.0 and not st.crash and not st.ground and _whole_on(s, field)
			miles_was = miles
		_check("%s's lip, flat out: %s" % [s.roads[lane].name, "; ".join(rows)], ok)

	# slow
	var slow := []
	var slow_ok := true
	for lp in [cliff, ramp]:
		for mph in [150.0, 1500.0, 4000.0]:
			var st := _held(s, int(lp[0]), mph, 0.0, 2.5)      # (the field's cushion takes 1.5 s to set a craft down from the top of its reach)
			slow.append("%s at %d mph: %s" % [s.roads[int(lp[0])].name, int(mph), _told(st)])
			slow_ok = slow_ok and st.lip and String(st.kind) == "catch" and String(st.field) == String(s.roads[int(lp[1])].name) and not st.crash and not st.ground and _whole_on(s, int(lp[1]))
	_check("a slow craft drops onto the field's first stretch whole: %s" % ["; ".join(slow)], slow_ok)

	# climbing: up the approach from its mouth, and up the far straight toward the cliff, at 3,000 mph on a held lever
	var climbs := []
	var climb_ok := true
	var hold := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "handling": "speed"}
	for run in [["up the approach, its middle", 560, 1, 0.0, AT.ramp - 2], ["up the approach, over the lane's ground", 760, 1, LANE, AT.ramp - 2],      # (to where the engines, 22 m ahead, are at the foot)
			["up the far straight, its middle", 11900, -1, 0.0, AT.end + 3], ["up the far straight, over the field's and the lane's ground", 11900, -1, -LANE, AT.end + 3]]:
		s.respawn_on(hy, int(run[1]), int(run[2]), float(run[3]))
		s.armed = false
		var way := int(run[2])
		var v := 3000.0 / MPH
		var feed: float = float(s.P.gate) * (2.0 * float(s.P.engineCd) + float(s.P.podCd)) * v * v / (2.0 * float(s.P.thrustMax))
		for b in s.bodies:
			b.vx = v * Y.tx[int(run[1])] * way
			b.vy = v * Y.ty[int(run[1])] * way
		var st := _stats()
		var level := 0.0
		var arrived := false
		while st.t < 120.0 and not arrived:
			var lever := clampf(feed + (v - Vector2(s.pod.vx, s.pod.vy).length()) * 0.003, 0.0, 0.87)
			hold.thrL = lever
			hold.thrR = lever
			s.step(hold, DT)
			_after(s, st)
			arrived = not s.pod.off_road and int(s.pod.path) == hy and (int(s.pod.hint) - int(run[4])) * way >= 0
			if not arrived:
				for b in s.bodies:
					level = maxf(level, absf(b.z - rise))
		climbs.append("%s: %s in %.1f s by way of %s, never more than %.2f m off the level, %d wall touches" % [run[0], "at the mountain's foot" if arrived else "NOT THERE", st.t, st.roads, level, int(st.hits)])
		climb_ok = climb_ok and arrived and st.air < 0.0 and not st.crash and level < 9.0 and String(st.roads[-1]) == "SHyperion"
		if float(run[3]) == 0.0:
			climb_ok = climb_ok and st.roads == ["SHyperion"] and level < 0.01 and int(st.hits) == 0
	_check("a craft climbing is not thrown: %s" % ["; ".join(climbs)], climb_ok)

	# plain: down the middle off the summit, flat out
	var plain := []
	var plain_ok := true
	for run in [["over the cliff", AT.lip - 16, 1, 12100], ["back down the ramp", AT.centre, -1, 560]]:
		var st := _from_summit(s, int(run[1]), int(run[2]), 0.0, false, 1.5, int(run[3]))
		plain.append("%s to sample %d in %.1f s on %s, doing %.0f mph there, %d wall touches" % [run[0], int(run[3]), st.t, st.roads, _speed(s), int(st.hits)])
		plain_ok = plain_ok and st.air < 0.0 and st.roads == ["SHyperion"] and not st.crash and int(st.hits) == 0 and absf(_lat(s, hy)) < 5.0
	_check("the plain way through, down the middle and flat out: %s" % ["; ".join(plain)], plain_ok)

	# astray
	var astray := []
	var astray_ok := true
	for lp in [cliff, ramp]:
		var near := _held(s, int(lp[0]), 10000.0, 0.5)
		var far := _held(s, int(lp[0]), 10000.0, 3.0, 1.5, 60.0)
		astray.append("%s, half a degree off: %s; three degrees off: %s%s" % [s.roads[int(lp[0])].name, _told(near), _told(far), ", whole" if not far.crash else ", WRECKED"])
		astray_ok = astray_ok and String(near.kind) == "catch" and String(near.field) == String(s.roads[int(lp[1])].name) and not near.crash
		astray_ok = astray_ok and far.caught < 0.0 and far.ground and not far.crash
	_check("off the line at the lip: %s" % ["; ".join(astray)], astray_ok)

	# marked
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("hyperion_leaps_test_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var world = v.network_world
	var boards := {}
	for key in world._signs:
		if not (key is Vector2i):
			continue
		for spec in world._signs[key]:
			if String(spec[2]) == "leap" or (int(key.x) in [int(cliff[1]), int(ramp[1])] and String(spec[2]) == "brake"):
				var on := String(v.sim.roads[int(key.x)].name)
				boards[on] = int(boards.get(on, 0)) + 1
	var marks := 0
	for mark in v.minimap._w_marks:
		marks += int(String(mark[1]) == "leap")
	var rails := 0
	for guide in world._leap_rails.get(hy, []):
		rails += int(absf(absf(float(guide[3])) - LANE) < 0.5)
	_check("marked: boards %s; %d lips on the map; %d runs of amber rails down the mountain to the lanes" % [boards, marks, rails],
		int(boards.get("SHyperion", 0)) >= 6 and int(boards.get("J21", 0)) >= 2 and int(boards.get("J22", 0)) >= 2 and int(boards.get("K21", 0)) >= 2 and int(boards.get("K22", 0)) >= 2
			and marks == 2 and rails == 2)
	# one deck
	var kfield := int(cliff[1])
	var F = v.sim.roads[kfield]
	var k_plain: Array = world._leap_plain.get(kfield, [])
	var cover: Array = world._leap_cover.get(hy, [])
	var one := k_plain.size() == 3 and cover.size() == 3 and int(k_plain[2]) == hy and int(cover[2]) == kfield
	var worst := 0.0
	var probes := 0
	var on_field := 0
	var empty := 0
	if one:
		for i in range(int(cover[0]), int(cover[1]) + 1, 97):
			var half: float = Y.w[i] / 2.0
			for k in 41:
				var lat := lerpf(-half + 1.0, half - 1.0, float(k) / 40.0)
				var x: float = Y.px[i] + Y.nx[i] * lat
				var y: float = Y.py[i] + Y.ny[i] * lat
				v.sim._nearest_on(kfield, x, y, clampi(i - int(cover[0]) + int(k_plain[0]), 0, F.N - 1), 60)
				var f_lat: float = v.sim._n_lat
				var f_w: float = v.sim._n_w
				var deep_field := absf(f_lat) - f_w / 2.0
				var deep_own := absf(lat) - half
				probes += 1
				if deep_field < deep_own - 10.0:      # (the sims give the body to the field: craft_sim.gd _collide_walls)
					on_field += 1
				else:
					worst = maxf(worst, absf(float(Sim.net_edge(Y.w[i], lat).x) - float(Sim.net_edge(f_w, f_lat).x)) + absf(v.sim.net_height(hy, float(i)) - v.sim.net_height(kfield, float(v.sim._n_i))))
		for k in range(int(cover[0]) / world.CH + 1, int(cover[1]) / world.CH):
			world._build_chunk(hy, k)
			empty += int((world.chunks[Vector2i(hy, k)][0] as Node3D).get_child_count() == 0)
			if k > int(cover[0]) / world.CH + 3:
				break
	_check("one deck: the views draw K21's samples %s as a plain road and leave SHyperion's %s under it undrawn (%d of its chunks built: all empty %s); across the far straight there, at %d places, a body is on the field at %d and on the far straight at the rest, where the two decks' heights differ by %.4f m at most" % [
			k_plain.slice(0, 2), cover.slice(0, 2), empty, empty >= 3, probes, on_field, worst],
		one and int(cover[1]) - int(cover[0]) > 1000 and probes > 500 and on_field > probes / 3 and on_field < probes and worst < 0.001 and empty >= 3)
	v.free()
	print("HYPERION LEAPS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
