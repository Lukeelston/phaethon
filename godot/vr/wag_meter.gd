## The nose wag, measured in flight (Luke: "the nose wagging as i correct and overshoot"): the
## engines' yaw rate with its slow part taken off (a 2 s average: the road's bends, a held turn),
## so what's left is the back-and-forth. A swing is the residual crossing zero after going more than
## SWING deg/s out. At speed only (over 300 mph). report() is the log line (every 10 s in the
## headset): swings per 10 s, their size (RMS deg/s), and the time in each gear.
class_name WagMeter
extends RefCounted

const SWING := 0.7          # deg/s out from the slow part before a turn back counts as a swing
const SLOW_T := 2.0         # s: the slow part's averaging time
const MIN_V := 134.0        # m/s (300 mph): slower than this doesn't count

var t := 0.0                # s at speed
var swings := 0
var _slow := 0.0
var _sq := 0.0
var _on := false            # at speed last frame
var _side := 0              # which side of the slow part the residual is out on (0: not out yet)
var gear_t := {}            # gear (1-4; 0: no gearbox) -> s at speed


## One frame: dt s, the yaw rate (rad/s), the speed (m/s), the gear shown (0: no gearbox).
func add(dt: float, yaw: float, speed: float, gear: int) -> void:
	var r := rad_to_deg(yaw)
	if speed < MIN_V:
		_on = false
		_side = 0
		return
	if not _on:   # just up to speed: the slow part starts where the yaw is
		_on = true
		_slow = r
	_slow += (r - _slow) * (1.0 - exp(-dt / SLOW_T))
	var res := r - _slow
	t += dt
	_sq += res * res * dt
	gear_t[gear] = gear_t.get(gear, 0.0) + dt
	if absf(res) > SWING:
		var s := 1 if res > 0.0 else -1
		if _side != 0 and s != _side:
			swings += 1
		_side = s


func per10() -> float:
	return swings / maxf(t, 1e-6) * 10.0


func rms() -> float:
	return sqrt(_sq / maxf(t, 1e-6))


func report() -> String:
	var g := []
	for k in [1, 2, 3, 4, 0]:
		if gear_t.get(k, 0.0) > 0.0:
			g.append("%s %.0f s" % ["G%d" % k if k > 0 else "no gears", gear_t[k]])
	return "WAG: %.1f swings / 10 s, %.2f deg/s RMS, over %.0f s at speed (%s)" % [per10(), rms(), t, ", ".join(g)]


func reset() -> void:
	t = 0.0
	swings = 0
	_sq = 0.0
	gear_t = {}
