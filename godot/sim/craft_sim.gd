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
	# front speed brakes (Luke: "front speed brake flaps for braking done at high speed"): flaps ahead
	# of the intakes open with the air brakes from 1,500 to 2,500 mph, adding 0.05 to the drag coefficient
	"frontBrakeCd": 0.05, "frontBrakeV0": 670.6, "frontBrakeV1": 1117.6,
	"engineGrip": 30.0, "podGrip": 10.0, "gripCapG": 15.0, "podCapG": 8.0, "finOffset": 0.2, "finK": 8.0,
	"yawDamp": 150000.0, "podYawDamp": 50000.0, "podAlignK": 1.0e6, "towK": 1.0e6, "towC": 40000.0,
	"cableLen": 16.0, "cableK": 600000.0, "cableC": 30000.0, "cableCouple": 0.2, "podAnchorW": 0.15,
	"binderK": 3.0e6, "binderC": 70000.0, "alignK": 2.0e7, "alignC": 6.0e5, "binderBreak": 3.0,
	"wallK": 6.0e6, "wallC": 1.5e5, "wallMu": 0.35, "wallDmgMin": 6.0,
	"damage": false,   # wall hits cost health (and can wreck you) only when this is on
	"towLongK": 2.0e6, "towLongC": 8.0e4, "towLongSlack": 0.3,   # pod stand-off: never closer to the engines than its taut-cable spot
	"bank": 1.0, "bankDown": 3.9e-4,   # banked corners: downforce per (m/s)^2, as g, presses you into the bank (~8 g at 1,000 mph)
	"towAudit": true, "towAuditG": 3.0,   # tow-bar energy audit: drag on the speed, never harder than this (g) ...
	"towIntF0": 0.05, "towIntF1": 0.3, "towIntMax": 60.0,   # ... shifting onto the swing and spin as their share of the energy grows
	"heatThrottle": 0.15, "heatBurner": 0.12, "heatRamjet": 0.35, "coolBase": 0.05, "coolSpeed": 0.10,
	"batteryDrain": 0.08, "batteryCharge": 0.05, "repairRate": 0.12, "damagePerMs": 0.012,
	"limits": false,   # battery and heat: off (Luke: "turn off battery and heat, let it be crazy"): the burner never runs dry, engines never heat up
	"rideH": 1.5, "hoverOmega": 9.0, "hoverZeta": 0.9,
	"binderKz": 3.0e6, "binderCz": 60000.0, "towKz": 2.0e5, "towCz": 16000.0,
	"track": "circuit", "startX": 0.0, "startY": 0.0, "handling": "speed",
	"sfEngageV": 558.8, "modeBlendT": 1.0,   # live switch: STARFIGHTER engages below 1,250 mph; the handling blends over 1 s
	"seed": 1337,
}
# Handling modes, mirroring sim-core.js: named overrides on top of DEFAULTS (explicit
# overrides still win). speed = the v3 sprint model; starfighter = ~990 mph lever / 1,200
# burner, 50 g grip, ~56 deg/s at 320 mph, stiff tow bar.
# Track settings, mirroring sim-core.js TRACKS: the GP's walls deflect rather than wreck (only
# impacts harder than 25 m/s into the wall do damage, a third as much; lower friction).
const TRACKS := {
	"gp": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
	"eridanus": {"wallDmgMin": 25.0, "damagePerMs": 0.004, "wallMu": 0.22},
}
const HANDLING := {
	"speed": {},
	"starfighter": {
		"thrustMax": 180000.0, "engineCd": 0.725, "podCd": 0.3625,
		"gripCapG": 50.0, "engineGrip": 90.0, "podGrip": 30.0, "podCapG": 30.0, "finK": 3.0, "yawDamp": 20000.0,
		"podAlignK": 6.0e6, "podYawDamp": 250000.0, "towK": 5.0e6, "towC": 200000.0,
	},
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


# The grand prix, mirroring sim-core.js: a 29.3 km circuit for STARFIGHTER at ~1,000 mph,
# straights and exact arcs (tools/design_gp.py closed it), sampled every ~12 m, 64 m wide.
const GP_SEGS := [["S", 2798.158], ["R", 230.0, 90.0], ["S", 450.0], ["L", 230.0, 90.0], ["S", 1500.0], ["L", 1100.0, 70.0],
	["S", 700.0], ["R", 600.0, 40.0], ["S", 900.0], ["L", 380.0, 150.0], ["S", 1100.0], ["R", 260.0, 120.0],
	["S", 700.0], ["L", 900.0, 30.0], ["S", 1278.727], ["L", 500.0, 90.0], ["S", 5200.0], ["R", 420.0, 40.0],
	["L", 420.0, 80.0], ["R", 420.0, 40.0], ["S", 1400.0], ["L", 160.0, 180.0], ["S", 500.0], ["R", 350.0, 90.0],
	["S", 3200.0], ["L", 1300.0, 90.0]]
const GP_STEP := 12.0
const GP_WIDTH := 96.0   # wider, and every corner banked GP_BANK degrees toward its inside (Luke, 2026-10-18),
const GP_BANK := 15.0    # easing in and out over ~360 m: two passes of a (2 * GP_BANK_R + 1)-sample box (was 30: "50% smaller")
const GP_BANK_R := 7
# Eridanus, mirroring sim-core.js: the dual-purpose course (tools/design_eridanus.py), 199 km. Each
# segment names its mode: "sf" (the towns, STARFIGHTER's) 140 m wide, corners banked 10 deg; "sp"
# (the speed loop, SPEEDCRAFT's) 400 m wide, sweepers banked 3 deg (Luke: "much wider", "bank the
# speedcraft corners just slightly to help with sight"); widths ease over ~1 km between, banks over
# ~1 km in the towns and ~5 km on the loop ("quick elevation changes ... too intense").
const ERI_SEGS := [["S", 3390.539, 0.0, "sf"], ["L", 450.0, 90.0, "sf"], ["S", 900.0, 0.0, "sf"], 
	["R", 300.0, 90.0, "sf"], ["S", 700.0, 0.0, "sf"], ["L", 600.0, 60.0, "sf"], ["R", 600.0, 60.0, "sf"], 
	["S", 1500.0, 0.0, "sf"], ["S", 9000.0, 0.0, "sp"], ["L", 30000.0, 8.0, "sp"], ["R", 30000.0, 8.0, "sp"], 
	["S", 8000.0, 0.0, "sp"], ["L", 22000.0, 90.0, "sp"], ["S", 11000.0, 0.0, "sp"], ["L", 500.0, 50.0, "sf"], 
	["S", 600.0, 0.0, "sf"], ["R", 320.0, 70.0, "sf"], ["S", 500.0, 0.0, "sf"], ["L", 400.0, 80.0, "sf"], 
	["S", 1500.0, 0.0, "sf"], ["S", 4000.0, 0.0, "sp"], ["R", 15000.0, 30.0, "sp"], ["S", 1000.0, 0.0, "sp"], 
	["L", 15000.0, 30.0, "sp"], ["S", 3000.0, 0.0, "sp"], ["L", 20000.0, 30.0, "sp"], ["S", 13100.0, 0.0, "sp"], 
	["L", 16000.0, 90.0, "sp"], ["S", 36152.417, 0.0, "sp"], ["L", 700.0, 60.0, "sf"], ["S", 900.0, 0.0, "sf"], 
	["R", 350.0, 80.0, "sf"], ["S", 800.0, 0.0, "sf"], ["L", 300.0, 100.0, "sf"], ["S", 1000.0, 0.0, "sf"], 
	["R", 500.0, 50.0, "sf"], ["S", 1200.0, 0.0, "sf"], ["L", 900.0, 60.0, "sf"]]
# The courses: widths per mode (else GP_WIDTH, constant); width_r: the width-easing box (samples);
# banks: per mode, degrees (else GP_BANK in the corners), each eased by two passes of its own box,
# bank_r (samples; else GP_BANK_R).
const COURSES := {
	"gp": {"segs": GP_SEGS, "checkpoints": 12},
	"eridanus": {"segs": ERI_SEGS, "checkpoints": 24, "widths": {"sf": 140.0, "sp": 400.0}, "width_r": 40,
		"banks": {"sf": 10.0, "sp": 3.0}, "bank_r": {"sf": 20, "sp": 100}},
}
var track_name := ""   # the course's name ("gp", "eridanus") on a course
var course := false    # on a course (COURSES): banked corners push
var tmode := PackedByteArray()   # courses: per sample, 0 a STARFIGHTER ("sf") section, 1 SPEEDCRAFT ("sp")


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
	var front := 0.0   # the front speed brakes' deployment, 0..1 (the view's flaps)
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
var tb := PackedFloat64Array()   # GP: bank per sample, radians (+ = tilted down to the left, a left-hander)

# race and craft state
var battery := 1.0
var armed := false
var mode := "normal"
# Live handling switch, mirroring sim-core.js: inp.handling asks for "speed" or "starfighter";
# STARFIGHTER only engages below P.sfEngageV, then the handling keys blend over P.modeBlendT s.
var hwant := "speed"
var hblend := 0.0
var _hk: Array = []      # the handling keys that blend (not given explicitly in the overrides)
var _h0 := {}
var _h1 := {}
var binder_broken := false
var _tow_u := -1.0          # tow bar's stored energy last substep (-1 = none yet), for the energy audit
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
var _n_t := 0.0   # how far along sample _n_i's segment the nearest point lies, 0..1
var _pvx := 0.0
var _pvy := 0.0


var _overrides := {}


func _init(overrides: Dictionary = {}) -> void:
	_overrides = overrides.duplicate()
	P = DEFAULTS.duplicate()
	# the grand prix is a STARFIGHTER track unless a handling is asked for
	var hname: String = overrides.get("handling", "starfighter" if COURSES.has(overrides.get("track", "")) else DEFAULTS.handling)
	P.merge(HANDLING.get(hname, {}), true)
	P.merge(TRACKS.get(overrides.get("track", ""), {}), true)
	P.merge(overrides, true)
	P.handling = hname
	hwant = hname
	hblend = 1.0 if hname == "starfighter" else 0.0
	for k in HANDLING.starfighter:
		if not overrides.has(k):
			_hk.append(k)
			_h0[k] = HANDLING.speed.get(k, DEFAULTS[k])
			_h1[k] = HANDLING.starfighter[k]
	_rng = int(P.seed) & 0xFFFFFFFF
	if _rng == 0:
		_rng = 1
	if P.track == "range":
		kind = "range"
		_build_range()
	elif COURSES.has(P.track):
		_build_course(P.track)
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


## Switch handling mode in place (Godot only: the game's in-cockpit toggle; not part of the
## JS parity surface). Presets only change per-step tuning, never masses or the track, so
## nothing built in _init goes stale. Restart or respawn afterwards.
func set_handling(name: String) -> void:
	_overrides["handling"] = name
	P = DEFAULTS.duplicate()
	P.merge(HANDLING.get(name, {}), true)
	P.merge(TRACKS.get(_overrides.get("track", ""), {}), true)
	P.merge(_overrides, true)
	hwant = name
	hblend = 1.0 if name == "starfighter" else 0.0


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


func _build_course(name: String) -> void:
	track_name = name
	course = true
	var C: Dictionary = COURSES[name]
	checkpoints = C.checkpoints
	var x := 0.0
	var y := 0.0
	var h := 0.0
	var raw := PackedFloat64Array()
	var wraw := PackedFloat64Array()
	for sg in C.segs:
		var m: String = sg[3] if sg.size() > 3 else "sf"
		var w: float = C.widths[m] if C.has("widths") else GP_WIDTH
		if sg[0] == "S":
			var n := maxi(1, int(ceil(sg[1] / GP_STEP)))
			var d: float = sg[1] / n
			for k in n:
				tpx.append(x)
				tpy.append(y)
				raw.append(0.0)
				wraw.append(w)
				tmode.append(0 if m == "sf" else 1)
				x += d * cos(h)
				y += d * sin(h)
		else:
			var r: float = sg[1]
			var sn := 1.0 if sg[0] == "L" else -1.0
			var ang: float = sg[2] * PI / 180.0
			var n := maxi(1, int(ceil(r * ang / GP_STEP)))
			var da := ang / n
			var c := 2.0 * r * sin(da / 2.0)
			for k in n:
				tpx.append(x)
				tpy.append(y)
				var bdeg: float = C.banks[m] if C.has("banks") else (GP_BANK if m == "sf" else 0.0)
				raw.append(sn * bdeg * PI / 180.0)
				wraw.append(w)
				tmode.append(0 if m == "sf" else 1)
				x += c * cos(h + sn * da / 2.0)
				y += c * sin(h + sn * da / 2.0)
				h += sn * da
	N = tpx.size()
	ttx.resize(N)
	tty.resize(N)
	tnx.resize(N)
	tny.resize(N)
	tlen.resize(N)
	tw.resize(N)
	var width: PackedFloat64Array = _smooth_box(wraw, C.width_r) if C.has("widths") else wraw
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
		tw[i] = width[i]
	track_length = s
	if C.has("bank_r"):
		tb = PackedFloat64Array()
		tb.resize(N)
		for m in ["sf", "sp"]:
			var part := PackedFloat64Array()
			part.resize(N)
			for i in N:
				part[i] = raw[i] if tmode[i] == (0 if m == "sf" else 1) else 0.0
			var r: int = C.bank_r[m]
			var sm := _smooth_run(_smooth_run(part, r), r)
			for i in N:
				tb[i] += sm[i]
	else:
		tb = _smooth_bank(_smooth_bank(raw))


## A centred moving average round the closed loop (box of 2 * r + 1 samples; banks: GP_BANK_R).
static func _smooth_box(a: PackedFloat64Array, r: int) -> PackedFloat64Array:
	var n := a.size()
	var out := PackedFloat64Array()
	out.resize(n)
	for i in n:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += a[posmod(i + k, n)]
		out[i] = acc / (2 * r + 1)
	return out


static func _smooth_bank(a: PackedFloat64Array) -> PackedFloat64Array:
	return _smooth_box(a, GP_BANK_R)


## The same average as a running sum: O(N) for the wide boxes (a 5 km bank ramp is 400 samples).
static func _smooth_run(a: PackedFloat64Array, r: int) -> PackedFloat64Array:
	var n := a.size()
	var w := 2 * r + 1
	var out := PackedFloat64Array()
	out.resize(n)
	var acc := 0.0
	for k in range(-r, r + 1):
		acc += a[posmod(k, n)]
	for i in n:
		out[i] = acc / w
		acc += a[posmod(i + r + 1, n)] - a[posmod(i - r, n)]
	return out


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
			_n_t = t


func _apply_at(b: Body, fx: float, fy: float, px: float, py: float) -> void:
	b.fx += fx
	b.fy += fy
	b.t += (px - b.x) * fy - (py - b.y) * fx


func _point_vel(b: Body, px: float, py: float) -> void:
	_pvx = b.vx - b.w * (py - b.y)
	_pvy = b.vy + b.w * (px - b.x)


## For the view (not the physics): the banked GP's surface at (x, y), near sample `hint`:
## Vector2(height above the desert, bank radians + = tilted down to the left). Corners pivot on
## their inside edge, so it stays at ground level and the outside climbs (96 m at 30 deg: 55 m);
## past the outside wall a 45-degree berm runs back down. (0, 0) everywhere else.
func surface_at(x: float, y: float, hint: int) -> Vector2:
	if tb.is_empty():
		return Vector2.ZERO
	_nearest(x, y, hint, 40)
	var bk: float = lerpf(tb[_n_i], tb[(_n_i + 1) % N], _n_t)
	return Vector2(bank_height(_n_w / 2.0, _n_lat, bk), bk)


## Height of the banked surface `off` metres left of the centreline, half-width hw, bank bk.
static func bank_height(hw: float, off: float, bk: float) -> float:
	var t := tan(bk)
	var base := hw * absf(t) - clampf(off, -hw, hw) * t
	return maxf(0.0, base - maxf(0.0, absf(off) - hw))   # the berm outside: down at 45 deg


## Range: back to the start line, run cleared (the Y button).
## A fresh start (the player's restart), mirroring sim-core.js: whole engines and pod, full
## battery, cool engines; the range goes back to its start line, a circuit to its grid with the
## lap count reset. Crashes still respawn through respawn(), keeping the damage.
func restart() -> void:
	crash_t = 0.0
	finished = false
	run_active = false
	run_start = -1.0
	result = {}
	for e in [eL, eR]:
		e.health = 1.0
		e.heat = 0.3 if P.limits else 0.0
	pod.health = 1.0
	battery = 1.0
	if kind == "range":
		pod.x = 30.0
		pod.y = 0.0
		respawn()
	else:
		lap = 0
		lap_start = -1.0
		visited = {0: true}
		checkpoint = 0
		respawn(0)


func respawn(ci: int = -1, at_idx: int = -1) -> void:   # at_idx: a debug start at that track sample (views only)
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
		if at_idx >= 0:
			idx = at_idx % N
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
		e.heat = minf(e.heat, 0.5) if P.limits else 0.0
		e.flameout = false
		e.sputter = 1.0
		e.sputter_t = 0.0
	if pod.health <= 0.0:
		pod.health = 1.0
	binder_broken = false
	_tow_u = -1.0
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
			var dmg: float = P.damagePerMs * maxf(0.0, -vn - P.wallDmgMin)
			if P.damage:   # off by default (Luke): a hit still registers (and buzzes), it just costs nothing
				if b == pod:
					pod.health -= dmg
				else:
					b.health = maxf(0.0, b.health - dmg)
			var who := "pod" if b == pod else ("L" if b == eL else "R")
			if dmg > 0.05:
				events.append({"type": "hit", "who": who, "dmg": dmg})
			else:
				events.append({"type": "scrape", "who": who})   # contact without (much) damage
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
	var hask: String = inp.get("handling", "")
	if hask == "speed" or hask == "starfighter":
		hwant = hask
	var htgt := 0.0
	if hwant == "starfighter":
		htgt = 1.0 if hblend > 0.0 or sqrt(pod.vx * pod.vx + pod.vy * pod.vy) <= P.sfEngageV else 0.0
	if hblend != htgt:
		hblend = minf(htgt, hblend + dt / P.modeBlendT) if htgt > hblend else maxf(htgt, hblend - dt / P.modeBlendT)
		for k in _hk:
			P[k] = _h1[k] if hblend == 1.0 else (_h0[k] if hblend == 0.0 else _h0[k] + (_h1[k] - _h0[k]) * hblend)
		P.handling = "starfighter" if hblend >= 0.5 else "speed"
		if hblend == htgt:
			events.append({"type": "handling", "mode": P.handling})
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
	if burner and P.limits:
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
		if not e.flameout and P.limits:
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
		e.front = brk * smoothstep(P.frontBrakeV0, P.frontBrakeV1, v) if P.frontBrakeCd > 0.0 else 0.0
		var cd: float = P.engineCd + P.brakeCd * brk + P.frontBrakeCd * e.front
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
		# Stand-off: the pod never closes on the engines past its taut-cable spot. Brake hard (or
		# spin the pair) and the cables go slack: without this the pod flew on into the engines
		# and knocked them about (Luke: "the pod flies forward and throws the engines off
		# balance"). Compression only (the cables already pull), along the pair's axis through
		# its centre, equal and opposite on the engines: it can't twist them or make energy.
		# (its spot: where the diagonal cables are just taut, as respawn() lays them out, plus a
		# little slack, so it only ever meets a real overrun and never fights the cables)
		var lat_c: float = P.engineGap / 2.0 - P.podAnchorW * P.podWidth / 2.0
		var rest: float = sqrt(P.cableLen * P.cableLen - lat_c * lat_c) + P.podLen / 2.0 + P.engineLen / 2.0
		var el: float = (Pd.x - tx) * pf + (Pd.y - ty) * ps2 - (back - rest) - P.towLongSlack
		if el > 0.0 and P.towLongK > 0.0:
			var elv := (Pd.vx - (L.vx + R.vx) / 2.0) * pf + (Pd.vy - (L.vy + R.vy) / 2.0) * ps2
			var fl: float = minf(0.0, -P.towLongK * el - P.towLongC * elv)
			Pd.fx += fl * pf
			Pd.fy += fl * ps2
			L.fx -= fl * pf / 2.0
			L.fy -= fl * ps2 / 2.0
			R.fx -= fl * pf / 2.0
			R.fy -= fl * ps2 / 2.0
		var pod_tw: float = P.podAlignK * wrap_angle(Pd.th - pair_th) + P.podYawDamp * (Pd.w - wpair)
		Pd.t -= pod_tw
		# Energy audit. The tow bar is one-way on purpose (the pod follows the engines without
		# yawing them back: that trailer feedback made the pair sway), so its pull and the pod's
		# twist have no equal and opposite, and that let it create energy: the pod whirled round a
		# pivoting pair, or swung by a spinning one after wall hits, gained speed from nothing and
		# the craft pinballed (pod 159 -> 495 km/h coasting with no thrust). So each substep,
		# whatever power these forces put in beyond what their springs gave up is taken back out.
		# Normal flight is untouched (yaw response, coast-down and the GP lap identical), and it
		# can never add energy (tests/test_energy.gd).
		if P.towAudit:
			var mvx := (L.vx + R.vx) / 2.0
			var mvy := (L.vy + R.vy) / 2.0
			var p_in: float = ft * ((Pd.vx - mvx) * lx + (Pd.vy - mvy) * ly) - pod_tw * Pd.w
			var dth := wrap_angle(Pd.th - pair_th)
			var u: float = 0.5 * P.towK * te * te + 0.5 * P.podAlignK * dth * dth
			if _tow_u >= 0.0:
				var created: float = p_in + (u - _tow_u) / dt
				if created > 0.0:
					# Where it comes out depends on where the craft's energy is. Travelling (nearly
					# all of it is speed down the track), it comes out of the speed, gently (never
					# past towAuditG); taking it out of the swing there would deaden the steering,
					# since every yaw step swings the pod. Whirling (much of it is swing and spin
					# about the centre of mass: the pod whirled round a pivoting pair, or pinballing
					# off walls), it comes out of the swing and spin, where it was made.
					var msum: float = Pd.m + L.m + R.m
					var cvx: float = (Pd.m * Pd.vx + L.m * L.vx + R.m * R.vx) / msum
					var cvy: float = (Pd.m * Pd.vy + L.m * L.vy + R.m * R.vy) / msum
					var ke := 0.0    # speed
					var rot := 0.0   # spin
					var kin := 0.0   # swing and spin about the centre of mass
					for b: Body in [Pd, L, R]:
						ke += 0.5 * b.m * (b.vx * b.vx + b.vy * b.vy)
						rot += 0.5 * b.inertia * b.w * b.w
						kin += 0.5 * b.m * ((b.vx - cvx) * (b.vx - cvx) + (b.vy - cvy) * (b.vy - cvy))
					kin += rot
					var c_int: float = created * smoothstep(P.towIntF0, P.towIntF1, kin / maxf(ke + rot, 1.0))
					var c_lin: float = created - c_int
					if c_int > 0.0 and kin > 1.0:
						var gi: float = minf(c_int / (2.0 * kin), P.towIntMax)
						for b: Body in [Pd, L, R]:
							b.fx -= gi * b.m * (b.vx - cvx)
							b.fy -= gi * b.m * (b.vy - cvy)
							b.t -= gi * b.inertia * b.w
					if c_lin > 0.0 and ke > 1.0:
						var vrms: float = sqrt(2.0 * ke / msum)
						var gam: float = minf(c_lin / (2.0 * ke), P.towAuditG * G / maxf(vrms, 1.0))
						for b: Body in [Pd, L, R]:
							b.fx -= gam * b.m * b.vx
							b.fy -= gam * b.m * b.vy
			_tow_u = u

	# Banked corners: the surface tilts toward the inside, so its push has a part toward the
	# corner's centre: gravity's (g tan bank) plus downforce's (bankDown v^2 sin bank).
	if course:
		for b: Body in bodies:
			var bk: float = tb[b.hint]
			if bk == 0.0:
				continue
			var v2 := b.vx * b.vx + b.vy * b.vy
			var fb: float = P.bank * b.m * (G * tan(bk) + P.bankDown * v2 * sin(bk)) * b.grip
			b.fx += fb * tnx[b.hint]
			b.fy += fb * tny[b.hint]
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
