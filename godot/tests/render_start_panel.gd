## The start panel by itself (vr/overhead_panel.gd, tools/art_start_panel_hd.py): stills of both pods
## from the seated eye and close up, at each step of the start-up, in an empty dark room. The panel
## lights itself (vr/panel_finish.gdshader), so this is close to what the cockpit shows of it, and it
## takes seconds where tests/render_startup.gd takes minutes: the one to run while the art is worked on.
## Run windowed: --xr-mode off --resolution 1600x900 -s res://tests/render_start_panel.gd -- --out=DIR
## [--views=a,b] [--states=a,b]
extends SceneTree

const Overhead := preload("res://vr/overhead_panel.gd")
const Sequence := preload("res://vr/startup_sequence.gd")
# Name, where the camera stands (canopy metres, or a pod's own with "L" / "R"), what it looks at, field of view.
const VIEWS := [
	["seat", "", Vector3(0.0, 0.12, 0.6), Vector3(0.0, 0.385, 0.36), 62.0],
	["left", "", Vector3(0.0, 0.12, 0.6), Vector3(-0.246, 0.385, 0.362), 30.0],
	["right", "", Vector3(0.0, 0.12, 0.6), Vector3(0.246, 0.385, 0.362), 30.0],
	["left-close", "L", Vector3(0.03, -0.05, 0.2), Vector3(0.0, -0.012, 0.0), 52.0],
	["right-close", "R", Vector3(-0.03, -0.05, 0.2), Vector3(0.0, -0.012, 0.0), 52.0],
	["left-side", "L", Vector3(0.2, 0.02, 0.1), Vector3(0.02, -0.01, 0.01), 40.0],
	["right-under", "R", Vector3(0.05, -0.19, 0.11), Vector3(0.0, -0.01, 0.01), 44.0],
	["guard", "L", Vector3(0.1, -0.04, 0.12), Vector3(0.044, -0.004, 0.02), 34.0],
	["button", "R", Vector3(-0.09, -0.05, 0.1), Vector3(-0.043, 0.0, 0.006), 34.0],
]
const STATES := ["cold", "power", "guard", "armed", "crank", "running", "flying"]


func _initialize() -> void:
	_run.call_deferred()


func _pass(s, seconds: float) -> void:
	var left := seconds
	while left > 1e-6:
		s.step(minf(left, 1.0 / 90.0), [0.0, 0.0], 1)
		left -= 1.0 / 90.0


## A sequence brought from cold to a named point.
func _reach(point: String):
	var s = Sequence.new()
	s.cold()
	if point == "cold":
		return s
	s.flick("batt", 1)
	_pass(s, Sequence.SELFTEST_S + 0.6)
	if point == "power":
		return s
	s.flick("engine", 1)
	_pass(s, 0.3)
	if point == "guard":
		return s
	s.flick("engine", 1)
	_pass(s, Sequence.GUARD_AFTER_S + 0.6)
	if point == "armed":
		return s
	s.press_start(0.0)
	_pass(s, 0.9)
	if point == "crank":
		return s
	_pass(s, Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S)
	if point == "running":
		return s
	for key in s.checks:
		s.checks[key] = true
	s.flick("park", -1)
	_pass(s, Sequence.CLEARED_S + 0.5)
	return s


func _run() -> void:
	var out := ""
	var views := PackedStringArray()
	var states := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			views = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--states="):
			states = arg.trim_prefix("--states=").split(",")
	if out.is_empty() or DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	var en := Environment.new()             # the game's own tone and bloom (view/craft_view.gd), in a dark room
	en.background_mode = Environment.BG_COLOR
	en.background_color = Color(0.012, 0.014, 0.018)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.85, 0.78, 0.7)
	en.ambient_light_energy = 0.06
	en.tonemap_mode = Environment.TONE_MAPPER_AGX
	en.tonemap_exposure = 1.22
	en.tonemap_white = 6.0
	en.glow_enabled = true
	en.glow_intensity = 0.55
	en.glow_strength = 0.9
	en.glow_bloom = 0.02
	en.glow_hdr_threshold = 0.95
	en.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for lv in 7:
		en.set_glow_level(lv, 1.0 if lv in [1, 2, 3, 4] else 0.0)
	en.adjustment_enabled = true
	en.adjustment_saturation = 1.04
	en.adjustment_contrast = 1.06
	var world := WorldEnvironment.new()
	world.environment = en
	root.add_child(world)
	var cam := Camera3D.new()
	cam.near = 0.01
	root.add_child(cam)
	cam.current = true
	var panel = Overhead.new()
	root.add_child(panel)
	panel.build()
	for state: String in STATES:
		if not states.is_empty() and not states.has(state):
			continue
		panel.show_state(_reach(state), 0.0)
		for view: Array in VIEWS:
			if not views.is_empty() and not views.has(view[0]):
				continue
			var frame := Transform3D.IDENTITY
			if view[1] != "":
				frame = (panel.pods[-1.0 if view[1] == "L" else 1.0] as Node3D).global_transform
			cam.global_position = frame * (view[2] as Vector3)
			cam.look_at(frame * (view[3] as Vector3), frame.basis.y if view[1] != "" else Vector3.UP)
			cam.fov = view[4]
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out.path_join("%s-%s.png" % [view[0], state])
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			print("PANEL_SHOT %s-%s" % [view[0], state])
	quit()
