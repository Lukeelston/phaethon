## Lever input. Priority: the printed levers (an unrecognised HID joystick: axes 0-3 =
## L/R throttle, L/R brake, buttons 0-3 = reignite, arm, repair, respawn), then a known
## gamepad (sticks as levers, triggers as brakes), then the keyboard with the feel lab's bindings.
class_name LeverInput
extends RefCounted

var thr_l := 0.0
var thr_r := 0.0
var brk_l := 0.0
var brk_r := 0.0
var source := "Keyboard"
var _latch := {}


## Returns {thrL, thrR, brkL, brkR, repair, reignite, arm, respawn}; arm and respawn are
## true only on the frame the control is first pressed.
func poll(delta: float) -> Dictionary:
	var held := {"repair": false, "reignite": false, "arm": false, "respawn": false}
	if not _poll_pad(held):
		source = "Keyboard"
		_poll_keys(delta, held)
	var out := {"thrL": thr_l, "thrR": thr_r, "brkL": brk_l, "brkR": brk_r,
		"repair": held.repair, "reignite": held.reignite}
	for k in ["arm", "respawn"]:
		out[k] = held[k] and not _latch.get(k, false)
		_latch[k] = held[k]
	return out


## Set both levers to the lower of the two: corner exit, sway recovery, straight-line reset.
func level_to_lower() -> void:
	var m := minf(thr_l, thr_r)
	thr_l = m
	thr_r = m


## Names the printed levers' Pico may enumerate as.
const LEVER_NAMES := ["phaethon", "pico"]


## "levers" for the printed lever controller, "gamepad" for a recognised gamepad,
## "ignore" for anything else. Unknown HID devices are NOT assumed to be levers:
## analog keyboards (Keychron K10 HE) and pedals rest at 0.0, which reads as 50% throttle.
static func classify_pad(joy_name: String, known: bool) -> String:
	var n := joy_name.to_lower()
	for want in LEVER_NAMES:
		if n.contains(want):
			return "levers"
	return "gamepad" if known else "ignore"


func _poll_pad(held: Dictionary) -> bool:
	var d := -1
	var kind := "ignore"
	for pad in Input.get_connected_joypads():
		kind = classify_pad(Input.get_joy_name(pad), Input.is_joy_known(pad))
		if kind != "ignore":
			d = pad
			break
	if d < 0:
		return false
	var l: float
	var r: float
	var bl: float
	var br: float
	if kind == "gamepad":
		l = maxf(0.0, -Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		r = maxf(0.0, -Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		bl = Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT)
		br = Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT)
		held.reignite = Input.is_joy_button_pressed(d, JOY_BUTTON_A)
		held.repair = Input.is_joy_button_pressed(d, JOY_BUTTON_X)
		held.arm = Input.is_joy_button_pressed(d, JOY_BUTTON_Y)
		held.respawn = Input.is_joy_button_pressed(d, JOY_BUTTON_BACK)
	else:
		l = _unit(Input.get_joy_axis(d, 0))
		r = _unit(Input.get_joy_axis(d, 1))
		bl = _unit(Input.get_joy_axis(d, 2))
		br = _unit(Input.get_joy_axis(d, 3))
		held.reignite = Input.is_joy_button_pressed(d, 0)
		held.arm = Input.is_joy_button_pressed(d, 1)
		held.repair = Input.is_joy_button_pressed(d, 2)
		held.respawn = Input.is_joy_button_pressed(d, 3)
	var active := l > 0.04 or r > 0.04 or bl > 0.04 or br > 0.04 or held.values().has(true)
	if not active:
		return false
	thr_l = l
	thr_r = r
	brk_l = bl
	brk_r = br
	source = "Gamepad: " + Input.get_joy_name(d).left(32)
	return true


static func _unit(axis: float) -> float:   # HID axis -1..1 -> 0..1
	return clampf((axis + 1.0) / 2.0, 0.0, 1.0)


func _poll_keys(delta: float, held: Dictionary) -> void:
	var k := func(key: Key) -> bool: return Input.is_key_pressed(key)
	var up := 0.9 * delta
	var down := 1.4 * delta
	if k.call(KEY_W) or k.call(KEY_E): thr_l += up
	if k.call(KEY_S) or k.call(KEY_D): thr_l -= down
	if k.call(KEY_UP) or k.call(KEY_E): thr_r += up
	if k.call(KEY_DOWN) or k.call(KEY_D): thr_r -= down
	if k.call(KEY_X):
		thr_l = 0.0
		thr_r = 0.0
	thr_l = clampf(thr_l, 0.0, 1.0)
	thr_r = clampf(thr_r, 0.0, 1.0)
	brk_l = clampf(brk_l + (6.0 if k.call(KEY_A) else -8.0) * delta, 0.0, 1.0)
	brk_r = clampf(brk_r + (6.0 if k.call(KEY_RIGHT) else -8.0) * delta, 0.0, 1.0)
	held.reignite = k.call(KEY_SPACE)
	held.repair = k.call(KEY_H)
	held.arm = k.call(KEY_R)
	held.respawn = k.call(KEY_BACKSPACE)
