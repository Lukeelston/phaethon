## Real scene integration: course routing, pause freezes simulation, restart and return.
## Run headless with -- --mute --job=emergency to check free-flight selection wins.
extends SceneTree

const View := preload("res://view/craft_view.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check("the release menu can be loaded", ResourceLoader.exists("res://release/menu.tscn"))
	_check("the release pause overlay can be loaded", ResourceLoader.exists("res://release/pause_overlay.gd"))
	if failures:
		_finish()
		return
	var overlay = root.get_node_or_null("ReleasePause")
	if overlay == null:
		overlay = load("res://release/pause_overlay.gd").new()
		overlay.name = "ReleasePause"
		root.add_child(overlay)
	change_scene_to_file("res://release/menu.tscn")
	await scene_changed
	await process_frame
	await process_frame
	var menu = current_scene
	_check("menu labels and buttons fit the 1280 x 720 viewport", _controls_fit(menu))
	overlay.set_paused(true)
	_check("Escape cannot pause the menu", not paused and not overlay.is_paused)
	menu.start_course("missing")
	_check("an unknown course keeps the menu open", current_scene == menu)
	for course in ["range", "gp", "eridanus", "emergency", "network"]:
		menu = current_scene
		menu.start_course(course)
		await scene_changed
		var view = current_scene
		_check("%s opens a playable CraftView" % course, view is View)
		_check("%s routes to the selected course" % course,
			view.sim.kind == course if course in ["range", "network"] else view.sim.track_name == ("eridanus" if course == "emergency" else course))
		_check("%s has only its selected mission even with --job=emergency" % course, not view.sim.job.is_empty() if course == "emergency" else view.sim.job.is_empty())
		if course == "gp":
			_check("Grand Prix starts with starfighter handling", view.sim.P.handling == "starfighter")
		await process_frame
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		Input.flush_buffered_events()
		_check("Escape pauses %s" % course, paused and overlay.is_paused)
		var before: float = view.sim.time
		await process_frame
		await process_frame
		_check("paused %s simulation does not advance" % course, view.sim.time == before)
		_check("pause controls fit the viewport", _controls_fit(overlay))
		_check("paused gameplay silences the master bus", AudioServer.is_bus_mute(0))
		overlay.resume_game()
		await process_frame
		await process_frame
		_check("resume restores gameplay and audio", not paused and not AudioServer.is_bus_mute(0) and view.sim.time > before)
		if course == "gp":
			overlay.set_paused(true)
			var old_id: int = view.get_instance_id()
			overlay.restart_game()
			await scene_changed
			view = current_scene
			_check("restart builds a new instance of the same course", view.get_instance_id() != old_id and view.sim.track_name == "gp")
			_check("restart clears pause and restores audio", not paused and not overlay.is_paused and not AudioServer.is_bus_mute(0))
		AudioServer.set_bus_mute(0, true)
		overlay.set_paused(true)
		overlay.return_to_menu()
		await scene_changed
		_check("return opens the menu with pause cleared", current_scene is Control and not paused and not overlay.is_paused)
		_check("pause preserves pre-existing audio mute", AudioServer.is_bus_mute(0))
		AudioServer.set_bus_mute(0, false)
	_finish()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)

func _controls_fit(node: Node) -> bool:
	var bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		if not bounds.encloses(node.get_global_rect()):
			print("  OUTSIDE: ", node.text, " ", node.get_global_rect())
			return false
	for child in node.get_children():
		if not _controls_fit(child):
			return false
	return true

func _finish() -> void:
	print("RELEASE MENU %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
