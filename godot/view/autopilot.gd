## The autopilot (Luke, overnight list of 2026-11-22: "Add autopilot."). It flies the Network with
## the pilot's own controls: each frame it gives the two levers and the two air brakes a pilot's
## hands would, and asks for the handling a pilot would throw the MODE switch to. The sim is not
## changed and is not told: to it this is a pilot.
## What it does: plans the drive to the target city (the one the dash and the map point to) over the
## junctions, holds the road's middle along it, holds a speed (the one it was engaged at, never
## more than the road ahead allows: each bend's grip, the towns' STARFIGHTER zones, the braking
## distance), moves over for traffic it would hit and slows behind what it cannot pass, and on
## arriving carries on to the next city the dash picks.
## The route finder and the speed plan are tools/net_route.js's (the pilot that drives Eridanus to
## Glacier for the recorded replay, tools/record_network.js), carried over line for line, and so is
## that pilot, pilot(): with like_recorded set it flies that drive's own inputs
## (tests/test_autopilot.gd holds it to them).
## What flies the craft is _hand(): the same route, plan and aim, with a hand on the controls (Luke,
## after flying the first one: "Autopilot works, but definitely runs like a computer running it -
## very jumpy."). The recorded pilot's law is a relay: full lever under its speed and a cut lever
## over it, a brake that goes from nothing to everything across 55 mph, a lever shut the moment a
## brake is on. Each is a jump, and held at a speed it sits on one and flips every frame or two (at
## 1,200 mph: both brakes full on and the levers 0 / 0.69 / 0, 30 times a second; in a town it hung
## at 1,262 mph, too fast ever to become a STARFIGHTER, the same way). The hand asks for an
## acceleration instead (the one that has her on the plan a half, one and two seconds on), works out
## from the sim's own figures the lever that gives it, holds a speed on the levers and uses the air
## brakes only for what lifting them cannot give, and moves each control no faster than a hand does.
## In traffic it picks a lane for a real gain and keeps it, moves over to it as a hand would steer
## there, and slows for a vehicle no harder than it takes to sit behind it.
## What it is held to: tests/test_autopilot.gd HANDS (a lever's and a brake's fastest move, turns
## back a minute, jerk at the seat, the nose's wag), measured by tests/hand_meter.gd;
## tests/probe_autopilot_hands.gd flies the same drives in the cockpit's frames and logs them.
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
# Its hands (_hand). The speed: an acceleration asked, and the lever and brake that give it.
# The acceleration asked is the one that has her on the plan at each of these looks ahead (s), the least of
# them: the far look begins a slowing two seconds before the plan does and takes the levers off early when she
# is climbing toward a plan that is coming down; the near one keeps her on it to the bottom. (Asked from her
# speed's error where she is, she climbed flat out into each braking point and went from 20 g on to 14 g off
# in a fifth of a second.)
const HAND_LOOKS := [0.5, 1.0, 2.0]
const HAND_KI := 0.1                 # m/s^2 per m/s she is off, held for a second: a trim, while she holds a speed ...
const HAND_TRIM := 2.0 * G           # ... to this much at most
const HAND_HOLD := 8.0               # m/s: within this of her speed she is holding it (the trim works)
const HAND_SLOW := 20.0 * G          # the hardest it slows her for its plan (the plan itself brakes at 14 g) ...
const HAND_STOP := 45.0 * G          # ... and when she is far over what the road or the traffic allows
const BEND_FROM := 300.0             # m ahead: from here a vehicle is placed by the route's own line where it is
const ACROSS := 0.8                  # a vehicle heading less along the route than this (the cosine: 37 degrees off) is crossing it
# Slowing for a vehicle in her lane: no harder than it takes to be at its speed a following gap behind it (her
# closing speed squared over twice the room), and this much to spare. (The speed she may hold behind one,
# _behind(), is a drag law's, and far under her own when a vehicle changes into her lane a mile ahead at 4,000
# mph: asked for by her speed's error alone that was all the brakes she had, 45 g and 86 at the seat, for the
# half second till she found another lane, where 11 g would have done.)
const FOLLOW_SPARE := 1.3
const FOLLOW_EASY := 2.0 * G
const KEEP := 0.25                   # "the throttle stays on while braking": the lever kept, at most ...
const KEEP_SHARE := 0.6              # ... and never more than this share of the lever that holds the speed asked
const STEER_FULL := 0.8              # the two levers' difference at full steering (the recorded pilot's, at its cruise lever)
const BRAKE_IN := 0.02               # a brake goes on when this much is wanted ...
const BRAKE_OUT := 0.004             # ... and comes off under this: no brushing on and off
# ... and how a hand moves them: no faster than this, easing in to where it is going, and not at all for less
# than HAND_STILL. (A finger takes a trigger's whole travel in about a quarter of a second at its quickest; the
# cockpit's own levers come up at 0.77 a second under Luke's hands, QuestControls.RAMP_UP.)
const LEVER_UP := 1.5                # a second: both levers together, up ...
const LEVER_DOWN := 2.0              # ... and down
const STEER_RATE := 2.0              # ... and their difference
const BRAKE_ON := 0.6                # a brake going on (0.15, the plan's 14 g at speed, in a quarter of a second) ...
const BRAKE_OFF := 1.2               # ... and coming off: a hand lets go quicker than it squeezes. (At 0.6 the brakes she
                                     # comes into a town on, near full under 1,750 mph where the flaps fade, were still half
                                     # out a second after she had become a STARFIGHTER and the levers had gone to full.)
const HAND_EASE := 0.08              # s: the easing (QuestControls.SPLIT_TAU)
const HAND_STILL := 0.004
const LANE_EASE := 1.5               # rad/s: the lane it holds moves over as a damped spring this stiff (90% over in 2.6 s) ...
const LANE_HURRY := 4.0              # ... or, for a vehicle it has less than LANE_HURRY_S to, up to this stiff (90% over in a second)
const LANE_HURRY_S := 4.5
const LANE_DWELL := 2.0              # s in a lane before it comes back toward the middle
# Choosing a lane. (In the Network's own traffic at 3,200 mph it chose five in fourteen seconds, one of them three
# lanes across the road and given up 0.9 s later, before she had moved a lane's width: each lane is scored by the
# seconds to the first vehicle she is closing on in it, the scores of two poor lanes pass each other from frame to
# frame, and the lane held had 0.75 s in hand.)
const LANE_GAIN := 2.0               # s: another lane has to be this much clearer than the one it holds ...
const LANE_FAR := 1.0                # ... and this much more for each lane further off it is
const LANE_COMMIT := 3.0             # s: a lane just chosen is kept this long ...
const LANE_PRESSED := 2.0            # ... unless a vehicle in it is nearer than this (s)

var on := false
var why_off := ""                    # why it gave the craft back, or would not take it
var cruise := SP_TOP                 # m/s
var target := -1                     # the city it is flying to (the sim's index)
var events: Array[String] = []       # "engaged", "replanned", "arrived", "lane", "off"
var status := ""                     # HOLDING, SLOWING, CLIMBING, TRAFFIC
var lane := 0.0                      # m left (+) of the road's middle it is holding
var lane_cap := INF                  # m/s: what traffic it cannot pass holds it to
var lane_need := 0.0                 # m/s^2: the slowing that has her at that traffic's speed a gap behind it
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
# its hands (_hand): where they have the controls now
var pull := 1.0                      # the gearbox's pull, if there is one (the view's, a frame: the sims' inp.thrMul) ...
var overdrive := false               # ... and whether it is in top gear, whose drag the sims shape (inp.gearOverdrive)
var _pull := 1.0                     # (the pull with the clutch's dip and grab eased out of it)
var _mean := 0.0                     # the two levers' mean ...
var _dif := 0.0                      # ... and their difference, right less left (+: a left turn)
var _brk_l := 0.0
var _brk_r := 0.0
var _braking := false                # the brakes are on (see BRAKE_IN)
var _a_trim := 0.0                   # m/s^2: the speed hold's trim
var _lane_now := 0.0                 # m left of the road's middle it is aiming, on its way to `lane` ...
var _lane_v := 0.0                   # ... and how fast that is moving (m/s)
var _lane_t := 0.0                   # s since it last chose another lane
var _lane_w := LANE_EASE             # ... and how stiffly it is moving over to it (rad/s)
var _ask := 1                        # the handling it asks for (1 SPEEDCRAFT, 2 STARFIGHTER), held (see _hand)


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
	hands(0.0, 0.0, 0.0, 0.0)
	_a_trim = 0.0
	_lane_now = 0.0
	_lane_v = 0.0
	_lane_t = LANE_COMMIT
	_lane_w = LANE_EASE
	_ask = 2 if sim.hblend >= 0.5 else 1
	return true


## Where the controls are as it takes them (the view's: the pilot's own levers and brakes that frame):
## it moves them on from there, as the next hand on them would, and does not drop them first.
func hands(thr_l: float, thr_r: float, brk_l: float, brk_r: float) -> void:
	_mean = clampf((thr_l + thr_r) / 2.0, 0.0, TOP_LEVER)
	_dif = clampf(thr_r - thr_l, -2.0 * _mean, 2.0 * _mean)
	_brk_l = clampf(brk_l, 0.0, 1.0)
	_brk_r = clampf(brk_r, 0.0, 1.0)
	_braking = maxf(_brk_l, _brk_r) > BRAKE_OUT


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


## A value part way between a route's samples.
static func _between(a: PackedFloat64Array, f: float) -> float:
	var last := a.size() - 1
	if f <= 0.0:
		return a[0]
	if f >= float(last):
		return a[last]
	var k := int(f)
	return lerpf(a[k], a[k + 1], f - k)


## A control moved as a hand moves it: toward `to` no faster than `up` or `down` a second, easing in
## as it gets there, and left where it is for less than HAND_STILL (a control at rest stays at rest;
## one asked right off goes right off).
func _move(x: float, to: float, up: float, down: float) -> float:
	var d := to - x
	if absf(d) < HAND_STILL and to != 0.0:
		return x
	d = clampf(d * (1.0 - exp(-_dt / HAND_EASE)), -down * _dt, up * _dt)
	if absf(to - x - d) < 1e-4:
		return to
	return x + d


## The craft's own figures (the sim's P and its bodies, read, not changed): N of thrust a unit of
## lever, N of drag at v, N of braking a unit of brake at v. As sim/craft_sim.gd step() has them, with
## the craft's attributes and its power this step (sim.k_thrust, k_drag, k_brake: 1 for the Phaethon).
func _figures(sim, v: float) -> Vector3:
	var P: Dictionary = sim.P
	var fs: float = P.forceScale
	var line := 1.0 / pow(float(sim.line_speed()), 2.0)      # (the Aurora Line's air goes along with her)
	var cd: float = (2.0 * P.engineCd + P.podCd) * line * float(sim.k_drag)
	var thrust: float = 2.0 * P.thrustMax * float(sim.k_thrust) / P.gate * (0.45 + 0.55 * (sim.eL.health + sim.eR.health) / 2.0) * _pull * fs
	var drag := cd * v * v
	if overdrive:      # top gear: the drag is shaped toward the full lever's thrust
		var nominal: float = 2.0 * P.thrustMax * float(sim.k_thrust) * (0.87 / P.gate) * _pull
		var ref := sqrt(maxf(1.0, nominal / cd))
		drag = lerpf(drag, nominal * (1.0 - exp(-v / (0.65 * ref))), smoothstep(0.6, 0.8, v / ref))
	var flap: float = P.frontBrakeCd
	if P.frontBrakeMaxG > 0.0:
		flap = minf(flap, sim.eL.m * P.frontBrakeMaxG * G / maxf(v * v, 1.0))
	flap *= smoothstep(P.frontBrakeV0, P.frontBrakeV1, v) if P.frontBrakeCd > 0.0 else 0.0
	var brake: float = ((2.0 * (P.brakeCd + flap) + 0.5 * P.brakeCd) * v * v + 2.5 * (P.brakeLin * v + P.brakeConst)) * float(sim.k_brake)
	return Vector3(thrust, drag * fs, brake * fs)


## The frame, flown by hand: the route, the plan and the aim are pilot()'s; the levers and the brakes
## are worked as a pilot's hands work them (see the header). [thrL, thrR, brkL, brkR, handling], or []
## at the route's end.
func _hand(sim) -> Array:
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
		var dd := (rx[k] - px) * (rx[k] - px) + (ry[k] - py) * (ry[k] - py)
		if dd < bd:
			bd = dd
			bi = k
	at = bi
	var i := bi
	if i >= n - 2:
		return []   # the route's end
	# where she is along it, to a part of a sample: nothing it reads from the route steps as she crosses one
	var fi := float(i) + clampf(((px - rx[i]) * rtx[i] + (py - ry[i]) * rty[i]) / maxf(1.0, rlen[i]), -0.5, 0.5)
	var sf: float = sim.hblend      # 0 a SPEEDCRAFT, 1 a STARFIGHTER, between while she changes

	# ---- her speed ----
	var plan := _between(vplan, fi + v * float(HAND_LOOKS[0]) / sp)
	var want := minf(plan, lane_cap)
	var off := want - v
	var a := INF
	for look: float in HAND_LOOKS:
		a = minf(a, (_between(vplan, fi + v * look / sp) - v) / look)
	if lane_cap < INF:      # the traffic: see FOLLOW_SPARE
		var far: float = HAND_LOOKS[HAND_LOOKS.size() - 1]
		a = minf(a, maxf((lane_cap - v) / (float(HAND_LOOKS[0]) if lane_cap < v else far), -(FOLLOW_SPARE * lane_need + FOLLOW_EASY)))
	_pull += (clampf(pull, 0.5, 2.0) - _pull) * (1.0 - exp(-_dt / 0.5))
	var mass: float = sim.eL.m + sim.eR.m + sim.pod.m
	var now := _figures(sim, v)
	# (a STARFIGHTER flat out in a town is short of the town's speed and gaining nothing: that is holding it)
	var gaining: bool = (now.x * TOP_LEVER - now.y) / mass > 1.0
	status = "TRAFFIC" if lane_cap < plan else ("SLOWING" if v > want + 12.0 or a < -2.0 * G else ("CLIMBING" if v < want - 25.0 and gaining else "HOLDING"))
	if absf(off) < HAND_HOLD and a > -G:
		_a_trim = clampf(_a_trim + HAND_KI * off * _dt, -HAND_TRIM, HAND_TRIM)
	a = clampf(a + _a_trim, -lerpf(HAND_SLOW, HAND_STOP, smoothstep(60.0, 250.0, -off)), 40.0 * G)
	var need := mass * a + now.y                               # N of thrust it takes
	var holds := clampf(_figures(sim, want).y / now.x, 0.0, TOP_LEVER)      # the lever that holds the speed asked
	var lever := clampf(need / now.x, KEEP_SHARE * minf(KEEP, holds), TOP_LEVER)

	# ---- her line ----
	_lane_v += (_lane_w * _lane_w * (lane - _lane_now) - 2.0 * _lane_w * _lane_v) * _dt
	_lane_now += _lane_v * _dt
	if absf(lane - _lane_now) < 0.05 and absf(_lane_v) < 0.05:
		_lane_now = lane
		_lane_v = 0.0
	var fa := fi + (60.0 + v * lerpf(0.5, 0.36, sf)) / sp
	var tx := _between(rtx, fa)
	var ty := _between(rty, fa)
	var tl := maxf(1e-6, sqrt(tx * tx + ty * ty))
	var aim_x := _between(rx, fa) - ty / tl * _lane_now
	var aim_y := _between(ry, fa) + tx / tl * _lane_now
	var mx: float = (sim.eL.x + sim.eR.x) / 2.0
	var my: float = (sim.eL.y + sim.eR.y) / 2.0
	# (a SPEEDCRAFT is steered by where it is going, a STARFIGHTER by where it points, and standing either by her
	# facing: one into the other as she changes, not a jump on the frame she does)
	var course := lerp_angle(atan2(sim.pod.vy, sim.pod.vx), float(sim.pair_th), sf)
	var facing := atan2(sin(sim.eL.th) + sin(sim.eR.th), cos(sim.eL.th) + cos(sim.eR.th))
	course = lerp_angle(facing, course, smoothstep(0.75 * SLOW_V, 1.25 * SLOW_V, v))
	var err := _wrap(atan2(aim_y - my, aim_x - mx) - course)
	var k := clampf(err * lerpf(3.0, 5.0, sf), -1.0, 1.0)
	_dif = _move(_dif, STEER_FULL * k, STEER_RATE, STEER_RATE)
	# the two levers about their mean: the mean gives way to the difference (a turn is never lost to the speed;
	# the brakes take up what the higher lever adds)
	var half := absf(_dif) / 2.0
	lever = clampf(lever, half, maxf(half, TOP_LEVER - half))
	_mean = clampf(_move(_mean, lever, LEVER_UP, LEVER_DOWN), half, maxf(half, TOP_LEVER - half))

	# ---- the air brakes: what the levers, where they can go, do not give ----
	var brake := clampf((now.x * lever - need) / maxf(now.z, 1.0), 0.0, 1.0)
	if _braking:
		_braking = brake > BRAKE_OUT
	else:
		_braking = brake > BRAKE_IN
	if not _braking:
		brake = 0.0
	# (a SPEEDCRAFT's brakes cost her grip: eased off in a turn, unless she is far over her speed)
	brake *= 1.0 - 0.8 * minf(1.0, absf(k) / 0.4) * (1.0 - sf) * (1.0 - smoothstep(30.0, 60.0, -off))
	_brk_l = _move(_brk_l, maxf(brake, (k - 0.6) * 2.0 if k > 0.6 else 0.0), BRAKE_ON, BRAKE_OFF)
	_brk_r = _move(_brk_r, maxf(brake, (-k - 0.6) * 2.0 if k < -0.6 else 0.0), BRAKE_ON, BRAKE_OFF)

	# (the handling goes by what the road allows two seconds on, not by a cruise speed that happens to be a town's;
	# and once asked for it is kept till the road is well clear of the other's: slowing, the sample two seconds on
	# comes back toward her, and at a town's edge the ask went STARFIGHTER, SPEEDCRAFT, STARFIGHTER in three frames)
	var ahead := vroad[mini(n - 1, i + ceili(v * 2.0 / sp))]
	if _ask == 2:
		if rmode[i] != 0 and ahead > SWITCH_V * 1.2:
			_ask = 1
	elif rmode[i] == 0 or ahead <= SWITCH_V * 1.05:
		_ask = 2
	return [_r4(clampf(_mean - _dif / 2.0, 0.0, 1.0)), _r4(clampf(_mean + _dif / 2.0, 0.0, 1.0)), _r4(_brk_l), _r4(_brk_r), _ask]


## Traffic in its way: the vehicles ahead on its road, each [m ahead along the route, m left of the
## route's line, m/s along it]. It moves a lane over for one it is closing on (the clearest lane,
## the nearest the middle on a tie), comes back to the middle when that is clear, and where there is
## no room it slows, in time, to sit FOLLOW_GAP_S behind what is in its way.
## cars: the view's (NetworkTraffic.cars: x, y, v, hx, hy).
func _traffic(sim, cars: Array) -> void:
	lane_cap = INF
	lane_need = 0.0
	if cars.is_empty() or rx.size() < 3:
		lane = move_toward(lane, 0.0, 0.5)
		return
	var v := Vector2(sim.pod.vx, sim.pod.vy).length()
	var reach := maxf(maxf(LOOK_MIN, v * LOOK_S), log(maxf(v, FOLLOW_SLOWEST) / FOLLOW_SLOWEST) / FOLLOW_K + FOLLOW_GAP_S * FOLLOW_SLOWEST + FOLLOW_ROOM)
	# (What it slows for is looked for further than that. Sat behind a slow vehicle she settles where that
	# vehicle's speed is all she may hold, and that is the look's own edge: the vehicle went out of it and came
	# back with each mph, the whole road's speed asked for in the frames it was out.)
	var far := reach * 1.25 + 300.0
	var n := rx.size()
	var i := at
	var ox := rx[i]
	var oy := ry[i]
	var tx := rtx[i]
	var ty := rty[i]
	var here: float = (sim.pod.x - ox) * tx + (sim.pod.y - oy) * ty
	var R = sim.roads[rpath[i]]
	var half: float = R.w[clampi(ri[i], 0, int(R.N) - 1)] * 0.5
	var lane_step := LANE_STEP_HWY if half > LANE_WIDE else LANE_STEP_RAMP
	var narrow := half <= LANE_WIDE
	var hull_offset := lane
	var hull_half := 0.0
	if narrow:
		var low := INF
		var high := -INF
		for body in sim.bodies:
			var side: float = -(body.x - ox) * ty + (body.y - oy) * tx
			low = minf(low, side)
			high = maxf(high, side)
		hull_offset = (low + high) * 0.5
		hull_half = (high - low) * 0.5
	var tracking_bias := hull_offset - _lane_now if narrow else 0.0
	var extra_half_width := maxf(0.0, hull_half - sim.P.engineGap * 0.5)
	var settled := not narrow or absf(hull_offset - lane) < lane_step * 0.25
	var seen: Array = []
	for c in cars:
		var tail: float = c.train_tail if "train_tail" in c else 0.0
		if absf(c.x - ox) > far + tail or absf(c.y - oy) > far + tail:
			continue
		if tail <= 0.0:
			_see_traffic_point(seen, c, c.x, c.y, here, half, far)
			continue
		# One train occupies a continuous strip. Include its middle on a bend and score it once.
		var sections := []
		for part in 3:
			var back := 0.5 * tail * part
			_see_traffic_point(sections, c, c.x - c.hx * back, c.y - c.hy * back, here, half, far)
		if not sections.is_empty():
			var train: Array = sections[0]
			var ahead: float = train[0]
			var left: float = train[1]
			var right := left
			for part in sections:
				train[0] = minf(train[0], part[0])
				ahead = maxf(ahead, part[0])
				left = minf(left, part[1])
				right = maxf(right, part[1])
			if ahead > 0.0:
				train[0] = maxf(0.01, train[0])
			train[1] = 0.5 * (left + right)
			train[3] = 0.5 * (right - left)
			seen.append(train)
	if seen.is_empty():
		if settled:
			lane = move_toward(lane, 0.0, lane_step) if absf(lane) > 0.5 else 0.0
		return
	var edge := floorf(half * LANE_EDGE / lane_step) * lane_step
	# Coming up to a change of road (within the look) it moves no further out, only back toward the middle: the
	# two roads' lanes do not line up (a highway's are 45 m apart, a ramp's 50, on half the width), and the
	# middle, the gap between the two middle lanes, is the one line that is clear on both. (A lane picked from
	# the highway's as she came to an exit, 90 m out, was off the side of the ramp she was turning onto.) The
	# same when the lane it holds is further out than this road has room for: it has just come off a wider one.
	var turning := (rnext[i] < n - 1 and rs[rnext[i]] - rs[i] < maxf(LOOK_MIN, v * LOOK_S)) or absf(lane) > edge + 0.5
	# On narrow pavement there are 25 m from a slot to traffic's lane centre. Don't start a
	# pass if the measured tracking error on this bend has already spent the available clearance.
	turning = turning or (narrow and absf(tracking_bias) + extra_half_width + CAR_HALF >= lane_step * 0.5)
	var lanes: Array = [lane]
	for step in [1, -1, 2, -2, 3, -3]:
		var cand := clampf(roundf(lane / lane_step) * lane_step + step * lane_step, -edge, edge)
		if turning and absf(cand) >= absf(lane):
			continue
		if not lanes.has(cand):
			lanes.append(cand)
	if not lanes.has(0.0):
		lanes.append(0.0)
	var best_lane := lane
	var best_score := -INF
	var gap := INF            # the nearest it is closing on in the lane it holds: how far ahead ...
	var gap_t := INF          # ... and how many seconds off
	for cand in lanes:
		var held := is_equal_approx(float(cand), lane)
		if not held and (not settled or not _can_cross(seen, hull_offset, cand + tracking_bias, v)):
			continue
		var t := INF
		for s in seen:
			if absf(float(s[1]) - float(cand)) > CAR_HALF + float(s[3]) + (0.0 if held else 8.0) or float(s[0]) > reach:
				continue
			var closing: float = v - float(s[2])
			if not held and float(s[0]) < 60.0:
				t = 0.0       # alongside: no moving into it
			elif float(s[0]) > 0.0 and closing > 1.0:
				t = minf(t, float(s[0]) / closing)
				if held and float(s[0]) < gap:
					gap = float(s[0])
					gap_t = float(s[0]) / closing
		var score := minf(t, LOOK_FAR_S) + (LANE_GAIN if held else -LANE_FAR * absf(float(cand) - lane) / lane_step) - absf(float(cand)) * 0.002
		if score > best_score:
			best_score = score
			best_lane = cand
	_lane_t += _dt
	if gap < INF and not is_equal_approx(best_lane, lane) and (_lane_t >= LANE_COMMIT or gap_t < LANE_PRESSED):
		lane = best_lane       # a clearer lane: over, now (it takes seconds to get there)
		_lane_t = 0.0
		_lane_w = clampf(LANE_EASE * LANE_HURRY_S / maxf(gap_t, 0.1), LANE_EASE, LANE_HURRY)
		events.append("lane")
		return
	if gap_t >= LOOK_S and absf(lane) > 0.5 and _lane_t >= LANE_DWELL and settled:
		# nothing in its way: back toward the middle, a lane at a time, when that is clear too. Clear of whatever
		# it would move over for again: it used to look 3 s ahead for this and 6 s to move over, and for a vehicle
		# between the two it changed lane every frame, over and back (132 times in the 2.2 s a 300 mph vehicle
		# took to come from the one to the other at 2,400).
		var back := move_toward(lane, 0.0, lane_step)
		var clear := _can_cross(seen, hull_offset, back + tracking_bias, v)
		for s in seen:
			if absf(float(s[1]) - back) > CAR_HALF + float(s[3]) + 8.0 or float(s[0]) <= -60.0 or float(s[0]) > reach:
				continue
			if float(s[0]) < maxf(LOOK_MIN, v * 3.0) or v - float(s[2]) > 1.0:
				clear = false
		if clear:
			lane = back
			_lane_t = 0.0
			_lane_w = LANE_EASE
	# No faster than the vehicles ahead in the lane it holds allow. Every one of them, closing on it or not: it
	# was the nearest it was closing on by more than 1 m/s, and matched to a vehicle's speed that came and went
	# with each mph, the whole road's speed asked for in the frames between.
	for s in seen:
		var closing: float = v - float(s[2])
		var width := CAR_HALF + float(s[3])
		var in_way := absf(float(s[1]) - lane) <= width
		if narrow and closing > 0.0 and float(s[0]) <= closing * LOOK_S:
			# At the encounter, the hull is still travelling from its actual lateral position
			# to the slot. The tracking bias on a bend also applies once the shift settles.
			var meet := clampf(float(s[0]) / closing / LANE_COMMIT, 0.0, 1.0)
			var line := lerpf(hull_offset, lane + tracking_bias, meet)
			in_way = in_way or absf(float(s[1]) - line) <= width + extra_half_width
		if float(s[0]) > 0.0 and in_way:
			lane_cap = minf(lane_cap, _behind(float(s[0]), float(s[2])))
			if closing > 0.0:
				lane_need = maxf(lane_need, closing * closing / (2.0 * maxf(30.0, float(s[0]) - FOLLOW_GAP_S * maxf(float(s[2]), 0.0) - FOLLOW_ROOM)))


## Locate a section against the route at the section, including bends. Ignore transverse traffic on overpasses.
func _see_traffic_point(seen: Array, car, x: float, y: float, here: float, half: float, far: float) -> void:
	var i := at
	var dx := x - rx[i]
	var dy := y - ry[i]
	var cx := rtx[i]
	var cy := rty[i]
	var along := dx * cx + dy * cy - here
	if along < -40.0 or along > far:
		return
	var left := -dx * cy + dy * cx
	if along > BEND_FROM:
		var j := clampi(i + roundi((along + here) / maxf(1.0, rlen[0])), 0, rx.size() - 1)
		j = clampi(j + roundi(((x - rx[j]) * rtx[j] + (y - ry[j]) * rty[j]) / maxf(1.0, rlen[j])), 0, rx.size() - 1)
		cx = rtx[j]
		cy = rty[j]
		dx = x - rx[j]
		dy = y - ry[j]
		left = -dx * cy + dy * cx
		along = rs[j] - rs[i] + dx * cx + dy * cy - here
	var alignment: float = car.hx * cx + car.hy * cy
	if absf(left) <= half + 10.0 and absf(alignment) >= ACROSS:
		seen.append([along, left, float(car.v) * alignment, 0.0])


## The road users between two slots must clear the craft while it moves across to the new one.
## Ignore the vehicle in the original slot that motivated the pass; the existing gap test handles it.
func _can_cross(seen: Array, from: float, to: float, speed: float) -> bool:
	for other in seen:
		var left: float = other[1]
		var half: float = other[3]
		if left + half <= minf(from, to) or left - half >= maxf(from, to) or absf(left - from) + half <= CAR_HALF:
			continue
		var ahead: float = other[0]
		var after := ahead + (float(other[2]) - speed) * LANE_COMMIT
		if minf(ahead, after) <= FOLLOW_ROOM and maxf(ahead, after) >= -40.0:
			return false
	return true


## The speed it may hold `gap` m behind a vehicle doing `its` m/s along the route: no faster than
## still lets it slow to that vehicle's speed a following gap behind it.
static func _behind(gap: float, its: float) -> float:
	var room := gap - FOLLOW_GAP_S * its - FOLLOW_ROOM
	var most := maxf(its, 20.0) * exp(FOLLOW_K * maxf(0.0, room)) if gap > FOLLOW_ROOM else maxf(0.0, its - 15.0)
	# (the recorded pilot's law brakes in proportion and keeps a quarter lever on within 110 mph of its ask: asked
	# for less than it may hold, by up to that, it has the brakes full out and the levers shut while there is far to go)
	return maxf(maxf(its - 15.0, 0.0), most - minf(FOLLOW_UNDER, 0.02 * maxf(room, 0.0)))


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
	var u := pilot(sim) if like_recorded else _hand(sim)
	var strayed := rx.size() >= 3 and Vector2(rx[at] - sim.pod.x, ry[at] - sim.pod.y).length() > STRAY + absf(lane)
	if u.is_empty() or strayed:
		if not plan_to(sim, city if city >= 0 else target):
			disengage("NO ROAD THERE FROM HERE")
			return {}
		events.append("replanned")
		u = pilot(sim) if like_recorded else _hand(sim)
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
