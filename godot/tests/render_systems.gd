## The consumables, the boost and the power-ups, for looking at (vr/vr_cockpit.gd's OPTIONS page,
## view/power_ups.gd): a gate from the seat at three distances and in its three colours, the dash
## with the boost burning and the battery and the engines' heat part used, and the OPTIONS page.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_systems.gd -- --mute --out=DIR [--time=night]
extends "res://tests/render_terminal_art.gd"

const PowerUps := preload("res://view/power_ups.gd")


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


func _fly(frames: int, inp: Dictionary) -> void:
	for frame in frames:
		seat.inp = inp.duplicate()
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
	print("SYSTEMS RENDER ", path)
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
	Seat.power_ups_on = true
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	if seat.power_ups == null:
		push_error("The power-ups did not build.")
		quit(1)
		return
	var sim = seat.sim
	var road := -1
	for r in sim.roads.size():
		if road < 0 and PowerUps.network_gates(sim, r).size() >= 4:
			road = r
	var gates: Array = PowerUps.network_gates(sim, road)
	print("SYSTEMS RENDER on %s: %d gates, the first four at samples %s" % [sim.roads[road].name, gates.size(), [gates[0].i, gates[1].i, gates[2].i, gates[3].i]])
	var still := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false, "burner": false}
	# the plain surge gate (heat and energy off), from 600, 250 and 80 m
	for row in [["a1-surge-gate-600m", 25], ["a2-surge-gate-250m", 10], ["a3-surge-gate-80m", 3]]:
		sim.respawn_on(road, int(gates[0].i) - int(row[1]), 1, -float(gates[0].lat))
		await _settle()
		await _fly(40, still)
		if not await _shot(row[0], 0.0, 2.0):
			quit(1)
			return
	# its other two colours, heat and energy on
	seat.set_consumables(true)
	for row in [["b1-energy-gate-250m", 1], ["b2-coolant-gate-250m", 3]]:
		sim.respawn_on(road, int(gates[row[1]].i) - 10, 1, -float(gates[row[1]].lat))
		await _settle()
		await _fly(40, still)
		if not await _shot(row[0], 0.0, 2.0):
			quit(1)
			return
	# the dash: the boost held a second and a half on the burner's lever, the battery and the heat part used
	sim.respawn_on(road, int(gates[1].i) - 400, 1, 0.0)
	await _settle()
	sim.battery = 0.62
	sim.eL.heat = 0.78
	sim.eR.heat = 0.66
	seat.boosting = true
	var burn := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false, "boost": true}
	await _fly(180, burn)
	print("SYSTEMS RENDER dash: boost %d, battery %.2f, heat %.2f / %.2f, %.0f mph, \"%s\"" % [sim.boost, sim.battery, sim.eL.heat, sim.eR.heat, seat._kmh() / 1.609344, seat.boost_text().strip_edges()])
	if not await _shot("c1-dash-boost-held-heat-and-energy-on", 0.0, -24.0):
		quit(1)
		return
	if not await _shot("c2-ahead-boost-held", 0.0, -4.0):
		quit(1)
		return
	seat.power_up("energy")
	await _fly(30, burn)
	print("SYSTEMS RENDER dash: boost %d after a gate, \"%s\", flash \"%s\"" % [sim.boost, seat.boost_text().strip_edges(), seat.flash_msg])
	if not await _shot("c3-dash-boost-and-a-gates-surge", 0.0, -24.0):
		quit(1)
		return
	# the OPTIONS page
	seat.boosting = false
	seat.menu_open(true)
	for k in seat.menu.items.size():
		if String(seat.menu.items[k].key) == "options":
			seat.menu.at = k
	seat._menu_show()
	if not await _shot("d1-quick-menu-with-options", 0.0, 0.0):
		quit(1)
		return
	seat.menu_choose()
	if not await _shot("d2-options-page", 0.0, 0.0):
		quit(1)
		return
	seat.menu_open(false)
	seat.set_consumables(false)
	seat.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Seat.PREFS))
	else:
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("SYSTEMS RENDER DONE")
	quit(0)
