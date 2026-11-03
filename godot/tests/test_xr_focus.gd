## Focus-loss gate, through the real VR cockpit (XR off, the controllers faked as XR trackers): when
## the OpenXR session stops being focused, OpenXR freezes the controllers' last state, and Luke's
## headset log (2026-10-20) had the pod flying on at full trigger with nobody aboard (session_stopping,
## then "L trig=1.00 R trig=1.00 | inp thr=1.00/1.00 | v=7991 km/h" for minutes). Both controllers
## must read as let go until session_focussed: the levers and brakes drop to 0, buttons do nothing (a
## button held as it went is no tap), the keyboard still flies, and with focus back the triggers ramp
## in again. A held lever (sticks, grab, mixed) goes to idle too and stays there till it's moved.
## Before any session event (a flat run) the controllers are live. Prints XR FOCUS PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_xr_focus.gd -- --mute
extends SceneTree

const VRScript := preload("res://vr/vr_cockpit.gd")


## The cockpit, counting restarts, and never writing user://vr_prefs.json: the headset build may be
## running beside the gate, saving Luke's scheme and handling to the same file.
class Probe extends "res://vr/vr_cockpit.gd":
	var respawns := 0
	var saves := 0

	func _respawn() -> void:
		respawns += 1
		super()

	func _save_prefs() -> void:
		saves += 1


var v
var pads := {}   # side -> the fake XRControllerTracker its XRController3D reads
var t := 0.0
var fails := 0
var passed := 0
var step := -1
var live := {}
var off_max := 0.0
var vis_max := 0.0
var kbd_min := INF
var armed0 := false
var handling0 := ""
var respawns0 := 0
var first_back := -1.0
var back := {}
var unfocused := {}   # what the buttons did while the session was away
var held_live := 0.0
var held_off := 0.0
var held_back := 0.0


func _initialize() -> void:
	VRScript.track_override = "range"
	v = Probe.new()
	root.add_child(v)
	for side in ["left", "right"]:
		var tr := XRControllerTracker.new()
		tr.type = XRServer.TRACKER_CONTROLLER
		tr.name = "%s_hand" % side
		XRServer.add_tracker(tr)
		pads[side] = tr
		tr.set_input("trigger", 1.0)   # both triggers squeezed all the way ...
		tr.set_input("grip", 0.5)      # ... and both air brakes half in


func _inp_max() -> float:
	return maxf(maxf(v.inp.thrL, v.inp.thrR), maxf(v.inp.brkL, v.inp.brkR))


func _process(delta: float) -> bool:
	t += delta
	match step:
		-1:   # the cockpit is ready by the first frame
			v.quest.scheme = "triggers"
			step = 0
		0:   # live (no session event yet, as in a flat run): the faked controllers fly the pod
			if t >= 1.8:
				live = v.inp.duplicate()
				pads.left.set_input("by_button", true)     # Y and the menu button held as the session goes
				pads.left.set_input("menu_button", true)
				armed0 = v.sim.armed
				handling0 = v.handling_ask
				respawns0 = v.respawns
				step = 1
		1:
			if t >= 2.0:
				v._on_xr_event("session_stopping")   # OpenXR keeps reporting the last state: full triggers
				step = 2
		2:
			if t >= 2.05:
				off_max = maxf(off_max, _inp_max())
			if t >= 2.2:
				pads.right.set_input("by_button", true)   # B (arm) pressed while unfocused
			if t >= 2.5:
				v.levers.thr_l = 0.4   # the keyboard's levers
				v.levers.thr_r = 0.4
				step = 3
		3:
			if t >= 2.6:
				kbd_min = minf(kbd_min, minf(v.inp.thrL, v.inp.thrR))
			if t >= 2.9:
				v.levers.thr_l = 0.0
				v.levers.thr_r = 0.0
				step = 4
		4:
			if t >= 3.0:
				v._on_xr_event("session_visible")   # visible without focus (the Link menu, say)
				step = 5
		5:
			if t >= 3.05:
				vis_max = maxf(vis_max, _inp_max())
			if t >= 3.2:
				for side in pads:
					pads[side].set_input("by_button", false)
					pads[side].set_input("menu_button", false)
			if t >= 3.5:
				v._on_xr_event("session_focussed")
				step = 6
		6:
			if first_back < 0.0:   # the first frame back: the trigger ramp starts again from idle
				first_back = maxf(v.inp.thrL, v.inp.thrR)
			if t >= 5.5:
				back = v.inp.duplicate()
				unfocused = {"armed": v.sim.armed, "respawns": v.respawns - respawns0, "scheme": v.quest.scheme,
					"handling": v.handling_ask, "saves": v.saves}
				v.quest.scheme = "sticks"   # a held lever: pushed to 0.6, it stays there when you let go
				v.quest.thr_l = 0.6
				v.quest.thr_r = 0.6
				step = 7
		7:
			if t >= 5.7:
				held_live = minf(v.inp.thrL, v.inp.thrR)
				v._on_xr_event("session_stopping")
				step = 8
		8:
			if t >= 5.75:
				held_off = maxf(held_off, maxf(v.inp.thrL, v.inp.thrR))
			if t >= 6.0:
				v._on_xr_event("session_focussed")
				step = 9
		9:
			if t >= 6.05:
				held_back = maxf(held_back, maxf(v.inp.thrL, v.inp.thrR))
			if t >= 6.3:
				_finish()
				return true
	return false


func _finish() -> void:
	_check("live (no session: a flat run): full triggers and half grips fly the pod (thr %.2f/%.2f, brk %.2f/%.2f)" % [
		live.thrL, live.thrR, live.brkL, live.brkR], live.thrL > 0.5 and live.thrR > 0.5 and live.brkL > 0.3 and live.brkR > 0.3)
	_check("session_stopping with OpenXR still reporting full triggers: levers and brakes at 0 (max %.3f)" % off_max, off_max == 0.0)
	_check("visible without focus: still let go (max %.3f)" % vis_max, vis_max == 0.0)
	_check("unfocused, the keyboard still flies (thr %.2f with its levers at 0.4)" % kbd_min, absf(kbd_min - 0.4) < 1e-6)
	var u := unfocused
	_check("unfocused, buttons do nothing: B pressed doesn't arm (armed %s -> %s), Y and menu held as it went aren't a tap or a hold (respawns %d, scheme %s, handling %s -> %s, prefs saves %d)" % [
		armed0, u.armed, u.respawns, u.scheme, handling0, u.handling, u.saves],
		u.armed == armed0 and u.respawns == 0 and u.scheme == "triggers" and u.handling == handling0 and u.saves == 0)
	_check("session_focussed: the triggers come back through the ramp (%.3f the first frame, %.2f/%.2f after 2 s; brk %.2f/%.2f)" % [
		first_back, back.thrL, back.thrR, back.brkL, back.brkR],
		first_back < 0.1 and back.thrL > 0.5 and back.thrR > 0.5 and back.brkL > 0.3 and back.brkR > 0.3)
	_check("sticks: a held lever (%.2f live) goes to idle as focus goes (max %.3f) and stays there with it back, till it's moved (max %.3f)" % [
		held_live, held_off, held_back], absf(held_live - 0.6) < 1e-6 and held_off == 0.0 and held_back == 0.0)
	for side in pads:
		XRServer.remove_tracker(pads[side])
	var good := fails == 0 and passed == 7
	print("XR FOCUS ", "PASS" if good else "FAIL (%d failed, %d passed)" % [fails, passed])
	quit(0 if good else 1)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
