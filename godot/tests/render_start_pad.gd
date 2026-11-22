## The starting pad, for looking at (view/start_pad.gd): from the seat held cold and released, and
## from outside, at a few start points. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_start_pad.gd -- --mute --out=DIR [--all-seats] [--views=a,b] [--time=night] [--weather=rain]
extends "res://tests/render_terminal_art.gd"

# Name, the start's spot, "cold" or "hot", then the camera: ["seat", yaw (left +), pitch] in degrees,
# or ["pad", where the eye is, what it looks at] in the pad's own metres (x right, y up, -z ahead).
const VIEWS := [
	["a1-frost-held-from-the-seat", "SFrost@140", "cold", ["seat", 0.0, -2.0]],
	["a2-frost-released-from-the-seat", "SFrost@140", "hot", ["seat", 0.0, -2.0]],
	["a3-frost-the-mast-from-the-seat", "SFrost@140", "cold", ["seat", -18.0, 6.0]],
	["a4-frost-from-behind", "SFrost@140", "cold", ["pad", Vector3(-9.0, 7.0, 34.0), Vector3(4.0, 2.0, -30.0)]],
	["a5-frost-from-the-road", "SFrost@140", "hot", ["pad", Vector3(-46.0, 5.0, -8.0), Vector3(4.0, 3.0, -24.0)]],
	["a6-frost-from-above", "SFrost@140", "cold", ["pad", Vector3(2.0, 70.0, 30.0), Vector3(1.0, 0.0, -18.0)]],
	["b1-glacier-hall-from-the-seat", "city:GLACIER", "cold", ["seat", 0.0, -2.0]],
	["b2-glacier-hall-from-behind", "city:GLACIER", "hot", ["pad", Vector3(-9.0, 7.0, 34.0), Vector3(4.0, 2.0, -30.0)]],
	["c1-summit-from-the-seat", "SHelios@8220", "cold", ["seat", 0.0, -2.0]],
	["c2-summit-from-behind", "SHelios@8220", "hot", ["pad", Vector3(-12.0, 9.0, 40.0), Vector3(4.0, 2.0, -30.0)]],
	["d1-highway-from-the-seat", "N3@300", "cold", ["seat", 0.0, -2.0]],
	["d2-highway-from-the-road", "N3@300", "hot", ["pad", Vector3(-60.0, 6.0, 20.0), Vector3(4.0, 3.0, -24.0)]],
	# "school": a taught run-up (vr/startup_sequence.gd `school`), stopped on its third lesson, the right turn
	["e1-school-the-lesson-on-the-glass", "SFrost@140", "school", ["seat", 0.0, 14.0]],
	["e2-school-from-the-seat", "SFrost@140", "school", ["seat", 0.0, 4.0]],
	# the Caucasus' two (2026-11-22): its foot, and the top of its crest (an open apron either side of the bay)
	["f1-caucasus-foot-from-the-seat", "SCaucasus", "cold", ["seat", 0.0, -2.0]],
	["f2-caucasus-foot-from-behind", "SCaucasus", "cold", ["pad", Vector3(-9.0, 7.0, 34.0), Vector3(4.0, 2.0, -30.0)]],
	["f3-caucasus-crest-from-the-seat", "SCaucasus@4534", "cold", ["seat", 0.0, -2.0]],
	["f4-caucasus-crest-from-behind", "SCaucasus@4534", "hot", ["pad", Vector3(-12.0, 9.0, 40.0), Vector3(4.0, 2.0, -30.0)]],
	["f5-caucasus-crest-from-the-road", "SCaucasus@4534", "cold", ["pad", Vector3(-46.0, 5.0, -8.0), Vector3(4.0, 3.0, -24.0)]],
]


func _run() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
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
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var spot := ""
	var was := ""
	var views: Array = VIEWS
	var all_seats := "--all-seats" in OS.get_cmdline_user_args()
	if all_seats:
		views = []
		for entry in preload("res://release/release_config.gd").INSERTIONS:
			if entry[2] != "":
				views.append([entry[0], entry[2], "cold", ["seat", 0.0, 3.0]])
	for view in views:
		if not only.is_empty() and not only.has(view[0]):
			continue
		if view[1] != spot or view[2] != was:      # a new place or a new state: a new flight, as a menu would start it
			if seat:
				seat.free()
				await process_frame
			spot = view[1]
			was = view[2]
			Seat.track_override = "network"
			Seat.job_override = "none"
			Seat.spot_override = spot
			Seat.pad_start = true
			Seat.best_dir = out_dir.path_join("review_")
			Seat._startup_loaded = true
			Seat.cold_start = true
			Seat.cold_on_entry = was == "cold" or was == "school"
			Seat._school_loaded = true
			Seat.school = was == "school"
			seat = Seat.new()
			root.add_child(seat)
			if seat.cam == null or seat.pad == null:
				push_error("The cockpit or its pad did not build.")
				quit(1)
				return
			seat.set_process(false)
			seat.cruise = 0.0
			if was == "school":      # through the switches and the first two lessons, to the right turn
				var s = seat.startup
				s.gears = true
				s.flick("batt", 1)
				for k in 270:
					s.step(STEP, [0.0, 0.0], 1)
				s.flick("engine", 1)
				s.flick("engine", 1)
				for k in 140:
					s.step(STEP, [0.0, 0.0], 1)
				s.press_start()
				for k in 480:
					s.step(STEP, [0.0, 0.0], 1)
				for k in 480:
					s.step(STEP, [0.87, 0.87], 1)
				print("START PAD school: on lesson \"%s\" (%d of %d)" % [s.lesson(), s.lesson_number(), s.lesson_count()])
			var world = seat.network_world
			for i in 6000:
				world.sync(seat.sim.pod.x, seat.sim.pod.y)
				seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
				if i % 40 == 0:
					await process_frame
				var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
				if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
					break
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		# Just into the second flash: the cold frame shows which switch the mast is asking for.
		for frame in 132:
			seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false, "burner": false}
			seat._process(STEP)
			if frame % 3 == 0:
				await process_frame
		var cam: Array = view[3]
		if str(cam[0]) == "seat":
			seat.cam.rotation_degrees = Vector3(float(cam[2]), float(cam[1]), 0.0)
		else:
			var frame_of: Transform3D = (seat.pad as Node3D).global_transform
			seat.cam.global_position = frame_of * (cam[1] as Vector3)
			seat.cam.look_at(frame_of * (cam[2] as Vector3), frame_of.basis.y)
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var pad = seat.pad
		if all_seats and (pad.station_id != view[0] or pad.gate_open != 0 or pad.released or not seat.cam.position.is_zero_approx()):
			push_error("Capture requires the requested station, a cold, closed gate and the pilot's eye point: " + str(view[0]))
			quit(1)
			return
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("PAD_SHOT %s: home %s, released %s, steps lit %s, flashing %d, gate %.2f, ground power %s, board %s" % [view[0], pad.home, pad.released, pad.lit, pad.flashing, pad.gate_open, pad.plugged,
			[pad.lines[0].text, pad.lines[1].text, pad.lines[2].text]])
	if seat:
		seat.free()
	quit()
