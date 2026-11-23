## What the fins cost (push 39: the engines' fins answer a turn). Two things, measured on the Range's
## flat view with nothing else moving:
##   posing    the craft's own sync() each frame, in microseconds: going straight flat out, and in a
##             slalom as he flies one (a grip a third in, one side then the other), the sim stepped
##             between frames and left out of the timing
##   drawing   what the craft adds to a frame: the frame's draw calls and objects with the craft shown,
##             less the same frame with it hidden; with the sun's shadows and without them (so what its
##             shadows add can be told from what the view itself adds); and the engines' drawn parts
## Run windowed: --xr-mode off --resolution 1280x720 --audio-driver Dummy
## -s res://tests/probe_fins_cost.gd -- --mute [--craft=shrike] [--rounds=7] [--view=seat]
## (--view=seat: from the headset's cockpit, flat on the desktop, as the render tools take their pictures.)
## It reads nothing an older craft did not have: run on the craft as it was, it gives the figure before.
## Other work on the machine is in the timings: the least of the rounds is the one to compare.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Seat := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 480.0
const FRAME := 1.0 / 120.0
const FRAMES := 1200


func _initialize() -> void:
	_run.call_deferred()


static func _input(thr_l: float, thr_r: float, brk_l: float, brk_r: float) -> Dictionary:
	return {"thrL": thr_l, "thrR": thr_r, "brkL": brk_l, "brkR": brk_r, "repair": false, "reignite": true}


## Microseconds a sync() over FRAMES frames of `how`.
func _time(v, how: String) -> float:
	var spent := 0
	for frame in FRAMES:
		var inp := _input(1.0, 1.0, 0.0, 0.0)
		if how == "slalom":
			var leg := (frame / 72) % 4      # 0.6 s a leg: left, straight, right, straight
			if leg == 0:
				inp = _input(0.74, 1.0, 0.16, 0.10)
			elif leg == 2:
				inp = _input(1.0, 0.74, 0.10, 0.16)
		for sub in 4:
			v.sim.step(inp, DT)
		v.sim.events.clear()
		v.inp = inp
		v.org_x = v.sim.pod.x      # (as a frame does: the craft is posed about the pod)
		v.org_y = v.sim.pod.y
		var t0 := Time.get_ticks_usec()
		v.craft.sync(v.sim, inp, FRAME)
		spent += Time.get_ticks_usec() - t0
	return float(spent) / FRAMES


static func _mid(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _drawn(frames: int) -> Array:      # [draw calls, objects]: the middle of `frames` frames
	var calls := []
	var objects := []
	for frame in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	return [_mid(calls), _mid(objects)]


func _run() -> void:
	var vehicle := "phaethon"
	var rounds := 7
	var seat := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--view=seat":
			seat = true
		if arg.begins_with("--craft="):
			vehicle = arg.trim_prefix("--craft=")
		if arg.begins_with("--rounds="):
			rounds = int(arg.trim_prefix("--rounds="))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	View.track_override = "range"
	View.job_override = "none"
	View.vehicle_override = vehicle
	View.best_dir = OS.get_user_data_dir().path_join("probe_fins_cost_")
	if seat:      # (the pilot's saved choices stay out of it)
		Seat._nose_loaded = true
		Seat._slide_loaded = true
		Seat._camera_loaded = true
		Seat.camera = "cockpit"
		Seat._startup_loaded = true
		Seat.cold_start = false
		Seat._map_loaded = true
		Seat._school_loaded = true
	var v = Seat.new() if seat else View.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	# drawing: the craft standing, shown and hidden, with the sun's shadows and without
	v.inp = _input(0.0, 0.0, 0.0, 0.0)
	if seat:
		for frame in 30:
			v._process(FRAME)
	else:
		v._sync_craft(FRAME)
	var parts := 0      # the engines' drawn parts and the batches that span them (the strobes apart: they flash)
	for node in (v.craft as Node).find_children("*", "GeometryInstance3D", true, false):
		var on_engine: bool = v.craft.engines.any(func(e): return (e as Node).is_ancestor_of(node))
		if (on_engine or node is MultiMeshInstance3D) and not v.craft.strobes.has(node):
			parts += int((node as GeometryInstance3D).is_visible_in_tree())
	for strobe in v.craft.strobes:      # (they flash: out, so that one count can be set against another)
		(strobe as Node3D).visible = false
	var said := []
	var suns := []      # the lights that throw shadows as the game has them
	for sun in v.find_children("*", "DirectionalLight3D", true, false):
		if (sun as DirectionalLight3D).shadow_enabled and (sun as DirectionalLight3D).visible:
			suns.append(sun)
	for shadows in [true, false]:
		for sun in suns:
			(sun as DirectionalLight3D).shadow_enabled = shadows
		var shown: Array = await _drawn(40)
		v.craft.visible = false
		var hidden: Array = await _drawn(40)
		v.craft.visible = true
		said.append("%s the craft adds %d draw calls and %d objects to a frame (%d with it, %d without)" % ["with the sun's shadows" if shadows else "without them", int(shown[0]) - int(hidden[0]), int(shown[1]) - int(hidden[1]), int(shown[0]), int(hidden[0])])
	for sun in suns:
		(sun as DirectionalLight3D).shadow_enabled = true
	print("FINS COST %s drawing, %s: %s; its two engines carry %d drawn parts" % [v.sim.P.vehicle, "from the seat" if seat else "the flat view", "; ".join(said), parts])
	# posing
	var straight := []
	var slalom := []
	for turn in rounds:
		v.sim.respawn()
		straight.append(_time(v, "straight"))
		v.sim.respawn()
		slalom.append(_time(v, "slalom"))
		await process_frame
	straight.sort()
	slalom.sort()
	print("FINS COST %s posing, microseconds a frame over %d frames, %d rounds: straight %.1f at the least (middle %.1f); in a slalom %.1f at the least (middle %.1f)" % [
		v.sim.P.vehicle, FRAMES, rounds, straight[0], straight[rounds / 2], slalom[0], slalom[rounds / 2]])
	print("FINS COST DONE")
	View.vehicle_override = ""
	quit(0)
