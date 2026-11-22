## The first minute of flying, coached (Luke, asked whether the run-up's lessons should "also coach the
## first minute of actual flying": "launch it then add it"). The flight school (vr/startup_sequence.gd
## `school`) teaches the hands on the parking brake, where nothing can go wrong. This is what comes
## after it, once the brake is off and the road is coming: one line on the glass at a time, only when
## the pilot needs it, about the thing he is doing or failing to do right now, and gone as soon as he
## has done it. What it asks for is how the game is flown by someone who can (his own flights,
## 2026-11-21: the triggers fully in 92% of the time and almost never part way, a gentle grip to
## steer, the throttle left on through the braking), and the two things a newcomer cannot know: that
## a gear runs out and wants a shift, and that the wall is nearer than it looks.
## The logic alone: no nodes, no sim. The cockpit tells it what is happening each frame and shows
## its page on the glass (the checklist's three lines: "ACTION  COUNT", "WHERE > WHAT", "NOTE | STATUS").
##   var c := FlightCoach.new()
##   c.begin()                               the brake has come off on a flight that is being taught
##   c.step(delta, {mph, thr, grip, gear, top, gears, rpm, edge, crashed})     every frame
##   c.message()                             its page, "" when it has nothing to say
##   c.tip                                   "go", "shift", "left", "right", "steer", "power", "farewell" or ""
class_name FlightCoach
extends RefCounted

const FULL_LEVER := 0.85         # a trigger all the way in (StartupSequence.FULL_LEVER)
const GO_MPH := 300.0            # over this she is flying
const GO_HOLD_S := 2.0           # both triggers in this long: he has gone
const REDLINE := 0.96            # the revs at which the limiter starts to cut the pull (QuestControls.LIMIT_X) ...
const REDLINE_S := 0.5           # ... for this long: he is sitting on it
const NEAR_EDGE := 0.58          # of the road's half-width from its middle: the wall is coming ...
const CLEAR_EDGE := 0.38         # ... and back inside this he has steered off it
const GENTLE := 0.15             # a grip past this is a squeeze ...
const TOO_HARD := 0.8            # ... and past this it is told to ease off (StartupSequence.TOO_HARD)
const LIFT_S := 1.5              # both triggers out this long at speed: he is told to put them back
const UNSTEERED_S := 12.0        # this long flying without a grip touched: he is told there are grips
const STEER_HOLD_S := 0.5
const ENOUGH_S := 75.0           # this long flying, and the coach has said its piece
const FAREWELL_S := 4.0

var on := false                  # it is coaching this flight
var done := false                # it has finished (and says nothing more)
var tip := ""
var events: Array[String] = []   # "tip" a new line went up, "tip_ok" he did what it asked, "coached" it has finished
var flown := 0.0                 # seconds over GO_MPH
var went := false                # he has held both triggers in
var shifts := 0                  # upshifts made when asked
var steers := 0                  # walls steered off, gently
var squeezed := false            # a grip has been used at all
var _hold := 0.0
var _redline := 0.0
var _lifted := 0.0
var _gear := -1
var _farewell := 0.0
var _state := {}


## The brake has come off on a flight that is being taught.
func begin() -> void:
	on = true
	done = false
	tip = ""
	flown = 0.0
	went = false
	shifts = 0
	steers = 0
	squeezed = false
	_hold = 0.0
	_redline = 0.0
	_lifted = 0.0
	_gear = -1
	_farewell = 0.0
	events.clear()


func _show(what: String) -> void:
	if what != tip:
		if what != "" and what != "farewell":
			events.append("tip")
		tip = what


func _passed() -> void:
	events.append("tip_ok")


## A frame. `s`: mph; thr [left, right] the triggers; grip [left, right]; gear (1 up) and top (it is
## the top one), gears (there is a gearbox); rpm 0..1 of the redline; edge, where the craft is across
## the road, -1 the left wall .. 1 the right (0 when that means nothing); crashed.
func step(dt: float, s: Dictionary) -> void:
	_state = s
	if not on or done:
		tip = ""
		return
	dt = clampf(dt, 0.0, 0.1)
	var mph := float(s.get("mph", 0.0))
	var thr: Array = s.get("thr", [0.0, 0.0])
	var grip: Array = s.get("grip", [0.0, 0.0])
	var gear := int(s.get("gear", 0))
	var edge := float(s.get("edge", 0.0))
	if bool(s.get("crashed", false)):      # the game has its own things to say about that
		_show("")
		_hold = 0.0
		_redline = 0.0
		_lifted = 0.0
		return
	if _farewell > 0.0:
		_farewell -= dt
		if _farewell <= 0.0:
			done = true
			tip = ""
			events.append("coached")
		return
	if mph > GO_MPH:
		flown += dt
	squeezed = squeezed or float(grip[0]) > GENTLE or float(grip[1]) > GENTLE
	var both_in := float(thr[0]) >= FULL_LEVER and float(thr[1]) >= FULL_LEVER
	var both_out := float(thr[0]) < 0.1 and float(thr[1]) < 0.1
	# he has it: every part of it done, or long enough in the air
	# (the gearbox: a shift made when asked, or top gear reached somehow, or no gearbox)
	if flown >= ENOUGH_S or (went and steers >= 3 and (shifts >= 1 or bool(s.get("top", true)) or not bool(s.get("gears", false)))):
		_farewell = FAREWELL_S
		tip = "farewell"
		return
	# 1. go: both triggers, all the way, held
	if not went:
		_hold = _hold + dt if both_in else 0.0
		if _hold >= GO_HOLD_S:
			went = true
			_hold = 0.0
			_passed()
		else:
			_show("go")
			return
	# 2. a gear run out: shift
	if _gear < 0:
		_gear = gear
	if gear > _gear and tip == "shift":
		shifts += 1
		_passed()
	_gear = gear
	# (once it is up the line stays while the revs are anywhere near the limiter, which makes them hunt)
	var at_redline: bool = bool(s.get("gears", false)) and not bool(s.get("top", true)) and both_in and float(s.get("rpm", 0.0)) >= (0.9 if tip == "shift" else REDLINE)
	_redline = _redline + dt if at_redline else 0.0
	if _redline >= REDLINE_S:
		_show("shift")
		return
	# 3. the wall coming: steer off it, gently (held until he is well clear, so the line does not flicker)
	var toward := "left" if edge > 0.0 else "right"
	if absf(edge) >= NEAR_EDGE:
		_show(toward)
		return
	if tip in ["left", "right"]:
		if absf(edge) > CLEAR_EDGE:
			return
		steers += 1
		_passed()
	# 4. the power let go at speed
	_lifted = _lifted + dt if both_out and mph > GO_MPH else 0.0
	if _lifted >= LIFT_S:
		_show("power")
		return
	# 5. nobody has told him there are grips
	if not squeezed and flown >= UNSTEERED_S:
		_show("steer")
		return
	if tip == "steer":
		_passed()
	_show("")


## Its page for the glass, "" when it has nothing to say.
func message() -> String:
	if not on or done:
		return ""
	var grip: Array = _state.get("grip", [0.0, 0.0])
	match tip:
		"go":
			return "GO  COACH\nBOTH TRIGGERS > ALL THE WAY IN AND HOLD\nFULL OR NOTHING, AS ON THE BRAKE | %d%%" % roundi(clampf(_hold / GO_HOLD_S, 0.0, 1.0) * 100.0)
		"shift":
			return "SHIFT UP  GEAR %d\nRIGHT STICK > FLICK IT UP\nSHE STOPS PULLING AT THE REDLINE | COACH" % int(_state.get("gear", 1))
		"left", "right":
			var k := 0 if tip == "left" else 1
			var side := "LEFT" if k == 0 else "RIGHT"
			var wall := "RIGHT" if k == 0 else "LEFT"
			var note := "THE WALL IS ON YOUR %s" % wall
			if float(grip[k]) > TOO_HARD:
				note = "TOO HARD: EASE OFF TO A THIRD"
			elif float(grip[1 - k]) > GENTLE and float(grip[k]) <= GENTLE:
				note = "THE OTHER HAND: THE %s GRIP" % side
			return "STEER %s  COACH\n%s GRIP > SQUEEZE GENTLY\n%s | %d%%" % [side, side, note, roundi(clampf(float(grip[k]), 0.0, 1.0) * 100.0)]
		"power":
			return "POWER  COACH\nBOTH TRIGGERS > BACK IN\nSLOW WITH THE GRIPS, NOT BY LIFTING | LIFTED"
		"steer":
			return "STEER  COACH\nEITHER GRIP > SQUEEZE GENTLY\nLEFT GRIP LEFT, RIGHT GRIP RIGHT | TRY IT"
		"farewell":
			return "SHE IS YOURS  COACH\nTRIGGERS IN > GENTLE SQUEEZES\nFLIGHT SCHOOL IS IN THE QUICK MENU | DONE"
	return ""


## The same, short, for an instrument strip.
func line() -> String:
	var page := message()
	if page == "":
		return ""
	var lines := page.split("\n")
	return "%s\n%s" % [lines[0].replace("  ", "   "), lines[1]]
