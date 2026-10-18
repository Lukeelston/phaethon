## Quest Touch control schemes, standing in for the printed levers. Cycle them with the left
## menu button; the choice is saved. Pure input mapping: update() takes a snapshot of both
## controllers and returns lever and brake values, so tests can drive it without a headset.
##   triggers  each trigger throttles the OPPOSITE engine, so a hand steers its own way: squeeze
##             the right trigger harder and the left engine pushes you right (Luke: "the brain
##             wants the right side to make the vehicle go right"). Read as throttle (the two
##             together) plus steering (their difference). The triggers MAGNET to each other: a
##             small difference between them is pulled toward none, so fingers that are nearly
##             together fly dead straight (smoothly: no dead zone to snap out of). Each engine's
##             lever rises over ~0.6 s at most, so a finger that lands first can't spin you off
##             the line; letting off is instant. Steering authority grows with speed (full from
##             500 mph, where every corner is), and with the triggers together the craft holds
##             itself straight, cancelling its own yaw (fly-by-wire; not on the burner). Then the
##             difference is softened near the
##             middle (a small wobble steers about a third as hard, a full split still all the
##             way) and each engine eases over ~0.08 s, so a twitch can't throw you into a roll. Not more:
##             a squared curve plus a 1.25 s ramp made small corrections do nothing, then snap
##             ("skippy"): an ideal pilot couldn't hold the GP straight (tests/test_controls_flyable.gd).
##             The pull itself is softened (about 25% less lever per bit of travel on average,
##             most at the bottom). They spring back when you let go; pulled all the way (past ~97%) is the burner
##             detent. Grips are the air brakes, same side (the left grip drags the left engine:
##             also a left turn).
##   mixed     left stick up/down sets one throttle for both engines (it holds); right stick
##             left/right steers (springs back) by easing off the inside engine, or on the
##             burner by feathering the inside air brake (so the burner stays lit). Triggers brake.
##   grab      squeeze a grip and push your hand forward or back: that lever follows (22 cm is
##             the whole travel) and stays put when you let go, like the printed levers.
##             Triggers brake.
##   sticks    the original: thumbsticks nudge the levers, which hold; triggers brake; both
##             grips level the levers to the lower one.
## ctrl snapshot keys: lt, rt (triggers 0..1), lg, rg (grips 0..1), ls, rs (sticks, Vector2),
## lz, rz (hand z in the seat's frame, metres; forward is -z); triggers also read speed (m/s)
## and yaw (the engines' yaw rate, rad/s) when given (without them: full authority, no hold).
class_name QuestControls
extends RefCounted

const SCHEMES := ["triggers", "mixed", "grab", "sticks"]
const NAMES := {"triggers": "TRIGGER THROTTLES", "mixed": "THROTTLE + STEER", "grab": "GRAB THE LEVERS",
	"sticks": "STICK LEVERS"}
const HINTS := {"triggers": "SQUEEZE RIGHT TO GO RIGHT  GRIPS BRAKE", "mixed": "L STICK THROTTLE  R STICK STEER  TRIGGERS BRAKE",
	"grab": "GRIP + PUSH = LEVER  TRIGGERS BRAKE", "sticks": "STICKS = LEVERS  TRIGGERS BRAKE"}
const GATE := 0.88          # burner gate (CraftSim P.gate)
const FULL := 0.87          # full lever without the burner
const DETENT := 0.97        # trigger / collective past this = burner
const STICK_DZ := 0.15
const GRIP_ON := 0.6        # grab: grip squeezed past this holds the lever
const GRIP_DZ := 0.08       # brake grips: ignore a resting finger
const GRAB_TRAVEL := 0.22   # metres of hand travel for the whole lever range
const RATE_UP := 0.9        # sticks / collective, per second
const RATE_DOWN := 1.4
const TRIG_SOFT := 0.55     # triggers: lever per bit of pull at the bottom (Luke: "25% less throttle
                            # response": ~25% less on average over the travel, full at the end)
const SPLIT_SOFT := 0.35    # triggers: steering gain at the centre (full gain at a full split)
const SPLIT_TAU := 0.08     # triggers: each engine's easing time constant, s
const MAGNET := 0.10        # triggers: magnet width, in trigger travel (Luke: "can the inputs magnet
                            # to each other?"). Fingers 0.07 apart (his median while both were pulled)
                            # now steer 15% as hard; a full split still turns all the way.
const SPEED_REF := 223.5    # triggers: full steering authority from 500 mph up (m/s). Below it the same
const SPEED_POW := 1.5      # split yaws you far harder (31 deg/s per 0.05 split at 236 mph, 5.6 at 747),
const SPEED_FLOOR := 0.15   # so authority scales (v / ref)^1.5, never under 15%. Every GP corner is fast.
const HOLD_K := 1.2         # triggers: straight-hold. With the triggers together, the craft cancels its
                            # own yaw rate (split per rad/s), so a correction stops instead of
                            # overshooting (Luke: "acceleration is still really hard to get into a
                            # straight line"; his log showed big alternating squeezes). It fades out
                            # as the triggers part (gone by 2 magnet widths), so it never fights a turn.
const BRAKE_REF := 134.0    # triggers: the grips (air brakes) magnet like the triggers, and above 300 mph
                            # their DIFFERENCE fades as (300 mph / speed)^2 (never under 10%): one air
                            # brake's drag grows with speed^2, so one-handed braking at 900 mph spun
                            # you 150 deg in 3 s and flung the pod into the engines (Luke: "if i brake
                            # too hard, the pod flies forward"). Now it slows you and turns you ~40 deg.
const HOLD_FULL_AT := 0.15  # triggers: the hold is at full strength from this much throttle (lever)
const RAMP_UP := 1.5        # triggers: each engine's lever rises at most this fast, per second (~0.6 s
                            # idle to full); letting off is instant. Stops a finger that lands first
                            # from spinning you off the line ("0-100 sends me into a whirlwind").

var scheme := "triggers"
var thr_l := 0.0            # held levers (sticks, grab)
var thr_r := 0.0
var collective := 0.0       # held throttle (mixed)
var _grab := [{}, {}]       # per side: {z0, lever0} while that grip is held
var _was := [0.0, 0.0]      # last output levers, for gate ticks
var _level_latch := false
var split := 0.0            # triggers: the shaped steering split asked for, -1..1 (+ = left engine harder, a right turn)
var magnet_w := MAGNET      # tunable for the tests (0 = off)
var ramp_up := RAMP_UP      # tunable for the tests (0 = instant)
var _ramp := [0.0, 0.0]     # triggers: each engine's lever as delivered (eased, ramped)
var speed_ref := SPEED_REF  # tunable for the tests (0 = full authority at any speed)
var hold_k := HOLD_K        # tunable for the tests (0 = off)
var brake_ref := BRAKE_REF  # tunable for the tests (0 = full grip-difference authority at any speed)


func next_scheme() -> String:
	scheme = SCHEMES[(SCHEMES.find(scheme) + 1) % SCHEMES.size()]
	_grab = [{}, {}]
	split = 0.0
	_ramp = [0.0, 0.0]
	return scheme


static func dz(v: float) -> float:
	return 0.0 if absf(v) < STICK_DZ else (v - signf(v) * STICK_DZ) / (1.0 - STICK_DZ)


## A trigger or collective (0..1) onto a lever: most of the travel spans idle to full lever,
## the last few percent is the burner detent.
static func detent(x: float) -> float:
	return 1.0 if x >= DETENT else FULL * clampf(x / 0.9, 0.0, 1.0)


## A trigger onto its engine's lever: the softened curve, then the burner detent at the very end.
static func trigger_lever(x: float) -> float:
	var soft := x * (TRIG_SOFT + (1.0 - TRIG_SOFT) * x)
	return 1.0 if x >= DETENT else FULL * clampf(soft / 0.9, 0.0, 1.0)


## The trigger magnet: a difference between the two triggers (-1..1) pulled toward zero, so
## fingers that are nearly together act exactly together. Smooth everywhere (no dead zone to
## snap out of): about cubic inside the width w, then d - w, rescaled so a full split is still full.
static func magnetise(d: float, w: float) -> float:
	if w <= 0.0:
		return d
	return (d - w * tanh(d / w)) / (1.0 - w * tanh(1.0 / w))


static func _grip_brake(g: float) -> float:
	return clampf((g - GRIP_DZ) / (1.0 - GRIP_DZ), 0.0, 1.0)


## Returns {thrL, thrR, brkL, brkR, tickL, tickR}. thrL/brkL are the left ENGINE's; tickL/tickR
## are HANDS: true on the frame the lever that hand drives crosses the burner gate either way
## (the cockpit buzzes that hand), so with crossed triggers the right hand ticks for the left engine.
func update(c: Dictionary, delta: float) -> Dictionary:
	var out := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0}
	match scheme:
		"triggers":
			var rt: float = c.rt
			var lt: float = c.lt
			var mid := (rt + lt) / 2.0
			var dif := magnetise(rt - lt, magnet_w)
			var a := trigger_lever(mid + dif / 2.0)   # crossed: right trigger, left engine
			var b := trigger_lever(mid - dif / 2.0)
			var throttle := (a + b) / 2.0
			var u := a - b         # -1..1
			split = u * (SPLIT_SOFT + (1.0 - SPLIT_SOFT) * absf(u))   # softened near the middle
			# each engine's target, from here on handled engine by engine. (It used to be one
			# throttle plus a smoothed split: squeeze one trigger from idle and for ~0.1 s BOTH
			# engines were told to rise, so a quick or pumped one-sided squeeze drove you straight
			# on instead of turning: Luke's GP wreck, "rt 1.00 -> 0.13/0.15".)
			var ta := clampf(throttle + split / 2.0, 0.0, 1.0)
			var tb := clampf(throttle - split / 2.0, 0.0, 1.0)
			# steering authority for this speed (ctrl key "speed", m/s): the stronger engine is
			# eased toward the weaker, never the weaker raised, so a trigger you've let go of
			# keeps its engine off at any speed
			var spd: float = c.get("speed", -1.0)
			if speed_ref > 0.0 and spd >= 0.0:
				var kv := clampf(pow(spd / speed_ref, SPEED_POW), SPEED_FLOOR, 1.0)
				if ta > tb:
					ta = tb + kv * (ta - tb)
				else:
					tb = ta + kv * (tb - ta)
			# per engine: rising no faster than the ramp, easing down over SPLIT_TAU (a finger
			# let up doesn't snap you into a roll); both let go is idle at once
			if a == 0.0 and b == 0.0:
				_ramp = [0.0, 0.0]
			else:
				var ease := 1.0 - exp(-delta / SPLIT_TAU)
				for k in 2:
					var tgt: float = ta if k == 0 else tb
					var x: float = _ramp[k]
					if tgt > x:
						x = minf(tgt, x + ramp_up * delta) if ramp_up > 0.0 else tgt
					else:
						x += (tgt - x) * ease
						if x - tgt < 0.002:
							x = tgt
					_ramp[k] = x
			# straight-hold (ctrl key "yaw", rad/s), on the levers as delivered so it acts at once
			# (a correction that lags overshoots). It only shares out throttle you're giving
			# (none at idle) and stands aside while either air brake is in: braking one side
			# yaws you on purpose, and the hold "correcting" that fired the other engine with the
			# triggers let go (Luke: "the air brakes are engaging the engines a bit"). Not on the
			# burner either, where shaving one lever would drop it under the gate.
			var la: float = _ramp[0]
			var lb: float = _ramp[1]
			var brk := maxf(_grip_brake(c.lg), _grip_brake(c.rg))
			var mean := (la + lb) / 2.0
			if hold_k > 0.0 and brk < 1.0 and minf(la, lb) < GATE:
				var together := clampf(1.0 - absf(rt - lt) / maxf(2.0 * magnet_w, 1e-3), 0.0, 1.0)
				var share := clampf(mean / HOLD_FULL_AT, 0.0, 1.0) * (1.0 - brk)
				var h := clampf(together * share * hold_k * float(c.get("yaw", 0.0)), -2.0 * mean, 2.0 * mean)
				la = clampf(la + h / 2.0, 0.0, 1.0)
				lb = clampf(lb - h / 2.0, 0.0, 1.0)
			out.thrL = la
			out.thrR = lb
			var bl := _grip_brake(c.lg)
			var br := _grip_brake(c.rg)
			var bm := (bl + br) / 2.0
			var bd := magnetise(bl - br, magnet_w)
			if brake_ref > 0.0 and spd > brake_ref:
				bd *= clampf(pow(brake_ref / spd, 2.0), 0.1, 1.0)
			out.brkL = clampf(bm + bd / 2.0, 0.0, 1.0)
			out.brkR = clampf(bm - bd / 2.0, 0.0, 1.0)
		"mixed":
			var y := dz((c.ls as Vector2).y)
			collective = clampf(collective + y * (RATE_UP if y > 0.0 else RATE_DOWN) * delta, 0.0, 1.0)
			var lever := detent(collective)
			var s := dz((c.rs as Vector2).x)
			s = s * absf(s)   # fine near the middle, full at the stop
			out.brkL = c.lt
			out.brkR = c.rt
			if lever >= GATE:
				# on the burner both levers sit past the gate, where easing one changes nothing
				# until it drops out and kills the burner: steer with the inside air brake instead
				out.thrL = lever
				out.thrR = lever
				out.brkL = maxf(out.brkL, maxf(0.0, -s))
				out.brkR = maxf(out.brkR, maxf(0.0, s))
			else:
				out.thrL = lever * (1.0 - maxf(0.0, -s))   # steering left eases the left engine
				out.thrR = lever * (1.0 - maxf(0.0, s))
		"grab":
			var zs := [c.lz, c.rz]
			var gs := [c.lg, c.rg]
			for k in 2:
				if gs[k] >= GRIP_ON:
					if _grab[k].is_empty():
						_grab[k] = {"z0": zs[k], "lever0": thr_l if k == 0 else thr_r}
					var v: float = clampf(_grab[k].lever0 + (_grab[k].z0 - zs[k]) / GRAB_TRAVEL, 0.0, 1.0)
					if k == 0:
						thr_l = v
					else:
						thr_r = v
				else:
					_grab[k] = {}
			out.thrL = thr_l
			out.thrR = thr_r
			out.brkL = c.lt
			out.brkR = c.rt
		_:   # sticks
			var both: bool = c.lg > 0.7 and c.rg > 0.7
			if both and not _level_latch:
				var m := minf(thr_l, thr_r)
				thr_l = m
				thr_r = m
			_level_latch = both
			for k in 2:
				var stick: Vector2 = c.ls if k == 0 else c.rs
				var y := dz(stick.y)
				var rate := RATE_UP if y > 0.0 else RATE_DOWN
				if k == 0:
					thr_l = clampf(thr_l + y * rate * delta, 0.0, 1.0)
				else:
					thr_r = clampf(thr_r + y * rate * delta, 0.0, 1.0)
			out.thrL = thr_l
			out.thrR = thr_r
			out.brkL = c.lt
			out.brkR = c.rt
	var cross_l: bool = (out.thrL >= GATE) != (_was[0] >= GATE)
	var cross_r: bool = (out.thrR >= GATE) != (_was[1] >= GATE)
	var crossed := scheme == "triggers"
	out.tickL = cross_r if crossed else cross_l
	out.tickR = cross_l if crossed else cross_r
	_was = [out.thrL, out.thrR]
	return out
