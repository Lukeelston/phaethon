## PCVR startup policy and the real no-headset screen. No headset claims.
## Run: --headless --xr-mode off --path godot -s res://tests/test_release_vr.gd
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check("PCVR boot scene is available", ResourceLoader.exists("res://release/vr_boot.tscn"))
	_check("PCVR diagnostic is available", ResourceLoader.exists("res://release/verify_vr_runner.gd"))
	if failures:
		_finish()
		return
	var boot = load("res://release/vr_boot.gd")
	var empty := PackedStringArray()
	var diagnostic := PackedStringArray(["--verify-vr-release"])
	var acknowledged := PackedStringArray(["--verify-vr-release", "--verify-xr-off"])
	_check("initialized OpenXR enters VR", boot.startup_route(true, empty) == "vr")
	_check("missing OpenXR shows setup instead of flat gameplay", boot.startup_route(false, empty) == "setup")
	_check("XR off acknowledgment alone never bypasses the setup guard", boot.startup_route(false, PackedStringArray(["--verify-xr-off"])) == "setup")
	_check("diagnostic flag alone never bypasses the setup guard", boot.startup_route(false, diagnostic) == "setup")
	_check("diagnostic with explicit XR off acknowledgment permits the scene check", boot.startup_route(false, acknowledged) == "diagnostic")
	_check("diagnostic cannot take over a live headset", boot.startup_route(true, acknowledged) == "setup")
	_check("default start is the range", boot.selected_track(empty) == "range")
	for course in ["range", "gp", "eridanus"]:
		_check("CLI can start on " + course, boot.selected_track(PackedStringArray(["--track=" + course])) == course)
	_check("unsupported track falls back to range", boot.selected_track(PackedStringArray(["--track=network"])) == "range")
	change_scene_to_file("res://release/vr_boot.tscn")
	await scene_changed
	await process_frame
	await process_frame
	_check("headless normal boot remains on the setup screen", current_scene.scene_file_path == "res://release/vr_boot.tscn")
	_check("headless normal boot creates no VR gameplay", current_scene.find_children("*", "XROrigin3D", true, false).is_empty())
	_check("setup screen provides a Quit action", current_scene.find_children("*", "Button", true, false).size() == 1)
	_check("setup labels and controls fit 1280 x 720", _controls_fit(current_scene))
	_finish()

func _controls_fit(node: Node) -> bool:
	var bounds := Rect2(Vector2.ZERO, Vector2(1280, 720))
	if node is Control and node.is_visible_in_tree() and (node is Label or node is Button):
		if not bounds.encloses(node.get_global_rect()):
			print("OUTSIDE: ", node.text, " ", node.get_global_rect())
			return false
	for child in node.get_children():
		if not _controls_fit(child):
			return false
	return true

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)

func _finish() -> void:
	print("RELEASE VR STARTUP %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
