## Realism spike: the engines and their jets, from the pilot seat and from outside. Run windowed, as
## render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_engine_spike.gd -- --mute --out=DIR [--views=a,b] [--open]
## Each view starts from rest on an open highway, holds the levers as told for some seconds (then,
## optionally, a hard turn for the last of them), and looks at the engines.
extends "res://tests/render_terminal_art.gd"

# Name; seconds at full throttle; burner; seconds of hard right turn at the end; where the camera is:
# "seat" (with a field of view), or [m right of the engines' middle, m up, m behind their nozzles]
# looking at the nozzles.
const VIEWS := [
	["f1-seat-dry", 2.5, false, 0.0, "seat", 34.0],
	["f2-seat-burner", 4.0, true, 0.0, "seat", 34.0],
	["f3-seat-burner-hard-right", 4.0, true, 0.9, "seat", 34.0],
	["f4-seat-burner-wide", 4.0, true, 0.0, "seat", 0.0],
	["f5-behind-burner", 4.0, true, 0.0, [0.0, 2.2, 7.0]],
	["f6-side-burner", 4.0, true, 0.0, [13.0, 1.2, 4.0]],
	["f7-above-burner", 4.0, true, 0.0, [0.0, 16.0, 5.0]],
	["f8-above-burner-hard-right", 4.0, true, 0.9, [0.0, 16.0, 5.0]],
	["f9-side-dry", 2.5, false, 0.0, [13.0, 1.2, 4.0]],
	["f10-behind-brakes", 4.0, true, -1.0, [3.0, 2.0, 6.0]],
	["f11-behind-ramjet", 4.0, true, 0.0, [2.5, 2.4, 8.0]],
	["f12-seat-ramjet", 4.0, true, 0.0, "seat", 34.0],
	["f13-chase-burner-hard-left", 4.0, true, 0.9, [-1.0, 5.0, 16.0]],
	# the approach guidance, lit: from the seat (field of view, then degrees of head pitch), and
	# ["pod", eye, target] in the canopy's own frame
	["h1-seat-guidance", 2.0, false, 0.0, "seat", 0.0, -3.0],
	["h2-seat-guidance-looking-up", 2.0, false, 0.0, "seat", 0.0, 24.0],
	["h3-seat-guidance-headset-field", 2.0, false, 0.0, "seat", 96.0, 6.0],
	["h4-housing-from-the-shoulder", 2.0, false, 0.0, ["pod", Vector3(0.22, 0.22, 0.72), Vector3(0.0, 0.44, 0.27)]],
	["h5-canopy-from-outside", 2.0, false, 0.0, ["pod", Vector3(1.5, 0.95, -2.1), Vector3(0.0, 0.42, 0.0)]],
	["h6-canopy-from-the-side", 2.0, false, 0.0, ["pod", Vector3(3.2, 0.5, -0.4), Vector3(0.0, 0.42, -0.4)]],
	# the windscreen's reflection of the cockpit: from the seat, looking up into the glass, the head
	# moved a hand's breadth, and what the mirror itself saw
	["r1-seat-ahead", 2.0, false, 0.0, "seat", 0.0, -3.0],
	["r2-seat-looking-up", 2.0, false, 0.0, "seat", 0.0, 18.0],
	["r3-seat-head-right", 2.0, false, 0.0, ["pod", Vector3(0.14, 0.12, 0.6), Vector3(0.14, 0.44, -0.4)]],
	["r4-seat-head-left", 2.0, false, 0.0, ["pod", Vector3(-0.14, 0.12, 0.6), Vector3(-0.14, 0.44, -0.4)]],
	# the cabin round the seat and over it, from the seated eye: the sides by the hips, the lap, over
	# each shoulder, the ceiling; and down into it from above (best with --open)
	["k1-seat-down-left", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(-0.55, -0.42, 0.62)]],
	["k2-seat-down-right", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(0.55, -0.42, 0.62)]],
	["k3-seat-lap", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(0.0, -0.6, 0.3)]],
	["k4-seat-over-left-shoulder", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(-0.6, -0.25, 1.25)]],
	["k5-seat-ceiling", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(0.0, 0.62, 0.45)]],
	["k6-seat-ceiling-aft", 1.0, false, 0.0, ["pod", Vector3(0.0, 0.12, 0.6), Vector3(0.25, 0.6, 1.0)]],
	["k7-cabin-from-above", 1.0, false, 0.0, ["pod", Vector3(0.0, 2.3, 0.75), Vector3(0.0, 0.0, 0.55)]],
	["k8-cabin-from-above-left", 1.0, false, 0.0, ["pod", Vector3(-1.1, 1.5, 1.5), Vector3(0.1, -0.2, 0.6)]],
]
const MESSAGE := "JUMP LIP  2 MI / 4.0 S
ASCENT J0 > N2 UPPER
MIN 3,000 MPH AT LIP | READY"


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
	if "--open" in OS.get_cmdline_user_args():
		preload("res://view/canopy.gd").roofed = false
	if "--no-reflection" in OS.get_cmdline_user_args():
		preload("res://view/screen_reflection.gd").enabled = false
	if "--reflection-every-frame" in OS.get_cmdline_user_args():   # timings: a picture every frame, to weigh one
		preload("res://view/screen_reflection.gd").every = 0.0
	if "--reflection-whole" in OS.get_cmdline_user_args():   # timings: the sheet over the whole pane, not cut to what shows
		preload("res://view/screen_reflection.gd").whole = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reflection="):
			preload("res://view/screen_reflection.gd").strength = float(arg.trim_prefix("--reflection="))
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	if seat.cam == null:      # a script under it failed to compile: say so now, not at the timeout
		push_error("The cockpit did not build.")
		quit(1)
		return
	seat.set_process(false)
	seat.cruise = 0.0
	city = {"road": 2, "i": 9000}   # E3, open country
	_set_pose(0)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	var wide: float = seat.cam.fov
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		_set_pose(0)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = wide
		for frame in 20:
			seat._process(STEP)
			await process_frame
		var total := int(float(view[1]) * 120.0)
		var turn := int(absf(float(view[3])) * 120.0)
		for frame in total:
			var turning: bool = frame >= total - turn
			seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": bool(view[2])}
			if turning and str(view[0]).contains("hard-left"):
				seat.inp.thrL = 0.25
				seat.inp.brkL = 1.0
			elif turning and float(view[3]) > 0.0:    # hard right: the right engine eased and its brake out
				seat.inp.thrR = 0.25
				seat.inp.brkR = 1.0
			elif turning:                            # both brakes out, levers held: the flaps under load
				seat.inp.brkL = 1.0
				seat.inp.brkR = 1.0
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		if str(view[0]).contains("ramjet"):      # (the ramjet wants Mach 5: show its fire without the run-up)
			seat.sim.mode = "ramjet"
			for frame in 60:
				seat.craft.sync(seat.sim, seat.inp, 1.0 / 120.0)
		var guided: bool = str(view[0]).begins_with("h")
		if str(view[0]).begins_with("r") and seat.approach_display:     # (nothing over the glass but the glass)
			seat.approach_display.set_message("")
			seat.approach_display._process(1.0)
		if str(view[0]).begins_with("r") and seat.screen_reflection:    # a fresh picture of the cockpit as it stands
			seat.screen_reflection.take()
			for frame in 6:
				await process_frame
		if guided and seat.approach_display:
			seat.approach_display.set_message(MESSAGE)
			seat.approach_display._process(1.0)
		if view[4] is String:
			seat.cam.fov = float(view[5]) if float(view[5]) > 0.0 else wide
			seat.cam.rotation_degrees = Vector3(-5.5 if float(view[5]) > 0.0 else -3.0, 0.0, 0.0)
			if view.size() > 6:
				seat.cam.rotation_degrees.x = float(view[6])
		elif str(view[4][0]) == "pod":
			var frame: Transform3D = (seat.canopy as Node3D).global_transform
			seat.cam.global_position = frame * (view[4][1] as Vector3)
			seat.cam.look_at(frame * (view[4][2] as Vector3), frame.basis.y)
		else:
			# outside: against the engines' nozzles, in the craft's own frame
			var craft = seat.craft
			var mid: Vector3 = ((craft.engines[0] as Node3D).global_position + (craft.engines[1] as Node3D).global_position) * 0.5
			var basis: Basis = (craft.engines[0] as Node3D).global_basis
			var nozzle: Vector3 = mid + basis.z * 4.3
			var off: Array = view[4]
			seat.cam.global_position = nozzle + basis.x * float(off[0]) + Vector3.UP * float(off[1]) + basis.z * float(off[2])
			seat.cam.look_at(nozzle + basis.z * 2.5, Vector3.UP if float(off[1]) < 10.0 else -basis.z)
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		if str(view[0]).begins_with("r1") and seat.screen_reflection:   # the mirror's own picture, beside the views of it
			print("REFLECTION sheet: %d cells, %.0f %% of the screen; sights %s" % [seat.screen_reflection.cells, seat.screen_reflection.share * 100.0, seat.screen_reflection.sights])
			seat.screen_reflection.port.get_texture().get_image().save_png(out_dir.path_join("r0-the-picture.png"))
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		print("ENGINE_SHOT %s  %.0f mph  mode %s  thrust %.2f %.2f  vane %.1f deg" % [view[0], sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694, seat.sim.mode,
			seat.sim.eL.thrust, seat.sim.eR.thrust, rad_to_deg(seat.craft.vane_angle)])
	seat.free()
	quit()
