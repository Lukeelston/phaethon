## The autopilot (Luke, overnight list of 2026-11-22: "Add autopilot."). It flies the Network with
## the pilot's own controls: each frame it gives the two levers and the two air brakes a pilot's
## hands would, and asks for the handling a pilot would throw the MODE switch to. The sim is not
## changed and is not told: to it this is a pilot.
## What it does: plans the drive to the target city (the one the dash and the map point to) over the
## junctions, holds the road's middle along it, holds a speed (the one it was engaged at, never
## more than the road ahead allows: each bend's grip, the towns' STARFIGHTER zones, the braking
## distance), moves over for traffic it would hit and slows behind what it cannot pass, and on
## arriving carries on to the next city the dash picks.
## The route finder, the speed plan and the pilot are tools/net_route.js's (the pilot that drives
## Eridanus to Glacier for the recorded replay, tools/record_network.js), carried over line for
## line: with no cruise cap and no traffic this flies that drive's own inputs
## (tests/test_autopilot.gd holds it to them).
## The logic alone: no nodes. The view calls it once a frame and applies what it returns.
##   var a := Autopilot.new()
##   a.engage(sim, city)          -> true if it has the craft (false: why_off says why not)
##   a.fly(sim, city, cars)       -> {thrL, thrR, brkL, brkR, handling} for this frame, or {} when
##                                   it has given the craft back (on is then false, why_off why)
##   a.nudge(+1 / -1)             its speed up or down a step
##   a.disengage(why)
##   a.message() / a.line() / a.suffix()      for the glass, the instrument strip, the Mach line
extends RefCounted

const G := 9.81
const MPH := 2.236936                # mph per m/s
const SF_OMEGA := 0.95               # STARFIGHTER: the turn rate it is planned at (rad/s) ...
const SF_ALAT := 38.0 * G            # ... its grip ...
const SF_TOP := 1150.0 / MPH         # ... and its speed
const SP_ALAT := 8.5 * G             # SPEEDCRAFT's grip, a margin under what it has
const SP_TOP := 4300.0 / MPH         # ... and the most it is flown at: full lever, no burner
const SWITCH_V := 1200.0 / MPH       # under this the towns are flown as a STARFIGHTER
const TOP_LEVER := 0.87              # full lever under the burner's gate (QuestControls.FULL)
const PAST_GOAL := 120               # samples flown on past a city's mark, so the arrival is taken at speed
const CRUISE_FLOOR := 600.0 / MPH    # engaged slower than this (standing on the pad) it takes CRUISE_DEFAULT
const CRUISE_DEFAULT := 2500.0 / MPH
const CRUISE_STEP := 250.0 / MPH     # a nudge
const SLOW_V := 40.0                 # m/s: under this a SPEEDCRAFT is steered by her facing, not her course
const STRAY := 260.0                 # m from the route: it has been knocked off it, and plans again
# The traffic keeps to lanes (view/network_traffic.gd LANES_HWY: 45 m apart, the two middle ones 22.5 m either
# side of the centreline; LANES_RAMP: 50 m apart, 25 m either side). The road's middle is the gap between the two
# middle lanes, and a lane over for the autopilot is the next gap out, never a lane itself.
const LANE_STEP_HWY := 45.0
const LANE_STEP_RAMP := 50.0
const LANE_WIDE := 170.0             # a road with a half width over this has the highways' lanes
const LANE_EDGE := 0.62              # ... never further out than this share of the road's half width
const CAR_HALF := 16.0               # m either side of its line that a vehicle is in its way
const LOOK_S := 6.0                  # s ahead that traffic is looked for ...
const LOOK_FAR_S := 30.0             # (a lane clear for this long is as good as clear)
const LOOK_MIN := 400.0              # ... and never less than this far (m)
const FOLLOW_GAP_S := 1.2            # behind what it cannot pass it keeps this many seconds ...
const FOLLOW_ROOM := 60.0            # ... and this many metres
# Slowing for it is the air brakes' work, and they are drag: full on they took her from 769 mph to 518 in six
# seconds and from 518 to 415 in the next six (0.8 g), a slowing of about 1.8e-4 of the speed squared. So the
# speed it may hold a distance behind a vehicle is that vehicle's times e^(FOLLOW_K x distance), with a margin.
# (Planned as steady braking, at 6 g and then at 3, it was still doing 415 mph when it reached a 300 mph wall.)
const FOLLOW_K := 1.2e-4
const FOLLOW_SLOWEST := 100.0        # m/s: the look reaches far enough to slow to a vehicle doing this
const FOLLOW_UNDER := 55.0           # m/s: how far under that speed it asks, far out (see _traffic)
const TRIM_RATE := 0.4               # the cruise hold's trim: m/s of ask taken off per m/s over, a second ...
const TRIM_MOST := 90.0              # ... to this much at most (m/s)

var on := false
var why_off := ""                    # why it gave the craft back, or would not take it
var cruise := SP_TOP                 # m/s
var target := -1                     # the city it is flying to (the sim's index)
var events: Array[String] = []       # "engaged", "replanned", "arrived", "lane", "off"
var status := ""                     # HOLDING, SLOWING, CLIMBING, TRAFFIC
var lane := 0.0                      # m left (+) of the road's middle it is holding
var lane_cap := INF                  # m/s: what traffic it cannot pass holds it to
# the route, a sample at a time: where, which way, how long, the road's mode, which road and sample
var rx := PackedFloat64Array()
var ry := PackedFloat64Array()
var rtx := PackedFloat64Array()
var rty := PackedFloat64Array()
var rlen := PackedFloat64Array()
var rmode := PackedByteArray()
var rpath := PackedInt32Array()
var ri := PackedInt32Array()
var rs := PackedFloat64Array()       # m along the route to each sample
var rnext := PackedInt32Array()      # the route sample at which the road next changes (the last, if never)
var vplan := PackedFloat64Array()    # m/s at each sample
var vroad := PackedFloat64Array()    # ... and what the road itself allows there, whatever the cruise speed
var like_recorded := false           # (the test's: the recorded pilot's own standing start, see pilot())
var at := 0                          # the route sample the pod is at
var _sim
var _dt := 1.0 / 60.0                # the frame it is flying (s)
var _trim := 0.0                     # m/s taken off the ask while it holds its cruise speed (pilot())


static func _wrap(a: float) -> float:
	return atan2(sin(a), cos(a))


static func _r4(v: float) -> float:
	return roundf(v * 1e4) / 1e4


## The index on the other road a junction maps road index i to (the sims' linear map).
## A junction: [a, a0, a1, b, b0, b1, sense].
static func across(J: Array, on_a: bool, i: int) -> int:
	var f0 := int(J[1]) if on_a else int(J[4])
	var f1 := int(J[2]) if on_a else int(J[5])
	var t0 := int(J[4]) if on_a else int(J[1])
	var t1 := int(J[5]) if on_a else int(J[2])
	var u := float(i - f0) / float(f1 - f0) if f1 > f0 else 0.0
	return roundi(t0 + u * (t1 - t0)) if int(J[6]) > 0 else roundi(t1 - u * (t1 - t0))


## A road the autopilot will not plan through (it may start on one): a shaft, a deck road, the
## Aurora Line, a jump's launch or catch, an on-ramp from the open ground.
static func special(sim, road: int) -> bool:
	var R = sim.roads[road]
	if R.shaft or R.deck or String(R.role) != "":
		return true
	return (sim.NET_PRESSURE as Array).has(road)


## The shortest drive from `from` ({road, i, dir}: dir +1 up the samples, -1 down, 0 either) to
## `goal` ({road, i}), as legs [{road, i0, i1, dir}]: Dijkstra over (road, sample, way), switching
## roads only inside junction zones and only the way a road can be entered. [] if there is none.
## `plain`: not through the special roads.
static func legs_to(sim, from: Dictionary, goal: Dictionary, plain := true) -> Array:
	var dist := {}
	var prev := {}
	var heap: Array = []
	var push := func(r: int, i: int, d: int, c: float, p) -> void:
		var k := Vector3i(r, i, d)
		if dist.has(k) and float(dist[k]) <= c:
			return
		dist[k] = c
		prev[k] = p
		heap.append([c, r, i, d])
	var ways: Array = [int(from.dir)] if int(from.dir) != 0 else [1, -1]
	for d in ways:
		push.call(int(from.road), int(from.i), int(d), 0.0, null)
	var best = null
	while not heap.is_empty():
		var m := 0
		for k in range(1, heap.size()):
			if float(heap[k][0]) < float(heap[m][0]):
				m = k
		var top: Array = heap.pop_at(m)
		var c := float(top[0])
		var r := int(top[1])
		var i := int(top[2])
		var d := int(top[3])
		if c > float(dist[Vector3i(r, i, d)]):
			continue
		if best != null and c >= float(best.c):
			break
		if r == int(goal.road) and (int(goal.i) - i) * d >= 0:
			var cg := c + absf(int(goal.i) - i)
			if best == null or cg < float(best.c):
				best = {"c": cg, "r": r, "i": i, "d": d}
		for k in sim.roads[r].jx:
			var J: Array = sim.junctions[k]
			var on_a := int(J[0]) == r
			# over where the two coincide: the joining road's end (b) and the parent's sample there
			var C = sim.roads[int(J[3])]
			var cb := 0 if int(J[4]) == 0 else (int(J[5]) if int(J[5]) == int(C.N) - 1 else roundi((int(J[4]) + int(J[5])) / 2.0))
			var ca := across(J, false, cb)
			var zc := ca if on_a else cb
			if (zc - i) * d <= 0:
				continue   # behind
			var q := int(J[3]) if on_a else int(J[0])
			var iq := cb if on_a else ca
			var dq := d * int(J[6])
			var qz0 := int(J[4]) if on_a else int(J[1])
			var qz1 := int(J[5]) if on_a else int(J[2])
			if qz0 == 0 and dq < 0:
				continue            # a road's start: only going up it
			if qz1 == int(sim.roads[q].N) - 1 and dq > 0:
				continue            # its end: only going down it
			if plain and q != int(goal.road) and special(sim, q):
				continue
			push.call(q, iq, dq, c + absf(zc - i), {"r": r, "i": i, "d": d, "at": zc})
	if best == null:
		return []
	var legs: Array = [{"road": int(best.r), "i0": int(best.i), "i1": int(goal.i), "dir": int(best.d)}]
	var k := Vector3i(int(best.r), int(best.i), int(best.d))
	while prev.get(k) != null:
		var p: Dictionary = prev[k]
		legs.push_front({"road": int(p.r), "i0": int(p.i), "i1": int(p.at), "dir": int(p.d)})
		k = Vector3i(int(p.r), int(p.i), int(p.d))
	return legs


## Take legs as the route: its samples (tangents the way it is flown), and the speed at each.
func set_route(sim, legs: Array) -> void:
	_sim = sim
	rx.clear(); ry.clear(); rtx.clear(); rty.clear(); rlen.clear(); rmode.clear(); rpath.clear(); ri.clear()
	for L in legs:
		var R = sim.roads[int(L.road)]
		var d := int(L.dir)
		var i := int(L.i0)
		while (i <= int(L.i1)) if d > 0 else (i >= int(L.i1)):
			rx.append(R.px[i]); ry.append(R.py[i])
			rtx.append(R.tx[i] * d); rty.append(R.ty[i] * d)
			rlen.append(R.len[i]); rmode.append(R.mode[i])
			rpath.append(int(L.road)); ri.append(i)
			i += d
	var n := rx.size()
	rs.resize(n)
	rnext.resize(n)
	for i in range(1, n):
		rs[i] = rs[i - 1] + Vector2(rx[i] - rx[i - 1], ry[i] - ry[i - 1]).length()
	var nxt := n - 1
	for i in range(n - 1, -1, -1):
		if i < n - 1 and rpath[i + 1] != rpath[i]:
			nxt = i + 1
		rnext[i] = nxt
	at = 0
	lane = 0.0
	lane_cap = INF
	_plan()


## The speed at each route sample: each mode's grip and turn-rate limits over the bends, the cruise
## speed, and the braking distance into whatever is slower ahead. (net_route.js plan(), with a cap.)
func _plan() -> void:
	var n := rx.size()
	vplan.resize(n)
	vroad.resize(n)
	var kap := PackedFloat64Array()
	kap.resize(n)
	for i in range(0, n - 1):
		kap[i] = absf(_wrap(atan2(rty[i + 1], rtx[i + 1]) - atan2(rty[i], rtx[i]))) / rlen[i]
	for i in n:
		var k := 0.0
		for j in range(-4, 5):
			k = maxf(k, kap[mini(n - 1, maxi(0, i + j))])
		if rmode[i] == 0:
			vroad[i] = minf(SWITCH_V, SF_TOP if k < 1e-6 else minf(SF_TOP, minf(SF_OMEGA / k, sqrt(SF_ALAT / k))))
		else:
			vroad[i] = SP_TOP if k < 1e-7 else minf(SP_TOP, sqrt(SP_ALAT / k))
		vplan[i] = minf(vroad[i], cruise)
	vroad = _braked(vroad)
	vplan = _braked(vplan)


## A speed plan with the braking distance into whatever is slower ahead taken out of it.
func _braked(plan: PackedFloat64Array) -> PackedFloat64Array:
	var n := plan.size()
	for pass_ in 3:
		for i in range(n - 2, -1, -1):
			var nx := plan[i + 1]
			var decel := (5.0 + 9.0 * minf(nx / 447.0, 1.0)) * G
			plan[i] = minf(plan[i], sqrt(nx * nx + 2.0 * decel * rlen[i]))
	return plan


## Which way along its road the pod is going: its travel, or standing its facing.
static func way(sim) -> int:
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, int(R.N) - 1)
	var along: float = sim.pod.vx * R.tx[i] + sim.pod.vy * R.ty[i]
	if absf(along) < 1.0:
		along = cos(sim.pod.th) * R.tx[i] + sin(sim.pod.th) * R.ty[i]
	return 1 if along >= 0.0 else -1


## Plan from where the pod is to a city. -> false if there is no drive to it from here, this way.
func plan_to(sim, city: int) -> bool:
	if city < 0 or city >= sim.cities.size():
		return false
	var R = sim.roads[sim.pod.path]
	var from := {"road": int(sim.pod.path), "i": clampi(int(sim.pod.hint), 0, int(R.N) - 1), "dir": way(sim)}
	var c: Dictionary = sim.cities[city]
	var legs := legs_to(sim, from, {"road": int(c.road), "i": int(c.i)})
	if legs.is_empty():
		legs = legs_to(sim, from, {"road": int(c.road), "i": int(c.i)}, false)
	if legs.is_empty():
		return false
	var last: Dictionary = legs[legs.size() - 1]
	last.i1 = clampi(int(last.i1) + int(last.dir) * PAST_GOAL, 0, int(sim.roads[int(last.road)].N) - 1)
	target = city
	set_route(sim, legs)
	return true


## Take the craft: on the Network, on a road, with a city to go to. The speed it holds is the one
## it is engaged at (standing or slow: CRUISE_DEFAULT), within what it flies at.
func engage(sim, city: int) -> bool:
	on = false
	why_off = ""
	if String(sim.kind) != "network":
		why_off = "THE NETWORK ONLY"
	elif sim.crash_t > 0.0 or sim.pod.off_road:
		why_off = "NOT ON A ROAD"
	elif city < 0:
		why_off = "NO DESTINATION"
	if why_off != "":
		return false
	var v := Vector2(sim.pod.vx, sim.pod.vy).length()
	cruise = clampf(v, CRUISE_FLOOR, SP_TOP) if v >= CRUISE_FLOOR else CRUISE_DEFAULT
	cruise = roundf(cruise * MPH / 50.0) * 50.0 / MPH      # (a round figure on the glass)
	if not plan_to(sim, city):
		why_off = "NO ROAD THERE FROM HERE"
		return false
	on = true
	status = "HOLDING"
	events.append("engaged")
	return true


func disengage(why := "") -> void:
	if on:
		events.append("off")
	on = false
	why_off = why
	lane = 0.0
	lane_cap = INF


## Its speed up (+1) or down (-1) a step.
func nudge(steps: int) -> void:
	set_cruise(cruise + steps * CRUISE_STEP)


## The speed it holds (m/s), within what it flies at.
func set_cruise(v: float) -> void:
	cruise = clampf(v, CRUISE_FLOOR, SP_TOP)
	if on:
		_plan()


## net_route.js makePilot()'s frame: the levers and brakes [thrL, thrR, brkL, brkR] and the handling
## it asks (1 SPEEDCRAFT, 2 STARFIGHTER), following the route `lane` m left of its line and no
## faster than `lane_cap`. [] at the route's end.
func pilot(sim) -> Array:
	var n := rx.size()
	if n < 3:
		return []
	var sp := maxf(1.0, rlen[0])
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var v := Vector2(sim.pod.vx, sim.pod.vy).length()
	var bd := INF
	var bi := at
	for k in range(maxi(0, at - 10), mini(n, at + 60)):
		var d := (rx[k] - px) * (rx[k] - px) + (ry[k] - py) * (ry[k] - py)
		if d < bd:
			bd = d
			bi = k
	at = bi
	var i := bi
	if i >= n - 2:
		return []   # the route's end
	var speedcraft := String(sim.P.handling) == "speed"
	var lead := ceili(v * 0.35 / sp)
	var want := minf(vplan[mini(n - 1, i + lead)], lane_cap)
	status = "TRAFFIC" if lane_cap < vplan[mini(n - 1, i + lead)] else ("SLOWING" if v > want + 12.0 else ("CLIMBING" if v < want - 25.0 else "HOLDING"))
	# Holding its cruise speed the recorded pilot's law settles over it (20 mph at 2,400, 110 at 1,200: its lever
	# never goes under a quarter, for steering, and the air brakes it holds that against bite less the slower she
	# flies). A trim takes that out, slowly, while the cruise speed is what limits it, and is let go otherwise.
	if not like_recorded and want >= cruise - 0.5 and absf(v - cruise) < 120.0:
		_trim = clampf(_trim + (v - cruise) * TRIM_RATE * _dt, 0.0, TRIM_MOST)
		want -= _trim
	else:
		_trim = move_toward(_trim, 0.0, 40.0 * _dt)
	var ai := mini(n - 1, i + roundi((60.0 + v * (0.5 if speedcraft else 0.36)) / sp))
	var aim_x := rx[ai] - rty[ai] * lane
	var aim_y := ry[ai] + rtx[ai] * lane
	var mx: float = (sim.eL.x + sim.eR.x) / 2.0
	var my: float = (sim.eL.y + sim.eR.y) / 2.0
	# (a SPEEDCRAFT is steered by where it is going; standing it is going nowhere, and the recorded pilot read that
	# as due east and pulled a lever off for the first seconds of a start that faced any other way: it goes by her
	# facing until she is moving)
	var course: float = atan2(sim.pod.vy, sim.pod.vx) if speedcraft else float(sim.pair_th)
	if v < SLOW_V and not like_recorded:
		course = atan2(sin(sim.eL.th) + sin(sim.eR.th), cos(sim.eL.th) + cos(sim.eR.th))
	var err := _wrap(atan2(aim_y - my, aim_x - mx) - course)
	var k := clampf(err * (3.0 if speedcraft else 5.0), -1.0, 1.0)
	var base := TOP_LEVER if v < want - 4.0 else clampf(TOP_LEVER * (want / maxf(v, 1.0)) - 0.1, 0.0, TOP_LEVER)
	var brk := clampf((v - want - 6.0) / 25.0, 0.0, 1.0)
	if speedcraft and v - want < 50.0:
		var keep := minf(TOP_LEVER, 0.25 + 0.75 * absf(k))
		if base < keep:
			brk = maxf(brk, minf(1.0, (v - want + 4.0) / 40.0))
			base = keep
		brk = minf(brk, 1.0 - 0.8 * minf(1.0, absf(k) / 0.4))
	elif brk > 0.0:
		base = 0.0
	# (the handling goes by what the road allows two seconds on, not by a cruise speed that happens to be a town's)
	var ahead := vroad[mini(n - 1, i + ceili(v * 2.0 / sp))]
	var h := 2 if rmode[i] == 0 or ahead <= SWITCH_V * 1.05 else 1
	return [_r4(minf(1.0, base * (1.0 - maxf(0.0, k)))), _r4(minf(1.0, base * (1.0 + minf(0.0, k)))),
		_r4(minf(1.0, maxf(brk, (k - 0.6) * 2.0 if k > 0.6 else 0.0))), _r4(minf(1.0, maxf(brk, (-k - 0.6) * 2.0 if k < -0.6 else 0.0))), h]


## Traffic in its way: the vehicles ahead on its road, each [m ahead along the route, m left of the
## route's line, m/s along it]. It moves a lane over for one it is closing on (the clearest lane,
## the nearest the middle on a tie), comes back to the middle when that is clear, and where there is
## no room it slows, in time, to sit FOLLOW_GAP_S behind what is in its way.
## cars: the view's (NetworkTraffic.cars: x, y, v, hx, hy).
func _traffic(sim, cars: Array) -> void:
	lane_cap = INF
	if cars.is_empty() or rx.size() < 3:
		lane = move_toward(lane, 0.0, 0.5)
		return
	var v := Vector2(sim.pod.vx, sim.pod.vy).length()
	var reach := maxf(maxf(LOOK_MIN, v * LOOK_S), log(maxf(v, FOLLOW_SLOWEST) / FOLLOW_SLOWEST) / FOLLOW_K + FOLLOW_GAP_S * FOLLOW_SLOWEST + FOLLOW_ROOM)
	var i := at
	var ox := rx[i]
	var oy := ry[i]
	var tx := rtx[i]
	var ty := rty[i]
	var here: float = (sim.pod.x - ox) * tx + (sim.pod.y - oy) * ty
	var R = sim.roads[rpath[i]]
	var half: float = R.w[clampi(ri[i], 0, int(R.N) - 1)] * 0.5
	var lane_step := LANE_STEP_HWY if half > LANE_WIDE else LANE_STEP_RAMP
	var seen: Array = []
	for c in cars:
		var dx: float = c.x - ox
		var dy: float = c.y - oy
		if absf(dx) > reach or absf(dy) > reach:
			continue
		# (the route is taken as straight over the look: the roads bend over tens of kilometres)
		var along: float = dx * tx + dy * ty - here
		if along < -40.0 or along > reach:
			continue
		var left: float = -dx * ty + dy * tx
		if absf(left) > half + 10.0:
			continue   # not on this road
		seen.append([along, left, float(c.v) * (float(c.hx) * tx + float(c.hy) * ty)])
	if seen.is_empty():
		lane = move_toward(lane, 0.0, lane_step) if absf(lane) > 0.5 else 0.0
		return
	var edge := floorf(half * LANE_EDGE / lane_step) * lane_step
	var lanes: Array = [lane]
	for step in [1, -1, 2, -2, 3, -3]:
		var cand := clampf(roundf(lane / lane_step) * lane_step + step * lane_step, -edge, edge)
		if not lanes.has(cand):
			lanes.append(cand)
	if not lanes.has(0.0):
		lanes.append(0.0)
	var best_lane := lane
	var best_score := -INF
	var gap := INF            # the nearest it is closing on in the lane it holds: how far ahead ...
	var gap_t := INF          # ... how many seconds off ...
	var gap_v := 0.0          # ... and its speed
	for cand in lanes:
		var held := is_equal_approx(float(cand), lane)
		var t := INF
		for s in seen:
			if absf(float(s[1]) - float(cand)) > CAR_HALF + (0.0 if held else 8.0):
				continue
			var closing: float = v - float(s[2])
			if not held and float(s[0]) < 60.0:
				t = 0.0       # alongside: no moving into it
			elif float(s[0]) > 0.0 and closing > 1.0:
				t = minf(t, float(s[0]) / closing)
				if held and float(s[0]) < gap:
					gap = float(s[0])
					gap_t = float(s[0]) / closing
					gap_v = float(s[2])
		var score := minf(t, LOOK_FAR_S) + (0.75 if held else 0.0) - absf(float(cand)) * 0.002
		if score > best_score:
			best_score = score
			best_lane = cand
	if gap < INF and not is_equal_approx(best_lane, lane):
		lane = best_lane       # a clearer lane: over, now (it takes seconds to get there)
		events.append("lane")
		return
	if gap_t >= LOOK_S and absf(lane) > 0.5:
		# nothing in its way: back toward the middle, a lane at a time, when that is clear too
		var back := move_toward(lane, 0.0, lane_step)
		var clear := true
		for s in seen:
			if absf(float(s[1]) - back) <= CAR_HALF + 8.0 and float(s[0]) > -60.0 and float(s[0]) < maxf(LOOK_MIN, v * 3.0):
				clear = false
		if clear:
			lane = back
	if gap < INF:
		# nowhere to go: no faster than still lets it slow to that vehicle's speed a gap behind it
		var room := gap - FOLLOW_GAP_S * gap_v - FOLLOW_ROOM
		lane_cap = maxf(gap_v, 20.0) * exp(FOLLOW_K * maxf(0.0, room)) if gap > FOLLOW_ROOM else maxf(0.0, gap_v - 15.0)
		# (the pilot's law brakes in proportion and keeps a quarter lever on within 110 mph of its ask: asked for
		# less than it may hold, by up to that, it has the brakes full out and the levers shut while there is far to go)
		lane_cap = maxf(maxf(gap_v - 15.0, 0.0), lane_cap - minf(FOLLOW_UNDER, 0.02 * maxf(room, 0.0)))


## A frame: the levers for it. `city` is where the dash points now (it follows a change, and the next
## city after an arrival); `cars` the traffic to keep clear of ([] for none). {} when it has given
## the craft back. `dt`: the frame's length (s).
func fly(sim, city: int, cars: Array = [], dt := 1.0 / 60.0) -> Dictionary:
	if not on:
		return {}
	_dt = clampf(dt, 0.0, 0.1)
	if sim.crash_t > 0.0:
		disengage("CRASHED")
		return {}
	if sim.pod.off_road:
		disengage("OFF THE ROAD")
		return {}
	if city >= 0 and city != target:
		var was := target
		if not plan_to(sim, city):
			disengage("NO ROAD THERE FROM HERE")
			return {}
		events.append("arrived" if was >= 0 and _near_city(sim, was) else "replanned")
	_traffic(sim, cars)
	var u := pilot(sim)
	var strayed := rx.size() >= 3 and Vector2(rx[at] - sim.pod.x, ry[at] - sim.pod.y).length() > STRAY + absf(lane)
	if u.is_empty() or strayed:
		if not plan_to(sim, city if city >= 0 else target):
			disengage("NO ROAD THERE FROM HERE")
			return {}
		events.append("replanned")
		u = pilot(sim)
		if u.is_empty():
			disengage("ARRIVED")
			return {}
	return {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "handling": "starfighter" if int(u[4]) == 2 else "speed"}


static func _near_city(sim, city: int) -> bool:
	var c: Dictionary = sim.cities[city]
	return Vector2(float(c.cx) - sim.pod.x, float(c.cy) - sim.pod.y).length() < 60000.0


static func _miles(m: float) -> String:
	var mi := m / 1609.344
	return ("%.1f MI" % mi) if mi < 10.0 else ("%d MI" % roundi(mi))


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## What comes next on the route: "N3 IN 12 MI" (the road it turns onto and how far off), or the
## city and how far.
func next_text() -> String:
	if not on or _sim == null or rx.size() < 3:
		return ""
	var j := rnext[at]
	if j < rx.size() - 1 and rpath[j] != rpath[at]:
		return "%s IN %s" % [String(_sim.roads[rpath[j]].name).to_upper(), _miles(rs[j] - rs[at])]
	return "%s IN %s" % [String(_sim.cities[target].name).to_upper() if target >= 0 else "THE END", _miles(maxf(0.0, rs[rx.size() - 1] - rs[at] - PAST_GOAL * maxf(1.0, rlen[0])))]


## Its page for the glass (the checklist's three lines: "ACTION  COUNT", "WHERE > WHAT", "NOTE | STATUS"),
## "" when it is not flying.
func message() -> String:
	if not on:
		return ""
	var city := String(_sim.cities[target].name).to_upper() if _sim != null and target >= 0 else ""
	return "AUTOPILOT  %s MPH\nTO %s > %s\nA TRIGGER OR A GRIP TAKES HER BACK | %s" % [_commas(roundi(cruise * MPH)), city, next_text(), status]


## The same, short, for an instrument strip.
func line() -> String:
	if not on:
		return ""
	return "AUTOPILOT   %s MPH\n%s" % [_commas(roundi(cruise * MPH)), next_text()]


## For the dash's Mach line, beside BOOST.
func suffix() -> String:
	return "   AUTO" if on else ""
