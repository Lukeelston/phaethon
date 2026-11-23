## The map's own controls (Luke, flying the fourteenth: "The map could use a switch like the other 2,
## that switches from 'local' to 'global' map. There should also be a button to cycle through
## different color schemes on the map"): the toggle and the button on the map's pod, worked by a hand
## in a real cockpit; what the screen then shows; what is remembered.
## And (2026-11-22: "Will you please add a switch to the map that projects it via the hud? Also I think
## the 'local' switch should zoom out a bit") the HUD toggle between them: where it stands, what a hand
## does to it, the map it puts in the windscreen (where that lies from the pilot's eye, what it is drawn
## from, that nothing of it exists while the switch is down), and how much ground LOCAL shows.
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_map_controls.gd -- --mute
## Prints MAP CONTROLS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const MapPanel := preload("res://vr/minimap_panel.gd")
const MapGlass := preload("res://view/minimap_glass.gd")
const MiniMap := preload("res://view/minimap.gd")
const Projector := preload("res://view/approach_projector.gd")
const MPH := 2.236936
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
	Cockpit.map_hud = false
	Cockpit.cold_start = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


## The hand's tip at `at` in a node's own frame taken without its scale (metres from its origin).
func _tip_at(node: Node3D, at: Vector3) -> void:
	hand.global_position = node.global_transform.orthonormalized() * at - hand.global_basis * ModeSwitch.TIP


## A flick through a toggle's zone (the map switch's, unless another is named), up (+1) or down (-1),
## a sixtieth of a second long; `aside`: this far off the toggle's middle (m).
func _flick(dir: int, sw: Node3D = null, aside := 0.0) -> String:
	if sw == null:
		sw = v.minimap_panel.map_switch
	_tip_at(sw, Vector3(aside, -0.02 * dir, 0.05))
	v.minimap_panel.poke(hand, 0.0)              # (the hand arrives: where it came from is no part of the flick)
	_tip_at(sw, Vector3(aside, 0.02 * dir, 0.05))
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
	elif worked == "hud_on" or worked == "hud_off":
		v.set_map_hud(worked == "hud_on")
	elif worked == "scheme":
		v.set_map_scheme(Cockpit.map_scheme + 1)
	return worked


## One frame of the map as the cockpit draws it (the windscreen's map given a second to come up or go out).
func _frame() -> Dictionary:
	v.minimap.whole = Cockpit.map_whole
	v.minimap_panel.show_controls(not Cockpit.map_whole, 1.0, Cockpit.map_hud)
	var f: Dictionary = v.minimap.update(v.sim.pod.th, 1.0 / 90.0)
	if v.minimap_panel.live:
		v.minimap_panel.show_frame(f)
	v.minimap_panel.show_glass(Cockpit.map_hud, 0.0, 1.0)
	return f


## Where a canopy-space point is from the pilot's eye: degrees right of dead ahead, degrees over eye level.
func _seen(at: Vector3) -> Vector2:
	var to: Vector3 = at - MapGlass.EYE
	return Vector2(rad_to_deg(atan2(to.x, -to.z)), rad_to_deg(asin(to.normalized().y)))


## How many nodes there are under the cockpit's canopy.
func _canopy_nodes() -> int:
	return v.canopy.find_children("*", "", true, false).size()


## The local map's frame with the craft at this speed, its zoom settled.
func _local_at(mph: float) -> Dictionary:
	var th: float = v.sim.pod.th
	v.sim.pod.vx = cos(th) * mph / MPH
	v.sim.pod.vy = sin(th) * mph / MPH
	v.minimap.whole = false
	return v.minimap.update(th, 60.0)


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
	_check("the map is in its pod and has its controls: two toggles and a button on a strip of their own", p != null and p.map_switch != null and p.hud_switch != null and p.button != null and p.get_node_or_null("controls") != null)
	if p == null or p.map_switch == null or p.hud_switch == null:
		print("MAP CONTROLS FAIL (no controls: %d failures)" % failures)
		quit(1)
		return

	# ---- where they are
	var sw: ModeSwitch = p.map_switch
	var hud: ModeSwitch = p.hud_switch
	var rig: Transform3D = v.shell.global_transform      # the cabin's own frame: EYE and the furniture are in it
	var eye: Vector3 = rig * Cockpit.EYE
	var shoulder: Vector3 = rig * (Cockpit.EYE + Vector3(-0.18, -0.2, 0.05))
	var k: float = p.global_transform.basis.get_scale().x
	var button_at: Vector3 = p.global_transform * MapPanel.BUTTON_AT
	_check("they stand on top of the pod (their middle %.0f mm over the screen's top edge), the map's toggle %.0f mm left of the HUD's and that %.0f mm left of the button; from the left shoulder they are %.2f, %.2f and %.2f m" % [
		(MapPanel.CONTROLS_Y - MapPanel.H / 2.0) * k * 1000.0, (sw.global_position - hud.global_position).length() * 1000.0, (hud.global_position - button_at).length() * 1000.0,
		shoulder.distance_to(sw.global_position), shoulder.distance_to(hud.global_position), shoulder.distance_to(button_at)],
		MapPanel.CONTROLS_Y > MapPanel.H / 2.0 + 0.05 and sw.position.x < hud.position.x - 0.08 and hud.position.x < MapPanel.BUTTON_AT.x - 0.07
		and shoulder.distance_to(sw.global_position) < 0.82 and shoulder.distance_to(hud.global_position) < 0.82 and shoulder.distance_to(button_at) < 0.82)
	_check("the strip is no wider than the pod it stands on (%.1f mm outboard of the screen's middle to %.1f inboard; the pod's sides are 133.5 out), and the toggles' panels and the button's bezel are on it" % [-MapPanel.STRIP_X.x * 1000.0, MapPanel.STRIP_X.y * 1000.0],
		MapPanel.STRIP_X.x >= -0.1336 and MapPanel.STRIP_X.y <= 0.1336 and sw.position.x - 0.06 * MapPanel.SWITCH_SCALE >= MapPanel.STRIP_X.x and MapPanel.BUTTON_AT.x + 0.021 <= MapPanel.STRIP_X.y)
	# A hand throwing either of the map's switches or pressing its button is in neither of the other switches' boxes.
	var strays := []
	for other: ModeSwitch in [v.slide_switch, v.mode_switch]:
		var into: Transform3D = other.global_transform.affine_inverse()
		for toggle: ModeSwitch in [sw, hud]:
			for sx in [-1.0, 0.0, 1.0]:
				for sy in [-1.0, 0.0, 1.0]:
					for sz in [0.0, 0.5, 1.0]:
						var at: Vector3 = toggle.global_transform.orthonormalized() * Vector3(sx * MapPanel.SWITCH_ZONE.x, sy * MapPanel.SWITCH_ZONE.y, sz * MapPanel.SWITCH_ZONE.z)
						var q: Vector3 = into * at
						if absf(q.x) < ModeSwitch.ZONE.x and absf(q.y) < ModeSwitch.ZONE.y and q.z > -0.01 and q.z < ModeSwitch.ZONE.z:
							strays.append([other.name, toggle.name, at])
		var qb: Vector3 = into * (p.global_transform * (MapPanel.BUTTON_AT + Vector3(0, 0, 0.03)))
		if absf(qb.x) < ModeSwitch.ZONE.x and absf(qb.y) < ModeSwitch.ZONE.y and qb.z > -0.01 and qb.z < ModeSwitch.ZONE.z:
			strays.append([other.name, "button"])
	_check("the toggles' boxes and the button are clear of the SLIDE and MODE switches' boxes (the SLIDE switch is %.2f m from the map's toggle and %.2f m from the HUD's; inside: %s)" % [
		sw.global_position.distance_to(v.slide_switch.global_position), hud.global_position.distance_to(v.slide_switch.global_position), strays.slice(0, 3)], strays.is_empty())
	_check("the map's toggle's box stops short of the HUD's and that short of the button (%.1f mm and %.1f mm between); from the seat they are %.1f, %.1f and %.1f degrees left of ahead" % [
		((hud.position.x - sw.position.x) * k - 2.0 * MapPanel.SWITCH_ZONE.x) * 1000.0, ((MapPanel.BUTTON_AT.x - MapPanel.BUTTON_REACH - hud.position.x) * k - MapPanel.SWITCH_ZONE.x) * 1000.0,
		rad_to_deg(atan2(-(sw.global_position - eye).dot(rig.basis.x), -(sw.global_position - eye).dot(rig.basis.z))),
		rad_to_deg(atan2(-(hud.global_position - eye).dot(rig.basis.x), -(hud.global_position - eye).dot(rig.basis.z))),
		rad_to_deg(atan2(-(button_at - eye).dot(rig.basis.x), -(button_at - eye).dot(rig.basis.z)))],
		(sw.position.x + MapPanel.SWITCH_ZONE.x / k) < hud.position.x - MapPanel.SWITCH_ZONE.x / k and (hud.position.x + MapPanel.SWITCH_ZONE.x / k) < MapPanel.BUTTON_AT.x - MapPanel.BUTTON_REACH)

	# ---- the switch
	var canopy_as_built := _canopy_nodes()
	var f := _frame()
	_check("it starts GLOBAL: the lever up, the whole country on the screen", not sw.down and f.has("whole") and p._roads != null and p._roads.visible)
	_check("... and with the HUD's lever down: nothing in the windscreen, nor anything made to put there (the canopy's %d nodes as built)" % canopy_as_built,
		hud.down and not Cockpit.map_hud and p.glass == null and v.canopy.get_node_or_null("MapGlass") == null and _canopy_nodes() == canopy_as_built and MapGlass._places.is_empty())
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

	# ---- the HUD switch (the map is LOCAL, in PHOSPHOR, as the last check left it)
	await _rest(900)
	_check("a flick down on the HUD's toggle when it is down already does nothing, and nor does one beside it, between it and the button", _flick(-1, hud) == "" and _flick(1, hud, 0.043) == "" and not Cockpit.map_hud and p.glass == null)
	_check("a hand flicks the HUD's lever up: \"%s\"; the map's own toggle and the colours are not touched" % _work(_flick(1, hud)), Cockpit.map_hud and not hud.down and sw.down and not Cockpit.map_whole and Cockpit.map_scheme == 2)
	f = _frame()
	var glass: Node3D = p.glass
	_check("the windscreen has the map: its own patch of the canopy's glass, outside the cabin's fittings, up and lit, and the pod's screen still lit under it",
		glass != null and glass.get_parent() == v.canopy and glass.is_in_group("exterior") and glass.visible and glass.shown == 1.0 and p.live and p.get_node("path").visible
		and float(glass.surface.get_shader_parameter("level")) > 0.99)
	if glass == null:
		print("MAP CONTROLS FAIL (no map in the windscreen: %d failures)" % failures)
		quit(1)
		return
	_check("it is the pod's own drawing, shown again: the same mesh the screen draws its local map with (%d inks, the scheme's among them), the whole map's roads put away; two parts, one material" % _inks(glass.path.mesh).size(),
		glass.path.mesh == p.lines and glass.roads.mesh == null and (_has_ink(_inks(glass.path.mesh), MapPanel.SCHEMES[2].speed) or _has_ink(_inks(glass.path.mesh), MapPanel.SCHEMES[2].star))
		and glass.find_children("*", "MeshInstance3D", true, false).size() == 2 and glass.path.material_override == glass.surface and glass.roads.material_override == glass.surface)
	# where it lies, from the pilot's eye
	var box := [INF, -INF, INF, -INF]
	var far := [INF, -INF]
	var off_glass := 0.0
	var half: Vector2 = MapGlass.PANEL * 0.5
	for i in 33:
		for j in 33:
			var x := lerpf(-half.x, half.x, i / 32.0)
			var y := lerpf(-half.y, half.y, j / 32.0)
			var at: Vector3 = MapGlass.lies_at(x, y)
			var a := _seen(at)
			box = [minf(box[0], a.x), maxf(box[1], a.x), minf(box[2], a.y), maxf(box[3], a.y)]
			far = [minf(far[0], at.distance_to(MapGlass.EYE)), maxf(far[1], at.distance_to(MapGlass.EYE))]
			# off the screen's own surface, along the eye's line: the inset and no more
			var hit: Vector3 = MapGlass.meet(MapGlass.sight(x, y))
			off_glass = maxf(off_glass, absf(ScreenReflection.screen(hit.x, hit.y).distance_to(MapGlass.EYE) - at.distance_to(MapGlass.EYE)))
	_check("it lies in the roof's screen, all of it (within %.1f mm of the glass along the eye's lines), %.2f to %.2f m from the pilot's eye (the pod's screen is %.2f m): a depth the eyes can hold, and the cabin's, not the head's" % [
		off_glass * 1000.0, far[0], far[1], MapPanel.DIST], MapGlass.on_glass() and off_glass < 0.012 and far[0] > 0.65 and far[1] < 1.2 and glass.get_parent() != v.cam and not v.cam.is_ancestor_of(glass))
	_check("low and to the left of the road ahead: from %.1f to %.1f degrees left of dead ahead, %.1f under eye level to %.1f over it (%.1f degrees on a side; the pod's screen fills %.1f)" % [
		-box[1], -box[0], -box[2], box[3], rad_to_deg(MapGlass.ACROSS), rad_to_deg(2.0 * atan(MapPanel.W * MapPanel.SCALE / 2.0 / MapPanel.DIST))],
		box[1] < -13.0 and box[0] > -32.6 and box[2] > -9.6 and box[3] < 6.5 and box[2] < -5.0 and MapGlass.ACROSS > 2.0 * atan(MapPanel.W * MapPanel.SCALE / 2.0 / MapPanel.DIST))
	# the approach readout's page is on the same glass: neither covers the other
	var page_foot := INF
	var page_left := INF
	for i in 41:
		page_foot = minf(page_foot, _seen(Projector.image_point(i / 40.0, 0.0)).y)
		page_left = minf(page_left, _seen(Projector.image_point(0.0, i / 40.0)).x)
	_check("the approach readout's page has its own glass: its foot is %.1f degrees over eye level, %.1f clear of the map's top (its left end is %.1f degrees left); neither gives way" % [page_foot, page_foot - box[3], -page_left],
		v.approach_display != null and v.approach_display.image != null and page_foot - box[3] > 1.0)
	# it follows the map's own switch and the colours
	await _rest(900)
	_work(_flick(1))
	f = _frame()
	_check("the map's toggle up: the windscreen has the whole country too, its roads the pod's own mesh", Cockpit.map_whole and glass.roads.mesh != null and glass.roads.mesh == p._roads.mesh and glass.path.mesh == p.lines)
	v.set_map_scheme(3)
	f = _frame()
	_check("the colour button: the windscreen's roads are the screen's, drawn again in %s" % MapPanel.SCHEMES[3].name, glass.roads.mesh == p._roads.mesh and (_has_ink(_inks(glass.roads.mesh), MapPanel.SCHEMES[3].speed) or _has_ink(_inks(glass.roads.mesh), MapPanel.SCHEMES[3].star)))
	v.set_map_scheme(2)
	v.set_map_whole(false)
	f = _frame()
	# the battery off: the windscreen's map goes with the screen, and comes back with it
	p.set_live(false)
	_frame()
	var dark_then: bool = not glass.visible and glass.path.mesh == null
	p.set_live(true)
	_frame()
	_check("with the screen dark the windscreen's map is dark too, and both come back together", dark_then and glass.visible and glass.path.mesh == p.lines)
	await _rest(900)
	_check("a flick down: \"%s\"; the windscreen is clear again and nothing of the map is drawn in it" % _work(_flick(-1, hud)), not Cockpit.map_hud and hud.down)
	_frame()
	_check("... its parts hidden, their meshes let go, the pod's screen as it was", not glass.visible and glass.path.mesh == null and glass.roads.mesh == null and glass.shown == 0.0 and p.get_node("path").visible)
	await _rest(900)
	_work(_flick(1, hud))
	_frame()

	# ---- LOCAL shows more ground (the Network's local map; a course's map is as it was)
	var said := []
	var grows := true
	var before := 0.0
	var wider := true
	for mph in [0.0, 2000.0, 5000.0]:
		f = _local_at(mph)
		var was: float = MiniMap.target_ahead(mph / MPH)
		var l: Dictionary = MiniMap.layout(f, MapPanel.W, MapPanel.H, MapPanel.MARGIN, MapPanel.TOP)
		var side: float = (MapPanel.W / 2.0 - MapPanel.MARGIN) / float(l.scale)
		var behind: float = (l.craft.y + MapPanel.H / 2.0 - MapPanel.MARGIN) / float(l.scale)
		said.append("%d mph: %.0f m ahead, %.0f m to each side, %.0f m behind (it was %.0f, %.0f and %.0f)" % [int(mph), f.ahead, side, behind, was, side / MiniMap.LOCAL_WIDER, behind / MiniMap.LOCAL_WIDER])
		wider = wider and absf(float(f.ahead) - was * 1.5) < 1.0 and absf(float(f.ahead) - MiniMap.local_reach(mph / MPH)) < 1.0
		grows = grows and float(f.ahead) > before
		before = f.ahead
	_check("LOCAL shows one and a half times the ground at every speed, and still more the faster she goes: %s" % "; ".join(said), wider and grows and MiniMap.LOCAL_WIDER == 1.5)
	_check("... a course's map and the zoom's own limits are as they were (%.0f s of road ahead, %.0f m at the least, %.0f at the most)" % [MiniMap.LOOK_S, MiniMap.MIN_AHEAD, MiniMap.MAX_AHEAD],
		MiniMap.LOOK_S == 12.0 and MiniMap.MIN_AHEAD == 1500.0 and MiniMap.MAX_AHEAD == 25000.0)
	f = _local_at(2000.0)
	# what is on the screen now that the old frame left off: lengths of road with an end outside it
	var laid: Dictionary = MiniMap.layout(f, MapPanel.W, MapPanel.H, MapPanel.MARGIN, MapPanel.TOP)
	var old_ahead: float = MiniMap.target_ahead(2000.0 / MPH)
	var old_side: float = (MapPanel.W / 2.0 - MapPanel.MARGIN) / float(laid.scale) / MiniMap.LOCAL_WIDER
	var old_behind: float = (laid.craft.y + MapPanel.H / 2.0 - MapPanel.MARGIN) / float(laid.scale) / MiniMap.LOCAL_WIDER
	var beyond := 0
	for seg in laid.segs:
		for end: Vector2 in [seg[0], seg[1]]:
			var q: Vector2 = (end - (laid.craft as Vector2)) / float(laid.scale)      # metres from the craft: to the right, ahead
			if q.y > old_ahead or q.y < -old_behind or absf(q.x) > old_side:
				beyond += 1
				break
	v.minimap_panel.show_frame(f)
	_check("at 2,000 mph the screen has road on it that the old frame left off: %d of its %d lengths of road have an end outside what it showed" % [beyond, laid.segs.size()],
		beyond > 0 and beyond < laid.segs.size())
	v.sim.pod.vx = 0.0
	v.sim.pod.vy = 0.0

	# ---- dark, and remembered
	p.set_live(false)
	_check("with the screen dark (the battery off) the controls do nothing", _flick(1) == "" and _press() == "" and _flick(-1, hud) == "" and not Cockpit.map_whole and Cockpit.map_scheme == 2 and Cockpit.map_hud)
	p.set_live(true)
	var saved: Dictionary = v._load_prefs()
	_check("the choice is saved (%s, %s, hud %s)" % [saved.get("map", "?"), saved.get("map_scheme", "?"), saved.get("map_hud", "?")],
		saved.get("map", "") == "local" and saved.get("map_scheme", "") == String(MapPanel.SCHEMES[2].name) and saved.get("map_hud", "") == "on")
	v.queue_free()
	await process_frame
	Cockpit.map_whole = true
	Cockpit.map_scheme = 0
	Cockpit.map_hud = false
	Cockpit._map_loaded = false
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v._update_hud()          # (a frame of the cockpit's own drawing: the saved choice reaches the pod there)
	_check("... and the next cockpit comes up with it: LOCAL, the lever down, in %s, the HUD's lever up and the map in the windscreen" % MapPanel.SCHEMES[v.minimap_panel.scheme].name,
		not Cockpit.map_whole and Cockpit.map_scheme == 2 and v.minimap_panel.scheme == 2 and v.minimap_panel.map_switch.down
		and Cockpit.map_hud and not v.minimap_panel.hud_switch.down and v.minimap_panel.glass != null and v.minimap_panel.glass.visible and v.minimap_panel.glass.get_parent() == v.canopy)
	# a pilot who has never thrown it: his file has no word of it, and the switch is down
	v.queue_free()
	await process_frame
	var old := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
	old.store_string(JSON.stringify({"map": "global", "map_scheme": "NETWORK"}))
	old.close()
	Cockpit.map_hud = true
	Cockpit._map_loaded = false
	v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v._update_hud()
	_check("a file from before the switch was fitted: the HUD's lever is down, and there is nothing in the windscreen", not Cockpit.map_hud and v.minimap_panel.hud_switch.down and v.minimap_panel.glass == null and v.canopy.get_node_or_null("MapGlass") == null)
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
	Cockpit.map_hud = false
	print("MAP CONTROLS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
