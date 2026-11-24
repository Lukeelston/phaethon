## The GUN switch in every armed cockpit, and the gun's controls (Raids, 2026-11-24; Luke: "every vehicle should have
## their own weapon system like the basilisk's hidden cannon"). Stage 1: the craft with a weapon (sim/pilot_craft.gd
## WEAPONS, armed) are the Phaethon, the Talon and the Basilisk, and only their cockpits have the switch.
##   check_switch_built        a GunSwitch (GUN up, SAFE down) in the Phaethon's, the Talon's and the Basilisk's
##                             cockpits: the Phaethons' the same, on the starboard console's inboard face up front
##                             (vr_cockpit.gd gun_switch_mount), the Basilisk's on its sill where it has stood since
##                             2026-11-23; none in the Shrike's, the Orrery's, the Kiln's or the Vesper's
##   check_x_fires_when_armed  in the Phaethon and the Talon (on the range, at rest): the GUN switch pushed up by hand
##                             arms the gun; X held then fires it, and is not the repair; thrown down to SAFE by hand,
##                             X held is the repair again and fires nothing
##   check_menu_blocks_fire    armed and out, with the quick menu open X held fires nothing
##   check_not_by_accident     the right hand's way from its grip at half and at full throttle up to the MODE switch
##                             over the GUN switch, a throw down and one up, and back, throws the GUN switch nowhere,
##                             at SAFE or at GUN
##   check_flat_keys           in the flat view in the Phaethon, K arms its gun and F held fires it
## X is faked with an XRControllerTracker for the left hand (as tests/test_partner_menu.gd); the hands that throw the
## switches are the test's own controllers, worked through the cockpit's own _work_controls (as test_power_controls).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_gun_controls.gd -- --mute
## Prints GUN CONTROLS PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const Switch := preload("res://vr/mode_switch.gd")
const DT := 1.0 / 90.0
const SECTIONS := 6           # built; X in the Phaethon and in the Talon; the menu; not by accident; the flat view
var failures := 0
var checks := 0
var sections := 0             # (a section that dies on a script error never counts itself: the verdict then fails)
var v
var hl: XRController3D        # the hands that reach for the switches
var hr: XRController3D
var pad: XRControllerTracker  # the left controller's buttons: X


func _initialize() -> void:
	View.track_override = "range"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_gun_controls_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._rush_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit._options_loaded = true
	Cockpit._power_loaded = true
	Cockpit.power_armed = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + label)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(Cockpit.PREFS)
	var prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if prefs_existed else PackedByteArray()
	pad = XRControllerTracker.new()
	pad.type = XRServer.TRACKER_CONTROLLER
	pad.name = "left_hand"
	pad.set_pose("default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	XRServer.add_tracker(pad)
	hl = XRController3D.new()
	hr = XRController3D.new()
	root.add_child(hl)
	root.add_child(hr)

	await check_switch_built()
	for id: String in [Craft.STANDARD, Craft.TALON]:
		print(id)
		await _cockpit(id)
		var armed := check_x_fires_when_armed(id)
		if armed and id == Craft.STANDARD:
			check_menu_blocks_fire()
			check_not_by_accident()
		v.free()
		await process_frame
	await check_flat_keys()

	XRServer.remove_tracker(pad)
	hl.free()
	hr.free()
	View.vehicle_override = ""
	if prefs_existed:
		var f := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		f.store_buffer(prefs)
		f.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	check("every section ran to its end (%d of %d)" % [sections, SECTIONS], sections == SECTIONS)
	print("GUN CONTROLS %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


# --- the cockpit and the hands ---------------------------------------------------------------------------

func _cockpit(id: String) -> void:
	View.vehicle_override = id
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.hands_live = true
	v._await_neutral_controls = false
	_park(hl)
	_park(hr)


## A controller placed so that its tip is at `tip` (cockpit-rig metres: the shell's frame).
func _put(h: Node3D, tip: Vector3) -> void:
	var g: Transform3D = v.shell.global_transform
	h.global_transform = Transform3D(g.basis, g * tip - g.basis * Switch.TIP)


func _park(h: Node3D) -> void:
	_put(h, Vector3(0.0, 0.55, 0.25))


## The reaching hands' frame: the switches worked, and shown as the cockpit shows them.
func _tick(dt := DT) -> void:
	v._work_controls(hl, hr, dt)
	v.gun_switch.show_state(not v.gun_wanted, 0.0 if v.gun_wanted else 1.0, false)
	v.mode_switch.show_state(v.handling_ask == "starfighter", v.sim.hblend, false)


## Carry a hand's tip from one place to another at `speed` m/s (the other hand parked).
func _move(h: Node3D, from: Vector3, to: Vector3, speed: float) -> void:
	var other: Node3D = hr if h == hl else hl
	var steps := maxi(1, int(ceil(from.distance_to(to) / (speed * DT))))
	for k in range(1, steps + 1):
		_put(h, from.lerp(to, float(k) / steps))
		_park(other)
		_tick()


func _rest(h: Node3D, at: Vector3, seconds: float) -> void:
	var other: Node3D = hr if h == hl else hl
	for k in int(seconds / DT):
		_put(h, at + Vector3(0.0002 * sin(k * 1.7), 0.0002 * cos(k * 2.3), 0.0))
		_park(other)
		_tick()


## A point on the GUN switch's panel (its own metres, unscaled), in the shell's.
func _on_gun(p: Vector3) -> Vector3:
	return v.gun_switch.transform * p


## The right grip's middle at a throttle (the shell's frame), its lever stood there.
func _grip(thr: float) -> Vector3:
	v.lever_pivots[1].rotation.x = deg_to_rad(lerpf(30.0, -30.0, thr))
	return v.lever_pivots[1].transform * Vector3(0.0, 0.39, 0.0)


## The right hand from its grip at half throttle to the GUN switch, a push up (from below) or down (from above)
## through its box, and back out along its face: what the push threw.
func _throw_gun(up: bool) -> bool:
	var was: bool = v.gun_wanted
	var grip := _grip(0.5)
	var start := _on_gun(Vector3(0.0, -0.06 if up else 0.06, 0.07))
	var end := _on_gun(Vector3(0.0, 0.06 if up else -0.06, 0.07))
	var out := _on_gun(Vector3(0.0, -0.06 if up else 0.06, 0.25))
	_move(hr, grip, out, 0.5)
	_move(hr, out, start, 0.4)
	_rest(hr, start, Switch.COOLDOWN + 0.1)
	_move(hr, start, end, 0.5)
	var thrown: bool = v.gun_wanted != was
	_move(hr, end, _on_gun(Vector3(0.0, 0.06 if up else -0.06, 0.25)), 0.4)
	_move(hr, _on_gun(Vector3(0.0, 0.06 if up else -0.06, 0.25)), grip, 0.5)
	v.lever_pivots[1].rotation.x = 0.0
	return thrown


## Fly frames (the cockpit's own _process), X held or not.
func _fly(seconds: float, x_held: bool) -> void:
	pad.set_input("ax_button", x_held)
	for i in int(seconds / DT):
		v._process(DT)
	pad.set_input("ax_button", false)


# --- the checks -------------------------------------------------------------------------------------------

func check_switch_built() -> void:
	var placed := {}
	for id: String in Craft.ORDER:
		await _cockpit(id)
		var sw: Node3D = v.gun_switch
		var want := id in [Craft.STANDARD, Craft.TALON, Craft.BASILISK]
		if sw == null:
			check("%s: no GUN switch in its cockpit (%s wanted)" % [id, "one" if want else "none"], not want)
		else:
			check("%s: a GUN switch in its cockpit (%s wanted): \"%s\", a guarded toggle, %s up and %s down, throwing %s" % [id, "one" if want else "none", sw.name, sw.legends[0], sw.legends[1], sw.throws],
				want and sw.name == "GunSwitch" and sw.get_script() == Switch and sw.legends == ["GUN", "SAFE"] and sw.throws == ["gun", "safe"]
				and sw.get_parent() == v.shell)
			placed[id] = sw.transform
		v.free()
		await process_frame
	if placed.size() == 3:
		var ph: Transform3D = placed[Craft.STANDARD]
		var b: Transform3D = placed[Craft.BASILISK]
		check("the Phaethon's and the Talon's stand alike (%s, %s)" % [ph.origin, (placed[Craft.TALON] as Transform3D).origin], ph.is_equal_approx(placed[Craft.TALON]))
		check("... on the starboard console's inboard face up front (%.3f, %.3f, %.3f), its face turned inboard" % [ph.origin.x, ph.origin.y, ph.origin.z],
			ph.origin.x > 0.5 and ph.origin.x < 0.56 and ph.origin.y < 0.38 and ph.origin.z < 0.2 and ph.basis.z.normalized().x < -0.5)
		check("the Basilisk's stands where it did, on its starboard sill (%.3f, %.3f, %.3f)" % [b.origin.x, b.origin.y, b.origin.z],
			b.origin.is_equal_approx(Vector3(0.80, 0.755, 0.30)))
	sections += 1


## -> whether it could be armed (the checks after it need that).
func check_x_fires_when_armed(id: String) -> bool:
	var g = null
	if v.gun_switch == null:
		check("%s: a GUN switch to arm (none)" % id, false)
		return false
	check("%s: SAFE to begin with, no fire control made yet" % id, not v.gun_wanted and v.gunnery == null)
	var thrown := _throw_gun(true)
	check("%s: the GUN switch pushed up by the right hand arms the gun (%s)" % [id, "GUN" if v.gun_wanted else "SAFE"], thrown and v.gun_wanted)
	_fly(1.3, false)
	g = v.gunnery
	var out: bool = g != null and g.mount.is_out()
	check("%s: its fire control is made, firing through the craft's weapon, and in 1.3 s the guns are out (%s)" % [id, out],
		g != null and g.mount == v.craft.weapon and out)
	if g == null:
		return false
	var shots0: int = g.shots
	pad.set_input("ax_button", true)
	var repairs := 0
	for i in int(0.5 / DT):
		v._process(DT)
		repairs += int(bool(v.inp.get("repair", false)))
	pad.set_input("ax_button", false)
	check("%s: X held half a second fires (%d shots) and is not the repair (%d frames of it)" % [id, g.shots - shots0, repairs], g.shots - shots0 > 0 and repairs == 0)
	thrown = _throw_gun(false)
	check("%s: pushed down by hand it is thrown to SAFE (%s)" % [id, "GUN" if v.gun_wanted else "SAFE"], thrown and not v.gun_wanted)
	_fly(0.1, false)
	shots0 = g.shots
	pad.set_input("ax_button", true)
	repairs = 0
	for i in int(0.5 / DT):
		v._process(DT)
		repairs += int(bool(v.inp.get("repair", false)))
	pad.set_input("ax_button", false)
	check("%s: at SAFE X held is the repair (%d frames of %d) and fires nothing (%d shots)" % [id, repairs, int(0.5 / DT), g.shots - shots0], repairs == int(0.5 / DT) and g.shots == shots0)
	sections += 1
	return true


func check_menu_blocks_fire() -> void:
	var g = v.gunnery
	v.set_gun(true)
	_fly(1.3, false)
	var out: bool = g.mount.is_out()
	var shots0: int = g.shots
	v.menu_open(true)
	_fly(1.0, true)
	var during: int = g.shots - shots0
	v.menu_open(false)
	v._await_neutral_controls = false
	check("armed and out (%s), with the quick menu open X held a second fires nothing (%d shots)" % [out, during], out and during == 0)
	v.set_gun(false)
	_fly(1.2, false)
	sections += 1


func check_not_by_accident() -> void:
	var mode: Node3D = v.mode_switch
	var bat: Vector3 = mode.transform * Vector3(0.0, 0.0, 0.07)
	var up: Vector3 = mode.transform * Vector3(0.0, 0.06, 0.07)
	var down: Vector3 = mode.transform * Vector3(0.0, -0.06, 0.07)
	var off: Vector3 = mode.transform * Vector3(0.0, 0.06, 0.2)
	var bad := []
	var mode_throws := 0
	for armed in [false, true]:
		v.set_gun(armed)
		_rest(hr, _grip(0.5), Switch.COOLDOWN + 0.1)
		for thr in [0.5, 1.0]:
			var grip := _grip(thr)
			v._flip_at = -100000      # (the handling's own cooldown goes by the wall clock, which a test outruns)
			for leg: Array in [[grip, bat], [bat, up], [up, down]]:
				_move(hr, leg[0], leg[1], 0.5)
			mode_throws += int(v.handling_ask == "starfighter")
			_rest(hr, down, Switch.COOLDOWN + 0.1)
			v._flip_at = -100000
			_move(hr, down, up, 0.5)
			mode_throws += int(v.handling_ask == "speed")
			for leg: Array in [[up, off], [off, grip]]:
				_move(hr, leg[0], leg[1], 0.5)
			_rest(hr, grip, 0.3)
			if v.gun_wanted != armed:
				bad.append("%s from the grip at %.0f%%" % ["GUN" if armed else "SAFE", thr * 100.0])
				v.set_gun(armed)
	v.lever_pivots[1].rotation.x = 0.0
	v.set_gun(false)
	check("the right hand's way from its grip at half and at full throttle to the MODE switch, a throw down and up (%d of 8 thrown), and back throws the GUN switch nowhere, at SAFE or at GUN (thrown: %s)" % [mode_throws, bad],
		mode_throws == 8 and bad.is_empty())
	sections += 1


func check_flat_keys() -> void:
	View.vehicle_override = Craft.STANDARD
	var flat = View.new()
	root.add_child(flat)
	await process_frame
	flat.set_process(false)
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	flat._unhandled_key_input(key)
	var armed: bool = flat.gun_wanted
	var f := InputEventKey.new()
	f.keycode = KEY_F
	f.pressed = true
	Input.parse_input_event(f)
	Input.flush_buffered_events()
	for i in int(1.6 / DT):
		flat._process(DT)
	f = InputEventKey.new()
	f.keycode = KEY_F
	f.pressed = false
	Input.parse_input_event(f)
	Input.flush_buffered_events()
	var g = flat.gunnery
	var shots: int = g.shots if g != null else 0
	check("in the flat view in the Phaethon K arms its gun (%s) and F held fires it (%d shots in 1.6 s)" % [armed, shots], armed and g != null and shots > 0)
	flat._unhandled_key_input(key)
	check("... and K again makes it safe", not flat.gun_wanted)
	flat.free()
	await process_frame
	sections += 1
