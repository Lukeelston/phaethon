## The speed rush from the pilot's seat (vr/speed_rush.gd): stills with it switched off (the cockpit as it
## was) and on, at rest, off the line, at 3,000 mph and at 8,000 mph. Each is a pose, not a flight: the craft
## is stood on the open road with its speed and its load along the nose told, and the rush settled where
## that speed and load hold it, so the two pictures of a pair differ by the rush alone.
## Run windowed, as render_g_meter.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_speed_rush.gd -- --mute --out=DIR [--views=a,b] [--states=a,b] [--at=road,sample]
## [--time=dusk] [--sequence=8: the streaks going by at 3,000 mph, frames a ninetieth of a second apart]
extends "res://tests/render_terminal_art.gd"

const Rush := preload("res://vr/speed_rush.gd")

# Name, the craft's speed (mph), her load along the nose (g: tests/probe_rush.gd has a launch at 29 g and
# third gear at 3,000 mph at 15), and her levers.
const STATES := [
	["rest", 0.0, 0.0, 0.0],
	["launch", 600.0, 29.0, 0.87],
	["3000", 3000.0, 15.0, 0.87],
	["8000", 8000.0, 0.0, 0.87],
]
# Name, the field of view up and down (38 degrees is about what a headset shows, pixel for pixel; 0 the
# camera's own wide one), and the head's pitch and yaw, degrees.
const VIEWS := [
	["wide", 0.0, 0.0, 0.0],
	["dash", 38.0, -26.0, 0.0],
	["edge-left", 38.0, 0.0, 34.0],
	["left", 38.0, 4.0, 62.0],
	["up-right", 38.0, 30.0, -40.0],
]


func _pose(state: Array, on: bool) -> void:
	_set_pose(0)
	var road = seat.sim.roads[int(city.road)]
	var i := int(city.i)
	var mps := float(state[1]) / 2.236936
	for b in seat.sim.bodies:
		b.vx = mps * road.tx[i]
		b.vy = mps * road.ty[i]
	seat.inp = {"thrL": state[3], "thrR": state[3], "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	Seat.speed_rush = on
	seat._process(0.0)      # (no time passes: the sim is not stepped, and she keeps the speed she was told)
	var rush = seat.rush
	for frame in 8:
		seat.g_along = float(state[2])
		rush.load_g = float(state[2])
		rush.surge = Rush.target(float(state[2]), float(state[1])) if on else 0.0
		rush.rate = 0.0
		rush.shown = 1.0 if on else 0.0
		rush.travel = 137.0      # (the same streaks in every picture)
		seat._process(0.0)
		await process_frame
	for read in 3:      # (the strip's figures are read by the wall's clock, which a harness outruns: read them now)
		seat.dashboard.settle(0.1)


func _run() -> void:
	var only := PackedStringArray()
	var states := PackedStringArray()
	var sequence := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--states="):
			states = arg.trim_prefix("--states=").split(",")
		if arg.begins_with("--sequence="):
			sequence = int(arg.trim_prefix("--sequence="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Seat._nose_loaded = true       # (the pilot's saved choices stay out of the pictures)
	Seat._slide_loaded = true
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat._rush_loaded = true
	Seat.camera = "cockpit"
	preload("res://view/livery.gd").pinned = true
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	if seat.cam == null:
		push_error("The cockpit did not build.")
		quit(1)
		return
	seat.set_process(false)
	seat.cruise = 0.0
	city = {"road": 2, "i": 9000}   # E3, open country
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):      # road,sample: another stretch
			var at := arg.trim_prefix("--at=").split(",")
			city = {"road": int(at[0]), "i": int(at[1])}
	_set_pose(0)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	var wide: float = seat.cam.fov
	for state in STATES:
		if not states.is_empty() and not states.has(str(state[0])):
			continue
		for on in [false, true]:
			await _pose(state, on)
			for view in VIEWS:
				if not only.is_empty() and not only.has(str(view[0])):
					continue
				seat.cam.position = Vector3.ZERO
				seat.cam.fov = float(view[1]) if float(view[1]) > 0.0 else wide
				seat.cam.rotation_degrees = Vector3(float(view[2]), float(view[3]), 0.0)
				for frame in 2:
					await process_frame
				await RenderingServer.frame_post_draw
				var path := out_dir.path_join("%s-%s-%s.png" % [state[0], view[0], "on" if on else "off"])
				if root.get_texture().get_image().save_png(path) != OK:
					push_error("Couldn't save " + path)
					quit(1)
					return
			var rush = seat.rush
			var streaks := "none"
			if rush.streaks.visible:
				streaks = "%.0f%% out, %.1f m long, strength %.2f" % [float(rush.mat.get_shader_parameter("amount")) * 100.0, float(rush.mat.get_shader_parameter("streak_length")), float(rush.mat.get_shader_parameter("strength"))]
			print("RUSH_SHOT %s %s  %.0f mph  %.1f g along  shell %.1f mm forward  streaks: %s" % [state[0], "on" if on else "off",
				seat._kmh() / 1.609344, seat.g_along, -seat._rush_shift.z * 1000.0, streaks])      # (the shell stands at the pod's pose: its own move is the rush's)
	if sequence > 0:      # the streaks going by: the head turned to the left, the craft held at 3,000 mph
		await _pose(STATES[2], true)
		seat.cam.position = Vector3.ZERO
		seat.cam.fov = 38.0
		seat.cam.rotation_degrees = Vector3(4.0, 62.0, 0.0)
		for k in sequence:
			seat.rush.sync(1.0 / 90.0, float(STATES[2][1]), true, seat._rush_flow)
			for frame in 2:
				await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(out_dir.path_join("seq-%02d.png" % k)) != OK:
				push_error("Couldn't save the sequence")
				quit(1)
				return
		print("RUSH_SEQUENCE %d frames, the streaks' travel %.2f m a frame (%.2f of their length)" % [sequence, Rush.STEP_MAX * Rush.streak_length(Rush.speed_share(float(STATES[2][1]))), Rush.STEP_MAX])
	seat.free()
	quit()
