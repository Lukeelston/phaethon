## Real menu -> course -> menu lifecycle, plus the controller input boundary.
## Breaks caught: auto-flight on boot, wrong map/job, sticky trigger launches,
## held sticks scrolling every frame, and cockpit/audio surviving a menu return.
extends SceneTree

const View := preload("res://view/craft_view.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	check("VR main menu scene exists", ResourceLoader.exists("res://release/vr_menu.tscn"))
	if failures:
		finish()
		return
	var boot = load("res://release/vr_boot.gd")
	check("ready headset starts at a menu", boot.startup_route(true, PackedStringArray()) == "menu")
	change_scene_to_file("res://release/vr_menu.tscn")
	await scene_changed
	await process_frame
	var menu = current_scene
	menu.set_process(false)
	check("VR menu text and buttons fit the panel", controls_fit(menu.screen))
	if DisplayServer.get_name() != "headless":
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		check("menu panel screenshot saved", menu.panel_view.get_texture().get_image().save_png("res://../evidence/menu-panel.png") == OK)
		check("menu in-world screenshot saved", root.get_texture().get_image().save_png("res://../evidence/menu-world.png") == OK)
	check("menu has a tracked camera and two controllers", menu.camera is XRCamera3D and menu.hands.size() == 2)
	check("no craft or engines run while choosing", menu.find_children("*", "AudioStreamPlayer", true, false).is_empty() and not menu is View)
	menu.consume_controller(0.0, true, true)
	check("held trigger on entry cannot select", menu.focus_index == 0 and current_scene == menu)
	menu.consume_controller(0.0, false, true)
	menu.consume_controller(-1.0, false, true)
	for i in 20:
		menu.consume_controller(-1.0, false, true)
	check("held stick moves only one row", menu.focus_index == 1)
	menu.consume_controller(0.0, false, true)
	menu.consume_controller(0.0, true, true)
	check("confirm chooses Grand Prix and focuses Start", menu.selected_course == "gp" and menu.focus_index == 5)
	menu.consume_controller(0.0, true, true)
	check("same held confirm cannot launch", current_scene == menu and not menu.launching)
	menu.consume_controller(0.0, false, false)
	menu.consume_controller(0.0, true, true)
	check("focus regain also requires release", not menu.launching)
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = "right_hand"
	tracker.set_pose("default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, 2)
	XRServer.add_tracker(tracker)
	for course in ["range", "gp", "eridanus", "emergency", "network"]:
		menu = current_scene
		menu.set_process(false)
		menu.choose_course(course)
		check(course + " selection does not enter flight", current_scene == menu and menu.selected_course == course)
		menu.choose_course("missing")
		check("invalid map preserves " + course, menu.selected_course == course)
		menu.focus_row(5)
		menu.consume_controller(0.0, false, true)
		tracker.set_input("trigger", 0.8)
		menu.consume_controller(0.0, true, true)
		await scene_changed
		var craft = current_scene
		check(course + " opens requested VR course", craft._track() == course)
		check(course + " has correct mission", not craft.sim.job.is_empty() if course == "emergency" else craft.sim.job.is_empty())
		check(course + " starts at idle in first gear", craft.quest.gear == 0 and craft.inp.thrL == 0.0 and craft.inp.thrR == 0.0)
		for i in 6:
			await process_frame
		check(course + " Start trigger cannot propel the craft", craft.inp.thrL == 0.0 and craft.inp.thrR == 0.0)
		tracker.set_input("trigger", 0.0)
		await process_frame
		await process_frame
		tracker.set_input("trigger", 0.8)
		for i in 6:
			await process_frame
		check(course + " fresh trigger press flies after release", maxf(craft.inp.thrL, craft.inp.thrR) > 0.01)
		tracker.set_input("trigger", 0.0)
		var old: WeakRef = weakref(craft)
		craft.return_to_menu()
		await scene_changed
		await process_frame
		check(course + " returns to menu and frees craft", current_scene.scene_file_path == "res://release/vr_menu.tscn" and old.get_ref() == null)
		check(course + " return remembers selection and clears pause", current_scene.selected_course == course and not paused)
	XRServer.remove_tracker(tracker)
	finish()

func finish() -> void:
	print("VR MENU %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

func controls_fit(node: Node) -> bool:
	if node is Label or node is Button:
		if not Rect2(Vector2.ZERO, Vector2(1440, 900)).encloses(node.get_global_rect()):
			print("OUTSIDE MENU: ", node.text, " ", node.get_global_rect())
			return false
	for child in node.get_children():
		if not controls_fit(child):
			return false
	return true
