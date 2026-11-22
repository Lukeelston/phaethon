## The craft's start-up, run like a jet's (Luke: "design a 'startup' sequence for the vehicle, similar
## to a jet startup sequence. Try to make them all mean something ... a covered switch for engine
## power, and another for a parking brake that holds the vehicle steady at rest to startup the
## turbines and test them. And then of course a dope start button ... a kind of tutorial i can walk
## people through on how to work the controls while they do it for the first time").
## Four controls across the windscreen header (vr/overhead_panel.gd), numbered in the order they
## are worked, and what each one is for:
##   1 BATT     the battery bus. Nothing in the cockpit is alive without it: the instruments light and
##              sweep through their self-test, the map boots, the projector throws the checklist on
##              the glass, the engines' strobes start flashing out ahead.
##   2 ENGINE   engine power, under a red guard (lift it, then throw the switch; it falls shut again
##              by itself, so a stray hand in flight cannot cut the engines). It charges the binder:
##              the arc strikes between the engines and the cables glow. No charge, no start.
##   3 START    the start button. Each engine turns over on its starter and catches, the left one
##              first. It will not start a craft at rest without the parking brake set.
##   4 PARK     the parking brake (Luke: "the 'park' lever should also engage the airbrakes to full
##              extents"). Set, both engines' air brakes run out to their full extent and stay
##              there, and the craft is held whatever the levers ask, which is what the run-up is
##              for: each lever shows on its own thrust dial and in its own nozzle, a gear shifted
##              shows on the centre dial, and both levers held forward spool the turbines up to
##              their test speed (the TURBINES lamp, the one that lights by itself at 4,500 mph).
##              Released, the air brakes stow and the craft is yours.
## Interlocks, each one a thing a pilot would have to learn anyway: the battery before engine power;
## engine power before a start; the brake set before a start at rest; engine power off before the
## battery goes off; the brake only goes on at rest. In flight the guarded switch still cuts both
## engines, and START relights them without the brake.
## This is the logic alone: no nodes, no sim. The cockpit asks it what the sim may be given
## (gate), and what to show, sound and shake (the fields and events).
##   var s := StartupSequence.new()     everything running, the brake off: nothing is held back
##   s.cold()                           parked, cold and dark
##   s.flick("batt", 1, mph) / s.press_start(mph)      a control worked: what happened ("" nothing)
##   s.step(delta, [thrL, thrR], gear)                 every frame
##   inp = s.gate(inp)                                 what the sim is given
##   s.message() / s.line() / s.display()              the checklist's page for the glass, its short form for an
##                                                     instrument strip, and what the glass draws in motion round it
class_name StartupSequence
extends RefCounted

const SELFTEST_S := 2.4          # the lamp and needle test after the battery comes on
const POWER_UP_S := 0.45         # the bus coming up ...
const POWER_DOWN_S := 0.8        # ... and dying away
const GUARD_OPEN_S := 4.0        # the guard falls shut this long after it was lifted, if nothing is thrown
const GUARD_AFTER_S := 1.1       # ... and this long after the switch under it is thrown
const CHARGE_S := 0.9            # the binder striking and the cables charging
const DISCHARGE_S := 1.4
const STAGGER_S := 1.2           # the right engine starts this long after the left
const CRANK_S := 1.6             # an engine turning over on its starter before it catches
const CATCH_S := 0.8             # from the catch to a steady idle
const REST_MPH := 5.0            # under this the craft is at rest
const CHECK_LEVER := 0.6         # the run-up: a lever past this has been tried
const TURBINE_LEVER := 0.75      # both levers past this ...
const TURBINE_UP_S := 2.4        # ... for this long spool the turbines to their test speed
const TURBINE_DOWN_S := 1.6
const CLEARED_S := 3.0           # CLEARED stays on the glass this long after the brake comes off
const STEPS := 5
# The run-up, taught (Luke, flying the fifteenth: "build a sort of 'tutorial' into the startup sequence.
# This is going to be a hard game for people to play first time, and i want to bring down the barrier to
# fun"). With `school` set the run-up is one lesson at a time, each a thing a pilot's hands do in flight,
# in the order he will need them, and passed by doing it with the craft held on its brake. What "doing
# it" means is taken from how the game is flown by someone who can: his own two flights that evening,
# read from the log's one-a-second input lines. Both triggers were fully in 92% of the time and fully
# out 7%, almost never part way (so: all the way in, and held). The air brakes were on half the time,
# a grip squeezed 0.40 at the median and hard in 1 to 4% of it (so: a turn is a gentle squeeze, and a
# full one is for stopping). The throttle stayed on through nearly all of the braking.
# For the trigger throttles (the default controls); any other scheme keeps the plain run-up.
const LESSONS := ["throttle", "turbines", "right", "left", "brake", "gear"]
const SCHOOL_CHECKS := ["steerR", "steerL", "brake"]   # the checks only a taught run-up asks for
const FULL_LEVER := 0.85         # a trigger all the way in (it gives 0.87 at its stop: the gate)
const THROTTLE_HOLD_S := 1.0     # ... and held this long
const GENTLE := Vector2(0.15, 0.65)   # a steering squeeze: a grip between these ...
const GENTLE_HOLD_S := 0.8       # ... for this long ...
const OTHER_GRIP := 0.12         # ... with the other grip under this
const TOO_HARD := 0.8            # a steering squeeze past this is told to ease off
const HARD_GRIP := 0.85          # both grips past this: the brakes, hard ...
const HARD_HOLD_S := 0.5         # ... for this long

var batt := true
var master := true
var guard_open := false
var park := false
var stage: Array[String] = ["run", "run"]   # each engine: off, wait (its turn to come), crank, catch, run
var stage_t: Array[float] = [0.0, 0.0]      # seconds left in that stage
var power := 1.0                 # the bus, 0 dead .. 1 up
var selftest := -1.0             # seconds into the lamp and needle test (-1: not running)
var tested := true               # the self-test has finished since the battery came on
var charge := 1.0                # the binder and the cables, 0 dead .. 1 charged
var turbine := 0.0               # the run-up's turbine test, 0 stopped .. 1 at test speed
var checks := {"thrL": true, "thrR": true, "gear": true, "turbines": true, "steerR": true, "steerL": true, "brake": true}
var gears := false               # there is a gearbox to try (the cockpit says): the run-up asks for a shift
var school := false              # the run-up is taught, a lesson at a time (the cockpit says, before cold(): a first flight, or the pilot asked)
var taught := false              # a taught run-up has been flown away from (the cockpit remembers it, and stops teaching)
var grips := [0.0, 0.0]          # the grips and the levers as last seen (the glass's bars in a lesson)
var levers := [0.0, 0.0]
var _hold := 0.0                 # seconds the lesson's ask has been met without a break
var _lesson_was := ""
var cleared := true              # the sequence is behind you (or was never asked for)
var refusal := ""                # why the last control worked was refused (for the glass), while _refusal_t lasts
var events: Array[String] = []   # what happened since they were last cleared (the cockpit's sounds and haptics)
var _guard_t := 0.0
var _cleared_t := 0.0
var _refusal_t := 0.0
var _gear_seen := -1             # the gear the run-up began in


## Everything running and the brake off: the craft as it always was. Nothing is held back.
func hot() -> void:
	batt = true
	master = true
	guard_open = false
	park = false
	stage = ["run", "run"]
	stage_t = [0.0, 0.0]
	power = 1.0
	selftest = -1.0
	tested = true
	charge = 1.0
	turbine = 0.0
	for key in checks:
		checks[key] = true
	cleared = true
	refusal = ""
	_cleared_t = 0.0
	_refusal_t = 0.0
	_guard_t = 0.0


## Parked, cold and dark: the brake set, everything off.
func cold() -> void:
	batt = false
	master = false
	guard_open = false
	park = true
	stage = ["off", "off"]
	stage_t = [0.0, 0.0]
	power = 0.0
	selftest = -1.0
	tested = false
	charge = 0.0
	turbine = 0.0
	_uncheck()
	cleared = false
	refusal = ""
	_cleared_t = 0.0
	_refusal_t = 0.0
	_guard_t = 0.0


func _uncheck() -> void:
	for key in checks:
		checks[key] = not school and key in SCHOOL_CHECKS      # (the plain run-up does not ask for the lessons' checks)
	_hold = 0.0
	_lesson_was = ""


## The lesson a taught run-up is on: "throttle", "turbines", "right", "left", "brake", "gear", or ""
## (not being taught, not in the run-up, or all of them passed).
func lesson() -> String:
	if not school or not held():
		return ""
	if not (checks.thrL and checks.thrR):
		return "throttle"
	if not checks.turbines:
		return "turbines"
	if not checks.steerR:
		return "right"
	if not checks.steerL:
		return "left"
	if not checks.brake:
		return "brake"
	if gears and not checks.gear:
		return "gear"
	return ""


## How many lessons a taught run-up has (the gearbox's is the last, where there is one), and which
## the pilot is on, 1 up.
func lesson_count() -> int:
	return LESSONS.size() if gears else LESSONS.size() - 1


func lesson_number() -> int:
	return LESSONS.find(lesson()) + 1


## How far the lesson's ask has been held, 0..1 (the turbines': their own spool).
func lesson_progress() -> float:
	match lesson():
		"throttle":
			return clampf(_hold / THROTTLE_HOLD_S, 0.0, 1.0)
		"turbines":
			return turbine
		"right", "left":
			return clampf(_hold / GENTLE_HOLD_S, 0.0, 1.0)
		"brake":
			return clampf(_hold / HARD_HOLD_S, 0.0, 1.0)
	return 0.0


func running(k: int) -> bool:
	return stage[k] == "run"


func all_running() -> bool:
	return stage[0] == "run" and stage[1] == "run"


## An engine is somewhere between the button and its idle.
func starting() -> bool:
	for k in 2:
		if stage[k] in ["wait", "crank", "catch"]:
			return true
	return false


## Nothing is held back from the sim (the gate hands back what it is given).
func is_hot() -> bool:
	return not park and all_running()


## The run-up: the engines are running and the brake holds the craft.
func held() -> bool:
	return park and all_running()


func checks_done() -> bool:
	for key in checks:
		if not checks[key] and (key != "gear" or gears):
			return false
	return true


## How alive an engine is, 0 stopped .. 1 at its idle: for its dials and its sound.
func engine_k(k: int) -> float:
	match stage[k]:
		"crank":
			return 0.25 * (1.0 - stage_t[k] / CRANK_S)
		"catch":
			return lerpf(1.0, 0.25, stage_t[k] / CATCH_S)
		"run":
			return 1.0
	return 0.0


## The light-off: a burst of flame as an engine catches, 0..1 (and nothing at any other time).
func catch_flare(k: int) -> float:
	if stage[k] != "catch":
		return 0.0
	return sin(PI * clampf(1.0 - stage_t[k] / CATCH_S, 0.0, 1.0))


## How far an engine is through its start, 0 stopped .. 1 at its idle: seven tenths of it on the
## starter, the rest from the catch (the bar the glass fills while it cranks and catches).
func start_progress(k: int) -> float:
	match stage[k]:
		"crank":
			return 0.7 * (1.0 - stage_t[k] / CRANK_S)
		"catch":
			return 0.7 + 0.3 * (1.0 - stage_t[k] / CATCH_S)
		"run":
			return 1.0
	return 0.0


func _refuse(why: String) -> String:
	refusal = why
	_refusal_t = 3.5
	events.append("refused")
	return "refused"


## A toggle flicked: `control` "batt", "engine" or "park"; `dir` +1 up, -1 down; `mph` the craft's
## speed. -> what happened: "batt_on", "batt_off", "guard_open", "guard_close", "master_on",
## "master_off", "park_set", "park_release", "refused" (see `refusal`), or "" (nothing to do).
func flick(control: String, dir: int, mph := 0.0) -> String:
	match control:
		"batt":
			if dir > 0 and not batt:
				batt = true
				selftest = 0.0
				tested = false
				return _did("batt_on")
			if dir < 0 and batt:
				if master:
					return _refuse("ENGINE POWER OFF FIRST")
				batt = false
				selftest = -1.0
				tested = false
				_uncheck()
				cleared = false
				return _did("batt_off")
		"engine":
			if not guard_open:
				if dir > 0:
					guard_open = true
					_guard_t = GUARD_OPEN_S
					return _did("guard_open")
				return ""               # the guard is in the way: that is what it is for
			if dir > 0 and not master:
				if not batt:
					return _refuse("BATTERY FIRST")
				master = true
				_guard_t = GUARD_AFTER_S
				return _did("master_on")
			if dir < 0 and master:
				master = false
				_guard_t = GUARD_AFTER_S
				if stage[0] != "off" or stage[1] != "off":
					events.append("shutdown")
				stage = ["off", "off"]
				stage_t = [0.0, 0.0]
				_uncheck()
				cleared = false
				return _did("master_off")
			if dir < 0 and not master:
				guard_open = false
				return _did("guard_close")
		"park":
			if dir > 0 and not park:
				if mph > REST_MPH:
					return _refuse("PARK BRAKE: ONLY AT REST")
				park = true
				_uncheck()
				cleared = false
				return _did("park_set")
			if dir < 0 and park:
				park = false
				return _did("park_release")
	return ""


func _did(what: String) -> String:
	events.append(what)
	refusal = ""            # (something was done: the last refusal is answered)
	_refusal_t = 0.0
	return what


## The start button pressed. -> "start", "refused" (see `refusal`), "dead" (no power: a click and
## nothing else) or "" (they are running or already starting).
func press_start(mph := 0.0) -> String:
	if not batt:
		return _did("dead")
	if not master:
		return _refuse("ENGINE POWER FIRST")
	if stage[0] != "off" and stage[1] != "off":
		return ""
	if not park and mph < REST_MPH:
		return _refuse("SET THE PARK BRAKE TO START")
	var turn := 0
	for k in 2:
		if stage[k] == "off":
			stage[k] = "wait"
			stage_t[k] = STAGGER_S * turn
			turn += 1
	return _did("start")


## A frame: `thr` is what the pilot's hands ask of each engine, [left, right]; `gear` the gear shown;
## `grip` how far each grip is squeezed, [left, right] (the air brakes' own ask: a taught run-up reads it).
func step(dt: float, thr: Array, gear := 0, grip: Array = [0.0, 0.0]) -> void:
	dt = clampf(dt, 0.0, 0.1)
	levers = [float(thr[0]), float(thr[1])]
	grips = [float(grip[0]), float(grip[1])]
	power = move_toward(power, 1.0 if batt else 0.0, dt / (POWER_UP_S if batt else POWER_DOWN_S))
	if selftest >= 0.0:
		selftest += dt
		if selftest >= SELFTEST_S:
			selftest = -1.0
			tested = true
			events.append("selftest_done")
	if guard_open:
		_guard_t -= dt
		if _guard_t <= 0.0:
			guard_open = false
			events.append("guard_close")
	charge = move_toward(charge, 1.0 if master else 0.0, dt / (CHARGE_S if master else DISCHARGE_S))
	for k in 2:
		if not stage[k] in ["wait", "crank", "catch"]:
			continue
		stage_t[k] -= dt
		if stage_t[k] > 0.0:
			continue
		match stage[k]:
			"wait":
				stage[k] = "crank"
				stage_t[k] = CRANK_S
				events.append("crank%d" % k)
			"crank":
				stage[k] = "catch"
				stage_t[k] = CATCH_S
				events.append("light%d" % k)
			"catch":
				stage[k] = "run"
				stage_t[k] = 0.0
				events.append("run%d" % k)
				if all_running():
					events.append("running")
	var both := false
	if held() and school:
		# a lesson at a time: only the one the pilot is on can be passed, by holding what it asks
		var on := lesson()
		if on != _lesson_was:
			_lesson_was = on
			_hold = 0.0
			_gear_seen = gear         # (the gearbox's lesson: a shift from the gear it began in)
		var met := false
		match on:
			"throttle":
				met = levers[0] >= FULL_LEVER and levers[1] >= FULL_LEVER
			"right":
				met = grips[1] >= GENTLE.x and grips[1] <= GENTLE.y and grips[0] < OTHER_GRIP
			"left":
				met = grips[0] >= GENTLE.x and grips[0] <= GENTLE.y and grips[1] < OTHER_GRIP
			"brake":
				met = grips[0] >= HARD_GRIP and grips[1] >= HARD_GRIP
		_hold = _hold + dt if met else 0.0
		match on:
			"throttle":
				if _hold >= THROTTLE_HOLD_S:
					checks.thrL = true
					checks.thrR = true
					events.append("check")
			"right":
				if _hold >= GENTLE_HOLD_S:
					checks.steerR = true
					events.append("check")
			"left":
				if _hold >= GENTLE_HOLD_S:
					checks.steerL = true
					events.append("check")
			"brake":
				if _hold >= HARD_HOLD_S:
					checks.brake = true
					events.append("check")
			"gear":
				if gear != _gear_seen:
					checks.gear = true
					events.append("check")
		both = on in ["throttle", "turbines"] and levers[0] >= TURBINE_LEVER and levers[1] >= TURBINE_LEVER
	elif held():
		for k in 2:
			var side := "L" if k == 0 else "R"
			if float(thr[k]) >= CHECK_LEVER and not checks["thr" + side]:
				checks["thr" + side] = true
				events.append("check")
		if _gear_seen < 0:
			_gear_seen = gear
		elif gear != _gear_seen and not checks.gear:
			checks.gear = true
			events.append("check")
		both = float(thr[0]) >= TURBINE_LEVER and float(thr[1]) >= TURBINE_LEVER
	else:
		_gear_seen = -1
	turbine = move_toward(turbine, 1.0 if both else 0.0, dt / (TURBINE_UP_S if both else TURBINE_DOWN_S))
	if turbine >= 1.0 and not checks.turbines:
		checks.turbines = true
		events.append("turbines_ok")
	if not cleared and is_hot():
		cleared = true
		_cleared_t = CLEARED_S
		events.append("cleared")
		if school and checks_done():      # every lesson passed and the brake let go: the next run-up is the plain one
			taught = true
			school = false
			events.append("schooled")
	_cleared_t = maxf(0.0, _cleared_t - dt)
	if _refusal_t > 0.0:
		_refusal_t -= dt
		if _refusal_t <= 0.0:
			refusal = ""


## What the sim is given of what the pilot asks: nothing from an engine that is not running; and
## while the parking brake is set, no thrust at all and both air brakes full out. (The cockpit keeps
## the ask itself: the levers, the dials and the engines' sound still follow the hands. That is the
## run-up.)
func gate(asked: Dictionary) -> Dictionary:
	if is_hot():
		return asked
	var out := asked.duplicate()
	if park or stage[0] != "run":
		out.thrL = 0.0
	if park or stage[1] != "run":
		out.thrR = 0.0
	if park:
		out.brkL = 1.0
		out.brkR = 1.0
	if out.has("burner"):
		out.burner = false
	return out


# ---- what the pilot is told ----

## Which control is next: "batt", "guard", "engine", "start", "park_set", "park", or "" (none: an
## engine is starting, or the sequence is behind you). The overhead panel blinks that one.
func next_control() -> String:
	if cleared:
		return ""
	if not batt:
		return "batt"
	if not master:
		return "engine" if guard_open else "guard"
	if starting():
		return ""
	if not all_running():
		return "start"   # (at rest without the brake the button refuses and says why)
	return "park" if park else ""


## The step the pilot is on, 1..STEPS.
func step_number() -> int:
	if not batt:
		return 1
	if not master:
		return 2
	if not all_running():
		return 3
	if park and not checks_done():
		return 4
	return 5


static func _tick(done: bool) -> String:
	return "OK" if done else "--"


## The checklist's page for the glass (view/approach_projector.gd's three lines: "ACTION  COUNT",
## "WHERE > WHAT", "NOTE | STATUS"), or "" when there is nothing to say: no power to say it with, or
## the sequence is behind you.
func message() -> String:
	if power < 0.5:
		return ""
	if cleared:
		return "CLEARED  5 / 5\nPARK BRAKE OFF > AIR BRAKES STOWED\nSHE IS YOURS | READY" if _cleared_t > 0.0 else ""
	var note := refusal
	var count := "%d / %d" % [step_number(), STEPS]
	if not master:
		if note == "":
			note = "SELF TEST" if selftest >= 0.0 else "SYSTEMS READY"
		var what := "FLICK 2 ENGINE UP" if guard_open else "LIFT THE RED GUARD"
		return "ENGINE POWER  %s\nOVERHEAD LEFT > %s\n%s | PARKED" % [count, what, note]
	if starting():
		var words := {"off": "OFF", "wait": "NEXT", "crank": "CRANKING", "catch": "IGNITION", "run": "RUNNING"}
		return "STARTING  %s\nLEFT %s > RIGHT %s\nHANDS OFF THE LEVERS | WAIT" % [count, words[stage[0]], words[stage[1]]]
	if not all_running():
		if note == "":
			note = "BINDER CHARGED" if charge >= 1.0 else "BINDER CHARGING"
		return "START ENGINES  %s\nOVERHEAD RIGHT > PRESS 3 START\n%s | %s" % [count, note, "ARMED" if park else "NO BRAKE"]
	if checks_done():
		var good := "TRIGGERS IN, STEER WITH GENTLE SQUEEZES" if school else "ALL CHECKS GOOD, AIR BRAKES OUT"
		return "RELEASE PARK BRAKE  %s\nOVERHEAD RIGHT > FLICK 4 PARK DOWN\n%s | READY" % [count, note if note != "" else good]
	if school:
		return _lesson_page(count, note)
	var route := "LEVERS %s %s > %sTURBINES %s" % [_tick(checks.thrL), _tick(checks.thrR), ("GEAR %s > " % _tick(checks.gear)) if gears else "",
		("%d%%" % roundi(turbine * 100.0)) if turbine > 0.0 and not checks.turbines else _tick(checks.turbines)]
	if note == "":
		note = "PUSH EACH LEVER, SHIFT A GEAR, HOLD BOTH LEVERS" if gears else "PUSH EACH LEVER, THEN HOLD BOTH"
	return "RUN-UP  %s\n%s\n%s | HELD" % [count, route, note]


## A lesson's page for the glass, in the checklist's three lines: what it is, which hand does what,
## and one thing to know about it (or what the pilot is doing wrong), with how far through the lessons he is.
func _lesson_page(count: String, note: String) -> String:
	var where := "%d OF %d" % [lesson_number(), lesson_count()]      # (the glass's status corner is six letters wide)
	var pct := roundi(lesson_progress() * 100.0)
	match lesson():
		"throttle":
			if note == "":
				note = "ONE TRIGGER IS HALF THE THRUST: BOTH" if (levers[0] >= FULL_LEVER) != (levers[1] >= FULL_LEVER) else "FULL OR NOTHING: HOLD THEM IN"
			return "THROTTLE  %s\nBOTH TRIGGERS > SQUEEZE ALL THE WAY%s\n%s | %s" % [count, ("  %d%%" % pct) if pct > 0 else "", note, where]
		"turbines":
			if note == "":
				note = "IN FLIGHT THEY CUT IN AT 4,500 MPH"
			return "TURBINES  %s\nBOTH TRIGGERS > KEEP HOLDING  %d%%\n%s | %s" % [count, pct, note, where]
		"right", "left":
			var k := 1 if lesson() == "right" else 0
			var side := "RIGHT" if k == 1 else "LEFT"
			if note == "":
				if float(grips[1 - k]) >= OTHER_GRIP and float(grips[k]) < GENTLE.x:
					note = "THE OTHER HAND: THE %s GRIP" % side
				elif float(grips[1 - k]) >= OTHER_GRIP:
					note = "ONE GRIP ONLY: LET THE OTHER GO"
				elif float(grips[k]) > TOO_HARD:
					note = "TOO HARD: EASE OFF TO A THIRD"
				else:
					note = "A THIRD OF A SQUEEZE IS A TURN"
			return "TURN %s  %s\n%s GRIP > SQUEEZE GENTLY  %d%%\n%s | %s" % [side, count, side, roundi(float(grips[k]) * 100.0), note, where]
		"brake":
			if note == "":
				note = "BOTH TOGETHER, HARDER TO SLOW HARDER"
			return "BRAKE  %s\nBOTH GRIPS > SQUEEZE HARD  %d%%\n%s | %s" % [count, roundi(minf(float(grips[0]), float(grips[1])) * 100.0), note, where]
		"gear":
			if note == "":
				note = "SHIFT UP WHEN THE REVS TOP OUT"
			return "SHIFT  %s\nRIGHT STICK > FLICK IT UP\n%s | %s" % [count, note, where]
	return ""


## One amount, 0..1, as the glass's two bars end to end: the left one fills, then the right.
static func _across(amount: float) -> Array:
	return [clampf(amount * 2.0, 0.0, 1.0), clampf(amount * 2.0 - 1.0, 0.0, 1.0)]


## What the glass draws in motion round the checklist's words (Luke: "animation to the startup
## sequence display"; view/approach_projector.gd set_checklist, view/startup_glass.gdshader), or {}
## when message() has nothing to say:
##   done     how many of the five steps are behind you (the rail's lit segments; 5: cleared)
##   mark     a tally that goes up whenever something on the page is done: a step, the self-test,
##            the guard lifted, the binder charged, an engine turning, lit, running, a check ticked
##            (the glass sweeps the line that changed)
##   bars     [left, right], 0..1: the bus's self-test, then the binder's charge, then (pair) each
##            engine from its starter to its idle, then the turbines spooling in the run-up; full
##            when there is nothing left of the step but the control to work
##   pair     the bars are the two engines', not one amount across both
##   flare    [left, right], 0..1: an engine catching
##   aim      where the control to work hangs: -1 overhead left, 1 overhead right, 0 no control to
##            work (wait, or the levers)
##   alert    a refusal is on the page
##   cleared  seconds since the brake came off, -1 before
func display() -> Dictionary:
	if power < 0.5 or (cleared and _cleared_t <= 0.0):
		return {}
	var shown := {"done": step_number() - 1, "mark": 0, "bars": [1.0, 1.0], "pair": false, "flare": [0.0, 0.0], "aim": 0,
		"alert": refusal != "", "cleared": -1.0}
	var sub := 0
	if cleared:
		shown.done = STEPS
		shown.cleared = CLEARED_S - _cleared_t
	elif not master:
		shown.bars = _across(selftest / SELFTEST_S if selftest >= 0.0 else float(tested))
		shown.aim = -1
		sub = int(tested) + 2 * int(guard_open)
	elif starting():
		shown.bars = [start_progress(0), start_progress(1)]
		shown.pair = true
		shown.flare = [catch_flare(0), catch_flare(1)]
		sub = 2
		for k in 2:
			sub += ["off", "wait", "crank", "catch", "run"].find(stage[k])
	elif not all_running():
		shown.bars = _across(charge)
		shown.aim = 1
		sub = int(charge >= 1.0)
	elif not checks_done():
		shown.bars = _across(1.0 if checks.turbines else turbine)
		match lesson():      # a taught run-up: the bars are the pilot's own hands, a trigger or a grip each
			"throttle":
				shown.bars = [clampf(float(levers[0]) / FULL_LEVER, 0.0, 1.0), clampf(float(levers[1]) / FULL_LEVER, 0.0, 1.0)]
				shown.pair = true
			"turbines":
				shown.bars = _across(turbine)
			"right", "left", "brake":
				shown.bars = [clampf(float(grips[0]), 0.0, 1.0), clampf(float(grips[1]), 0.0, 1.0)]
				shown.pair = true
			"gear":
				shown.bars = [1.0, 1.0]
		for key in checks:
			sub += int(checks[key] and (key != "gear" or gears) and (school or not key in SCHOOL_CHECKS))
	else:
		shown.aim = 1 if park else 0
	shown.mark = int(shown.done) * 16 + sub
	return shown


## The same, short, for an instrument strip.
func line() -> String:
	var page := message()
	if page == "":
		return ""
	var lines := page.split("\n")
	return "%s\n%s" % [lines[0].replace("  ", "   "), lines[1].get_slice(" > ", 1) if step_number() != 4 or checks_done() else lines[1]]
