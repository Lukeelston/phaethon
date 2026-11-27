## The GUN switch in every armed cockpit, and the gun's controls (Raids, 2026-11-24; Luke: "every vehicle should have
## their own weapon system like the basilisk's hidden cannon"). Stage 1: the craft with a weapon (sim/pilot_craft.gd
## WEAPONS, armed) are the Phaethon, the Talon and the Basilisk; stage 2 adds the Shrike, the Kiln and the Vesper; only
## their cockpits have the switch.
##   check_switch_built        a GunSwitch (GUN up, SAFE down) in the Phaethon's, the Talon's, the Shrike's, the Kiln's,
##                             the Vesper's and the Basilisk's cockpits: the Phaethons', the Shrike's, the Kiln's and the
##                             Vesper's the same (their consoles are the Phaethons'), on the starboard console's inboard
##                             face up front (vr_cockpit.gd gun_switch_mount), the Basilisk's on its sill where it has
##                             stood since 2026-11-23; none in the Orrery's
##   check_x_fires_when_armed  in the Phaethon and the Talon (on the range, at rest): the GUN switch pushed up by hand
##                             arms the gun; X held then fires it, and is not the repair; thrown down to SAFE by hand,
##                             X held is the repair again and fires nothing
##   check_menu_blocks_fire    armed and out, with the quick menu open X held fires nothing
##   check_not_by_accident     the right hand's way from its grip at half and at full throttle up to the MODE switch
##                             over the GUN switch, a throw down and one up, and back, throws the GUN switch nowhere,
##                             at SAFE or at GUN
##   check_zones_apart         (the Phaethon's and the Talon's) the box before the GUN switch where a hand throws it and
##                             the MODE switch's box, each mapped through its mount, stand ZONES_APART apart at the least
##                             (two oriented boxes, by their separating axes: exact, not sampled)
##   check_overshoot_push      a push up through the aft upper part of the GUN switch's box that runs on 1.5 cm past its
##                             top, faster than either switch asks, throws the GUN switch and not the MODE switch above
##                             it (at STARFIGHTER, so a push up there would throw it to SPEED): a hand that has just
##                             thrown one is not given the other (vr_cockpit.gd _work_controls)
##   check_flat_keys           in the flat view in the Phaethon, K arms its gun and F held fires it
## X is faked with an XRControllerTracker for the left hand (as tests/test_partner_menu.gd); the hands that throw the
## switches are the test's own controllers, worked through the cockpit's own _work_controls (as test_power_controls).
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_gun_controls.gd -- --mute
## Prints GUN CONTROLS PASS. Puts user://vr_prefs.json back as it found it, and has its own settings file for the run (a
## MODE throw saves the craft's set-up): the default one is left as it was.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const Switch := preload("res://vr/mode_switch.gd")
const Settings := preload("res://release/game_settings.gd")
const DT := 1.0 / 90.0
const ZONES_APART := 0.010    # m: the GUN switch's box and the MODE switch's, at the least
const SECTIONS := 9           # built; X and the boxes in the Phaethon and in the Talon; the menu; not by accident; the overshoot; the flat view
var failures := 0
var checks := 0
var sections := 0             # (a section that dies on a script error never counts itself: the verdict then fails)
var v
var hl: XRController3D        # the hands that reach for the switches
var hr: XRController3D
var pad: XRControllerTracker  # the left controller's buttons: X
var _settings_before := ""                      # the settings file in use before the run (the default: the player's)
var _default_existed := false
var _default_settings := PackedByteArray()


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


## Its own settings file for the run, as tests/test_fly_last_used.gd has: a MODE or SLIDE throw saves the craft's set-up
## (release/game_settings.gd set_craft_setup), and the default file is the player's.
func _own_settings(file_name: String) -> void:
	_settings_before = Settings.prefs_path
	_default_existed = FileAccess.file_exists(_settings_before)
	_default_settings = FileAccess.get_file_as_bytes(_settings_before) if _default_existed else PackedByteArray()
	Settings.prefs_path = "user://%s-%d.cfg" % [file_name, OS.get_process_id()]


## The run's own settings file removed and the path put back. Is the default file as it was?
func _settings_back() -> bool:
	if Settings.prefs_path != _settings_before and FileAccess.file_exists(Settings.prefs_path):      # (never the file it found in use)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = _settings_before
	return FileAccess.file_exists(_settings_before) == _default_existed \
		and (not _default_existed or FileAccess.get_file_as_bytes(_settings_before) == _default_settings)


func _run() -> void:
	_own_settings("test-gun-controls")
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
		check_zones_apart(id)
		var armed := check_x_fires_when_armed(id)
		if armed and id == Craft.STANDARD:
			check_menu_blocks_fire()
			check_not_by_accident()
			check_overshoot_push()
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
	check("the default settings file is as it was (the run had its own)", _settings_back())
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
		var want := id in [Craft.STANDARD, Craft.TALON, Craft.SHRIKE, Craft.KILN, Craft.VESPER, Craft.BASILISK]
		if sw == null:
			check("%s: no GUN switch in its cockpit (%s wanted)" % [id, "one" if want else "none"], not want)
		else:
			check("%s: a GUN switch in its cockpit (%s wanted): \"%s\", a guarded toggle, %s up and %s down, throwing %s" % [id, "one" if want else "none", sw.name, sw.legends[0], sw.legends[1], sw.throws],
				want and sw.name == "GunSwitch" and sw.get_script() == Switch and sw.legends == ["GUN", "SAFE"] and sw.throws == ["gun", "safe"]
				and sw.get_parent() == v.shell)
			placed[id] = sw.transform
		v.free()
		await process_frame
	if placed.size() == 6:
		var ph: Transform3D = placed[Craft.STANDARD]
		var b: Transform3D = placed[Craft.BASILISK]
		check("the Phaethon's, the Talon's, the Shrike's, the Kiln's and the Vesper's stand alike (%s, %s, %s, %s, %s)" % [ph.origin, (placed[Craft.TALON] as Transform3D).origin,
			(placed[Craft.SHRIKE] as Transform3D).origin, (placed[Craft.KILN] as Transform3D).origin, (placed[Craft.VESPER] as Transform3D).origin],
			ph.is_equal_approx(placed[Craft.TALON]) and ph.is_equal_approx(placed[Craft.SHRIKE]) and ph.is_equal_approx(placed[Craft.KILN])
			and ph.is_equal_approx(placed[Craft.VESPER]))
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


## A switch's throw box (ModeSwitch.ZONE before its face, mapped through its mount, the shell's frame): its middle,
## its three axes (unit) and its half-sizes along them.
static func _zone_box(sw: Node3D) -> Array:
	var t: Transform3D = sw.transform
	var middle := t * Vector3(0.0, 0.0, (Switch.ZONE.z - 0.01) / 2.0)
	var half := [Switch.ZONE.x, Switch.ZONE.y, (Switch.ZONE.z + 0.01) / 2.0]
	var axes := []
	var sizes := []
	for i in 3:
		axes.append(t.basis[i].normalized())
		sizes.append(float(half[i]) * t.basis[i].length())
	return [middle, axes, sizes]


## Two oriented boxes by their separating axes: the widest gap between them along any of the fifteen (m; negative:
## they meet).
static func _box_gap(a: Array, b: Array) -> float:
	var tests := []
	for i in 3:
		tests.append(a[1][i])
		tests.append(b[1][i])
		for j in 3:
			var c: Vector3 = (a[1][i] as Vector3).cross(b[1][j])
			if c.length() > 1e-6:
				tests.append(c.normalized())
	var widest := -INF
	var apart: Vector3 = (b[0] as Vector3) - (a[0] as Vector3)
	for axis: Vector3 in tests:
		var ra := 0.0
		var rb := 0.0
		for i in 3:
			ra += float(a[2][i]) * absf((a[1][i] as Vector3).dot(axis))
			rb += float(b[2][i]) * absf((b[1][i] as Vector3).dot(axis))
		widest = maxf(widest, absf(apart.dot(axis)) - ra - rb)
	return widest


func check_zones_apart(id: String) -> void:
	if v.gun_switch == null:
		check("%s: a GUN switch whose box to measure (none)" % id, false)
		return
	var gap := _box_gap(_zone_box(v.gun_switch), _zone_box(v.mode_switch))
	check("%s: the GUN switch's box and the MODE switch's stand %.1f mm apart at the least, along a separating axis (%.0f wanted)" % [id, gap * 1000.0, ZONES_APART * 1000.0], gap >= ZONES_APART)
	sections += 1


## Is a tip (the shell's frame) in the box before the MODE switch where a hand throws it?
func _in_mode_box(p: Vector3) -> bool:
	var q: Vector3 = v.mode_switch.transform.affine_inverse() * p
	return absf(q.x) < Switch.ZONE.x and absf(q.y) < Switch.ZONE.y and q.z > -0.01 and q.z < Switch.ZONE.z


## From the right grip at half throttle, GUN at SAFE and MODE at STARFIGHTER: in to the aft upper part of the GUN
## switch's box and a push straight up at 0.8 m/s to `end`, and back. -> [GUN thrown, the handling asked, MODE's bat
## down, how many of the push's frames had the tip in MODE's box].
func _push_up(start: Vector3, end: Vector3) -> Array:
	v.set_gun(false)
	v._flip_at = -100000
	v.ask_handling("starfighter")
	var grip := _grip(0.5)
	_rest(hr, grip, Switch.COOLDOWN + 0.1)      # (the switches shown as they stand: GUN at SAFE, MODE at STARFIGHTER)
	var out := start + (_on_gun(Vector3(0.0, 0.0, 0.25)) - _on_gun(Vector3(0.0, 0.0, 0.07)))
	_move(hr, grip, out, 0.5)
	_move(hr, out, start, 0.4)
	_rest(hr, start, Switch.COOLDOWN + 0.1)
	v._flip_at = -100000      # (the handling's wall-clock cooldown would refuse a throw: it must not be what holds it)
	var in_mode := 0
	var steps := maxi(1, int(ceil(start.distance_to(end) / (0.8 * DT))))
	for k in range(1, steps + 1):
		var p := start.lerp(end, float(k) / steps)
		in_mode += int(_in_mode_box(p))
		_put(hr, p)
		_park(hl)
		_tick()
	var got := [v.gun_wanted, v.handling_ask, v.mode_switch.down, in_mode]
	var back := end + (out - start)
	_move(hr, end, back, 0.4)
	_move(hr, back, grip, 0.5)
	v.lever_pivots[1].rotation.x = 0.0
	return got


func check_overshoot_push() -> void:
	var s: float = v.gun_switch.transform.basis.y.length()      # (its scale: 1.5 cm past the box's top, in its own metres)
	var aft := Switch.ZONE.x * 0.8
	var start := _on_gun(Vector3(aft, -0.02, 0.03))
	var past_top := _on_gun(Vector3(aft, Switch.ZONE.y + 0.015 / s, 0.03))
	var a := _push_up(start, past_top)
	check("a push up at 0.8 m/s through the aft upper part of the GUN switch's box, 1.5 cm on past its top (%d of its frames in the MODE switch's box), throws it (%s) and not the MODE switch over it (handling \"%s\", wanted \"starfighter\"; its bat %s)" % [
		a[3], "GUN" if a[0] else "SAFE", a[1], "down" if a[2] else "up"], a[0] and a[1] == "starfighter" and a[2])
	# ... and the same stroke run on straight up until it is a centimetre inside the MODE switch's box: the hand that has
	# just thrown the GUN switch is not given the MODE switch (whatever the two boxes' places)
	var into := past_top
	var reached := false
	for k in 300:
		into += Vector3(0.0, 0.0005, 0.0)
		var q: Vector3 = v.mode_switch.transform.affine_inverse() * into
		if minf(minf(Switch.ZONE.x - absf(q.x), Switch.ZONE.y - absf(q.y)), minf(q.z + 0.01, Switch.ZONE.z - q.z)) > 0.01:
			reached = true
			break
	var b := _push_up(start, into)
	check("... and run on straight up %.0f mm into the MODE switch's box (%s, %d frames in it), it throws the GUN switch (%s) and still not the MODE switch (handling \"%s\"; its bat %s)" % [
		(into.y - past_top.y) * 1000.0, "reached" if reached else "not reached", b[3], "GUN" if b[0] else "SAFE", b[1], "down" if b[2] else "up"],
		reached and b[3] > 0 and b[0] and b[1] == "starfighter" and b[2])
	v._flip_at = -100000
	v.ask_handling("speed")
	v.set_gun(false)
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
