## The autopilot, for looking at (view/autopilot.gd, vr/vr_cockpit.gd): from the seat with it flying
## a highway (its page on the glass, AUTO on the dash's Mach line, nobody's hands on her), moved over
## for a vehicle, and the OPTIONS page's line.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_autopilot.gd -- --mute --out=DIR [--time=night]
extends "res://tests/render_terminal_art.gd"


func _settle() -> void:
	var world = seat.network_world
	for i in 6000:
		world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break


## Whole frames, the cockpit reading its own (empty) hands: the autopilot's levers are what fly her.
func _fly(frames: int) -> void:
	for frame in frames:
		seat._process(STEP)
		if frame % 3 == 0:
			await process_frame


func _shot(name: String, yaw: float, pitch: float) -> bool:
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation_degrees = Vector3(pitch, yaw, 0.0)
	for frame in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Couldn't save " + path)
		return false
	print("AUTOPILOT RENDER ", path)
	return true


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._school_loaded = true
	Seat.school = false
	Seat._nose_loaded = true
	Seat._options_loaded = true
	Seat.consumables = false
	Seat.power_ups_on = false
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	var sim = seat.sim
	var road := -1
	for r in sim.roads.size():
		if String(sim.roads[r].name) == "N3":
			road = r
	sim.respawn_on(road, 1500, 1)
	await _settle()
	var took: bool = seat.set_autopilot(true)
	seat.autopilot.set_cruise(2400.0 / 2.236936)
	print("AUTOPILOT RENDER taken %s: %s" % [took, seat.autopilot.message().replace("\n", " / ")])
	await _fly(2400)             # twenty seconds: up through the gears to its speed
	await _settle()
	await _fly(60)
	print("AUTOPILOT RENDER at %.0f mph, gear %d, \"%s\", the dash's line \"%s\"" % [seat._kmh() / 1.609344, seat.quest.gear, seat.autopilot.message().replace("\n", " / "), seat.autopilot.suffix()])
	if not await _shot("a1-flying-the-glass-and-the-road", 0.0, 8.0):
		quit(1)
		return
	if not await _shot("a2-flying-the-dash", 0.0, -24.0):
		quit(1)
		return
	if not await _shot("a3-flying-ahead", 0.0, -2.0):
		quit(1)
		return
	# the OPTIONS page's line
	seat.menu_open(true)
	for k in seat.menu.items.size():
		if String(seat.menu.items[k].key) == "options":
			seat.menu.at = k
	seat.menu_choose()
	for k in seat.menu.items.size():
		if String(seat.menu.items[k].key) == "autopilot":
			seat.menu.at = k
	seat._menu_show()
	if not await _shot("b1-options-page-autopilot", 0.0, 0.0):
		quit(1)
		return
	seat.menu_open(false)
	seat.set_autopilot(false)
	seat.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Seat.PREFS))
	else:
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("AUTOPILOT RENDER DONE")
	quit(0)
