## Actual input-event regressions for desktop keyboard/gamepad ownership.
## Run headless with --xr-mode off; no physical controller is required.
extends SceneTree

const LI := preload("res://input/lever_input.gd")
const View := preload("res://view/craft_view.gd")
const PAD := 7
var fails := 0


## Only device discovery is substituted: actual Godot axis/key events still feed
## the real polling and arbitration code. Headless Input cannot create a HID.
class TestInput extends LI:
	var connected := true
	var lever_present := false
	func _connected_pads() -> Array[int]:
		return ([7, 8] if lever_present else [7]) if connected else []
	func _classify_device(device: int) -> String:
		return "levers" if device == 8 else "gamepad"


func _initialize() -> void:
	var li = TestInput.new()
	_axes(0.8, 0.6, 0.4, 0.3)
	var out: Dictionary = li.poll(0.1)
	_check(_levers(out, 0.8, 0.6, 0.4, 0.3), "active gamepad supplies absolute levers")
	_axes(0.0, 0.0, 0.0, 0.0)
	out = li.poll(0.1)
	_check(_levers(out, 0.0, 0.0, 0.0, 0.0), "returning pad to neutral clears all pad-driven levers")

	_key(KEY_E, true)
	out = li.poll(0.5)
	_key(KEY_E, false)
	out = li.poll(0.1)
	_check(_levers(out, 0.45, 0.45, 0.0, 0.0), "idle connected pad preserves keyboard throttle latch")
	_axes(0.7, 0.9, 0.0, 0.0)
	out = li.poll(0.1)
	_check(_levers(out, 0.7, 0.9, 0.0, 0.0), "new pad input takes over keyboard latch")
	_key(KEY_X, true)
	out = li.poll(0.1)
	_check(_levers(out, 0.0, 0.0, 0.0, 0.0), "keyboard cut overrides a held pad")
	_key(KEY_X, false)
	out = li.poll(0.1)
	_check(_levers(out, 0.0, 0.0, 0.0, 0.0), "held pad cannot immediately reclaim after keyboard cut")
	_axes(0.0, 0.0, 0.0, 0.0)
	li.poll(0.1)
	_axes(0.5, 0.4, 0.0, 0.0)
	out = li.poll(0.1)
	_check(_levers(out, 0.5, 0.4, 0.0, 0.0), "neutral then fresh pad input reclaims control")
	li.connected = false
	out = li.poll(0.1)
	_check(_levers(out, 0.0, 0.0, 0.0, 0.0), "unplugging an active pad clears its throttle")
	li.connected = true
	li.lever_present = true
	_axes(0.9, 0.9, 0.0, 0.0)
	for pair in [[0, -0.4], [1, -0.6], [2, -1.0], [3, -1.0]]:
		_axis(8, pair[0], pair[1])
	out = li.poll(0.1)
	_check(_levers(out, 0.3, 0.2, 0.0, 0.0), "printed levers outrank an earlier-enumerated gamepad")
	_axes(0.0, 0.0, 0.0, 0.0)
	_test_arm(false)
	_test_arm(true)
	print("RELEASE INPUT ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)


func _test_arm(gamepad: bool) -> void:
	var device := "pad Y" if gamepad else "keyboard R"
	var view := View.new()
	view.levers = TestInput.new()
	# Exercise the flight's input reader and fixed sim step on a known course.
	var course := {"track": "range", "startY": -3000.0}
	view.sim = View.CraftSimScript.new(course)
	if gamepad:
		_axes(0.45, 0.45, 0.0, 0.0)
	else:
		_key(KEY_E, true)
		view._read_input(0.5)
		_key(KEY_E, false)
	_arm(gamepad, true)
	view._read_input(0.1)
	_check(not view.sim.armed and not view.inp.get("boost", false), device + " press waits for tap or hold")
	_arm(gamepad, false)
	view._read_input(0.01)
	_check(view.sim.armed and not view.inp.get("boost", false), device + " tap arms on release")
	view._read_input(0.01)
	_check(view.sim.armed, device + " idle frame preserves the arm state")

	_arm(gamepad, true)
	view._read_input(0.34)
	_check(view.sim.armed and not view.inp.get("boost", false), device + " stays below boost at 0.34 s")
	view._read_input(0.01)
	var plain := View.CraftSimScript.new(course)
	plain.armed = true
	var reference := view.inp.duplicate()
	reference.erase("boost")
	plain.step(reference, View.DT)
	view._sim_step()
	var thrust: float = view.sim.eL.thrust
	_check(view.sim.boost == 1 and plain.eL.thrust > 0 and is_equal_approx(thrust, plain.eL.thrust * 1.3),
		"%s at 0.35 s gives one stage and 1.3x thrust (%.6f vs %.6f)" % [device, thrust, plain.eL.thrust])
	view._read_input(0.2)
	view._sim_step()
	_check(view.sim.boost == 1 and view.sim.armed, device + " sustains boost without toggling ramjet")
	_arm(gamepad, false)
	view._read_input(0.01)
	view._sim_step()
	_check(view.sim.boost == 0 and view.sim.armed, device + " release stops boost without toggling ramjet")
	_arm(gamepad, true)
	view._read_input(0.05)
	_arm(gamepad, false)
	view._read_input(0.01)
	_check(not view.sim.armed, device + " next tap disarms")
	_axes(0.0, 0.0, 0.0, 0.0)
	view.free()


func _arm(gamepad: bool, down: bool) -> void:
	if not gamepad:
		_key(KEY_R, down)
		return
	var event := InputEventJoypadButton.new()
	event.device = PAD
	event.button_index = JOY_BUTTON_Y
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _axes(left: float, right: float, brake_left: float, brake_right: float) -> void:
	for pair in [[JOY_AXIS_LEFT_Y, -left], [JOY_AXIS_RIGHT_Y, -right],
			[JOY_AXIS_TRIGGER_LEFT, brake_left], [JOY_AXIS_TRIGGER_RIGHT, brake_right]]:
		_axis(PAD, pair[0], pair[1])


func _axis(device: int, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _levers(out: Dictionary, l: float, r: float, bl: float, br: float) -> bool:
	return is_equal_approx(out.thrL, l) and is_equal_approx(out.thrR, r) \
		and is_equal_approx(out.brkL, bl) and is_equal_approx(out.brkR, br)


func _check(ok: bool, message: String) -> void:
	fails += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + message)
