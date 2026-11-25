## The consoles' live switches (vr/console_switches.gd, vr/vr_cockpit.gd; push 44, Luke, 2026-11-23: "if there are any
## menu items that could replace the vanity switches/buttons in the cockpit even better. I like the idea of physical
## controls to manipulate in-world."). Through the cockpit's own hands loop (_work_controls), with two stand-in
## controllers moved as a hand moves:
##   built        six toggles and two knobs cut out of the authored consoles (each bat and knob its own triangles,
##                gone from the console's mesh), their legends, the placards; and with no hand near nothing changes:
##                every OPTIONS line as it was, nothing written
##   by hand      each toggle rested on and pushed switches its OPTIONS line, as the menu does and saved as it is;
##                the menu's line moves the toggle; the hand drawn back after a push does not throw it back; the
##                AUTOPILOT refused (cold) springs back, as the menu's line is refused
##   by accident  a hand going by along the console at the bats' height between their guards, slowly or fast, or
##                across them, throws nothing; a tracking jump is not a push; a hand at a throttle grip, the lever
##                anywhere in its travel, is nowhere near a bat or a knob
##   neighbours   a hand reaching from the levers for each toggle and throwing it throws neither the SLIDE nor the MODE
##                switch (whichever way they stand), takes and moves no drift slider (at either end of its slot or in
##                its notch) and works no map; a hand working each of those throws no toggle; and each works again
##                as soon as the console has let the hand go
##   knobs        taken by a rested tip, turned by the wrist's roll (clockwise more), a tick each 15 degrees, the
##                detent at 1, the stops; a jump in the roll moves nothing; let go they are saved; the next cockpit
##                reads them
##   cost         the hands loop's console work a frame, two hands, in microseconds
##   settings     the run has its own settings file (a MODE or SLIDE throw saves the craft's set-up): the default one is
##                left as it was
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_console_switches.gd -- --mute
## Prints CONSOLE SWITCHES PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Console := preload("res://vr/console_switches.gd")
const Switch := preload("res://vr/mode_switch.gd")
const Drift := preload("res://vr/drift_slider.gd")
const Tactical := preload("res://view/tactical_display.gd")
const Startup := preload("res://vr/startup_sequence.gd")
const Settings := preload("res://release/game_settings.gd")
const FRAME := 1.0 / 90.0
const PREF_KEY := {"tactical": "tactical", "field": "field", "powerups": "powerups", "consumables": "consumables", "rush": "rush"}
var v
var hl: XRController3D
var hr: XRController3D
var failures := 0
var checks := 0
var _settings_before := ""                      # the settings file in use before the run (the default: the player's)
var _default_existed := false
var _default_settings := PackedByteArray()


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_console_switches_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this (the OPTIONS page's are read: there are none)
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit.slide_feel = true
	Cockpit.slide_amount = 1.0
	Cockpit._rush_loaded = true
	Cockpit.speed_rush = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Cockpit.cold_start = false
	Cockpit.school = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


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


func _saved() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS)) if FileAccess.file_exists(Cockpit.PREFS) else {}
	return d if d is Dictionary else {}


func _cockpit() -> void:
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.hands_live = true
	v._await_neutral_controls = false


## A controller placed so that its tip is at `tip` (the consoles' metres), turned by `turn` there.
func _put(h: Node3D, tip: Vector3, turn := Basis.IDENTITY) -> void:
	var cg: Transform3D = v.console.global_transform
	var b: Basis = cg.basis * turn
	h.global_transform = Transform3D(b, cg * tip - b * Console.TIP)


## Where a controller's tip is, in the consoles' metres.
func _tip(h: Node3D) -> Vector3:
	return v.console.global_transform.affine_inverse() * (h.global_transform * Console.TIP)


## Each frame as the cockpit's own: the hands loop's controls, then what _process shows.
func _tick(dt := FRAME) -> void:
	v._work_controls(hl, hr, dt)
	v._show_console(dt)
	v.mode_switch.show_state(v.handling_ask == "starfighter", v.sim.hblend, false)
	v.slide_switch.show_state(not Cockpit.slide_feel, 0.0 if Cockpit.slide_feel else 1.0, false)
	v.drift_slider.show_state(Cockpit.slide_feel, 1.0)
	v.minimap_panel.show_controls(not Cockpit.map_whole, 1.0, Cockpit.map_hud)


## The other hand out of the way: in front of the pilot's chest.
func _park(h: Node3D) -> void:
	_put(h, Vector3(0.0, 0.55, 0.25))


## Carry a hand's tip from one place to another at `speed` m/s (the other hand parked), turned `turn`.
func _move(h: Node3D, from: Vector3, to: Vector3, speed: float, turn := Basis.IDENTITY) -> void:
	var other: Node3D = hr if h == hl else hl
	var steps := maxi(1, int(ceil(from.distance_to(to) / (speed * FRAME))))
	for k in range(1, steps + 1):
		_put(h, from.lerp(to, float(k) / steps), turn)
		_park(other)
		_tick()


## Hold a hand still there (a hand's own tremor: a fifth of a millimetre).
func _rest(h: Node3D, at: Vector3, seconds: float, turn := Basis.IDENTITY) -> void:
	var other: Node3D = hr if h == hl else hl
	for k in int(seconds / FRAME):
		_put(h, at + Vector3(0.0002 * sin(k * 1.7), 0.0002 * cos(k * 2.3), 0.0002 * sin(k * 3.1)), turn)
		_park(other)
		_tick()


## A throttle grip's middle, the consoles' metres: lever k (0 left) at `levers` (0 idle .. 1 full).
func _grip(k: int, levers: float) -> Vector3:
	var pivot: Node3D = v.lever_pivots[k]
	pivot.rotation.x = deg_to_rad(lerpf(30.0, -30.0, levers))
	return v.console.global_transform.affine_inverse() * (pivot.global_transform * Vector3(0.0, 0.36, 0.0))


## A pilot throwing toggle i: from the grip on its side (the lever at `levers`) the tip up, along the console inboard of
## the SLIDE and MODE switches' panels (not through their levers), out over the bat and down onto it; a rest on it, a
## push along the console (forward to switch it on), a rest, the hand drawn back along the console, lifted, and the
## same way back to the grip, where it rests.
func _throw(i: int, levers := 0.0) -> void:
	v._flip_at = -100000      # (the handling's own cooldown: a MODE switch thrown by mistake must show, not be refused unseen)
	var side: float = Console.TOGGLES[i][2]
	var h: Node3D = hl if side < 0.0 else hr
	var start := _grip(0 if side < 0.0 else 1, levers) + Vector3(0.0, 0.03, 0.0)
	var bat := Console.toggle_at(i) + Vector3(0.0, 0.03, 0.0)
	var high := Console.FACE_Y + 0.08
	var way := [start, Vector3(start.x, high, start.z), Vector3(start.x, high, bat.z), Vector3(bat.x, high, bat.z), bat]
	for k in range(1, way.size()):
		_move(h, way[k - 1], way[k], 0.5 if k < way.size() - 1 else 0.4)
	var push := Vector3(0.0, 0.0, 0.025 if v.console.shown[i] else -0.025)
	_rest(h, bat, 0.12)
	_move(h, bat, bat + push, 0.4)
	_rest(h, bat + push, 0.1)
	_move(h, bat + push, bat, 0.4)
	way.reverse()
	for k in range(1, way.size()):
		_move(h, way[k - 1], way[k], 0.5)
	_rest(h, start, Console.CLAIM_S + 0.1)


## Which of the toggles' own settings changed between two _states.
func _console_changed(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for k in Console.KEYS:
		if a[k] != b[k]:
			out.append(k)
	return out


## The settings the toggles work, and those of their neighbours, as they stand.
func _states() -> Dictionary:
	var s := {}
	for key: String in Console.KEYS:
		s[key] = v.option_on(key)
	s["slide"] = Cockpit.slide_feel
	s["handling"] = v.handling_ask
	s["slide_down"] = v.slide_switch.down
	s["mode_down"] = v.mode_switch.down
	s["amount"] = v.drift_slider.amount
	s["slider_held"] = v.drift_slider.held_by != null
	s["map_whole"] = Cockpit.map_whole
	s["map_hud"] = Cockpit.map_hud
	s["map_scheme"] = Cockpit.map_scheme
	return s


## What changed between two _states.
func _changed(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for k in a:
		if a[k] != b[k]:
			out.append(k)
	return out


func _run() -> void:
	_own_settings("test-console-switches")
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	if prefs_before != "":      # a pilot with nothing saved: what he gets
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	Cockpit._options_loaded = false
	Cockpit.tactical_dim = 1.0
	Cockpit.tactical_pace = 1.0
	await _cockpit()
	var c = v.console
	_check("the cockpit has its consoles' switches, a child of the interior", c != null and c.get_script() == Console and c.get_parent() == v.interior)
	if c == null:
		print("CONSOLE SWITCHES FAIL (no switches)")
		_settings_back()
		quit(1)
		return
	hl = XRController3D.new()
	hr = XRController3D.new()
	root.add_child(hl)
	root.add_child(hr)
	_park(hl)
	_park(hr)

	# ---- built
	var cut_ok := true
	var parts := []
	for side in [-1.0, 1.0]:
		var unit := v.interior.get_node("ConsoleL" if side < 0.0 else "ConsoleR") as MeshInstance3D
		parts.append(unit.mesh.get_faces().size() / 3)
	var tris: Array = c.cut_tris
	cut_ok = tris.size() == 8 and tris.slice(0, 6).count(224) == 6 and tris[6] == 720 and tris[7] == 720
	var authored := []
	for side in [-1.0, 1.0]:
		authored.append(_authored_tris(side))
	_check("each bat (224 triangles) and each live knob (720) is cut out of the authored consoles: %s; the consoles keep the rest (%s of %s: %s fewer, a bat each three times and a knob)" % [tris, parts, authored, [authored[0] - parts[0], authored[1] - parts[1]]],
		cut_ok and authored[0] - parts[0] == 3 * 224 + 720 and authored[1] - parts[1] == 3 * 224 + 720)
	var words := {}
	for l: Label3D in v.interior.find_children("*", "Label3D", true, false):
		words[l.text] = l
	var wanted := ["TAC HUD", "FIELD", "AUTOPILOT", "GATES", "HEAT", "RUSH", "TAC DIM", "TAC WARN", "CABIN", "BALANCE", "ASSISTS  /  01", "PROPULSION  /  02"]
	var missing := []
	for w: String in wanted:
		if not words.has(w):
			missing.append(w)
	var gone := []
	for w: String in ["AUX PWR", "COMMS", "TRIM", "BINDER", "COOLANT", "STAB", "DIMMER", "SENS", "AUXILIARY  /  01"]:
		if words.has(w):
			gone.append(w)
	var legends_aft := true
	for i in 6:
		var l: Label3D = c.legends[i]
		legends_aft = legends_aft and is_equal_approx(l.position.z - Console.toggle_at(i).z, Console.LEGEND_AFT)
	_check("the legends read TAC HUD, FIELD, AUTOPILOT and GATES, HEAT, RUSH, the knobs TAC DIM and TAC WARN beside CABIN and BALANCE, the placards ASSISTS and PROPULSION (missing %s; left over %s); each toggle's legend just aft of its bat (%s)" % [missing, gone, legends_aft],
		missing.is_empty() and gone.is_empty() and legends_aft)
	# with nothing near: nothing changes, nothing is written
	var first := _states()
	for k in 60:
		_tick()
	var defaults: bool = not v.option_on("tactical") and not v.option_on("field") and not v.option_on("autopilot") and v.option_on("powerups") and not v.option_on("consumables") and v.option_on("rush")
	var leans := []
	for i in 6:
		leans.append(snappedf(rad_to_deg((c.levers[i] as Node3D).rotation.x), 0.1))
	_check("with no hand near, a second of frames: every setting as it was (%s), the bats as they stand (forward ON at 0 degrees, aft OFF at %.0f: %s), nothing written (%s)" % [
			_changed(first, _states()), rad_to_deg(2.0 * Console.THROW), leans, FileAccess.file_exists(Cockpit.PREFS)],
		_changed(first, _states()).is_empty() and defaults and not FileAccess.file_exists(Cockpit.PREFS) and str(c.shown) == "[false, false, false, true, false, true]"
		and leans == [snappedf(rad_to_deg(0.6), 0.1), snappedf(rad_to_deg(0.6), 0.1), snappedf(rad_to_deg(0.6), 0.1), 0.0, snappedf(rad_to_deg(0.6), 0.1), 0.0])

	# ---- by hand: each toggle switches its OPTIONS line, as the menu does, and saved as that is
	var by_hand := []
	var all_ok := true
	for i in 6:
		var key: String = Console.KEYS[i]
		var was := _states()
		_throw(i)
		var now := _states()
		var on: bool = v.option_on(key)
		var saved_ok: bool = not PREF_KEY.has(key) or _saved().get(PREF_KEY[key], "") == ("on" if on else "off")
		var shown_ok: bool = c.shown[i] == on and absf((c.levers[i] as Node3D).rotation.x - (0.0 if on else 2.0 * Console.THROW)) < 0.02
		by_hand.append("%s %s%s" % [Console.TOGGLES[i][1], "ON" if on else "off", "" if saved_ok else " (not saved)"])
		all_ok = all_ok and _changed(was, now) == [key] and saved_ok and shown_ok
		was = now
		_throw(i)
		now = _states()
		on = v.option_on(key)
		saved_ok = not PREF_KEY.has(key) or _saved().get(PREF_KEY[key], "") == ("on" if on else "off")
		by_hand.append("then %s" % ("ON" if on else "off"))
		all_ok = all_ok and _changed(was, now) == [key] and saved_ok and c.shown[i] == on
	_check("each toggle rested on and pushed switches its own line and nothing else, saved as the menu saves it, its bat standing where the line is; and back again (%s)" % [", ".join(by_hand)], all_ok)
	# the menu's line moves the toggle
	v.menu_open(true)
	v._menu_page = "options"
	v.menu.items = v._menu_items()
	var moved := []
	for key: String in ["tactical", "field", "powerups", "consumables", "rush"]:
		var found := false
		for page in 2:      # (the OPTIONS page is laid out as panels: TACTICAL DISPLAY is on the second)
			if found:
				break
			v.menu.page = page
			v.menu.items = v._menu_items()
			for k in v.menu.items.size():
				if String(v.menu.items[k].key) == key:
					v.menu.at = k
					found = true
		if not found:
			moved.append([key, false])
			continue
		var before: bool = v.option_on(key)
		v.menu_choose()
		for k in 30:
			v._show_console(FRAME)
		var i: int = Console.KEYS.find(key)
		moved.append([key, c.shown[i] != before and c.shown[i] == v.option_on(key) and absf((c.levers[i] as Node3D).rotation.x - (0.0 if c.shown[i] else 2.0 * Console.THROW)) < 0.02])
		v.menu_choose()      # (and back)
	v._menu_page = ""
	v.menu_open(false)
	v._await_neutral_controls = false
	var all_moved := true
	for m in moved:
		all_moved = all_moved and bool(m[1])
	_check("chosen in the quick menu, each line throws its toggle, its bat over in a third of a second: %s" % [moved], all_moved)
	# the AUTOPILOT, refused cold as the menu's line is: two taps, the glass says why, and its bat goes back
	v.startup.cold()
	var cold_was := _states()
	var i_auto: int = Console.KEYS.find("autopilot")
	_throw(i_auto)
	_check("cold, the AUTOPILOT toggle thrown is refused as the menu's line is (\"%s\"): it stays off, its bat back aft (%.0f degrees)" % [v.flash_msg, rad_to_deg((c.levers[i_auto] as Node3D).rotation.x)],
		not v.autopilot.on and String(v.flash_msg).contains("START HER FIRST") and not c.shown[i_auto] and _changed(cold_was, _states()).is_empty()
		and absf((c.levers[i_auto] as Node3D).rotation.x - 2.0 * Console.THROW) < 0.02)
	v.startup = Startup.new()      # (hot again)

	# ---- by accident
	var still := _states()
	var passes := []
	for side in [-1.0, 1.0]:
		var h: Node3D = hl if side < 0.0 else hr
		var along_from := Vector3(Console.CX * side, Console.FACE_Y + 0.03, Console.AIR_Z.x + 0.005)      # (from just aft of the SLIDE and MODE switches' panels: ahead of that it brushes their faces)
		var along_to := Vector3(Console.CX * side, Console.FACE_Y + 0.03, 0.64)
		for speed in [0.3, 0.6, 1.5]:
			_move(h, along_from, along_to, speed)
			_move(h, along_to, along_from, speed)
		for i in 6:
			if float(Console.TOGGLES[i][2]) != side:
				continue
			var bat := Console.toggle_at(i) + Vector3(0.0, 0.03, 0.0)
			_move(h, bat + Vector3(-0.15, 0.0, 0.0), bat + Vector3(0.15, 0.0, 0.0), 0.6)      # across it
			_move(h, bat + Vector3(0.0, 0.12, 0.0), bat + Vector3(0.0, 0.005, 0.0), 0.6)      # down onto it and up again
			_move(h, bat + Vector3(0.0, 0.005, 0.0), bat + Vector3(0.0, 0.12, 0.0), 0.6)
		_rest(h, along_to, Console.CLAIM_S + 0.1)
		passes.append(_changed(still, _states()))
	_check("a hand going by along each console at the bats' height between their guards, fore and aft at 0.3, 0.6 and 1.5 m/s, across each bat and down onto it and up, throws nothing, nor the SLIDE or MODE switch (changed: %s)" % [passes],
		passes == [[], []])
	# a tracking jump: a hand at rest on a bat, then 60 mm along the console in a frame (5.4 m/s)
	still = _states()
	var bat0 := Console.toggle_at(0) + Vector3(0.0, 0.03, 0.0)
	_move(hl, _grip(0, 0.0) + Vector3(0.0, 0.05, 0.0), bat0 + Vector3(0.0, 0.05, 0.0), 0.5)
	_move(hl, bat0 + Vector3(0.0, 0.05, 0.0), bat0, 0.4)
	_rest(hl, bat0, 0.12)
	var had: bool = int(c._h[hl].has) == 0
	_put(hl, bat0 + Vector3(0.0, 0.0, -0.06))
	_tick()
	_put(hl, bat0 + Vector3(0.0, 0.0, -0.025))
	_tick()
	_move(hl, bat0 + Vector3(0.0, 0.0, -0.025), bat0 + Vector3(0.0, 0.1, 0.0), 0.5)
	_rest(hl, bat0 + Vector3(0.0, 0.1, 0.0), Console.CLAIM_S + 0.1)
	_check("a hand at rest on TAC HUD's bat (it had it: %s) that jumps 60 mm along the console in a frame throws nothing (changed: %s)" % [had, _changed(still, _states())],
		had and _changed(still, _states()).is_empty())
	# the throttle grips: nowhere near a bat or a knob, the lever anywhere in its travel (a tip is 71 mm from its controller)
	var nearest := INF
	for k in 2:
		for step in 9:
			var g := _grip(k, step / 8.0)
			for i in 6:
				var d := g - Console.toggle_at(i)
				var box := Vector3(maxf(absf(d.x) - Console.ZONE.x, 0.0), maxf(maxf(Console.ZONE_FOOT - d.y, d.y - Console.ZONE.y), 0.0), maxf(absf(d.z) - Console.ZONE.z, 0.0))
				nearest = minf(nearest, box.length())
			for kn in 2:
				nearest = minf(nearest, g.distance_to(Console.knob_cap(kn)) - Console.HOLD_R)
	_check("a throttle grip, the lever anywhere from idle to full, stands %.0f mm from the nearest place a tip has a bat or a knob: a hand on it (its tip %.0f mm from it) cannot reach one" % [nearest * 1000.0, Console.TIP.length() * 1000.0],
		nearest > Console.TIP.length() + 0.02)
	# ... and a hand working a lever, its tip round the grip every way, the lever through its travel and back
	var working := _states()
	for k in 2:
		var h: Node3D = hl if k == 0 else hr
		for turn: Basis in [Basis.IDENTITY, Basis(Vector3.UP, PI / 2.0), Basis(Vector3.UP, -PI / 2.0), Basis(Vector3.RIGHT, -PI / 2.0), Basis(Vector3.UP, PI)]:
			for step in 31:
				var g := _grip(k, 0.5 - 0.5 * cos(step / 30.0 * TAU))
				var cg: Transform3D = v.console.global_transform
				var b: Basis = cg.basis * turn
				h.global_transform = Transform3D(b, cg * g)      # (the controller in the hand on the grip; its tip where it points)
				_park(hl if k == 1 else hr)
				_tick(1.0 / 30.0)
	print("GRIPS_NEIGHBOURS what else the hands on the grips threw (the SLIDE and MODE switches' own boxes, as at d193f50): %s" % [_changed(working, _states())])
	_check("hands on the throttle grips, pointing ahead, out, in, down and back, the levers swung through their travel and back: no toggle thrown (changed: %s)" % [_console_changed(working, _states())],
		_console_changed(working, _states()).is_empty())
	v.set_slide(true)
	v.handling_ask = "speed"

	# ---- neighbours: reaching for the toggles leaves them be ...
	var stays := []
	for setup in [[true, "speed", 1.0], [false, "starfighter", Drift.AMOUNT_MAX], [true, "speed", 0.0]]:
		v.set_slide(bool(setup[0]))
		v.handling_ask = String(setup[1])
		v.set_slide_amount(float(setup[2]))
		for k in 3:
			_tick()
		for i in 6:
			for twice in 2:
				var was := _states()
				_throw(i, 0.0 if twice == 0 else 1.0)
				var what := _changed(was, _states())
				if what != [Console.KEYS[i]]:
					stays.append("%s %s with the SLIDE switch %s, %s, the slider at %.1f: %s" % [Console.TOGGLES[i][1], "on" if twice == 0 else "off", "up" if setup[0] else "down", setup[1], setup[2], what])
	_check("a hand reaching from the levers (at idle, and at full) for each toggle and throwing it on and off throws neither the SLIDE switch nor the MODE switch, up or down, takes no drift slider at either end of its slot or in its notch, and works no map (all else that changed: %s)" % [stays],
		stays.is_empty())
	v.set_slide(true)
	v.handling_ask = "speed"
	v.set_slide_amount(1.0)
	for k in 3:
		_tick()
	# ... and working them throws no toggle, and each works as soon as the console has let the hand go
	var worked := []
	var none_thrown := true
	for sw: Node3D in [v.slide_switch, v.mode_switch]:
		var h: Node3D = hl if sw == v.slide_switch else hr
		var into: Transform3D = v.console.global_transform.affine_inverse() * sw.global_transform
		for twice in 2:
			v._flip_at = -100000      # (the handling's own cooldown between flips: not what is tested here)
			var was := _states()
			var down: bool = sw.down
			var above := into * Vector3(0.0, -0.05 if down else 0.05, 0.07)     # over the bat's end, where it stands
			var through := into * Vector3(0.0, 0.03 if down else -0.03, 0.07)
			var start := _grip(0 if h == hl else 1, 0.0) + Vector3(0.0, 0.03, 0.0)
			_move(h, start, above, 0.5)
			_rest(h, above, 0.15)
			_move(h, above, through, 0.4)
			_rest(h, through, 0.1)
			_move(h, through, into * Vector3(0.0, 0.0, 0.16), 0.4)
			_move(h, into * Vector3(0.0, 0.0, 0.16), start, 0.5)
			_rest(h, start, Console.CLAIM_S + 0.1)
			var what := _changed(was, _states())
			worked.append([sw.name, what])
			for key: String in Console.KEYS:
				none_thrown = none_thrown and not what.has(key)
	# the drift slider: taken, slid both ways, let go
	var into_slider: Transform3D = v.console.global_transform.affine_inverse() * v.drift_slider.global_transform
	for amount in [Drift.AMOUNT_MAX, 0.0, 1.0]:
		var was := _states()
		var cap: Vector3 = into_slider * (v.drift_slider.cap_at() as Vector3)
		var start := _grip(0, 0.0) + Vector3(0.0, 0.03, 0.0)
		_move(hl, start, cap, 0.5)
		_rest(hl, cap, 0.25)
		var to: Vector3 = into_slider * Vector3(Drift.place(amount), 0.0, Drift.CAP_Z)
		_move(hl, cap, to, 0.25)
		_move(hl, to, to + (into_slider.basis * Vector3(0.0, 0.0, 0.12)), 0.4)
		_move(hl, to + (into_slider.basis * Vector3(0.0, 0.0, 0.12)), start, 0.5)
		_rest(hl, start, Console.CLAIM_S + 0.1)
		var what := _changed(was, _states())
		worked.append(["DriftSlider to %.1f" % amount, what])
		for key: String in Console.KEYS:
			none_thrown = none_thrown and not what.has(key)
	# the map's GLOBAL / LOCAL switch
	var map_sw: Node3D = v.minimap_panel.map_switch
	var into_map: Transform3D = v.console.global_transform.affine_inverse() * map_sw.global_transform.orthonormalized()
	var map_was := _states()
	var map_start := _grip(0, 0.0) + Vector3(0.0, 0.03, 0.0)
	_move(hl, map_start, into_map * Vector3(0.0, 0.03, 0.05), 0.5)
	_rest(hl, into_map * Vector3(0.0, 0.03, 0.05), 0.15)
	_move(hl, into_map * Vector3(0.0, 0.03, 0.05), into_map * Vector3(0.0, -0.02, 0.05), 0.4)
	_move(hl, into_map * Vector3(0.0, -0.02, 0.05), map_start, 0.5)
	_rest(hl, map_start, Console.CLAIM_S + 0.1)
	var map_what := _changed(map_was, _states())
	worked.append(["map", map_what])
	for key: String in Console.KEYS:
		none_thrown = none_thrown and not map_what.has(key)
	var each_worked: bool = worked.size() == 8
	for w in worked:
		each_worked = each_worked and not (w[1] as Array).is_empty()
	_check("worked by hand, the SLIDE switch (down and up), the MODE switch (STARFIGHTER and back), the drift slider (to its stop, to none, to the notch) and the map's switch each do their own thing and throw no toggle: %s" % [worked],
		none_thrown and each_worked and (worked[0][1] as Array).has("slide") and (worked[2][1] as Array).has("handling") and (worked[4][1] as Array).has("amount") and (worked[7][1] as Array).has("map_whole"))
	# blocked only while the console has the hand: a toggle thrown, and the SLIDE switch straight after, then again later
	v.set_slide(true)      # (the hand on its way to the map's switch, over the SLIDE switch, threw it: theirs, as at d193f50)
	for k in 3:
		_tick()
	var before_hud := _states()
	_throw(0)
	var hud_alone: bool = _changed(before_hud, _states()) == ["tactical"]
	var bat_up := Console.toggle_at(0) + Vector3(0.0, 0.03, 0.0)
	var slide_into: Transform3D = v.console.global_transform.affine_inverse() * v.slide_switch.global_transform
	_move(hl, _grip(0, 0.0) + Vector3(0.0, 0.05, 0.0), bat_up + Vector3(0.0, 0.05, 0.0), 0.5)
	_move(hl, bat_up + Vector3(0.0, 0.05, 0.0), bat_up, 0.4)
	_rest(hl, bat_up, 0.12)
	var claimed: bool = c.claims(hl)
	_move(hl, bat_up, bat_up + Vector3(0.0, 0.0, 0.025 if c.shown[0] else -0.025), 0.4)      # (TAC HUD thrown back)
	var slide_was: bool = Cockpit.slide_feel
	var above_slide := slide_into * Vector3(0.0, 0.05, 0.07)
	_move(hl, _tip(hl), above_slide, 0.6)
	_move(hl, above_slide, slide_into * Vector3(0.0, -0.03, 0.07), 0.4)      # at once: still the console's
	var blocked_then: bool = Cockpit.slide_feel == slide_was
	_move(hl, slide_into * Vector3(0.0, -0.03, 0.07), slide_into * Vector3(0.0, 0.0, 0.16), 0.4)
	_rest(hl, slide_into * Vector3(0.0, 0.0, 0.16), Console.CLAIM_S + 0.1)
	var free_after: bool = not c.claims(hl)
	_move(hl, slide_into * Vector3(0.0, 0.0, 0.16), above_slide, 0.4)
	_rest(hl, above_slide, 0.15)
	_move(hl, above_slide, slide_into * Vector3(0.0, -0.03, 0.07), 0.4)
	var works_later: bool = Cockpit.slide_feel != slide_was
	_move(hl, slide_into * Vector3(0.0, -0.03, 0.07), slide_into * Vector3(0.0, 0.0, 0.16), 0.4)
	_rest(hl, slide_into * Vector3(0.0, 0.0, 0.16), Console.CLAIM_S + 0.1)
	_check("TAC HUD thrown on alone (%s); a hand with a bat is the console's (%s): straight from throwing it back it does not throw the SLIDE switch (%s); settled, %.1f s on, it is let go (%s) and the SLIDE switch answers it (%s)" % [hud_alone, claimed, blocked_then, Console.CLAIM_S, free_after, works_later],
		hud_alone and claimed and blocked_then and free_after and works_later)
	v.set_slide(true)

	# ---- the knobs: taken, turned by the wrist, felt, saved
	var down := Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)      # a controller pointing down at a knob
	var did := []
	var dim_cap := Console.knob_cap(0)
	var roll := func(turn: Basis, degrees: float) -> Basis: return turn * Basis(Vector3(0.0, 0.0, -1.0), deg_to_rad(degrees))   # + clockwise, as the hand sees it
	var kpoke := func(h: Node3D, tip: Vector3, turn: Basis) -> String:
		_put(h, tip, turn)
		var what: String = c.poke(h, FRAME)
		v._work_console(what)
		return what
	_put(hr, Vector3(0.0, 0.55, 0.25))
	# a hand going by at 0.3 m/s over the cap takes nothing
	var by := []
	for k in 40:
		var what: String = kpoke.call(hl, dim_cap + Vector3(0.0, 0.0, -0.06 + 0.12 * k / 39.0), down)
		if what != "":
			by.append(what)
	var took := -1.0
	for k in 40:
		if kpoke.call(hl, dim_cap, down) == "held":
			took = (k + 1) * FRAME
			break
	_check("TAC DIM: a hand going by over it takes nothing (%s); a tip rested on its cap has it in %.2f s; it stands at its stop, the display as it is drawn (%.2f)" % [by, took, Cockpit.tactical_dim],
		by.is_empty() and took > 0.1 and took < 0.3 and c.knob_held[0] == hl and Cockpit.tactical_dim == 1.0)
	var turn := down
	var ticks := []
	for k in 30:      # anticlockwise 30 degrees of the wrist: 60 of the knob
		turn = roll.call(turn, -1.0)
		var what: String = kpoke.call(hl, dim_cap, turn)
		if what != "":
			ticks.append(what)
	var at_60: float = Cockpit.tactical_dim
	_check("rolled 30 degrees anticlockwise it turns 60 (%.1f), the display dimmer (%.3f), a tick each 15 (%s)" % [rad_to_deg(Console.STOP - c.knob_angle[0]), at_60, ticks],
		absf(rad_to_deg(Console.STOP - c.knob_angle[0]) - 60.0) < 0.5 and absf(at_60 - Console.value_at("dim", Console.STOP - deg_to_rad(60.0))) < 0.002 and ticks.count("tick") >= 3)
	ticks.clear()
	for k in 28:      # clockwise back, to within the detent of its stop
		turn = roll.call(turn, 1.0)
		var what: String = kpoke.call(hl, dim_cap, turn)
		if what != "":
			ticks.append(what)
	var notched: float = Cockpit.tactical_dim
	turn = roll.call(turn, -40.0)      # a jump in the roll: 40 degrees in a frame
	var jumped: String = kpoke.call(hl, dim_cap, turn)
	_check("rolled back 28 it falls into its detent at 1, exactly (%.3f; %s); a jump of 40 degrees' roll in a frame moves nothing (\"%s\", %.3f)" % [notched, ticks, jumped, Cockpit.tactical_dim],
		notched == 1.0 and ticks.has("notch") and jumped == "" and Cockpit.tactical_dim == 1.0)
	ticks.clear()
	for k in 160:      # anticlockwise past the other stop
		turn = roll.call(turn, -1.0)
		var what: String = kpoke.call(hl, dim_cap, turn)
		if what != "":
			ticks.append(what)
	var second_took := -1.0
	for k in 30:
		if kpoke.call(hr, dim_cap + Vector3(0.01, 0.0, 0.0), down) == "held":
			second_took = k
	var unsaved: bool = not _saved().has("tactical_dim") or float(_saved().tactical_dim) == 1.0
	var off := []
	for k in 10:
		var what: String = kpoke.call(hl, dim_cap + Vector3(0.0, 0.012 * (k + 1), 0.0), turn)
		if what != "":
			off.append(what)
	_park(hr)
	_check("on past the other stop it stops there (%.2f, \"end\" %s); a second hand cannot take it meanwhile (%s); lifted away it is let go (%s) and that is saved (\"tactical_dim\": %s; not while it was held: %s)" % [
			Cockpit.tactical_dim, ticks.has("end"), second_took < 0.0, off, _saved().get("tactical_dim", "nothing"), unsaved],
		Cockpit.tactical_dim == Console.DIM_LEAST and ticks.has("end") and second_took < 0.0 and off == ["let_go"] and unsaved and absf(float(_saved().get("tactical_dim", -1.0)) - Console.DIM_LEAST) < 0.001)
	# TAC WARN: clockwise is sooner
	var warn_cap := Console.knob_cap(1)
	_put(hl, Vector3(0.0, 0.55, 0.25))
	for k in 30:
		if kpoke.call(hr, warn_cap, down) == "held":
			break
	turn = down
	for k in 20:
		turn = roll.call(turn, 1.0)
		kpoke.call(hr, warn_cap, turn)
	var sooner: float = Cockpit.tactical_pace
	ticks.clear()
	for k in 22:
		turn = roll.call(turn, -1.0)
		var what: String = kpoke.call(hr, warn_cap, turn)
		if what != "":
			ticks.append(what)
	var back_in: float = Cockpit.tactical_pace
	for k in 50:
		turn = roll.call(turn, -1.0)
		kpoke.call(hr, warn_cap, turn)
	var later: float = Cockpit.tactical_pace
	for k in 10:
		kpoke.call(hr, warn_cap + Vector3(0.0, 0.012 * (k + 1), 0.0), turn)
	_check("TAC WARN: straight ahead it is the display's own pace (1); rolled 20 degrees clockwise the rails warn sooner (%.3f), back 22 it falls into its detent at 1 exactly (%.3f; %s), on anticlockwise later (%.3f); let go, saved (\"tactical_pace\": %s)" % [
			sooner, back_in, ticks, later, _saved().get("tactical_pace", "nothing")],
		absf(sooner - Console.value_at("pace", deg_to_rad(40.0))) < 0.002 and sooner < 1.0 and back_in == 1.0 and ticks.has("notch") and later > 1.3
		and absf(float(_saved().get("tactical_pace", -1.0)) - later) < 0.001 and c.knob_held == [null, null])
	# (merged with the tactical display's own settings, push 44: the knobs reach the display as they are turned)
	_check("the knobs' settings reach the tactical display, which reads them every frame: pace %.3f against TAC WARN's %.3f, dim %.3f against TAC DIM's %.3f" % [
			Tactical.pace, Cockpit.tactical_pace, Tactical.dim, Cockpit.tactical_dim],
		v.has_method("_apply_tactical_knobs") and Tactical.pace == Cockpit.tactical_pace and Tactical.dim == Cockpit.tactical_dim and Tactical.pace > 1.3)
	var dim_saved: float = Cockpit.tactical_dim
	var pace_saved: float = Cockpit.tactical_pace

	# ---- cost: the hands loop's console work, a frame, two hands (parked; one at rest on a bat)
	_park(hl)
	_park(hr)
	var t0 := Time.get_ticks_usec()
	for k in 2000:
		v._work_controls(hl, hr, FRAME)
		v._show_console(FRAME)
	var parked_us := (Time.get_ticks_usec() - t0) / 2000.0
	var on_bat := Console.toggle_at(1) + Vector3(0.0, 0.03, 0.0)
	_put(hl, on_bat)
	t0 = Time.get_ticks_usec()
	for k in 2000:
		v._work_controls(hl, hr, FRAME)
		v._show_console(FRAME)
	var at_bat_us := (Time.get_ticks_usec() - t0) / 2000.0
	_park(hl)
	for k in 70:
		_tick()
	var t1 := Time.get_ticks_usec()
	for k in 2000:
		v._show_console(FRAME)
	var show_us := (Time.get_ticks_usec() - t1) / 2000.0
	print("CONSOLE_COST hands loop with the switches, two hands parked: %.1f us a frame; one at rest on a bat: %.1f us; the consoles shown: %.1f us" % [parked_us, at_bat_us, show_us])
	_check("cost: the whole hands loop of the switches %.0f us a frame (hands parked), %.0f us with a hand on a bat; showing the consoles %.0f us" % [parked_us, at_bat_us, show_us], at_bat_us < 1000.0)

	hl.queue_free()
	hr.queue_free()
	v.queue_free()
	await process_frame
	# the next cockpit (the next flight): what was saved is read, its knobs stand there, its toggles where the lines are
	Cockpit._options_loaded = false
	Cockpit.tactical_dim = 1.0
	Cockpit.tactical_pace = 1.0
	await _cockpit()
	v._show_console(FRAME)
	_check("the next cockpit reads them: TAC DIM %.2f, TAC WARN %.2f, its knobs there (%.2f, %.2f)" % [Cockpit.tactical_dim, Cockpit.tactical_pace, v.console.knob_value("dim"), v.console.knob_value("pace")],
		absf(Cockpit.tactical_dim - dim_saved) < 0.001 and absf(Cockpit.tactical_pace - pace_saved) < 0.001 and absf(v.console.knob_value("dim") - dim_saved) < 0.002
		and absf(v.console.knob_value("pace") - pace_saved) < 0.002)
	v.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.tactical_dim = 1.0
	Cockpit.tactical_pace = 1.0
	Cockpit.consumables = false
	View.avoid_on = false
	View.power_ups_on = true
	Cockpit.speed_rush = true
	Tactical.wanted = false
	Tactical.pace = 1.0      # (the knobs reach the display now: put its settings back for whatever runs next in this process)
	Tactical.dim = 1.0
	_check("the default settings file is as it was (the run had its own)", _settings_back())
	print("CONSOLE SWITCHES %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


## The authored console's whole triangle count, as imported (before it was cut).
func _authored_tris(side: float) -> int:
	var source := (load(preload("res://vr/cockpit_interior.gd").HD_CONSOLE) as PackedScene).instantiate()
	var mesh: Mesh = (source.find_children("ConsoleL" if side < 0.0 else "ConsoleR", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var n := mesh.get_faces().size() / 3
	source.free()
	return n
