## Headless input paths, viewport readback and telemetry. Physical foveation needs an XR runtime.
extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := load("res://vr/quest_flight.tscn") as PackedScene
	if scene == null:
		quit(1)
		return
	var flight = scene.instantiate()
	root.add_child(flight)
	flight.set_process(false)
	flight.menu_open(true)
	var ok: bool = flight.menu.key() == "graphics" and flight.menu_choose()
	ok = ok and flight.menu.key() == "foveation" and flight.menu_choose()
	ok = ok and flight.actual.foveation == "unavailable"
	flight.menu.move(1)
	for expected in [0.8, 0.7, 1.0]:
		flight.menu_choose()
		ok = ok and is_equal_approx(flight.actual.requested_scale, expected)
		var region: Rect2i = flight.eye_region(Vector2i(2000, 2100), expected)
		ok = ok and region.size == Vector2i(2000 * expected, 2100 * expected)
		ok = ok and region.position == Vector2i((2000 - region.size.x) / 2.0, (2100 - region.size.y) / 2.0)
		ok = ok and is_equal_approx(root.scaling_3d_scale, 1.0)
	flight.menu.move(1)
	for expected in [Viewport.MSAA_2X, Viewport.MSAA_DISABLED, Viewport.MSAA_4X]:
		flight.menu_choose()
		ok = ok and root.msaa_3d == expected
	flight.menu.move(1)
	flight.menu_choose()
	ok = ok and flight.menu.key() == "graphics"
	flight.menu_open(false)
	flight._full_eye = Vector2i(2000, 2100)
	flight._observe_eye(flight._generation - 1, Vector2i(1400, 1470))
	ok = ok and flight.actual.scale == null
	flight._observe_eye(flight._generation, Vector2i(2000, 2100))
	ok = ok and is_equal_approx(flight.actual.scale, 1.0) and flight.actual.eye_h == 2100
	flight._start_us = 1000000
	for i in 300:
		flight._sample_frame(1000000 + roundi((i+1)*5000000.0/300), 9.5 if i < 299 else 0.0)
	ok = ok and flight._frame_count == 0 and flight._start_us == 6000000
	flight.free()
	print("QUEST_FLIGHT_CHECK ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
