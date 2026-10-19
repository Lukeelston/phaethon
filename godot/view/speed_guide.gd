## The speed guide (Luke: "turn the stopping reference point into a series of variable lights that
## tell you how close you're gonna cut it. Green lights if approaching corner at safe speed, red if
## you're gonna blow past. A similar design could follow the rest of the lights on the track. A
## 'proximity sensor' to the line of least wrecks").
##   the line    a safe speed at every track sample: the limits the autopilot plans its clean lap to
##               (tools/record_course.js: each mode's turn-rate and grip, STARFIGHTER's top speed,
##               1,200 mph in the towns so STARFIGHTER can engage)
##   the brakes  full braking as a(v) = c0 + c2 v^2, from the sim's own drag for the live handling:
##               both engines' and the pod's drag with the air brakes in, the brakes' constant pull,
##               and the front speed brakes opening from 1,500 to 2,500 mph; below 1,250 mph on
##               STARFIGHTER's (you flip as you slow into a town: its drag is 10x, and it's what
##               the autopilot's clean lap leans on)
##   the cut     for a point ahead, the share of full braking it takes to be down to its safe speed
##               by the time you get there: under AMBER_AT green, up to RED_AT amber (brake now),
##               past RED_AT red (full brakes won't make it)
## The braking boards show the cut for the next town; every beacon and light column shows its own
## (view/guide.gdshaderinc does the same sums on the GPU from the uniforms `apply` sets).
##   var g := SpeedGuide.new(); g.setup(sim)     once
##   g.apply(material)                           every frame, for each guide-lit material
extends RefCounted

const G := 9.81
const MPH := 2.236936
const SF_OMEGA := 0.95           # the autopilot's plan (tools/record_course.js), a little inside each mode's limits
const SF_ALAT := 38.0 * G
const SF_TOP := 1150.0 / MPH
const SP_ALAT := 10.0 * G
const SP_TOP := 4300.0 / MPH
const TOWN_V := 1200.0 / MPH     # into a town: STARFIGHTER engages below 1,250 mph
const AMBER_AT := 0.6
const RED_AT := 1.0
const REACH := 30000.0           # lights further ahead than this (m) stay neutral
const HEADROOM := 1.05           # the safe speeds sit inside the true limits (the autopilot's 38 g of
                                 # STARFIGHTER's 50): a hair over one isn't a wreck ...
const NEAR := 100.0              # ... and nor is being on it: the cut counts at least this far (m)
const TOWN_LOOK := 3000.0        # a town's cut: the worst over its first 3 km

var sim
var s := PackedFloat64Array()     # distance along the lap at each sample (s[N]: the lap)
var vlim := PackedFloat32Array()  # the safe speed at each sample, m/s
var mouths := PackedInt32Array()  # each town's first sample


func setup(sm) -> void:
	sim = sm
	var n: int = sim.N
	s.resize(n + 1)
	var acc := 0.0
	for i in n:
		s[i] = acc
		acc += sim.tlen[i]
	s[n] = acc
	var kap := PackedFloat64Array()
	kap.resize(n)
	for i in n:
		var j := (i + 1) % n
		kap[i] = absf(wrapf(atan2(sim.tty[j], sim.ttx[j]) - atan2(sim.tty[i], sim.ttx[i]), -PI, PI)) / sim.tlen[i]
	vlim.resize(n)
	for i in n:
		var k := 0.0
		for d in range(-4, 5):
			k = maxf(k, kap[posmod(i + d, n)])
		var town := mode_at(i) == 0
		var v := 0.0
		if town:
			v = SF_TOP if k < 1e-6 else minf(SF_TOP, minf(SF_OMEGA / k, sqrt(SF_ALAT / k)))
			if sim.tmode.size() == n:   # a course: into a town below STARFIGHTER's engage speed
				v = minf(v, TOWN_V)
		else:
			v = SP_TOP if k < 1e-7 else minf(SP_TOP, sqrt(SP_ALAT / k))
		vlim[i] = v
		if sim.tmode.size() == n and town and mode_at(posmod(i - 1, n)) == 1:
			mouths.append(i)


func mode_at(i: int) -> int:
	return sim.tmode[i] if i < sim.tmode.size() else 0


## Full braking's c2 (per m) with the front flaps shut, half open and full; and c0 (m/s^2):
## Vector4(c0, c2 shut, c2 half, c2 full) for the sim's live handling (or `handling`'s preset).
func brake_model(handling := "") -> Vector4:
	var P: Dictionary = sim.P
	if handling != "":
		P = P.duplicate()
		P.merge(sim.HANDLING[handling], true)
	var m: float = sim.eL.m + sim.eR.m + sim.pod.m
	var base: float = 2.0 * (P.engineCd + P.brakeCd) + P.podCd + 0.5 * P.brakeCd
	var fl: float = 2.0 * P.frontBrakeCd
	return Vector4(2.5 * P.brakeConst / m, base / m, (base + 0.5 * fl) / m, (base + fl) / m)


static func _seg(va: float, vb: float, c0: float, c2: float) -> float:
	return log((c0 + c2 * va * va) / (c0 + c2 * vb * vb)) / (2.0 * c2) if va > vb else 0.0


## Distance (m) full brakes take from v down to vt (0 if already slower): the integral of v / a(v),
## in pieces: the live handling `b` with the front flaps full above V1, half between, shut below
## V0, down to STARFIGHTER's engage speed; then STARFIGHTER's `bsf`.
func stop_distance(v: float, vt: float, b: Vector4, bsf: Vector4) -> float:
	if v <= vt:
		return 0.0
	var v0: float = sim.P.frontBrakeV0
	var v1: float = sim.P.frontBrakeV1
	var ve: float = sim.P.sfEngageV
	var d := 0.0
	var a := v
	if a > v1:
		var e := maxf(maxf(vt, ve), v1)
		d += _seg(a, e, b.x, b.w)
		a = e
	if a > vt and a > v0:
		var e := maxf(maxf(vt, ve), v0)
		d += _seg(a, e, b.x, b.z)
		a = e
	if a > vt and a > ve:
		var e := maxf(vt, ve)
		d += _seg(a, e, b.x, b.y)
		a = e
	if a > vt:
		d += _seg(a, vt, bsf.x, bsf.y)
	return d


## The cut for sample j from where the craft is: full braking's share it takes (see the header);
## -1 when it's behind or out of REACH.
func cut(j: int, v: float, b: Vector4, bsf: Vector4) -> float:
	if sim.pod.path > 0:
		return -1.0   # off the loop (the shade line): no guide
	var d := fposmod(s[j] - s[sim.pod.hint], s[sim.N])
	if d > REACH:
		return -1.0
	return stop_distance(v, vlim[j] * HEADROOM, b, bsf) / maxf(d, NEAR)


## The next town's cut: the worst over its first TOWN_LOOK metres (0 on tracks without towns).
func town_cut(v: float, b: Vector4, bsf: Vector4) -> float:
	if mouths.is_empty() or sim.pod.path > 0:
		return 0.0
	var here: float = s[sim.pod.hint]
	var best := -1
	var bd := INF
	for m in mouths:
		var d := fposmod(s[m] - here, s[sim.N])
		if d < bd:
			bd = d
			best = m
	var q := 0.0
	var j := best
	while fposmod(s[j] - s[best], s[sim.N]) < TOWN_LOOK:
		q = maxf(q, cut(j, v, b, bsf))
		j = (j + 10) % sim.N
	return q


## Green, amber, red for a cut (the shader's guide_color).
static func color(q: float) -> Color:
	var green := Color(0.15, 0.95, 0.3)
	var amber := Color(1.0, 0.65, 0.05)
	var red := Color(1.0, 0.08, 0.05)
	return green.lerp(amber, smoothstep(AMBER_AT - 0.1, AMBER_AT + 0.1, q)).lerp(red, smoothstep(RED_AT - 0.08, RED_AT, q))


## This frame's state into a guide-lit material (view/guide.gdshaderinc's uniforms).
func apply(mat: ShaderMaterial) -> void:
	if sim.pod.path > 0:   # off the loop (the shade line): the lights go neutral
		mat.set_shader_parameter("guide_on", 0.0)
		return
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	mat.set_shader_parameter("guide_on", 1.0)
	mat.set_shader_parameter("v_now", v)
	mat.set_shader_parameter("s_now", float(s[sim.pod.hint]))
	mat.set_shader_parameter("lap", float(s[sim.N]))
	mat.set_shader_parameter("brake", brake_model())
	mat.set_shader_parameter("brake_sf", brake_model("starfighter"))
	mat.set_shader_parameter("speeds", Vector3(sim.P.frontBrakeV0, sim.P.frontBrakeV1, sim.P.sfEngageV))
