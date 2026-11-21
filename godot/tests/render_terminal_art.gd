## Render the production pilot seat on the default Network departure with XR disabled.
## Run with --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_terminal_art.gd -- --track=network --handling=speed --mute --out=DIR
## Optional: --captures-only, --benchmark-only, --flat-panel (the flat instrument panel and
## heads-up map instead of the gauge cluster and map pod). Timings are for one desktop eye.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const STEP := 1.0 / 120.0
const SHOTS := {
	"01-terminal": 0, "02-under-ribs": 60, "03-portal": 80,
	"04-daylight": 98, "05-landmark": 124, "06-downrange": 180, "07-controls": 98
}

var seat
var city: Dictionary
var out_dir := ""
var gpu := PackedFloat64Array()
var cpu := PackedFloat64Array()
var elapsed := PackedFloat64Array()
var draws := PackedFloat64Array()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable review directory.")
		quit(1)
		return
	if "--flat-panel" in OS.get_cmdline_user_args():   # v0.3.2's flat instrument panel and heads-up map
		preload("res://vr/gauge_cluster.gd").enabled = false
		preload("res://vr/minimap_panel.gd").enclosure = false
	if "--open" in OS.get_cmdline_user_args():   # the open cockpit, before the roof
		preload("res://view/canopy.gd").roofed = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--edge-probe="):   # timings: the scenic roads' open edges undrawn
			preload("res://view/network_world.gd").open_edge_probe = arg.trim_prefix("--edge-probe=")
		if arg.begins_with("--roof-probe="):   # timings: the roof without its glass, or without its dome light
			preload("res://view/canopy.gd").probe = arg.trim_prefix("--roof-probe=")
	if "--no-beam" in OS.get_cmdline_user_args():   # timings: the approach guidance without its projector beam
		preload("res://view/approach_projector.gd").beams = false
	if "--no-plume" in OS.get_cmdline_user_args():   # timings: the jets' gas undrawn
		preload("res://view/craft_model.gd").plumes = false
	Seat._nose_loaded = true                              # (the pilot's saved choice stays out of the pictures and the timings)
	if "--closed-nose" in OS.get_cmdline_user_args():   # the nose skinned over (the quick menu's NOSE line)
		preload("res://view/craft_model.gd").nose_closed = true
	if "--guidance-every-frame" in OS.get_cmdline_user_args():   # timings: the approach readout's picture drawn every frame, to weigh one
		preload("res://view/approach_projector.gd").picture_every_frame = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):   # timings: the quick menu's chase views
			Seat.camera = arg.trim_prefix("--camera=")
			Seat._camera_loaded = true
	if "--no-start-panel" in OS.get_cmdline_user_args():   # timings: the cockpit without its start panel
		preload("res://vr/overhead_panel.gd").fitted = false
	if "--no-reflection" in OS.get_cmdline_user_args():   # timings: the windscreen without its reflection of the cockpit
		preload("res://view/screen_reflection.gd").enabled = false
	if "--reflection-every-frame" in OS.get_cmdline_user_args():   # timings: a picture every frame, to weigh one
		preload("res://view/screen_reflection.gd").every = 0.0
	if "--reflection-whole" in OS.get_cmdline_user_args():   # timings: the sheet over the whole pane, not cut to what shows
		preload("res://view/screen_reflection.gd").whole = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reflection="):   # (looking at it: the reflection this many times its strength)
			preload("res://view/screen_reflection.gd").strength = float(arg.trim_prefix("--reflection="))
	if "--no-scenic" in OS.get_cmdline_user_args():   # the scenic roads' land and edges left out
		preload("res://view/network_world.gd").scenic_on = false
	# The pilot's saved hour, weather, paint and chase stay out of pictures and timings: a fair afternoon
	# in Ember, no chase, unless --time= or --weather= says otherwise.
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	if "--headset" in OS.get_cmdline_user_args():   # twice the window each way: with --resolution 2064x1104, a Quest 3's two eyes' worth of pixels in one flat view
		root.scaling_3d_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr:
		push_error("This review requires the Eridanus Network road and a monoscopic viewport.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-at="):   # road,sample: time the seat along another stretch (open country, a sky bridge)
			var at := arg.trim_prefix("--bench-at=").split(",")
			city = {"road": int(at[0]), "i": int(at[1])}
	if "--as-flown" in OS.get_cmdline_user_args():   # the first spike flight's world: no banks, no fins, level traffic
		seat.network_world.banks = false
		seat.network_world.fins = false
		seat.traffic_net.grade = false
	_set_pose(0)
	# Resolve both streamers before capture; their regular sync budgets stay in force while travelling.
	for i in 5000:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
		if seat.landscape.pending.is_empty() and seat.landscape._job.is_empty() and seat.landscape._decor_job.is_empty() and i > 1200:
			break
	if "--benchmark-only" not in OS.get_cmdline_user_args():
		for name in SHOTS:
			_set_pose(SHOTS[name])
			seat.cam.position = Vector3.ZERO
			seat.cam.rotation = Vector3.ZERO
			if name == "07-controls":
				# A plausible seated lean and glance down at the starboard control.
				seat.cam.position = Vector3(0.12, 0.04, -0.04)
				seat.cam.rotation_degrees = Vector3(-27, -32, 0)
			for frame in 84:
				seat._process(STEP)
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join(name + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			print("TERMINAL_SHOT ", name, " sample=", int(city.i) + int(SHOTS[name]))
	if "--captures-only" not in OS.get_cmdline_user_args():
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		await _benchmark()
	seat.free()
	quit()


func _set_pose(offset: int) -> void:
	seat.sim.respawn_on(int(city.road), int(city.i) + offset, 1)
	seat._ride.clear()


func _benchmark() -> void:
	var road = seat.sim.roads[int(city.road)]
	var vp := root.get_viewport_rid()
	var burner := "--burner" in OS.get_cmdline_user_args()
	var guidance := "--guidance" in OS.get_cmdline_user_args()
	# Two warm passes give the runtime a chance to compile newly visible materials.
	# Every pass follows identical transforms even if the host display rate changes.
	for lap in 3:
		var last := Time.get_ticks_usec()
		for frame in 480:
			var offset := frame / 2
			var idx := int(city.i) + offset
			_set_pose(offset)
			var dx: float = road.px[idx + 1] - road.px[idx]
			var dy: float = road.py[idx + 1] - road.py[idx]
			for body in seat.sim.bodies:
				body.x += dx * 0.5 * (frame % 2)
				body.y += dy * 0.5 * (frame % 2)
				body.vx = dx * 60.0
				body.vy = dy * 60.0
			if burner:      # both levers through the gate: the long plumes
				seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": true}
			var begin := Time.get_ticks_usec()
			seat._process(STEP)
			var update_ms := (Time.get_ticks_usec() - begin) / 1000.0
			if guidance and seat.approach_display:      # the approach readout held up (the frame's own update has just stowed it)
				seat.approach_display.set_message("JUMP LIP  2 MI / 4.0 S\nASCENT J0 > N2 UPPER\nMIN 3,000 MPH AT LIP | READY")
				seat.approach_display._process(1.0)
			await process_frame
			var now := Time.get_ticks_usec()
			if lap == 2:
				cpu.append(update_ms)
				elapsed.append((now - last) / 1000.0)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			last = now
	if burner:
		print("TERMINAL_BENCH engines: mode %s, thrust %.2f %.2f, plume %.1f m, camera %s" % [seat.sim.mode, seat.sim.eL.thrust, seat.sim.eR.thrust, seat.craft.plume_len[0], Seat.camera])
	var result := {"viewport": str(root.size), "frames": cpu.size(), "road": road.name,
		"view_update_ms": _stats(cpu), "viewport_gpu_ms": _stats(gpu),
		"wall_frame_ms": _stats(elapsed), "draw_calls": _stats(draws)}
	print("TERMINAL_BENCH ", JSON.stringify(result))
	var output := FileAccess.open(out_dir.path_join("timing.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))


func _stats(values: PackedFloat64Array) -> Dictionary:
	values.sort()
	return {"p50": values[int(values.size() * 0.50)], "p95": values[int(values.size() * 0.95)],
		"p99": values[int(values.size() * 0.99)], "max": values[-1]}
