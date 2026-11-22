## The avoidance field, for looking at (sim/craft_sim.gd inp.avoid; view/craft_view.gd): the craft
## flown at a highway's left wall at 6 degrees and 2,000 mph, the field off (the moment before the
## wall) and on (the moment it takes hold, and half a second on), from the seat and down at the
## dash; and the OPTIONS page with its line.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_field.gd -- --mute --out=DIR
extends "res://tests/render_systems.gd"

const MPH := 2.236936


## The craft on N1's straight, its pod `start` m from the left wall, turned `deg` toward it, at mph.
func _approach(start: float, deg: float, mph: float) -> void:
	var sim = seat.sim
	var R = sim.roads[3]
	var i := 300
	sim.respawn_on(3, i, 1)
	var th := deg_to_rad(deg)
	var c := cos(th)
	var s := sin(th)
	var px: float = sim.pod.x
	var py: float = sim.pod.y
	var off: float = R.w[i] / 2.0 - start
	for b in sim.bodies:
		var dx: float = b.x - px
		var dy: float = b.y - py
		b.x = px + dx * c - dy * s + R.nx[i] * off
		b.y = py + dx * s + dy * c + R.ny[i] * off
		b.th += th
		b.vx = mph / MPH * (R.tx[i] * c + R.nx[i] * s)
		b.vy = mph / MPH * (R.ty[i] * c + R.ny[i] * s)
	sim.crash_t = 0.0
	sim.events.clear()


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
	Seat.avoid_on = false
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var sim = seat.sim
	var fly := {"thrL": 0.6, "thrR": 0.6, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false, "burner": false}
	var ok := true
	# off: flown into the wall; the picture a moment before it
	_approach(150.0, 6.0, 2000.0)
	await _settle()
	var frames_off := 0
	var touched := false
	while frames_off < 400 and not touched:
		await _fly(1, fly)
		frames_off += 1
		touched = sim.eL.contact[0] or sim.eL.contact[1] or sim.pod.contact[0]
	print("FIELD RENDER off: the wall touched after %d frames" % frames_off)
	_approach(150.0, 6.0, 2000.0)
	await _fly(maxi(1, frames_off - 4), fly)
	ok = ok and await _shot("a1-field-off-a-moment-before-the-wall", 24.0, -2.0)
	# on: the moment it takes hold, and half a second on
	Seat.avoid_on = true
	_approach(150.0, 6.0, 2000.0)
	var frames_on := 0
	while frames_on < 400 and sim.avoid_a <= 0.0:
		await _fly(1, fly)
		frames_on += 1
	await _fly(6, fly)
	print("FIELD RENDER on: the field takes hold after %d frames, %.1f g, \"%s\"" % [frames_on, sim.avoid_a / 9.81, seat.avoid_text()])
	ok = ok and await _shot("b1-field-on-as-it-takes-hold", 24.0, -2.0)
	ok = ok and await _shot("b2-field-on-the-dash-says-so", 0.0, -24.0)
	await _fly(maxi(1, frames_off - frames_on - 6), fly)
	var R = sim.roads[3]
	var to_wall: float = 200.0 - ((sim.pod.x - R.px[300]) * R.nx[300] + (sim.pod.y - R.py[300]) * R.ny[300])
	print("FIELD RENDER on: where the wall was touched without it, the pod is %.1f m from the wall" % to_wall)
	ok = ok and await _shot("b3-field-on-where-the-wall-was-hit-without-it", 24.0, -2.0)
	# the OPTIONS page
	Seat.avoid_on = false
	_approach(150.0, 0.0, 300.0)
	await _fly(20, fly)
	seat.menu_open(true)
	for k in seat.menu.items.size():
		if String(seat.menu.items[k].key) == "options":
			seat.menu.at = k
	seat.menu_choose()
	ok = ok and await _shot("c1-options-page-with-the-avoidance-field", 0.0, 0.0)
	seat.menu_open(false)
	seat.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Seat.PREFS))
	else:
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("FIELD RENDER ", "DONE" if ok else "FAILED")
	quit(0 if ok else 1)
