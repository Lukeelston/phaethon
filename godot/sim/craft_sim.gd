## Phaethon flight model: twin-engine tethered podracer, top-down slice.
## Line-for-line port of web/sim-core.js; tuning keys are identical so the lab's
## "Copy tuning JSON" pastes straight into CraftSim.new(overrides).
## Scalar floats only: GDScript float is 64-bit, Vector2 is 32-bit and would
## break parity with the JS reference. Units: m, s, N. x right, y up.
class_name CraftSim
extends RefCounted

const G := 9.81
const DEFAULTS := {
	"engineMass": 1200.0, "engineLen": 8.0, "engineGap": 6.0,
	"podMass": 500.0, "podLen": 4.0, "podWidth": 2.4,
	# v3 (2026-10-17), mirrors sim-core.js: ~4,450 mph full lever, ~5,400 mph afterburner,
	# ~15 g grip cap, speed^2 fins, tow-bar pod. tools/handling_test.js measures it.
	"thrustMax": 350000.0, "burnerMult": 1.45, "ramjetMult": 1.9, "gate": 0.88,
	"engineCd": 0.07, "podCd": 0.035, "brakeCd": 0.04, "brakeLin": 0.0, "brakeConst": 60000.0,
	"engineGrip": 30.0, "podGrip": 10.0, "gripCapG": 15.0, "podCapG": 8.0, "finOffset": 0.2, "finK": 8.0,
	"yawDamp": 150000.0, "podYawDamp": 50000.0, "podAlignK": 1.0e6, "towK": 1.0e6, "towC": 40000.0,
	"cableLen": 16.0, "cableK": 600000.0, "cableC": 30000.0, "cableCouple": 0.2, "podAnchorW": 0.15,
	"binderK": 3.0e6, "binderC": 70000.0, "alignK": 2.0e7, "alignC": 6.0e5, "binderBreak": 3.0,
	"wallK": 6.0e6, "wallC": 1.5e5, "wallMu": 0.35,
	"heatThrottle": 0.15, "heatBurner": 0.12, "heatRamjet": 0.35, "coolBase": 0.05, "coolSpeed": 0.10,
	"batteryDrain": 0.08, "batteryCharge": 0.05, "repairRate": 0.12, "damagePerMs": 0.012,
	"rideH": 1.5, "hoverOmega": 9.0, "hoverZeta": 0.9,
	"binderKz": 3.0e6, "binderCz": 60000.0, "towKz": 2.0e5, "towCz": 16000.0,
	"track": "circuit", "startX": 0.0, "startY": 0.0,
	"seed": 1337,
}
# The range: 100 miles of open desert. Speed runway along y = 0, a jump lane at y = +400
# with a kicker every 1.5 km, and a twisty lane at y = -400 that only the view draws.
const RANGE_LEN := 160934.4
const JUMP_Y := 400.0
const JUMP_W := 40.0
# kickers are long and shallow, sized for 2,000-5,000 mph (launch speed = slope x speed)
const RAMP_X0 := 8000.0
const RAMP_EVERY := 4000.0
const RAMP_H := [3.0, 6.0, 10.0, 15.0]
const RAMP_SLOPE := [0.007, 0.011, 0.0157, 0.022]
# Sprint: stop dead inside a 50 m box at mile 100. Past BOX_X + OVERRUN is a DNF.
const BOX_X := RANGE_LEN
const BOX_HALF := 25.0
const OVERRUN := 15000.0
const STOPPED := 0.5
const CTRL := [[0.0, 0.0], [900.0, -100.0], [1700.0, 150.0], [2300.0, 700.0], [2400.0, 1300.0],
	[2000.0, 1700.0], [1400.0, 1600.0], [1100.0, 1150.0], [700.0, 1300.0], [300.0, 1800.0],
	[-400.0, 1700.0], [-900.0, 1100.0], [-800.0, 400.0], [-400.0, 80.0]]


class Body:
	var m: float
	var inertia: float
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var th := 0.0
	var w := 0.0
	var fx := 0.0
	var fy := 0.0
	var t := 0.0
	var hint := 0
	var contact := [false, false]
	var heat := 0.3
	var health := 1.0
	var flameout := false
	var sputter := 1.0
	var sputter_t := 0.0
	var thrust := 0.0
	var z := 0.0
	var vz := 0.0
	var grip := 1.0

	func _init(mass: float, moment: float) -> void:
		m = mass
		inertia = moment


var P: Dictionary
var eL: Body
var eR: Body
var pod: Body
var bodies: Array

# track: "circuit" (parallel arrays below) or "range" (ramps)
var kind := "circuit"
var ramps: Array = []   # [x0, len, h] per kicker
var N := 0
var track_length := 0.0
var checkpoints := 8
var tpx := PackedFloat64Array()
var tpy := PackedFloat64Array()
var ttx := PackedFloat64Array()
var tty := PackedFloat64Array()
var tnx := PackedFloat64Array()
var tny := PackedFloat64Array()
var tlen := PackedFloat64Array()
var tw := PackedFloat64Array()

# race and craft state
var battery := 1.0
var armed := false
var mode := "normal"
var binder_broken := false
var crash_t := 0.0
var time := 0.0
var lap := 0
var lap_start := -1.0   # -1 means not started (JS null)
var last_lap := -1.0
var best_lap := -1.0
var visited := {}
var checkpoint := 0
var progress_i := 0
var cables := [{"f": 0.0}, {"f": 0.0}]
var events: Array = []
var run_start := -1.0   # range run timer; -1 = not started (JS null)
var last_run := -1.0
var best_run := -1.0
var finished := false
var run_active := false
var result: Dictionary = {}   # empty = no result (JS null); else {type, t, err}
var pair_th := 0.0
var binder_stretch := 0.0

var _rng := 1
var _n_i := 0
var _n_lat := 0.0
var _n_w := 0.0
var _n_nx := 0.0
var _n_ny := 0.0
var _pvx := 0.0
var _pvy := 0.0


func _init(overrides: Dictionary = {}) -> void:
	P = DEFAULTS.duplicate()
	P.merge(overrides, true)
	_rng = int(P.seed) & 0xFFFFFFFF
	if _rng == 0:
		_rng = 1
	if P.track == "range":
		kind = "range"
		_build_range()
	else:
		_build_track()
	var e_i: float = P.engineMass * pow(P.engineLen, 2) / 12.0
	var p_i: float = P.podMass * (pow(P.podLen, 2) + pow(P.podWidth, 2)) / 12.0
	eL = Body.new(P.engineMass, e_i)
	eR = Body.new(P.engineMass, e_i)
	pod = Body.new(P.podMass, p_i)
	bodies = [eL, eR, pod]
	pod.x = float(P.startX) + 30.0   # range spawn point (respawn backs off 30 m)
	pod.y = float(P.startY)
	respawn(0)
	visited[0] = true


func _build_range() -> void:
	var i := 0
	while RAMP_X0 + RAMP_EVERY * i < RANGE_LEN - 500.0:
		var h: float = RAMP_H[i % 4]
		ramps.append([RAMP_X0 + RAMP_EVERY * i, h / RAMP_SLOPE[i % 4], h])
		i += 1
	track_length = RANGE_LEN


## Ground height under (x, y): kickers on the range's jump lane, flat everywhere else.
func ground(x: float, y: float) -> float:
	if kind != "range" or absf(y - JUMP_Y) > JUMP_W / 2.0 or x < RAMP_X0:
		return 0.0
	var idx := int(floor((x - RAMP_X0) / RAMP_EVERY))
	if idx >= ramps.size():
		return 0.0
	var r: Array = ramps[idx]
	var u: float = x - r[0]
	if u <= r[1]:
		return r[2] * u / r[1]
	if u <= r[1] + r[2]:
		return r[2] - (u - r[1])
	return 0.0


## Repulsor hover: spring-damper toward ride height, push-only, plus gravity. Exactly
## balanced on flat ground, so flat tracks are unchanged. Grip fades as a body lifts clear.
func _hover(b: Body, dt: float, az: float) -> void:
	var h := ground(b.x, b.y)
	var dhdt := (ground(b.x + b.vx * dt, b.y + b.vy * dt) - h) / dt
	var w: float = P.hoverOmega
	var up := maxf(0.0, G + w * w * (P.rideH - (b.z - h)) - 2.0 * P.hoverZeta * w * (b.vz - dhdt))
	b.vz += (up - G + az) * dt
	b.z += b.vz * dt
	if b.z - h < 0.3:
		b.z = h + 0.3
		if b.vz < dhdt:
			if dhdt - b.vz > 12.0:
				events.append({"type": "land", "v": dhdt - b.vz})
			b.vz = dhdt
	b.grip = clampf(1.0 - (b.z - h - P.rideH - 0.5) / 1.5, 0.0, 1.0)


## xorshift32, bit-identical to the JS reference.
func rand() -> float:
	var x := _rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rng = x
	return float(x) / 4294967296.0


static func wrap_angle(a: float) -> float:
	return atan2(sin(a), cos(a))


func _cr(a: float, b: float, c: float, d: float, t: float, t2: float, t3: float) -> float:
	return 0.5 * (2.0 * b + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2 + (-a + 3.0 * b - 3.0 * c + d) * t3)


func _build_track() -> void:
	var per := 48
	var n := CTRL.size()
	for i in n:
		var p0: Array = CTRL[(i - 1 + n) % n]
		var p1: Array = CTRL[i]
		var p2: Array = CTRL[(i + 1) % n]
		var p3: Array = CTRL[(i + 2) % n]
		for k in per:
			var t := float(k) / per
			var t2 := t * t
			var t3 := t2 * t
			tpx.append(_cr(p0[0], p1[0], p2[0], p3[0], t, t2, t3))
			tpy.append(_cr(p0[1], p1[1], p2[1], p3[1], t, t2, t3))
	N = tpx.size()
	# Packed arrays are value types: resize each one directly, not through a loop variable.
	ttx.resize(N)
	tty.resize(N)
	tnx.resize(N)
	tny.resize(N)
	tlen.resize(N)
	tw.resize(N)
	var s := 0.0
	for i in N:
		var j := (i + 1) % N
		var dx := tpx[j] - tpx[i]
		var dy := tpy[j] - tpy[i]
		var l := sqrt(dx * dx + dy * dy)
		ttx[i] = dx / l
		tty[i] = dy / l
		tnx[i] = -tty[i]
		tny[i] = ttx[i]
		tlen[i] = l
		s += l
		tw[i] = 82.0 + 24.0 * sin(float(i) / N * PI * 6.0 + 0.6)
	track_length = s


## Nearest centreline point in a window around hint. Results land in _n_*.
func _nearest(x: float, y: float, hint: int, win: int) -> void:
	var bd := INF
	for k in range(-win, win + 1):
		var i := posmod(hint + k, N)
		var t := clampf(((x - tpx[i]) * ttx[i] + (y - tpy[i]) * tty[i]) / tlen[i], 0.0, 1.0)
		var px := tpx[i] + ttx[i] * tlen[i] * t
		var py := tpy[i] + tty[i] * tlen[i] * t
		var d := (x - px) * (x - px) + (y - py) * (y - py)
		if d < bd:
			bd = d
			_n_i = i
			_n_lat = (x - tpx[i]) * tnx[i] + (y - tpy[i]) * tny[i]
			_n_w = tw[i]
			_n_nx = tnx[i]
			_n_ny = tny[i]


func _apply_at(b: Body, fx: float, fy: float, px: float, py: float) -> void:
	b.fx += fx
	b.fy += fy
	b.t += (px - b.x) * fy - (py - b.y) * fx


func _point_vel(b: Body, px: float, py: float) -> void:
	_pvx = b.vx - b.w * (py - b.y)
	_pvy = b.vy + b.w * (px - b.x)


## Range: back to the start line, run cleared (the Y button).
func restart() -> void:
	pod.x = 30.0
	pod.y = 0.0
	crash_t = 0.0
	finished = false
	run_active = false
	run_start = -1.0
	result = {}
	respawn()


func respawn(ci: int = -1) -> void:
	# engines placed so each cable is exactly at length: a stretched spawn makes the stiff
	# cables yank the pod forward on the first step
	var lat: float = P.engineGap / 2.0 - P.podAnchorW * P.podWidth / 2.0
	var ahead: float = sqrt(P.cableLen * P.cableLen - lat * lat) + P.podLen / 2.0 + P.engineLen / 2.0
	# Circuit: back at a checkpoint. Range: 30 m behind where the pod is, facing +x.
	var idx := 0
	var ax: float
	var ay: float
	var atx := 1.0
	var aty := 0.0
	var anx := 0.0
	var any := 1.0
	if kind == "range":
		ax = maxf(0.0, pod.x - 30.0)
		ay = pod.y
	else:
		var c := checkpoint if ci < 0 else ci
		idx = int(round(float(c) * N / checkpoints)) % N
		ax = tpx[idx]
		ay = tpy[idx]
		atx = ttx[idx]
		aty = tty[idx]
		anx = tnx[idx]
		any = tny[idx]
	var th := atan2(aty, atx)
	for pair in [[eL, 1.0], [eR, -1.0], [pod, 0.0]]:
		var b: Body = pair[0]
		var side: float = pair[1]
		var fwd := 0.0 if side == 0.0 else ahead
		b.x = ax + atx * fwd + anx * side * P.engineGap / 2.0
		b.y = ay + aty * fwd + any * side * P.engineGap / 2.0
		b.vx = 0.0
		b.vy = 0.0
		b.w = 0.0
		b.th = th
		b.hint = idx
		b.contact = [false, false]
		b.z = ground(b.x, b.y) + P.rideH
		b.vz = 0.0
		b.grip = 1.0
	for e: Body in [eL, eR]:
		e.heat = minf(e.heat, 0.5)
		e.flameout = false
		e.sputter = 1.0
		e.sputter_t = 0.0
	if pod.health <= 0.0:
		pod.health = 1.0
	binder_broken = false
	crash_t = 0.0
	progress_i = idx


func _collide_walls(b: Body, circles: Array, dt: float) -> void:
	_nearest(b.x, b.y, b.hint, 40)
	b.hint = _n_i
	for ci in circles.size():
		var cx: float = circles[ci][0]
		var cy: float = circles[ci][1]
		var r: float = circles[ci][2]
		_nearest(cx, cy, b.hint, 12)
		var pen := absf(_n_lat) + r - _n_w / 2.0
		if pen <= 0.0:
			b.contact[ci] = false
			continue
		var sgn := -1.0 if _n_lat > 0.0 else 1.0
		var nx := _n_nx * sgn
		var ny := _n_ny * sgn
		_point_vel(b, cx, cy)
		var vx := _pvx
		var vy := _pvy
		var vn := vx * nx + vy * ny
		if not b.contact[ci]:
			var dmg: float = P.damagePerMs * maxf(0.0, -vn - 6.0)
			if b == pod:
				pod.health -= dmg
			else:
				b.health = maxf(0.0, b.health - dmg)
			if dmg > 0.05:
				var who := "pod" if b == pod else ("L" if b == eL else "R")
				events.append({"type": "hit", "who": who, "dmg": dmg})
			b.contact[ci] = true
		var fn: float = P.wallK * pen - (P.wallC * vn if vn < 0.0 else 0.0)
		var tx := -ny
		var ty := nx
		var vt := vx * tx + vy * ty
		var ft: float = -signf(vt) * minf(P.wallMu * fn, absf(vt) * b.m / dt)
		_apply_at(b, fn * nx + ft * tx, fn * ny + ft * ty, cx, cy)


func _engine_circles(e: Body) -> Array:
	var c := cos(e.th)
	var s := sin(e.th)
	var o: float = P.engineLen / 2.0 - 1.2
	return [[e.x + c * o, e.y + s * o, 1.2], [e.x - c * o, e.y - s * o, 1.2]]


func _body_push(a: Body, ca: Array, b: Body, cb: Array) -> void:
	for p in ca:
		for q in cb:
			var dx: float = q[0] - p[0]
			var dy: float = q[1] - p[1]
			var d := sqrt(dx * dx + dy * dy)
			var pen: float = p[2] + q[2] - d
			if pen <= 0.0 or d < 1e-6:
				continue
			var nx := dx / d
			var ny := dy / d
			var f := 1.0e6 * pen
			_apply_at(b, f * nx, f * ny, q[0], q[1])
			_apply_at(a, -f * nx, -f * ny, p[0], p[1])


## One fixed step. input keys: thrL, thrR, brkL, brkR (0..1), repair, reignite (bool).
func step(inp: Dictionary, dt: float) -> void:
	var L := eL
	var R := eR
	var Pd := pod
	if crash_t > 0.0:
		crash_t -= dt
		if crash_t <= 0.0:
			if finished:   # back to the start line
				pod.x = 30.0
				pod.y = 0.0
				finished = false
				result = {}
			respawn()
		return
	# Vertical ties: the binder holds both engines at one height and the tow bar lifts the
	# pod toward their mean, so a one-sided ramp hit lifts the whole craft instead of
	# flinging one engine skyward. Exactly zero when heights match (flat ground).
	var az := [0.0, 0.0, 0.0]
	if not binder_broken:
		var fz: float = P.binderKz * (R.z - L.z) + P.binderCz * (R.vz - L.vz)
		az[0] += fz / L.m
		az[1] -= fz / R.m
	var ftz: float = P.towKz * ((L.z + R.z) / 2.0 - Pd.z) + P.towCz * ((L.vz + R.vz) / 2.0 - Pd.vz)
	az[2] += ftz / Pd.m
	az[0] -= ftz / 2.0 / L.m
	az[1] -= ftz / 2.0 / R.m
	for k in 3:
		var b: Body = bodies[k]
		b.fx = 0.0
		b.fy = 0.0
		b.t = 0.0
		_hover(b, dt, az[k])
	time += dt
	var repair: bool = inp.get("repair", false)
	var reignite: bool = inp.get("reignite", false)
	var in_gate: bool = inp.thrL >= P.gate and inp.thrR >= P.gate and not repair
	var ramjet := armed and in_gate
	var burner := not ramjet and in_gate and battery > 0.0
	mode = "ramjet" if ramjet else ("burner" if burner else "normal")
	if burner:
		battery = maxf(0.0, battery - P.batteryDrain * dt)
	elif not in_gate:
		battery = minf(1.0, battery + P.batteryCharge * dt)
	var speed := sqrt(Pd.vx * Pd.vx + Pd.vy * Pd.vy)

	for side in [[L, inp.thrL, inp.brkL], [R, inp.thrR, inp.brkR]]:
		var e: Body = side[0]
		var thr: float = side[1]
		var brk: float = side[2]
		var c := cos(e.th)
		var s := sin(e.th)
		var gain := 0.0
		if not e.flameout:
			gain = maxf(0.0, thr - 0.6) * P.heatThrottle + (P.heatBurner if burner else 0.0) + (P.heatRamjet if ramjet else 0.0)
		var cool: float = P.coolBase + P.coolSpeed * minf(1.5, speed / 200.0) + (0.15 if e.flameout else 0.0)
		e.heat = clampf(e.heat + (gain - cool) * dt, 0.0, 1.25)
		if e.heat >= 1.0 and not e.flameout:
			e.flameout = true
			events.append({"type": "flameout", "who": "L" if e == L else "R"})
		if e.flameout and reignite and e.heat < 0.6:
			e.flameout = false
		if repair:
			e.health = minf(1.0, e.health + P.repairRate * dt)
		e.sputter_t -= dt
		if e.sputter_t <= 0.0:
			e.sputter_t = 0.15
			e.sputter = 0.3 if rand() < (0.5 - e.health) * 1.2 else 1.0
		var lever: float = minf(thr, P.gate) / P.gate
		if repair:
			lever = minf(lever, 0.6)
		var mult: float = P.ramjetMult if ramjet else (P.burnerMult if burner else 1.0)
		var thrust: float = 0.0 if e.flameout else P.thrustMax * lever * mult * (0.45 + 0.55 * e.health) * e.sputter
		e.thrust = thrust / P.thrustMax
		e.fx += thrust * c
		e.fy += thrust * s
		# Air brake = quadratic drag plus a linear term, so the flaps still bite at low speed.
		var v := sqrt(e.vx * e.vx + e.vy * e.vy)
		# A constant term keeps the brakes biting across a 100x speed range (smoothed below 2 m/s).
		var cd: float = P.engineCd + P.brakeCd * brk
		var bl: float = P.brakeLin * brk + P.brakeConst * brk / maxf(v, 2.0)
		e.fx -= cd * v * e.vx + bl * e.vx
		e.fy -= cd * v * e.vy + bl * e.vy
		var fxp: float = e.x - c * P.finOffset
		var fyp: float = e.y - s * P.finOffset
		_point_vel(e, fxp, fyp)
		var vlat := -s * _pvx + c * _pvy
		var cap: float = e.m * P.gripCapG * G * (1.0 - 0.45 * brk)
		var flat := clampf(-e.m * P.engineGrip * vlat, -cap, cap) * e.grip
		_apply_at(e, -s * flat, c * flat, fxp, fyp)
		e.t -= P.yawDamp * e.w
		# Aero fins: restoring torque toward the direction of travel, growing with speed^2.
		if v > 1.0:
			e.t -= P.finK * v * v * sin(wrap_angle(e.th - atan2(e.vy, e.vx)))

	if not binder_broken:
		var dx := R.x - L.x
		var dy := R.y - L.y
		var d := sqrt(dx * dx + dy * dy)
		var ax := dx / d
		var ay := dy / d
		var dvx := R.vx - L.vx
		var dvy := R.vy - L.vy
		var stretch: float = d - P.engineGap
		var f: float = P.binderK * stretch + P.binderC * (dvx * ax + dvy * ay)
		R.fx -= f * ax
		R.fy -= f * ay
		L.fx += f * ax
		L.fy += f * ay
		# Forward is +90 deg from the L->R axis. Align both engines to it and feed the
		# reaction back into the pair as a force couple so angular momentum holds.
		var fwx := -ay
		var fwy := ax
		var thf := atan2(fwy, fwx)
		var wf := (ax * dvy - ay * dvx) / d
		var tq_sum := 0.0
		for e: Body in [L, R]:
			var tq: float = -P.alignK * wrap_angle(e.th - thf) - P.alignC * (e.w - wf)
			e.t += tq
			tq_sum += tq
		var sc := -tq_sum / d
		R.fx += sc * fwx
		R.fy += sc * fwy
		L.fx -= sc * fwx
		L.fy -= sc * fwy
		pair_th = thf
		binder_stretch = stretch
		if absf(stretch) > P.binderBreak:
			binder_broken = true
			events.append({"type": "binder"})
			crash_t = 1.6

	var pc := cos(Pd.th)
	var ps := sin(Pd.th)
	for k in 2:
		var e: Body = L if k == 0 else R
		var side := 1.0 if k == 0 else -1.0
		var ec := cos(e.th)
		var es := sin(e.th)
		var ex: float = e.x - ec * P.engineLen / 2.0
		var ey: float = e.y - es * P.engineLen / 2.0
		var aw: float = side * P.podAnchorW * P.podWidth / 2.0
		var px: float = Pd.x + pc * P.podLen / 2.0 - ps * aw
		var py: float = Pd.y + ps * P.podLen / 2.0 + pc * aw
		var dx := ex - px
		var dy := ey - py
		var d := sqrt(dx * dx + dy * dy)
		cables[k] = {"ex": ex, "ey": ey, "px": px, "py": py, "f": 0.0, "slack": d < P.cableLen}
		if d <= P.cableLen:
			continue
		var nx := dx / d
		var ny := dy / d
		_point_vel(e, ex, ey)
		var evx := _pvx
		var evy := _pvy
		_point_vel(Pd, px, py)
		var f: float = P.cableK * (d - P.cableLen) + P.cableC * ((evx - _pvx) * nx + (evy - _pvy) * ny)
		if f <= 0.0:
			continue
		cables[k].f = f
		_apply_at(Pd, f * nx, f * ny, px, py)
		# Bridle: most tension reaches the pair through the binder so pod sway
		# yanks the craft without steering it (see spec section 3).
		var own: float = P.cableCouple + (1.0 - P.cableCouple) / 2.0
		var other: Body = R if k == 0 else L
		e.fx -= f * nx * own
		e.fy -= f * ny * own
		other.fx -= f * nx * (1.0 - own)
		other.fy -= f * ny * (1.0 - own)

	var pb := minf(inp.brkL, inp.brkR)
	var pv := sqrt(Pd.vx * Pd.vx + Pd.vy * Pd.vy)
	var pcd: float = P.podCd + 0.5 * P.brakeCd * pb
	var pbl: float = 0.5 * (P.brakeLin * pb + P.brakeConst * pb / maxf(pv, 2.0))
	Pd.fx -= pcd * pv * Pd.vx + pbl * Pd.vx
	Pd.fy -= pcd * pv * Pd.vy + pbl * Pd.vy
	var qx := Pd.x - pc * 1.2
	var qy := Pd.y - ps * 1.2
	_point_vel(Pd, qx, qy)
	var pcap: float = Pd.m * P.podCapG * G
	var plat := clampf(-Pd.m * P.podGrip * (-ps * _pvx + pc * _pvy), -pcap, pcap) * Pd.grip
	_apply_at(Pd, -ps * plat, pc * plat, qx, qy)
	# Tow bar: hold the pod on the engines' centreline (lateral spring-damper toward the
	# point straight behind the pair) and align its heading to theirs; reaction to the engines.
	if not binder_broken:
		var pf := cos(pair_th)
		var ps2 := sin(pair_th)
		var lx := -ps2
		var ly := pf
		var back: float = P.engineLen / 2.0 + P.cableLen + P.podLen / 2.0
		var mxp := (L.x + R.x) / 2.0
		var myp := (L.y + R.y) / 2.0
		var wpair := (L.w + R.w) / 2.0
		var tx := mxp - pf * back
		var ty := myp - ps2 * back
		var tvx := (L.vx + R.vx) / 2.0 + wpair * ps2 * back
		var tvy := (L.vy + R.vy) / 2.0 - wpair * pf * back
		var te := (Pd.x - tx) * lx + (Pd.y - ty) * ly
		var tev := (Pd.vx - tvx) * lx + (Pd.vy - tvy) * ly
		var ft: float = -P.towK * te - P.towC * tev
		Pd.fx += ft * lx
		Pd.fy += ft * ly
		L.fx -= ft * lx / 2.0
		L.fy -= ft * ly / 2.0
		R.fx -= ft * lx / 2.0
		R.fy -= ft * ly / 2.0
		Pd.t -= P.podAlignK * wrap_angle(Pd.th - pair_th) + P.podYawDamp * (Pd.w - wpair)

	var cl := _engine_circles(L)
	var cr := _engine_circles(R)
	var cp := [[Pd.x, Pd.y, 1.6]]
	if kind == "circuit":
		_collide_walls(L, cl, dt)
		_collide_walls(R, cr, dt)
		_collide_walls(Pd, cp, dt)
	_body_push(L, cl, Pd, cp)
	_body_push(R, cr, Pd, cp)
	_body_push(L, cl, R, cr)

	for b: Body in bodies:
		b.vx += b.fx / b.m * dt
		b.vy += b.fy / b.m * dt
		b.w += b.t / b.inertia * dt
		b.w *= 1.0 - 0.5 * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.th += b.w * dt
	if Pd.health <= 0.0 and crash_t <= 0.0:
		events.append({"type": "wreck"})
		crash_t = 1.6
		Pd.health = 0.0

	if kind == "range":
		# Sprint: the clock starts on the first lever input and stops when the pod sits still
		# inside the box. Overrunning by OVERRUN, or crashing mid-run, is a DNF back to the start.
		if not run_active and result.is_empty() and inp.thrL + inp.thrR > 0.02:
			run_active = true
			run_start = time
		if run_active:
			var in_box := absf(Pd.x - BOX_X) <= BOX_HALF and absf(Pd.y) <= BOX_HALF
			var end := {}
			if in_box and pv < STOPPED:
				var t := time - run_start
				end = {"type": "finish", "t": t, "err": sqrt((Pd.x - BOX_X) * (Pd.x - BOX_X) + Pd.y * Pd.y)}
				last_run = t
				best_run = t if best_run < 0.0 else minf(best_run, t)
			elif Pd.x > BOX_X + OVERRUN:
				end = {"type": "overrun"}
			elif crash_t > 0.0:
				end = {"type": "crash"}
			if not end.is_empty():
				run_active = false
				result = end
				events.append(end)
				if end.type != "finish":
					finished = true
					crash_t = maxf(crash_t, 1.6)
		return
	if kind != "circuit":
		return
	# Laps: count when the pod wraps past the start having visited every checkpoint.
	var prev := progress_i
	var cur := Pd.hint
	var cps := checkpoints
	var cpi := int(floor(float(cur) * cps / N))
	if cpi != checkpoint and posmod(cpi - checkpoint + cps, cps) == 1:
		checkpoint = cpi
		visited[cpi] = true
	if lap_start < 0.0 and pv > 2.0:
		lap_start = time
	if prev > N * 0.9 and cur < N * 0.1 and visited.size() >= cps - 1 and lap_start >= 0.0:
		last_lap = time - lap_start
		best_lap = last_lap if best_lap < 0.0 else minf(best_lap, last_lap)
		lap += 1
		lap_start = time
		visited = {0: true}
		events.append({"type": "lap", "t": last_lap})
	progress_i = cur
