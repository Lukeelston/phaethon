## How like a hand a pilot's inputs are, and how the craft rides under them (Luke, of the autopilot:
## "definitely runs like a computer running it - very jumpy"). Fed a frame at a time with what the
## sim was given and the sim after it; tests/test_autopilot.gd holds the autopilot to it and
## tests/probe_autopilot_hands.gd prints and logs it.
##   var m := HandMeter.new()
##   m.add(dt, thrL, thrR, brkL, brkR, sim)      every frame (dt: the sim's seconds since the last)
##   m.note("lane")                              a lane change, a "handling" ask, a "gear" shift
##   m.stats() -> Dictionary                     see below
## What it counts:
##   rates       how fast a lever or a brake moves (per second; a hand takes a few tenths of a second
##               over its travel, a machine one frame)
##   reversals   a control turning back after moving more than HYST one way: per minute, and how many
##               came within QUICK s of the one before (no hand turns back and forth faster)
##   steer       the two sides' difference (right lever less left, plus left brake less right)
##   the ride    the pod's sideways and fore-and-aft acceleration (g) and jerk (g/s) from its velocity
##               frame to frame, and the nose's wag as the headset logs it (vr/wag_meter.gd)
extends RefCounted

const WagMeterScript := preload("res://vr/wag_meter.gd")
const G := 9.81
const HYST := 0.02            # a control has moved when it has gone this far (of its travel)
const QUICK := 0.25           # s: two turns closer than this are a machine's
const NAMES := ["thrL", "thrR", "brkL", "brkR", "steer"]
const FULL := 0.85            # a lever at or over this is fully in (the gate is at 0.88, full lever 0.87)
const MIN_V := 134.0          # m/s (300 mph): the ride is measured at speed, as the wag is

var t := 0.0                  # s measured
var frames := 0
var wag = WagMeterScript.new()
var notes := {}               # "lane", "handling", "gear" -> how many
var _last := PackedFloat64Array()      # each control last frame
var _ext := PackedFloat64Array()       # ... its running extreme since its last turn
var _dir := PackedInt32Array()         # ... which way it is going (0: not yet moved)
var _turn_t := PackedFloat64Array()    # ... when it last turned
var reversals := PackedInt32Array()    # ... its turns
var quick := PackedInt32Array()        # ... those within QUICK s of the one before
var rate_max := PackedFloat64Array()   # ... the most it moved, per second
var _rates: Array = [[], [], [], [], []]
var _steer: Array = []        # |steer| each frame at speed
var _full := 0.0              # s with both levers fully in ...
var _part := 0.0              # ... with either part way (not full, not shut)
var _brake_t := 0.0           # s with a brake on
var _brakes: Array = []       # the harder brake, each frame it is on
var _thr_braking := 0.0       # the levers' mean summed over braking frames
var _moving := 0.0            # s over MIN_V
var _v := Vector2.ZERO
var _a := Vector2.ZERO        # (sideways, fore and aft) m/s^2 last frame
var _have := 0                # frames of velocity in hand
var _lat: Array = []          # |sideways acceleration| g, each frame at speed
var _lat_jerk: Array = []     # |sideways jerk| g/s
var _lon_jerk: Array = []     # |fore-and-aft jerk| g/s
var _lon: Array = []          # fore-and-aft acceleration g (signed)


func _init() -> void:
	for k in NAMES.size():
		_last.append(0.0); _ext.append(0.0); _dir.append(0); _turn_t.append(-INF)
		reversals.append(0); quick.append(0); rate_max.append(0.0)


func note(what: String) -> void:
	notes[what] = int(notes.get(what, 0)) + 1


## A frame: what the sim was given for it, and the sim after it.
func add(dt: float, thr_l: float, thr_r: float, brk_l: float, brk_r: float, sim) -> void:
	if dt <= 0.0:
		return
	var now := [thr_l, thr_r, brk_l, brk_r, thr_r - thr_l + brk_l - brk_r]
	var speed := Vector2(sim.pod.vx, sim.pod.vy).length()
	for k in NAMES.size():
		var x: float = now[k]
		if frames > 0:
			var r := absf(x - _last[k]) / dt
			rate_max[k] = maxf(rate_max[k], r)
			(_rates[k] as Array).append(r)
			# a turn: it has come back more than HYST from the furthest it went
			if _dir[k] == 0:
				if absf(x - _ext[k]) > HYST:
					_dir[k] = 1 if x > _ext[k] else -1
					_ext[k] = x
			elif (x - _ext[k]) * _dir[k] > 0.0:
				_ext[k] = x
			elif absf(x - _ext[k]) > HYST:
				reversals[k] += 1
				if t - _turn_t[k] < QUICK:
					quick[k] += 1
				_turn_t[k] = t
				_dir[k] = -_dir[k]
				_ext[k] = x
		else:
			_ext[k] = x
		_last[k] = x
	var v := Vector2(sim.pod.vx, sim.pod.vy)
	if speed >= MIN_V:
		_moving += dt
		_steer.append(absf(float(now[4])))
		if thr_l >= FULL and thr_r >= FULL:
			_full += dt
		elif maxf(thr_l, thr_r) > 0.02:
			_part += dt
		var hard := maxf(brk_l, brk_r)
		if hard > 0.02:
			_brake_t += dt
			_brakes.append(hard)
			_thr_braking += (thr_l + thr_r) / 2.0
		if _have >= 1:
			var along := _v.normalized()
			var acc := (v - _v) / dt
			var a := Vector2(along.x * acc.y - along.y * acc.x, along.dot(acc))
			_lat.append(absf(a.x) / G)
			_lon.append(a.y / G)
			if _have >= 2:
				_lat_jerk.append(absf(a.x - _a.x) / dt / G)
				_lon_jerk.append(absf(a.y - _a.y) / dt / G)
			_a = a
		_have += 1
	else:
		_have = 0
	_v = v
	wag.add(dt, (sim.eL.w + sim.eR.w) / 2.0, speed, 0)
	t += dt
	frames += 1


static func pct(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	var k := (s.size() - 1) * q
	var lo := int(k)
	var hi := mini(lo + 1, s.size() - 1)
	return lerpf(float(s[lo]), float(s[hi]), k - lo)


static func rms(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sq := 0.0
	for x in values:
		sq += float(x) * float(x)
	return sqrt(sq / values.size())


## rate_<control>: the most it moved (/s); rate99_<control>: 99% of frames under this
## rev_<control>: its turns a minute; quick_<control>: those within QUICK s of the last, a minute
## lever_rate, brake_rate, lever_rev, brake_rev, lever_quick, brake_quick: the worse side's
## steer_med, steer_90: the two sides' difference at speed; full, part: share of the time at speed with
## both levers fully in / either part way; braking: with a brake on; brake_med: the harder brake when on
## lat_g (rms), lat_jerk95, lat_jerk99, lon_jerk95, lon_jerk99 (g/s), lon_g_min (the hardest slowing, g)
## wag10: the nose's swings a 10 s; wag_rms: deg/s; lanes, handlings, gears: a minute
func stats() -> Dictionary:
	var out := {"t": t, "frames": frames}
	var per_min := 60.0 / maxf(t, 1e-6)
	for k in NAMES.size():
		out["rate_" + NAMES[k]] = rate_max[k]
		out["rate99_" + NAMES[k]] = pct(_rates[k], 0.99)
		out["rev_" + NAMES[k]] = reversals[k] * per_min
		out["quick_" + NAMES[k]] = quick[k] * per_min
	out.lever_rate = maxf(rate_max[0], rate_max[1])
	out.brake_rate = maxf(rate_max[2], rate_max[3])
	out.lever_rev = maxf(reversals[0], reversals[1]) * per_min
	out.brake_rev = maxf(reversals[2], reversals[3]) * per_min
	out.lever_quick = maxf(quick[0], quick[1]) * per_min
	out.brake_quick = maxf(quick[2], quick[3]) * per_min
	out.steer_rev = reversals[4] * per_min
	out.steer_quick = quick[4] * per_min
	out.steer_med = pct(_steer, 0.5)
	out.steer_90 = pct(_steer, 0.9)
	out.full = _full / maxf(_moving, 1e-6)
	out.part = _part / maxf(_moving, 1e-6)
	out.braking = _brake_t / maxf(_moving, 1e-6)
	out.brake_med = pct(_brakes, 0.5)
	out.brake_90 = pct(_brakes, 0.9)
	out.thr_braking = _thr_braking / maxf(1.0, float(_brakes.size()))
	out.lat_g = rms(_lat)
	out.lat_g_max = pct(_lat, 1.0)
	out.lat_jerk = rms(_lat_jerk)
	out.lat_jerk95 = pct(_lat_jerk, 0.95)
	out.lat_jerk99 = pct(_lat_jerk, 0.99)
	out.lon_jerk = rms(_lon_jerk)
	out.lon_jerk95 = pct(_lon_jerk, 0.95)
	out.lon_jerk99 = pct(_lon_jerk, 0.99)
	out.lon_g_min = pct(_lon, 0.0)
	out.lon_g_max = pct(_lon, 1.0)
	out.wag10 = wag.per10()
	out.wag_rms = wag.rms()
	for what in ["lane", "handling", "gear"]:
		out[what + "s"] = int(notes.get(what, 0)) * per_min
		out[what + "_n"] = int(notes.get(what, 0))
	return out


## The same, to read.
func text() -> String:
	var s := stats()
	return ("levers: most %.1f /s (99%% under %.2f), %.0f turns a minute (%.0f of them within %.2f s of the last); both fully in %.0f%% of the time, part way %.0f%%\n"
		+ "brakes: most %.1f /s (99%% under %.2f), %.0f turns a minute (%.0f quick); on %.0f%% of the time, the harder one's median %.2f (90%% under %.2f), the levers at %.2f meanwhile\n"
		+ "steer (the sides' difference): median %.3f, 90%% under %.3f; %.0f turns a minute (%.0f quick)\n"
		+ "ride: sideways %.2f g rms (most %.1f), sideways jerk %.1f g/s rms, 95%% under %.1f, 99%% under %.1f; fore-and-aft jerk 95%% under %.1f, 99%% under %.1f g/s, the hardest slowing %.1f g\n"
		+ "nose wag: %.1f swings / 10 s, %.2f deg/s rms; lane changes %d, handling asks %d, gear shifts %d in %.0f s") % [
		s.lever_rate, maxf(s.rate99_thrL, s.rate99_thrR), s.lever_rev, s.lever_quick, QUICK, 100.0 * s.full, 100.0 * s.part,
		s.brake_rate, maxf(s.rate99_brkL, s.rate99_brkR), s.brake_rev, s.brake_quick, 100.0 * s.braking, s.brake_med, s.brake_90, s.thr_braking,
		s.steer_med, s.steer_90, s.steer_rev, s.steer_quick,
		s.lat_g, s.lat_g_max, s.lat_jerk, s.lat_jerk95, s.lat_jerk99, s.lon_jerk95, s.lon_jerk99, -s.lon_g_min,
		s.wag10, s.wag_rms, s.lane_n, s.handling_n, s.gear_n, s.t]
