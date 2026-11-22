## What the title costs the headset's menu, measured without a headset: the real menu scene drawn into
## an offscreen viewport the size of both of a Quest 3's eyes side by side (4128 x 2208, MSAA 4x as the
## headset's menu sets), with the title and without it, turn and turn about in one run so that whatever
## else the machine is doing falls on both alike.
## It is a stand-in: one wide flat view, not the headset's two, at a flat camera's field of view.
## Run windowed (a small window: the work is offscreen):
## --xr-mode off --resolution 640x360 --audio-driver Dummy -s res://tests/probe_title_cost.gd -- --mute [--frames=400] [--rounds=3] [--size=4128x2208]
## Prints for each of with and without, looking ahead and at each craft: the GPU's time for the view, the
## renderer's CPU time for it, and the whole frame's time as the engine reports it (a number it refreshes
## once a second, and the machine's other work is in it); and the title's own scripts' time a frame, by
## running four hundred frames' worth of them at once.
extends SceneTree

const Stage := preload("res://release/title_stage.gd")
const LOOKS := {"ahead": 0.0, "left craft": 57.0, "right craft": -57.0}

var frames := 400
var rounds := 3
var size := Vector2i(4128, 2208)
var results := {}      # "on/ahead" -> {gpu: [...], cpu: [...], script: [...]}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		if arg.begins_with("--rounds="):
			rounds = int(arg.trim_prefix("--rounds="))
		if arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for turn in rounds:
		for on in [false, true]:
			await _measure(on)
	print("TITLE COST at %d x %d, MSAA 4x, %d frames a look, %d rounds (median ms; p95 in brackets)" % [size.x, size.y, frames, rounds])
	for key in results:
		var r: Dictionary = results[key]
		print("TITLE COST %-22s gpu %6.3f (%6.3f)   render cpu %6.3f (%6.3f)   whole frame, engine's figure %6.3f (%6.3f)" % [key, _mid(r.gpu), _p95(r.gpu), _mid(r.cpu), _p95(r.cpu), _mid(r.script), _p95(r.script)])
	print("TITLE COST DONE")
	quit(0)


func _mid(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] if not sorted.is_empty() else 0.0


func _p95(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0


func _measure(on: bool) -> void:
	Stage.enabled = on
	var view := SubViewport.new()
	view.size = size
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
	var t0 := Time.get_ticks_msec()
	var menu = load("res://release/vr_menu.tscn").instantiate()
	view.add_child(menu)
	var built := Time.get_ticks_msec() - t0
	(menu.camera as Camera3D).make_current()
	for look in LOOKS:
		(menu.camera as Camera3D).rotation_degrees = Vector3(0.0, float(LOOKS[look]), 0.0)
		for i in 90:      # (settle: shaders compiled, the arcs struck, the fans up to speed)
			await process_frame
		var key := "%s / %s" % ["title" if on else "as it was", look]
		if not results.has(key):
			results[key] = {"gpu": [], "cpu": [], "script": []}
		for i in frames:
			await process_frame
			results[key].gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			results[key].cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu())
			results[key].script.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	print("TITLE COST built the menu %s in %d ms%s" % ["with the title" if on else "as it was", built, (" " + str(menu.stage.build_split)) if on else ""])
	if on:      # the title's own work a frame: the craft posed, the arcs redrawn, the clouds moved
		var t1 := Time.get_ticks_usec()
		for i in 400:
			menu.stage._process(1.0 / 120.0)
		print("TITLE COST the title's scripts: %.3f ms a frame (400 frames' work, run in one)" % [(Time.get_ticks_usec() - t1) / 400000.0])
	view.queue_free()
	await process_frame
	await process_frame
	Stage.enabled = true
