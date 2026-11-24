## The title (release/title_stage.gd, release/title_letters.gd): it stands round both menus, the menus
## work at once and start a flight exactly as they did, a flight has none of it, and the menu has it
## again afterwards. Breaks it is here to catch: a title that is a step before the menu, a board hidden
## in the scene or the scene hidden by the board, a craft or the word standing in the board's way, a
## title that outlives the menu (its nodes, its hour in the shaders, what it loaded), a desktop picture
## composed under the menu's panels.
## Prints TITLE PASS. Run headless: --headless --xr-mode off -s res://tests/test_title.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Stage := preload("res://release/title_stage.gd")
const Letters := preload("res://release/title_letters.gd")
const Settings := preload("res://release/game_settings.gd")
const UI := preload("res://release/release_config.gd")
const Outlook := preload("res://view/outlook.gd")
const Shrike := preload("res://view/shrike_airframe.gd")
const CraftModel := preload("res://view/craft_model.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")

var checks := 0
var failures := 0
var saved := {}


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> bool:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)
	return ok


func frames(count: int) -> void:
	for i in count:
		await process_frame


## Degrees up from level, and right of `forward`, of a place as seen from `eye`.
func _sight(eye: Vector3, forward: Vector3, at: Vector3) -> Vector2:
	var d := at - eye
	var right := forward.cross(Vector3.UP).normalized()
	return Vector2(rad_to_deg(atan2(d.dot(right), d.dot(forward))), rad_to_deg(atan2(d.y, Vector2(d.dot(right), d.dot(forward)).length())))


## The word's own corners in its mesh's space (cap heights): its faces' four (the italic's lean taken:
## a box round it has corners no letter is at), and with `stroke` the two ends of the stroke's underside.
func _word_corners(stroke: bool) -> Array:
	var wide := Letters.width(Stage.WORD)
	var out := [Vector3(0.0, 0.0, Letters.PROUD), Vector3(wide, 0.0, Letters.PROUD), Vector3(Letters.SLANT, 1.0, Letters.PROUD), Vector3(wide + Letters.SLANT, 1.0, Letters.PROUD)]
	if stroke:
		out.append_array([Vector3(-0.58, -0.36, 0.0), Vector3(wide + 0.27, -0.36, 0.0)])
	return out


func _fits(node: Node, bounds: Rect2) -> bool:
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		if not bounds.encloses(node.get_global_rect()):
			print("  OUTSIDE: ", node.text, " ", node.get_global_rect())
			return false
	for child in node.get_children():
		if not _fits(child, bounds):
			return false
	return true


func _count(node: Node, named: String) -> int:
	var n := int(node.name == named)
	for child in node.get_children():
		n += _count(child, named)
	return n


func _run() -> void:
	for path in [Settings.PREFS, Cockpit.PREFS]:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	Settings.set_selected_craft("phaethon")      # (the flights here are the Phaethon's: the Shrike's maps must then be the title's alone)
	_letters()
	await _headset()
	await _desktop()
	await _switched_off()
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved[path])
			file.close()
	print("TITLE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _wait_for_art(stage) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while not stage.art_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	return check("the complete title arrives behind the usable menu within 3 s (%s)" % stage.build_split,
		stage.art_ready and stage.build_ms < 3000 and stage.build_split.frames > 1)


func _letters() -> void:
	var missing := []
	var thin := []
	for i in Stage.WORD.length():
		var letter := Stage.WORD[i]
		if Letters.glyph(letter).is_empty():
			missing.append(letter)
			continue
		var solo: ArrayMesh = Letters.word(letter, false)
		var box := solo.get_aabb()
		# a whole letter: a cap high, as deep as the word, and most of its box filled with face (a failed triangulation leaves sides and no face)
		var face := 0.0
		var arrays := solo.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for t in range(0, verts.size(), 3):
			if absf(colours[t].r - Letters.CREAM.r) + absf(colours[t].g - Letters.CREAM.g) + absf(colours[t].b - Letters.CREAM.b) < 0.02:      # (a mesh's colours are 8-bit)
				face += (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).length() / 2.0
		if absf(box.size.y - 1.0) > 0.01 or absf(box.size.z - Letters.DEPTH - Letters.PROUD) > 0.01 or face < 0.25 * box.size.x * box.size.y:
			thin.append("%s: %s, face %.2f" % [letter, box.size, face])
	check("every letter of %s is drawn, a cap high, with its cream face (missing %s, wrong %s)" % [Stage.WORD, missing, thin], missing.is_empty() and thin.is_empty())
	var word: ArrayMesh = Letters.word(Stage.WORD)
	var tris: int = (word.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var wide := Letters.width(Stage.WORD)
	check("the word is one mesh of %d triangles, %.2f caps wide, its stroke under it (box %s)" % [tris, wide, word.get_aabb()],
		tris > 600 and tris < 6000 and wide > 6.0 and wide < 9.5 and word.get_aabb().position.y < -0.3 and word.get_aabb().size.x > wide)


func _headset() -> void:
	check("the title is on unless switched off", Stage.enabled)
	change_scene_to_file(UI.VR_MENU_SCENE)
	await scene_changed
	var menu = current_scene
	# at once: the board is there to be used in the frame the menu arrives, before anything else is asked of the pilot
	var stage = menu.stage
	if not check("the headset's menu stands in the title, laid out for the headset", stage != null and stage is Stage and stage.layout == "vr" and stage.is_inside_tree()):
		return
	check("the menu is usable in its first frame: its rows are there, one has the highlight, nothing is launching",
		menu.buttons.size() > UI.COURSES.size() and menu.focus_index == UI.course_index(menu.selected_course) and not menu.launching and menu.board.visible)
	menu.set_process(false)
	if not await _wait_for_art(stage):
		return
	print("TITLE build: %d ms (headset layout) %s" % [stage.build_ms, stage.build_split])
	check("one sky: the title's, not the board's old dark", menu.find_children("*", "WorldEnvironment", true, false).size() == 1 and stage.environment.environment.background_mode == Environment.BG_SKY)
	check("no engine sounds in the menu", menu.find_children("*", "AudioStreamPlayer", true, false).is_empty() and menu.find_children("*", "AudioStreamPlayer3D", true, false).is_empty())
	# what it is made of
	check("the word is PHAETHON in solid letters, unshaded cream and orange-red", stage.letters != null and stage.letters.mesh != null
		and (stage.letters.material_override as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	var kinds := []
	for c: Dictionary in stage.craft:
		kinds.append("%s/%s/%.0f" % [c.sim.P.vehicle, "sf" if c.sim.hblend > 0.5 else "speed", c.sim.eL.thrust * 100.0])
	check("two craft, the game's own models: the Phaethon on SPEEDCRAFT's links and the Shrike on STARFIGHTER's, both idling (%s)" % [kinds],
		stage.craft.size() == 2 and stage.craft[0].model is CraftModel and stage.craft[0].sim.P.vehicle == "phaethon" and stage.craft[1].sim.P.vehicle == "shrike"
		and stage.craft[0].sim.hblend == 0.0 and stage.craft[1].sim.hblend == 1.0 and stage.craft[0].model.engines.size() == 2
		and stage.craft[1].model.engines[0].has_node("ShrikeFairing") and stage.craft[0].model.engines[0].has_node("NacelleShell")
		and stage.craft[0].model.pod.has_node("pilot") and stage.craft[1].model.pod.has_node("pilot"))
	var parts := []
	for part in ["road", "kerb", "structures", "mesas", "skyline", "clouds", "ground", "stand"]:
		if stage.world.get_node_or_null(part) == null:
			parts.append(part)
	check("the road and its kerb, the road on pillars and the shaft, mesas, the city, the cloud deck and the stand are all there (missing %s)" % [parts], parts.is_empty())
	# where it stands: round the pilot's eye, the board in front of him, the word over the board, a craft on either hand
	var eye: Vector3 = menu.camera.global_position
	var forward: Vector3 = -menu.camera.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var board: MeshInstance3D = menu.board
	var half: Vector2 = (board.mesh as QuadMesh).size / 2.0
	var to_board := board.global_position - eye
	check("the stand's deck is %.2f m under the eye, level" % Stage.EYE, absf(stage.global_position.y - (eye.y - Stage.EYE)) < 0.001 and stage.global_basis.y.is_equal_approx(Vector3.UP))
	check("the board is 3 m in front, %.2f m under the eye, and faces it (%.3f)" % [menu.BOARD_DROP, board.global_basis.z.dot(-to_board.normalized())],
		absf(Vector2(to_board.x, to_board.z).length() - 3.0) < 0.01 and absf(to_board.y + menu.BOARD_DROP) < 0.001 and board.global_basis.z.dot(-to_board.normalized()) > 0.999)
	var board_top: float = _sight(eye, forward, board.global_transform * Vector3(0.0, half.y, 0.0)).y
	var board_side: float = _sight(eye, forward, board.global_transform * Vector3(half.x, 0.0, 0.0)).x
	var word_hi := -INF
	var word_side := 0.0
	for corner: Vector3 in _word_corners(true):
		var s := _sight(eye, forward, stage.letters.global_transform * corner)
		word_hi = maxf(word_hi, s.y)
		word_side = maxf(word_side, absf(s.x))
	# ... and its stroke, the lowest of it, clears the board's top wherever it is over the board (its ends run on past the board's sides)
	var corners := _word_corners(true)
	var over_board := INF
	for i in 41:
		var s := _sight(eye, forward, stage.letters.global_transform * (corners[4] as Vector3).lerp(corners[5], float(i) / 40.0))
		if absf(s.x) < board_side + 1.0:
			over_board = minf(over_board, s.y)
	check("the word stands over the board's top edge and under where the neck has to work: its stroke %.1f degrees up at its lowest over the board (the board's top %.1f), its top %.1f, within %.1f degrees of straight ahead" % [over_board, board_top, word_hi, word_side],
		over_board > board_top + 0.5 and word_hi < 30.0 and word_side < 38.0)
	var nearest := INF
	var low := INF
	var high := -INF
	for c: Dictionary in stage.craft:
		for k in 2:
			var engine: Node3D = c.model.engines[k]
			for x in [-2.3, 2.3]:      # (an engine's half-width and its outboard fin)
				nearest = minf(nearest, absf(_sight(eye, forward, engine.global_transform * Vector3(x, 0.0, -3.85)).x))
			var up: float = engine.global_position.y - stage.world.global_position.y
			low = minf(low, up)
			high = maxf(high, up)
		for part in c.model.link_parts[0]:
			if not (part as Node3D).visible:
				nearest = -1.0      # (a link not drawn)
	check("each craft is clear of the board's edges (nearest %.1f degrees off ahead, the board's edge %.1f), its links drawn" % [nearest, board_side], nearest > board_side + 1.0)
	check("the engines ride at their hover height over the road (%.2f to %.2f m), not in it or adrift" % [low, high], low > 1.35 and high < 1.85)
	var strap: Node3D = menu.strap
	check("the strap line hangs under the board", strap != null and strap.get_parent() == board and (strap.get_node("lean/words") as Label3D).text == Stage.STRAP and strap.position.y < -half.y)
	# nothing moves the camera, and the scene stands still but for its small motions
	var cam_was: Transform3D = menu.camera.global_transform
	var stage_was: Transform3D = stage.global_transform
	var strikes: int = stage.craft[0].model.binder_arc.revision
	var fan: float = (stage.craft[0].model.rotors[0][0] as Node3D).rotation.z
	var cloud_was: Vector2 = (stage.clouds.material_override as ShaderMaterial).get_shader_parameter("world_offset")
	await create_timer(0.3).timeout      # (by the clock: headless frames are too short for an arc to restrike in a dozen)
	check("a third of a second on, the camera and the scene are where they were", menu.camera.global_transform == cam_was and stage.global_transform == stage_was)
	check("... and the scene is alive: the arcs restrike, the fans turn, the clouds drift", stage.craft[0].model.binder_arc.revision > strikes
		and (stage.craft[0].model.rotors[0][0] as Node3D).rotation.z != fan and (stage.clouds.material_override as ShaderMaterial).get_shader_parameter("world_offset") != cloud_was)
	await _turntable(menu, stage, eye, forward)
	# recentred, it all turns together
	menu.camera.rotation.y = deg_to_rad(40.0)
	menu.recenter_panel()
	var turned: Vector3 = -menu.camera.global_basis.z
	check("a recentre turns the board and the scene together", (board.global_position - eye).normalized().dot(turned) > 0.98 and (-stage.global_basis.z).dot(turned) > 0.999)
	menu.camera.rotation.y = 0.0
	menu.recenter_panel()
	# a flight starts as it did: highlight, select, Start. Two presses, no step added.
	menu.choose_course("gp")
	menu.focus_row(UI.course_index("range"))
	menu.consume_controller(0.0, false, true)
	menu.consume_controller(0.0, true, true)
	check("the first press chooses the highlighted map and moves to Start", menu.selected_course == "range" and menu.focus_index == menu.start_index and not menu.launching)
	menu.consume_controller(0.0, false, true)
	menu.consume_controller(0.0, true, true)
	check("the second press launches", menu.launching)
	var old_stage: WeakRef = weakref(stage)
	var old_menu: WeakRef = weakref(menu)
	var old_display_model: WeakRef = weakref(stage.craft[0].model)
	var old_shrike_source: WeakRef = weakref(stage._sources["res://art/shrike/bodywork.glb"])
	stage = null
	menu = null
	board = null
	strap = null
	await scene_changed
	await frames(2)
	var flight = current_scene
	check("the flight is the Sprint, in the real cockpit", flight is Cockpit and flight._track() == "range")
	check("in flight the title is gone: its nodes freed, none left in the tree", old_stage.get_ref() == null and old_menu.get_ref() == null and _count(root, "TitleStage") == 0)
	check("the idle model and its Shrike source are released; the title cache holds two fairing meshes", old_display_model.get_ref() == null
		and old_shrike_source.get_ref() == null and Stage._display_bodies.size() == 2 and Stage._display_bodies.values().all(func(body): return body is ArrayMesh))
	check("... its hour is out of the shaders (the afternoon's suns again)", Outlook.shader_globals.get("sky_sun") == Outlook.GLOBALS.sky_sun and Outlook.shader_globals.get("sky_haze") == Outlook.GLOBALS.sky_haze)
	check("... and what it loaded for itself is let go (the Shrike's bodywork, with the Phaethon flown)", Shrike.meshes.is_empty())
	check("the flight has its own sky and nothing of the title's", flight.find_children("*", "WorldEnvironment", true, false).size() == 1)
	var old_flight: WeakRef = weakref(flight)
	flight.return_to_menu()
	flight = null
	await scene_changed
	await frames(2)
	menu = current_scene
	check("back at the menu the title is back, and the flight freed", menu.scene_file_path == UI.VR_MENU_SCENE and menu.stage != null and menu.stage.is_inside_tree() and old_flight.get_ref() == null
		and menu.selected_course == "range")
	# Launch again while a craft is partly built, with user input and flight paint available between slices.
	var partial = menu.stage
	var deadline := Time.get_ticks_msec() + 3000
	while partial.world.get_node_or_null("craft_phaethon") == null and not partial.art_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	var unfinished: WeakRef = weakref(partial)
	var had_partial: bool = partial.world.has_node("craft_phaethon") and partial.craft.is_empty()
	menu.start_selected()
	await scene_changed
	await frames(2)
	check("starting during craft assembly frees its partial model and leaves the flight in control",
		had_partial and unfinished.get_ref() == null and _count(root, "TitleStage") == 0 and current_scene is Cockpit)
	check("a cancelled title leaves the selected flight paint intact", CraftModel.Livery.current != "boxcover")


## How far the craft on show reaches from the turntable's middle, level (the same however the deck has
## turned it): its engines' noses and tails with their fins, and the pod's corners.
func _reach(stage) -> float:
	var middle: Vector3 = stage.turntable.global_position
	var far := 0.0
	var model = stage.showcase.model
	var points := []
	for k in 2:
		for x in [-2.3, 2.3]:
			for z in [-3.85, 4.2]:
				points.append((model.engines[k] as Node3D).global_transform * Vector3(x, 0.0, z))
	for x in [-1.4, 1.4]:
		for z in [-2.3, 2.3]:
			points.append((model.pod as Node3D).global_transform * Vector3(x, 0.0, z))
	for p: Vector3 in points:
		far = maxf(far, Vector2(p.x - middle.x, p.z - middle.z).length())
	return far


## Wait for the turntable to show `key` (vehicle/livery); true once it does.
func _shown(stage, key: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while stage.showcase.get("key", "") != key and Time.get_ticks_msec() < deadline:
		await process_frame
	return stage.showcase.get("key", "") == key


## The turntable (Luke, 2026-11-23: "when you choose a vehicle, it rotates in front of the player"): the
## chosen craft on it in its flight's paint, turning, straight ahead behind the board; the board swinging
## aside, clear of its sweep, while a row that changes it has the highlight, and back after; each of the
## five craft coming onto it as it is chosen; a new paint coming onto it.
func _turntable(menu, stage, eye: Vector3, forward: Vector3) -> void:
	var on_show: Dictionary = stage.showcase
	if not check("a turntable is built in the title with the chosen pilot craft on it, in the next flight's paint (%s)" % [on_show.get("key", "none")],
			stage.turntable != null and not on_show.is_empty() and on_show.sim.P.vehicle == Settings.selected_craft() and String(on_show.key).ends_with("/" + Stage.flight_livery())
			and on_show.model is CraftModel and on_show.model.pod.has_node("pilot")):
		return
	check("... put away under the road until a craft is being chosen: the title is as it was", not stage.turntable_base.visible and stage.turntable_base.position.y <= -Stage.SHOW_SINK + 0.001
		and stage.turntable_base.global_position.y + Stage.SHOW_H + 0.06 < stage.world.global_position.y)
	var middle: Vector3 = stage.turntable.global_position
	var ahead := _sight(eye, forward, middle)
	var away: float = Vector2(middle.x - eye.x, middle.z - eye.z).length()
	check("... straight ahead of the pilot (%.1f degrees off), %.0f m out, behind the board" % [ahead.x, away], absf(ahead.x) < 1.0 and away > 20.0)
	# the board: in front until a row that changes the craft has had the highlight a moment, then aside
	var board: MeshInstance3D = menu.board
	var half: Vector2 = (board.mesh as QuadMesh).size / 2.0
	var home: Transform3D = board.global_transform
	var row: int = menu.buttons.find(menu.craft_selector.button)
	menu.focus_row(row)
	menu.update_swing(0.1)
	check("the highlight passing over the pilot craft row leaves the board where it is, the turntable away", board.global_transform.is_equal_approx(home) and not stage.attend_wanted)
	for i in 12:
		menu.update_swing(0.1)
	check("held there, the board swings aside", menu.swing == 1.0 and not board.global_transform.is_equal_approx(home))
	await create_timer(Stage.SHOW_UP_S + 0.9).timeout
	check("... and the turntable comes up out of the road with the craft on it (deck at %.2f m)" % stage.turntable_base.position.y,
		stage.reveal == 1.0 and stage.turntable_base.visible and absf(stage.turntable_base.position.y) < 0.001 and (on_show.holder as Node3D).is_visible_in_tree())
	var engines_up: float = (on_show.model.engines[0] as Node3D).global_position.y - stage.turntable.global_position.y
	check("... its engines hovering over the deck as over a road (%.2f m over the deck's foot)" % engines_up, engines_up > Stage.SHOW_H + 1.3 and engines_up < Stage.SHOW_H + 1.9)
	var spun: float = stage.turntable.rotation.y
	await create_timer(0.3).timeout
	check("... and it turns", absf(wrapf(stage.turntable.rotation.y - spun, -PI, PI)) > deg_to_rad(Stage.SHOW_SPIN * 0.15))
	# each of the five, chosen in turn on that row (A or the trigger), comes onto the deck; the board stays clear of its sweep
	var seen := []
	var reaches := []
	var clear := INF
	var arrived := true
	for i in Pilot.ORDER.size():
		menu.activate()
		var want: String = Pilot.ORDER[(Pilot.ORDER.find(Pilot.STANDARD) + i + 1) % Pilot.ORDER.size()]
		if not await _shown(stage, want + "/" + Stage.flight_livery()):
			seen.append(want + " NOT SHOWN")
			continue
		arrived = arrived and stage._drop > 0.5 and stage._whip > 0.5
		var visible := 0
		for child in stage.turntable.get_children():
			if child is Node3D and String(child.name).begins_with("showcase_") and (child as Node3D).visible:
				visible += 1
		var reach := _reach(stage)
		reaches.append("%s %.1f m" % [want, reach])
		var sweep := rad_to_deg(asin(minf(1.0, reach / away)))
		var edge: float = _sight(eye, forward, board.global_transform * Vector3(half.x, 0.0, 0.0)).x
		clear = minf(clear, -edge - sweep)
		seen.append("%s%s" % [want, "" if visible == 1 and (stage.plate.get_node("board/name") as Label3D).text == String(Pilot.NAMES[want]).to_upper() and reach < Stage.SHOW_R - 0.5 else " (WRONG)"])
		await frames(3)
	check("each pilot craft chosen comes onto the turntable, alone, named on its board, on the deck (%s; reach %s)" % [seen, reaches], seen.size() == Pilot.ORDER.size() and not str(seen).contains("NOT") and not str(seen).contains("WRONG"))
	check("... coming down onto it and swung round as it arrives", arrived)
	check("... and the swung board is clear of each one's sweep (by %.1f degrees at the least)" % clear, clear > 1.0)
	# ... and so are the two craft standing either side (their engines and pods)
	var widest := 0.0
	for r: String in reaches:
		widest = maxf(widest, float(r.get_slice(" ", 1)))
	var gap := INF
	for c: Dictionary in stage.craft:
		var points := []
		for k in 2:
			for x in [-2.3, 2.3]:
				for z in [-3.85, 4.2]:
					points.append((c.model.engines[k] as Node3D).global_transform * Vector3(x, 0.0, z))
		for x in [-1.4, 1.4]:
			for z in [-2.3, 2.3]:
				points.append((c.model.pod as Node3D).global_transform * Vector3(x, 0.0, z))
		for p: Vector3 in points:
			gap = minf(gap, Vector2(p.x - middle.x, p.z - middle.z).length() - widest)
	check("the longest craft's sweep (%.1f m) passes the two craft either side with room (%.1f m at the closest)" % [widest, gap], gap > 0.5)
	# a new paint comes onto the turntable (the paint row also swings the board aside)
	var paint_row := -1
	for i in menu.buttons.size():
		if menu.buttons[i] is Button and String(menu.buttons[i].text).begins_with("Paint:"):
			paint_row = i
	var was_paint := Stage.flight_livery()
	menu.focus_row(paint_row)
	menu.activate()
	var now_paint := Stage.flight_livery()
	var repainted: bool = await _shown(stage, Pilot.STANDARD + "/" + now_paint)
	check("choosing a paint puts the craft on show in it (%s to %s)" % [was_paint, now_paint], now_paint != was_paint and repainted)
	for i in Livery.ids_for(Pilot.STANDARD).size() - 1:      # (round to the paint it had: the Phaethon's row)
		menu.activate()
	var back: bool = await _shown(stage, Pilot.STANDARD + "/" + was_paint)
	check("... and back (%s)" % Stage.flight_livery(), Stage.flight_livery() == was_paint and back)
	menu.focus_row(menu.start_index)
	for i in 12:
		menu.update_swing(0.1)
	await create_timer(Stage.SHOW_DOWN_S + 0.3).timeout
	check("with the highlight off those rows the board swings back to where it was, and the turntable is put away", menu.swing == 0.0 and board.global_transform.is_equal_approx(home)
		and stage.reveal == 0.0 and not stage.turntable_base.visible)


func _desktop() -> void:
	var overlay = root.get_node_or_null("ReleasePause")
	change_scene_to_file(UI.MENU_SCENE)
	await scene_changed
	await frames(2)
	var menu = current_scene
	var stage = menu.stage
	if not check("the desktop menu lies over the title, laid out for the desktop", menu is Control and stage != null and stage.layout == "flat" and stage.camera != null):
		return
	var window := Vector2(1280, 720)
	check("the menu's labels and buttons fit the 1280 x 720 window", _fits(menu, Rect2(Vector2.ZERO, window)))
	check("the menu works at once: a course has the keyboard's focus, every course has its button",
		menu.get_viewport().gui_get_focus_owner() == menu.find_child("Course_range", true, false) and menu.find_children("Course_*", "Button", true, false).size() == UI.COURSES.size())
	check("the picture is the title's own camera, one that does not move", menu.get_viewport().get_camera_3d() == stage.camera and stage.camera.projection == Camera3D.PROJECTION_FRUSTUM and stage.get_script() == Stage)
	var art: Rect2 = menu.art
	var spine := menu.get_node("Spine") as Control
	var strip := menu.get_node("Controls") as Control
	var strap := menu.get_node("Strap") as Control
	check("the picture's part of the window is clear of the menu's panels (%s; the spine ends at %.0f, the controls start at %.0f)" % [art, spine.get_global_rect().end.x, strip.get_global_rect().position.y],
		art.size.x > 700.0 and art.size.y > 500.0 and spine.get_global_rect().end.x <= art.position.x + 0.5 and strip.get_global_rect().position.y >= art.end.y - 0.5 and strip.get_global_rect().end.x <= window.x)
	check("the strap line lies across the picture's foot", strap.get_global_rect().end.y <= art.end.y + 0.5 and strap.get_global_rect().position.x >= art.position.x
		and (strap.find_children("*", "Label", true, false)[0] as Label).text == Stage.STRAP)
	if not await _wait_for_art(stage):
		return
	print("TITLE build: %d ms (desktop layout)" % stage.build_ms)
	# composed as the cover is: the word across the top of the picture, the craft under the horizon, all inside it
	var word_box := Rect2()
	var first := true
	for corner: Vector3 in _word_corners(false):
		var at: Vector2 = stage.camera.unproject_position(stage.letters.global_transform * corner)
		word_box = Rect2(at, Vector2.ZERO) if first else word_box.expand(at)
		first = false
	var horizon: float = stage.camera.unproject_position(stage.camera.global_position + Vector3(0.0, 0.0, -100000.0)).y
	check("the word is across the top of the picture, over the horizon (%s in %s; the horizon at %.0f)" % [word_box, art, horizon],
		art.encloses(word_box) and word_box.size.x > 0.6 * art.size.x and word_box.end.y < horizon and word_box.position.y < art.position.y + 0.1 * art.size.y)
	var craft_box := Rect2()
	first = true
	for c: Dictionary in stage.craft:
		for k in 2:
			for x in [-1.3, 1.3]:
				var at: Vector2 = stage.camera.unproject_position((c.model.engines[k] as Node3D).global_transform * Vector3(x, 0.0, -3.85))
				craft_box = Rect2(at, Vector2.ZERO) if first else craft_box.expand(at)
				first = false
	check("all four engines' noses are in the picture, under the horizon (%s; the horizon at %.0f, %.0f%% down the picture)" % [craft_box, horizon, 100.0 * (horizon - art.position.y) / art.size.y],
		art.encloses(craft_box) and craft_box.position.y > horizon and horizon > art.position.y + 0.3 * art.size.y and horizon < art.position.y + 0.55 * art.size.y)
	# the turntable stands beside the cover's picture, out of it, until a button that changes its craft has the keyboard (or the pointer)
	var home: Transform3D = stage.camera.transform
	var middle: Vector3 = stage.turntable.global_position
	var in_view := 0
	for i in 32:
		var a := TAU * float(i) / 32.0
		for p: Vector3 in [middle + Vector3(sin(a), 0.0, cos(a)) * (Stage.SHOW_R + 1.0) + Vector3.UP * Stage.SHOW_H, middle + Vector3(sin(a), 0.0, cos(a)) * 15.0 + Vector3.UP * 2.5]:
			if not stage.camera.is_position_behind(p) and art.has_point(stage.camera.unproject_position(p)):
				in_view += 1
	check("the turntable is out of the cover's picture (%d of its points in it)" % in_view, in_view == 0 and not stage.showcase.is_empty())
	(menu.craft_selector.button as Button).grab_focus()
	await create_timer(Stage.SHOW_TURN_S + 0.6).timeout
	var on_screen: Vector2 = stage.camera.unproject_position(middle + Vector3.UP * 1.4)
	var show_box := Rect2(on_screen, Vector2.ZERO)
	var turned_was: float = stage.turntable.rotation.y
	for step in 12:      # (all the way round: broadside is its widest)
		stage.turntable.rotation.y = TAU * float(step) / 12.0
		for k in 2:
			for x in [-2.3, 2.3]:
				for z in [-3.85, 4.2]:
					show_box = show_box.expand(stage.camera.unproject_position((stage.showcase.model.engines[k] as Node3D).global_transform * Vector3(x, 0.0, z)))
		for x in [-1.4, 1.4]:
			for z in [-2.3, 2.3]:
				show_box = show_box.expand(stage.camera.unproject_position((stage.showcase.model.pod as Node3D).global_transform * Vector3(x, 0.0, z)))
	stage.turntable.rotation.y = turned_was
	check("with the pilot craft button focused the turntable comes up and the camera turns to it: its middle in the middle of the picture, the craft inside it all the way round (%s, craft %s, picture %s)" % [on_screen, show_box, art],
		stage.attention == 1.0 and stage.reveal == 1.0 and (stage.showcase.holder as Node3D).is_visible_in_tree() and on_screen.distance_to(art.get_center()) < 0.12 * art.size.x
		and art.encloses(show_box) and show_box.size.x > 0.4 * art.size.x)
	(menu.find_child("Course_range", true, false) as Button).grab_focus()
	await create_timer(Stage.SHOW_TURN_S + 0.3).timeout
	check("... and back to the cover's view, exactly, the turntable put away, when the focus moves on", stage.attention == 0.0 and stage.camera.transform.is_equal_approx(home)
		and stage.reveal == 0.0 and not stage.turntable_base.visible)
	# a flight starts as it did, without the title; and the title is back after
	var old_stage: WeakRef = weakref(stage)
	stage = null
	spine = null
	strip = null
	strap = null
	menu.start_course("range")
	menu = null
	await scene_changed
	await frames(2)
	var flight = current_scene
	check("a course's button starts its flight", flight is View and flight.sim.kind == "range")
	check("in flight the title is gone and its camera is not the flight's", old_stage.get_ref() == null and _count(root, "TitleStage") == 0 and flight.get_viewport().get_camera_3d() == flight.cam)
	check("... and its hour is out of the shaders", Outlook.shader_globals.get("sky_sun") == Outlook.GLOBALS.sky_sun)
	if overlay != null:
		overlay.set_paused(true)
		overlay.return_to_menu()
		flight = null
		await scene_changed
		await frames(2)
		check("back at the menu the title is back", current_scene.scene_file_path == UI.MENU_SCENE and current_scene.stage != null and current_scene.stage.camera == current_scene.get_viewport().get_camera_3d())


## Switched off (timings against the menus as they were): the board in its dark, the desktop menu on its
## own ground, nothing of the title built.
func _switched_off() -> void:
	Stage.enabled = false
	change_scene_to_file(UI.VR_MENU_SCENE)
	await scene_changed
	var menu = current_scene
	menu.set_process(false)
	var eye: Vector3 = menu.camera.global_position
	check("switched off, the headset's menu is as it was: no title, its dark, the board level with the eye", menu.stage == null and menu.strap == null and _count(root, "TitleStage") == 0
		and menu.find_children("*", "WorldEnvironment", true, false).size() == 1 and absf(menu.board.global_position.y - eye.y) < 0.001 and absf(menu.board.global_position.distance_to(eye) - 3.0) < 0.001)
	change_scene_to_file(UI.MENU_SCENE)
	await scene_changed
	await frames(2)
	menu = current_scene
	check("... and the desktop menu too: no title, no camera, its panel of controls", menu.stage == null and menu.get_viewport().get_camera_3d() == null and menu.get_node_or_null("Spine") == null
		and _fits(menu, Rect2(Vector2.ZERO, Vector2(1280, 720))))
	Stage.enabled = true
