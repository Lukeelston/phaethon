## The map's own controls (Luke, flying the fourteenth: "The map could use a switch like the other 2,
## that switches from 'local' to 'global' map. There should also be a button to cycle through
## different color schemes on the map"): the toggle and the button on the map's pod, worked by a hand
## in a real cockpit; what the screen then shows; what is remembered.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_map_controls.gd -- --mute
## Prints MAP CONTROLS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
var v
var hand: Node3D
var failures := 0
var checks := 0


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_map_controls_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true      # the pilot's saved choices stay out of this
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit._map_loaded = true
	Cockpit.map_whole = true
	Cockpit.map_scheme = 0
	Cockpit.cold_start = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The hand's tip at `at` in a node's own frame taken without its scale (metres from its origin).
func _tip_at(node: Node3D, at: Vector3) -> void:
	hand.global_position = node.global_transform.orthonormalized() * at - hand.global_basis * ModeSwitch.TIP


## A flick through the map switch's zone, up (+1) or down (-1), a sixtieth of a second long.
func _flick(dir: int) -> String:
	var sw: Node3D = v.minimap_panel.map_switch
	_tip_at(sw, Vector3(0.0, -0.02 * dir, 0.05))
	v.minimap_panel.poke(hand, 0.0)              # (the hand arrives: where it came from is no part of the flick)
	_tip_at(sw, Vector3(0.0, 0.02 * dir, 0.05))
	return v.minimap_panel.poke(hand, 1.0 / 60.0)


## A push into the colour button's face, and away again.
func _press() -> String:
	var p: Node3D = v.minimap_panel
	var k: float = p.global_transform.basis.get_scale().x      # the pod's scale: BUTTON_AT is in its units
	_tip_at(p, (MapPanel.BUTTON_AT + Vector3(0, 0, 0.06)) * k)
	p.poke(hand, 0.0)
	_tip_at(p, (MapPanel.BUTTON_AT + Vector3(0, 0, 0.012)) * k)
	var worked: String = p.poke(hand, 1.0 / 60.0)
	_tip_at(p, (MapPanel.BUTTON_AT + Vector3(0, 0, 0.09)) * k)
	p.poke(hand, 1.0 / 60.0)
	return worked


## What the cockpit does with what the pod reported (as _read_input does).
func _work(worked: String) -> String:
	if worked == "global" or worked == "local":
		v.set_map_whole(worked == "global")
	elif worked == "scheme":
		v.set_map_scheme(Cockpit.map_scheme + 1)
	return worked


## One frame of the map as the cockpit draws it.
func _frame() -> Dictionary:
	v.minimap.whole = Cockpit.map_whole
	v.minimap_panel.show_controls(not Cockpit.map_whole, 1.0)
	var f: Dictionary = v.minimap.update(v.sim.pod.th, 1.0 / 90.0)
	v.minimap_panel.show_frame(f)
	return f


## A rest, by the wall clock (the controls' own rests are timed by it, whatever the engine's time is doing).
func _rest(ms: int) -> void:
	var from := Time.get_ticks_msec()
	while Time.get_ticks_msec() - from < ms:
		await process_frame


## The whole map's roads as drawn now (null when they are put away or not drawn yet).
func _roads() -> Mesh:
	var roads: MeshInstance3D = v.minimap_panel._roads
	return roads.mesh if roads != null else null


## The colours a mesh is drawn in, as a set of their hex names (alpha left out).
func _inks(mesh: Mesh) -> Dictionary:
	var seen := {}
	if mesh == null or mesh.get_surface_count() == 0:
		return seen
	var colours: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for k in range(0, colours.size(), 6):
		seen[Color(colours[k], 1.0).to_html(false)] = true
	return seen


## Is this colour among a mesh's inks? (A mesh keeps colours in eight bits: within two steps of it.)
func _has_ink(inks: Dictionary, colour: Color) -> bool:
	for name: String in inks:
		var ink := Color.html(name)
		if absf(ink.r - colour.r) < 0.009 and absf(ink.g - colour.g) < 0.009 and absf(ink.b - colour.b) < 0.009:
			return true
	return false


func _run() -> void:
	var prefs_before := FileAccess.get_file_as_string(Cockpit.PREFS) if FileAccess.file_exists(Cockpit.PREFS) else ""
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	hand = Node3D.new()
	root.add_child(hand)
	var p = v.minimap_panel
	_check("the map is in its pod and has its controls: a toggle and a button on a strip of their own", p != null and p.map_switch != null and p.button != null and p.get_node_or_null("controls") != null)
	if p == null or p.map_switch == null:
		print("MAP CONTROLS FAIL (no controls: %d failures)" % failures)
		quit(1)
		return

	# ---- where they are
	var sw: ModeSwitch = p.map_switch
	var rig: Transform3D = v.shell.global_transform      # the cabin's own frame: EYE and the furniture are in it
	var eye: Vector3 = rig * Cockpit.EYE
	var shoulder: Vector3 = rig * (Cockpit.EYE + Vector3(-0.18, -0.2, 0.05))
	var k: float = p.global_transform.basis.get_scale().x
	var button_at: Vector3 = p.global_transform * MapPanel.BUTTON_AT
	_check("they stand on top of the pod (their middle %.0f mm over the screen's top edge), the toggle %.0f mm left of the button; from the left shoulder the toggle is %.2f m and the button %.2f m" % [
		(MapPanel.CONTROLS_Y - MapPanel.H / 2.0) * k * 1000.0, (sw.global_position - button_at).length() * 1000.0, shoulder.distance_to(sw.global_position), shoulder.distance_to(button_at)],
		MapPanel.CONTROLS_Y > MapPanel.H / 2.0 + 0.05 and sw.position.x < MapPanel.BUTTON_AT.x - 0.08 and shoulder.distance_to(sw.global_position) < 0.82 and shoulder.distance_to(button_at) < 0.82)
	# A hand throwing the map's switch or pressing its button is in neither of the other switches' boxes.
	var strays := []
	for other: ModeSwitch in [v.slide_switch, v.mode_switch]:
		var into: Transform3D = other.global_transform.affine_inverse()
		for sx in [-1.0, 0.0, 1.0]:
			for sy in [-1.0, 0.0, 1.0]:
				for sz in [0.0, 0.5, 1.0]:
					var at: Vector3 = sw.global_transform.orthonormalized() * Vector3(sx * MapPanel.SWITCH_ZONE.x, sy * MapPanel.SWITCH_ZONE.y, sz * MapPanel.SWITCH_ZONE.z)
					var q: Vector3 = into * at
					if absf(q.x) < ModeSwitch.ZONE.x and absf(q.y) < ModeSwitch.ZONE.y and q.z > -0.01 and q.z < ModeSwitch.ZONE.z:
						strays.append([other.name, at])
		var qb: Vector3 = into * (p.global_transform * (MapPanel.BUTTON_AT + Vector3(0, 0, 0.03)))
		if absf(qb.x) < ModeSwitch.ZONE.x and absf(qb.y) < ModeSwitch.ZONE.y and qb.z > -0.01 and qb.z < ModeSwitch.ZONE.z:
			strays.append([other.name, "button"])
	_check("the toggle's box and the button are clear of the SLIDE and MODE switches' boxes (the SLIDE switch is %.2f m off; inside: %s)" % [sw.global_position.distance_to(v.slide_switch.global_position), strays.slice(0, 3)], strays.is_empty())
	_check("the toggle's box stops short of the button; from the seat the toggle is %.1f degrees left of ahead and the button %.1f" % [
		rad_to_deg(atan2(-(sw.global_position - eye).dot(rig.basis.x), -(sw.global_position - eye).dot(rig.basis.z))),
		rad_to_deg(atan2(-(button_at - eye).dot(rig.basis.x), -(button_at - eye).dot(rig.basis.z)))],
		(sw.position.x + MapPanel.SWITCH_ZONE.x / k) < MapPanel.BUTTON_AT.x - MapPanel.BUTTON_REACH)

	# ---- the switch
	var f := _frame()
	_check("it starts GLOBAL: the lever up, the whole country on the screen", not sw.down and f.has("whole") and p._roads != null and p._roads.visible)
	_check("a hand flicks the lever down: \"%s\"" % _work(_flick(-1)), not Cockpit.map_whole and sw.down)
	f = _frame()
	_check("LOCAL: the roads round the craft, heading up (%d inks in what is drawn), the whole map's roads put away" % _inks(p.lines).size(), not f.has("whole") and p._roads != null and not p._roads.visible and _inks(p.lines).size() > 1)
	_check("the same hand cannot throw it straight back (a rest between throws)", _flick(1) == "" and sw.down)
	await _rest(900)
	_check("after the rest a flick up: \"%s\"" % _work(_flick(1)), Cockpit.map_whole and not sw.down)
	f = _frame()
	_check("GLOBAL again: the whole country back", f.has("whole") and p._roads != null and p._roads.visible)
	await _rest(900)
	_check("a flick up when it is up already does nothing", _flick(1) == "" and Cockpit.map_whole)

	# ---- the button
	var first := _inks(_roads())
	var glass0: Color = p._glass.albedo_color
	_check("a push into the button: \"%s\"; the toggle is not thrown by it" % _work(_press()), Cockpit.map_scheme == 1 and p.scheme == 1 and Cockpit.map_whole and not sw.down)
	f = _frame()
	var second := _inks(_roads())
	_check("the screen is drawn again in %s: the roads' inks changed (%s to %s), the glass too, and the readout names it: \"%s\"" % [MapPanel.SCHEMES[1].name, first.keys().slice(0, 2), second.keys().slice(0, 2), p.label.text],
		not second.is_empty() and second.keys() != first.keys() and p._glass.albedo_color != glass0 and p.label.text.contains(String(MapPanel.SCHEMES[1].name)))
	_check("a second push at once is not taken (the button's own rest)", _press() == "" and Cockpit.map_scheme == 1)
	var names := [String(MapPanel.SCHEMES[1].name)]
	var all_differ := true
	var seen_inks := {"%s" % [first.keys()]: true, "%s" % [second.keys()]: true}
	for step in range(2, MapPanel.SCHEMES.size() + 1):
		await _rest(550)
		_work(_press())
		_frame()
		names.append(String(MapPanel.SCHEMES[Cockpit.map_scheme].name))
		var key := "%s" % [_inks(_roads()).keys()]
		if step < MapPanel.SCHEMES.size():
			all_differ = all_differ and not seen_inks.has(key)
			seen_inks[key] = true
	_check("pushes step through every scheme and round to the first again (%s), each with inks of its own" % ", ".join(names),
		names.size() == MapPanel.SCHEMES.size() and Cockpit.map_scheme == 0 and names[-1] == String(MapPanel.SCHEMES[0].name) and all_differ and MapPanel.SCHEMES.size() >= 4)
	_check("... and the first is the map as it was: the SPEEDCRAFT blue and STARFIGHTER magenta, the dark glass", MapPanel.SCHEMES[0].speed == MapPanel.SP_COL and MapPanel.SCHEMES[0].star == MapPanel.SF_COL and p._glass.albedo_color == glass0)
	# local view in another scheme: its path is drawn in that scheme's inks
	v.set_map_scheme(2)
	v.set_map_whole(false)
	_frame()
	var path := _inks(p.lines)
	_check("the local map takes the scheme too (%d inks in its path: %s; the scheme's road colours among them)" % [path.size(), path.keys()],
		(_has_ink(path, MapPanel.SCHEMES[2].speed) or _has_ink(path, MapPanel.SCHEMES[2].star)) and not _has_ink(path, MapPanel.SP_COL) and not _has_ink(path, MapPanel.SF_COL))

	# ---- dark, and remembered
	p.set_live(false)
	_check("with the screen dark (the battery off) the controls do nothing", _flick(1) == "" and _press() == "" and not Cockpit.map_whole and Cockpit.map_scheme == 2)
	p.set_live(true)
	var saved: Dictionary = v._load_prefs()
	_check("the choice is saved (%s, %s)" % [saved.get("map", "?"), saved.get("map_scheme", "?")], saved.get("map", "") == "local" and saved.get("map_scheme", "") == String(MapPanel.SCHEMES[2].name))
	v.queue_free()
	await process_frame
	Cockpit.map_whole = true
	Cockpit.map_scheme = 0
	Cockpit._map_loaded = false
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v._update_hud()          # (a frame of the cockpit's own drawing: the saved choice reaches the pod there)
	_check("... and the next cockpit comes up with it: LOCAL, the lever down, in %s" % MapPanel.SCHEMES[v.minimap_panel.scheme].name,
		not Cockpit.map_whole and Cockpit.map_scheme == 2 and v.minimap_panel.scheme == 2 and v.minimap_panel.map_switch.down)
	v.queue_free()
	await process_frame
	# the pilot's own file as it was found
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	else:
		var out := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	Cockpit.map_whole = true
	Cockpit.map_scheme = 0
	print("MAP CONTROLS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
