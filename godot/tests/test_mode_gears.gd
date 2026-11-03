## Handling-specific gearbox through the actual cockpit, tracked controls, HUD and audio input.
extends SceneTree

const VR := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 72.0

class Probe extends "res://vr/vr_cockpit.gd":
	func _load_prefs() -> Dictionary:
		return {"scheme": "triggers", "handling": "speed"}

	func _save_prefs() -> void:
		pass

var view
var pads := {}
var checks := 0
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	VR.track_override = "range"
	for side in ["left", "right"]:
		var tracker := XRControllerTracker.new()
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.name = "%s_hand" % side
		XRServer.add_tracker(tracker)
		pads[side] = tracker
	view = Probe.new()
	root.add_child(view)
	view.set_process(false)
	_tick()
	_check("Speedcraft starts in displayed first with the old second audio profile", view.quest.gear == 1 and view.dashboard.labels.gear.text == "1" and view._engine_inp().gearIndex == 1)
	_speed(397.68)
	for frame in 120:
		_tick()
	_check("Speedcraft first retains old second pull, steering and 795.36 m/s reference", absf(view.inp.gearRpm - 0.5) < 0.001 and absf(view.inp.thrMul - 1.3) < 0.001 and absf(view.quest.steer_k - 0.75 / 1.3) < 0.001)
	_flick(-1.0)
	_check("Speedcraft cannot downshift into the Starfighter profile", view.quest.gear == 1 and view.dashboard.labels.gear.text == "1")
	for i in 5:
		_flick(1.0)
	_check("Speedcraft stops at displayed fourth and forwards unlimited audio and physics", view.quest.gear == 4 and view.dashboard.labels.gear.text == "4" and view.inp.gearOverdrive and view._engine_inp().gearOverdrive and view.dashboard.labels.gear.modulate == view.dashboard.ORANGE)
	_speed(1500.0)
	view.ask_handling("starfighter")
	for frame in 40:
		view._sim_step()
		_tick()
	_check("queued Starfighter at high speed keeps the actual Speedcraft gearbox", view.sim.hblend == 0.0 and view.quest.gear == 4 and view.inp.gearOverdrive)
	_speed(300.0)
	pads.right.set_input("primary", Vector2(0.0, 1.0))
	for frame in 600:
		view._sim_step()
		_tick()
	_check("engaged Starfighter selects its single first and bounded audio", view.sim.P.handling == "starfighter" and view.quest.gear == 0 and view.dashboard.labels.gear.text == "1" and view._engine_inp().gearIndex == 0 and not view.inp.gearOverdrive and not view._engine_inp().has("gearSpoolL"))
	for y in [-1.0, 1.0, -1.0, 1.0]:
		_flick(y)
	_check("right-stick flicks cannot shift Starfighter", view.quest.gear == 0 and view.dashboard.labels.gear.text == "1")
	_speed(400.0)
	_tick()
	_check("Starfighter first has full steering, full normal pull and full-range revs", absf(view.quest.steer_k - 1.0) < 0.001 and absf(view.inp.get("thrMul", -1.0) - 1.0) < 0.001 and absf(view.inp.get("gearRpm", -1.0) - 400.0 / 443.0) < 0.001)
	pads.left.set_input("primary", Vector2(0.0, 1.0))
	_tick()
	_check("Starfighter's sole gear permits the burner", view.inp.burner)
	pads.left.set_input("primary", Vector2.ZERO)
	pads.right.set_input("primary", Vector2(0.0, 1.0))
	_tick()
	view.handling_ask = "speed"
	for frame in 600:
		view._sim_step()
		_tick()
	_check("entering Speedcraft resets to first without a shift from the held stick", view.sim.hblend == 0.0 and view.quest.gear == 1 and view.dashboard.labels.gear.text == "1" and not view.inp.burner)
	_flick(1.0)
	_check("releasing then flicking after the mode change shifts normally", view.quest.gear == 2 and view.dashboard.labels.gear.text == "2")
	view.quest.set_gear(4)
	view._respawn()
	_tick()
	_check("Speedcraft respawn resets the displayed and audio gear to first", view.quest.gear == 1 and view.dashboard.labels.gear.text == "1" and view._engine_inp().gearIndex == 1)
	view.set_handling("starfighter")
	_tick()
	_check("direct handling changes and respawn select Starfighter first immediately", view.quest.gear == 0 and view.dashboard.labels.gear.text == "1" and not view.inp.gearOverdrive)
	view.queue_free()
	await process_frame
	for tracker in pads.values():
		XRServer.remove_tracker(tracker)
	pads.clear()
	print("MODE GEARS %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(int(fails > 0))

func _speed(speed: float) -> void:
	for body in view.sim.bodies:
		body.vx = speed * cos(view.sim.pair_th)
		body.vy = speed * sin(view.sim.pair_th)

func _tick() -> void:
	view._diag_t = -1.0
	view._read_input(DT)
	view._update_hud()

func _flick(y: float) -> void:
	pads.right.set_input("primary", Vector2.ZERO)
	_tick()
	pads.right.set_input("primary", Vector2(0.0, y))
	_tick()

func _check(label: String, ok: bool) -> void:
	checks += 1
	fails += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)
