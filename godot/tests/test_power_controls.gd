## The craft's power's controls (sim/pilot_craft.gd TRAITS; Luke, 2026-11-24: "build the attributes and powers into
## the game"): the guarded POWER switch (ARM / SAFE) on the left console's inboard face and its button beside it
## (vr_cockpit.gd, vr/power_button.gd), the keyboard's P in the flat view, and what the power says and shows.
##   built      the switch (a ModeSwitch: ARM up, SAFE down) and the button on the port console's inboard face, the
##              button over the switch and carrying the power's name; ARM unless saved otherwise
##   by hand    a tip pushed down through the switch's box throws it to SAFE (saved "power": "safe"), up to ARM; a
##              fingertip brought in to the button's cap fires the power: the Orrery's Gyro Lock runs the next step,
##              its word is on the status strip, and its ring pulses; at SAFE the button fires nothing
##   the ring   dark while the power charges, steady when it is ready, pulsing while it runs; dark at SAFE
##   not by accident   the hand's way to each of the left console's toggles and back throws nothing of it, nor its way
##              from the grip at half and at full throttle to the SLIDE switch over them and back (they stand under that
##              switch, beside the lever, since flight 34), and the drift slider's knob, wherever it stands, is out of
##              the switch's box
##   the flat view     P fires the power (the autopilot is O now)
##   the drift reach   the Orrery's cockpit steps out 0.8 as far as the Phaethon's in the same turn (the view's own)
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_power_controls.gd -- --mute
## Prints POWER CONTROLS PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Console := preload("res://vr/console_switches.gd")
const Switch := preload("res://vr/mode_switch.gd")
const PowerButton := preload("res://vr/power_button.gd")
const Drift := preload("res://vr/drift_slider.gd")
const FRAME := 1.0 / 90.0
var v
var hl: XRController3D
var hr: XRController3D
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_power_controls_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit.slide_feel = true
	Cockpit.slide_amount = 1.0
	Cockpit._rush_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._options_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


func _cockpit(vehicle: String) -> void:
	View.vehicle_override = vehicle
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.hands_live = true
	v._await_neutral_controls = false


## A controller placed so that its tip is at `tip` (cockpit-rig metres: the shell's frame).
func _put(h: Node3D, tip: Vector3) -> void:
	var g: Transform3D = v.shell.global_transform
	h.global_transform = Transform3D(g.basis, g * tip - g.basis * Switch.TIP)


func _tick(dt := FRAME) -> void:
	v._work_controls(hl, hr, dt)
	v.power_switch.show_state(not v.power_armed, 0.0 if v.power_armed else 1.0, false)
	v.power_button.show_state(v.power_ring(), 1.0, dt)


func _park(h: Node3D) -> void:
	_put(h, Vector3(0.0, 0.55, 0.25))


## Carry a hand's tip from one place to another at `speed` m/s (the other hand parked).
func _move(h: Node3D, from: Vector3, to: Vector3, speed: float) -> void:
	var other: Node3D = hr if h == hl else hl
	var steps := maxi(1, int(ceil(from.distance_to(to) / (speed * FRAME))))
	for k in range(1, steps + 1):
		_put(h, from.lerp(to, float(k) / steps))
		_park(other)
		_tick()


func _rest(h: Node3D, at: Vector3, seconds: float) -> void:
	var other: Node3D = hr if h == hl else hl
	for k in int(seconds / FRAME):
		_put(h, at + Vector3(0.0002 * sin(k * 1.7), 0.0002 * cos(k * 2.3), 0.0))
		_park(other)
		_tick()


## A point on the switch's panel (its own metres, unscaled), in the rig's.
func _on_switch(p: Vector3) -> Vector3:
	return v.power_switch.transform * p


func _on_button(p: Vector3) -> Vector3:
	return v.power_button.transform * p


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(Cockpit.PREFS)
	var prefs_before := FileAccess.get_file_as_bytes(Cockpit.PREFS) if prefs_existed else PackedByteArray()
	if prefs_existed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	Cockpit._power_loaded = false
	View.power_armed = true
	await _cockpit("orrery")
	hl = XRController3D.new()
	hr = XRController3D.new()
	root.add_child(hl)
	root.add_child(hr)
	_park(hl)
	_park(hr)

	# ---- built
	var sw = v.power_switch
	var bt = v.power_button
	var sw_at: Vector3 = sw.position
	var bt_at: Vector3 = bt.position
	_check("the POWER switch is a guarded toggle (ARM up, SAFE down) on the port console's inboard face (%.3f, %.3f, %.3f)" % [sw_at.x, sw_at.y, sw_at.z],
		sw != null and sw.get_script() == Switch and sw.legends == ["ARM", "SAFE"] and sw_at.x < -0.5 and sw_at.x > -0.56 and sw_at.y < 0.38)
	_check("its button stands over it on the same face (%.0f mm apart; since flight 34, at the grip's height), with the power's name: \"%s\"" % [sw_at.distance_to(bt_at) * 1000.0, bt.legend.text],
		bt != null and bt_at.y > sw_at.y + 0.08 and absf(bt_at.x - sw_at.x) < 0.02 and sw_at.distance_to(bt_at) < 0.13 and bt.legend.text.replace("\n", " ") == "GYRO LOCK")
	_check("ARM unless saved otherwise; the Orrery's power is ready, its ring steady", v.power_armed and v.sim.power == "gyro" and v.sim.power_state == "ready" and v.power_ring() == "steady")

	# ---- the switch by hand: a tip pushed down through its box, then up
	var top := _on_switch(Vector3(0.0, 0.06, 0.07))
	var foot := _on_switch(Vector3(0.0, -0.06, 0.07))
	var from := _on_switch(Vector3(0.0, 0.06, 0.25))
	_move(hl, Vector3(-0.3, 0.55, 0.45), from, 0.5)
	_move(hl, from, top, 0.4)
	_move(hl, top, foot, 0.5)
	_check("pushed down through its box it is thrown to SAFE, and saved (\"power\": \"%s\"); the ring goes dark" % _saved().get("power", ""),
		not v.power_armed and _saved().get("power", "") == "safe" and v.power_ring() == "dark" and sw.down)
	var face := _on_button(bt.face_at())
	var out := _on_button(bt.face_at() + Vector3(0.0, 0.0, 0.06))
	var clear_foot := _on_switch(Vector3(0.0, -0.06, 0.24))      # (out of the switch's box along its face's normal before going anywhere)
	var clear_top := _on_switch(Vector3(0.0, 0.06, 0.24))
	_move(hl, foot, clear_foot, 0.4)
	_move(hl, clear_foot, out, 0.4)
	_rest(hl, out, Console.CLAIM_S + 0.1)
	_move(hl, out, face, 0.25)
	v.sim.step(v.inp.merged({"power": View.power_armed, "powerFire": v._power_fire}), 1.0 / 480.0)
	v.sim.events.clear()
	_check("at SAFE its button fires nothing (%s)" % v.sim.power_state, v.sim.power_state == "ready" and not v._power_fire)
	_move(hl, face, out, 0.3)
	_move(hl, out, clear_foot, 0.4)
	_move(hl, clear_foot, foot, 0.4)
	_rest(hl, foot, Switch.COOLDOWN + 0.1)
	_move(hl, foot, top, 0.5)
	_check("pushed up through its box it is thrown back to ARM (\"power\": \"%s\")" % _saved().get("power", ""), v.power_armed and _saved().get("power", "") == "arm" and not sw.down)

	# ---- the button by hand: a fingertip in to its cap
	_move(hl, top, clear_top, 0.4)
	_move(hl, clear_top, out, 0.4)
	_rest(hl, out, Console.CLAIM_S + 0.1)
	_move(hl, out, face, 0.25)
	var asked: bool = v._power_fire
	v._sim_step()      # (the next step of the sim: the button's press goes with it)
	var fired: bool = v.sim.power_state == "active"
	_check("a fingertip in to its cap fires the power: Gyro Lock runs (%s, grip x%.2f), its word on the status strip (\"%s\"), its ring pulsing" % [
		v.sim.power_state, v.sim.k_grip, v._strip_feat()[0]], asked and fired and is_equal_approx(v.sim.k_grip, 1.13 * 1.2)
		and v._strip_feat()[0] == "GYRO LOCK" and v.power_ring() == "pulse")
	v.sim.power_state = "charging"
	_check("charging, its ring is dark", v.power_ring() == "dark")
	v.sim.power_state = "ready"
	_move(hl, face, out, 0.3)
	_park(hl)

	# ---- not by accident: the hand's way to each of the left console's toggles and back
	var was_armed: bool = v.power_armed
	var presses := 0
	for i in 3:
		var bat := Console.toggle_at(i) + Vector3(0.0, 0.03, 0.0)
		var into: Transform3D = v.console.transform      # (the consoles' metres to the interior's: the same as the rig's but for the interior's own place)
		var bat_rig: Vector3 = v.interior.transform * (into * bat)
		var grip: Vector3 = v.lever_pivots[0].transform * Vector3(0.0, 0.39, 0.0)
		var high := bat_rig.y + 0.05
		var way := [grip, Vector3(grip.x, high, grip.z), Vector3(grip.x, high, bat_rig.z), Vector3(bat_rig.x, high, bat_rig.z), bat_rig]
		for k in range(1, way.size()):
			_move(hl, way[k - 1], way[k], 0.5)
			presses += int(v._power_fire)
			v._power_fire = false
		way.reverse()
		for k in range(1, way.size()):
			_move(hl, way[k - 1], way[k], 0.5)
			presses += int(v._power_fire)
			v._power_fire = false
	_check("the hand's way from the left lever to each of the console's toggles and back throws the switch nowhere (%s) and presses the button %d times" % [
		"ARM" if v.power_armed else "SAFE", presses], v.power_armed == was_armed and presses == 0)
	# ... and to the SLIDE switch over them, from the grip at half and at full throttle: up to its bat, a throw down and
	# one up (a second apart), and back
	presses = 0
	var slide_bat: Vector3 = v.slide_switch.transform * Vector3(0.0, 0.0, 0.07)
	var slide_up: Vector3 = v.slide_switch.transform * Vector3(0.0, 0.06, 0.07)
	var slide_down: Vector3 = v.slide_switch.transform * Vector3(0.0, -0.06, 0.07)
	var slide_off: Vector3 = v.slide_switch.transform * Vector3(0.0, 0.06, 0.2)
	for thr in [0.5, 1.0]:
		v.lever_pivots[0].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
		var grip: Vector3 = v.lever_pivots[0].transform * Vector3(0.0, 0.39, 0.0)
		var there := [grip, slide_bat, slide_up]
		for k in range(1, there.size()):
			_move(hl, there[k - 1], there[k], 0.5)
		_move(hl, slide_up, slide_down, 0.5)
		_rest(hl, slide_down, Switch.COOLDOWN + 0.1)
		_move(hl, slide_down, slide_up, 0.5)
		var back := [slide_up, slide_off, grip]
		for k in range(1, back.size()):
			_move(hl, back[k - 1], back[k], 0.5)
		presses += int(v._power_fire)
		v._power_fire = false
	v.lever_pivots[0].rotation.x = 0.0
	_check("nor its way from the grip at half and at full throttle to the SLIDE switch, throwing it, and back (%s, the button pressed %d times)" % [
		"ARM" if v.power_armed else "SAFE", presses], v.power_armed == was_armed and presses == 0)
	# ... and the button's own use in flight: from the grip at half and at full throttle down to its cap, a press, and
	# back to the grip, the switch under it is not thrown
	presses = 0
	var cap_out := _on_button(bt.face_at() + Vector3(0.0, 0.0, 0.05))
	var cap_in := _on_button(bt.face_at())
	for thr in [0.5, 1.0]:
		v.lever_pivots[0].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
		var grip: Vector3 = v.lever_pivots[0].transform * Vector3(0.0, 0.39, 0.0)
		_move(hl, grip, cap_out, 0.5)
		_rest(hl, cap_out, Console.CLAIM_S + 0.1)
		_move(hl, cap_out, cap_in, 0.25)
		presses += int(v._power_fire)
		v._power_fire = false
		_move(hl, cap_in, cap_out, 0.3)
		_move(hl, cap_out, grip, 0.5)
		_rest(hl, grip, 0.6)
	v.lever_pivots[0].rotation.x = 0.0
	_check("its way from the grip at half and at full throttle to the button, a press, and back fires it each time (%d of 2) and throws the switch nowhere (%s)" % [
		presses, "ARM" if v.power_armed else "SAFE"], v.power_armed == was_armed and presses == 2)
	var inside := 0
	var into_switch: Transform3D = sw.global_transform.affine_inverse() * v.shell.global_transform
	for a in [0.0, Drift.STANDARD, Drift.AMOUNT_MAX]:
		var cap: Vector3 = v.drift_slider.transform * Vector3(Drift.place(a), 0.0, Drift.CAP_Z)
		var q: Vector3 = into_switch * cap
		inside += int(absf(q.x) < Switch.ZONE.x and absf(q.y) < Switch.ZONE.y and q.z > -0.01 and q.z < Switch.ZONE.z)
	_check("the drift slider's knob, at either end and in its notch, is out of the POWER switch's box (%d in it)" % inside, inside == 0)

	# ---- the drift reach: the Orrery's cockpit steps out 0.8 of the Phaethon's
	_check("the Orrery's drift reach is 0.8 (the view's: %.2f)" % v.drift_reach(), is_equal_approx(v.drift_reach(), 0.8))
	v.free()
	await process_frame

	# ---- the flat view: P fires it, O is the autopilot
	View.vehicle_override = "orrery"
	View.power_armed = true
	var flat = View.new()
	root.add_child(flat)
	await process_frame
	flat.set_process(false)
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_P
	flat._unhandled_key_input(key)
	var p_fired: bool = flat._power_fire
	flat._sim_step()
	_check("in the flat view P fires it (%s), and the line under the speed says so (\"%s\")" % [flat.sim.power_state, flat.flash_msg],
		p_fired and flat.sim.power_state == "active" and flat.flash_msg == "GYRO LOCK")
	flat.free()
	await process_frame

	# ---- Slipstream's eyes (view/network_traffic.gd draft_gap): a craft at the origin going +x at 1,000 mph
	var Traffic := preload("res://view/network_traffic.gd")
	var tr = Traffic.new()
	var gaps := {}
	for case: Array in [["80 m ahead in its lane", 80.0, 5.0, 1.0, 0], ["80 m ahead, a lane over", 80.0, 30.0, 1.0, 0],
			["150 m ahead", 150.0, 0.0, 1.0, 0], ["80 m ahead, coming the other way", 80.0, 0.0, -1.0, 0],
			["a transport's tractor 300 m ahead, its last car 34 m", 300.0, 0.0, 1.0, Traffic.TRANSPORT]]:
		var c = Traffic.Car.new()
		c.x = float(case[1])
		c.y = float(case[2])
		c.hx = float(case[3])
		c.hy = 0.0
		c.v = 300.0
		c.kind = int(case[4])
		tr.cars.clear()
		tr.cars.append(c)
		gaps[case[0]] = tr.draft_gap(0.0, 0.0, 447.0, 0.0, 120.0, 22.0)
	_check("Slipstream drafts a vehicle in its lane within 120 m (%s), and none a lane over, further, or coming the other way (%s, %s, %s); a train by its last car (%s m)" % [
		gaps["80 m ahead in its lane"], gaps["80 m ahead, a lane over"], gaps["150 m ahead"], gaps["80 m ahead, coming the other way"],
		gaps["a transport's tractor 300 m ahead, its last car 34 m"]],
		is_equal_approx(gaps["80 m ahead in its lane"], 80.0) and gaps["80 m ahead, a lane over"] == INF and gaps["150 m ahead"] == INF
		and gaps["80 m ahead, coming the other way"] == INF and is_equal_approx(gaps["a transport's tractor 300 m ahead, its last car 34 m"], 300.0 - 7 * 38.0))
	tr.free()

	# ---- the Basilisk's: its gun's heat (view/gunnery.gd) and the raised turret's drag
	View.vehicle_override = "basilisk"
	var gun_view = View.new()
	root.add_child(gun_view)
	await process_frame
	gun_view.set_process(false)
	var g = preload("res://view/gunnery.gd").new()
	g.view = gun_view
	var t := 0.0
	var hot_at := -1.0
	var cool_at := -1.0
	for i in int(8.0 / FRAME):      # the trigger held on a target the whole while: it fires whenever it can
		var was: bool = g.firing
		g.firing = g.hot <= 0.0
		g._heat_step(FRAME, was)
		t += FRAME
		if g.hot > 0.0 and hot_at < 0.0:
			hot_at = t
		if hot_at > 0.0 and cool_at < 0.0 and g.hot == 0.0:
			cool_at = t
	_check("the Basilisk's gun held on overheats after %.2f s of fire (4) and fires again %.2f s later (3)" % [hot_at, cool_at - hot_at],
		absf(hot_at - 4.0) <= 1.5 * FRAME and absf(cool_at - hot_at - 3.0) <= 1.5 * FRAME)
	g.free()
	gun_view.craft.turret.t = 0.5
	gun_view._sim_step()
	var out_drag: float = gun_view.sim.k_drag
	gun_view.craft.turret.t = 0.0
	gun_view._sim_step()
	_check("its turret up, the sims are told (inp.turretOut) and its drag is x%.3f of its own (1.04); stowed, x%.3f" % [out_drag / 1.02, gun_view.sim.k_drag / 1.02],
		is_equal_approx(out_drag, 1.02 * 1.04) and is_equal_approx(gun_view.sim.k_drag, 1.02))
	gun_view.free()
	await process_frame

	if prefs_existed:
		var f := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		f.store_buffer(prefs_before)
		f.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	View.vehicle_override = ""
	print("POWER CONTROLS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
