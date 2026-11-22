## The Shrike RS, for looking at: its cockpit from the seat and close on each dial (Luke: "for Shrike,
## fix the cut-off tachometer nose"), its nose from outside, and its engine fins on their hinges and
## rams at rest and at speed (view/shrike_airframe.gd). Run windowed, as render_tow_links.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_shrike.gd -- --mute --out=DIR [--views=a,b] [--time=night] [--closed-nose]
## It reads nothing an older Shrike did not have (the fins' own numbers only where they exist), so the
## same pictures can be taken of the craft as it was.
extends "res://tests/render_terminal_art.gd"

# Name; how it is flown ("rest": standing; "braked": standing with the brakes held; "cruise": 2 s at
# full dry thrust; "burner": 4 s on the burner); where the fins are put for the picture (rad from upright; -1: where the flying left them);
# and the camera:
#   ["seat", field of view, degrees of head pitch, degrees of head yaw]
#   ["dash", x, y along the instrument panel, m back from it, field of view]     square on to a dial
#   ["shell", eye, target, field of view]         in the cockpit's own frame
#   ["pod", eye, target]                          in the canopy's own frame
#   ["engine", which, eye, target]                in that engine's frame
const VIEWS := [
	["c1-seat-ahead", "rest", -1.0, ["seat", 60.0, -7.0, 0.0]],
	["c2-seat-instruments", "rest", -1.0, ["seat", 60.0, -24.0, 0.0]],
	["c3-seat-headset-field", "rest", -1.0, ["seat", 96.0, -14.0, 0.0]],
	["c4-seat-over-the-nose", "rest", -1.0, ["seat", 34.0, -13.0, 0.0]],
	["c5-left-tachometer", "rest", -1.0, ["dash", -0.2115, 0.021, 0.30, 44.0]],
	["c6-right-tachometer", "rest", -1.0, ["dash", 0.2115, 0.021, 0.30, 44.0]],
	["c7-centre-dial", "rest", -1.0, ["dash", 0.0, 0.038, 0.36, 44.0]],
	["c8-coaming-from-above", "rest", -1.0, ["shell", Vector3(0.0, 1.0, 0.22), Vector3(0.0, 0.55, -0.75), 60.0]],
	["c9-nose-from-ahead", "rest", -1.0, ["shell", Vector3(0.0, 1.05, -3.3), Vector3(0.0, 0.45, -0.6), 40.0]],
	["c10-nose-from-the-side", "rest", -1.0, ["shell", Vector3(-2.3, 1.0, -1.3), Vector3(0.0, 0.5, -0.75), 40.0]],
	["c11-seat-flown", "cruise", -1.0, ["seat", 60.0, -16.0, 0.0]],
	["f1-ram-standing-tall", "rest", 0.48, ["engine", 1, Vector3(-1.0, 1.55, 2.7), Vector3(0.75, 0.62, 0.75)]],
	["f2-ram-as-drawn", "rest", 0.76, ["engine", 1, Vector3(-1.0, 1.55, 2.7), Vector3(0.75, 0.62, 0.75)]],
	["f3-ram-laid-out", "rest", 1.04, ["engine", 1, Vector3(-1.0, 1.55, 2.7), Vector3(0.75, 0.62, 0.75)]],
	["f4-hinge-from-ahead-tall", "rest", 0.48, ["engine", 1, Vector3(2.3, 1.35, -2.4), Vector3(0.95, 0.55, 0.4)]],
	["f5-hinge-from-ahead-laid-out", "rest", 1.04, ["engine", 1, Vector3(2.3, 1.35, -2.4), Vector3(0.95, 0.55, 0.4)]],
	["f6-ram-close", "rest", 0.76, ["engine", 1, Vector3(0.15, 1.05, 1.75), Vector3(0.72, 0.70, 0.80)]],
	["f7-port-engine-from-behind-tall", "rest", 0.48, ["engine", 0, Vector3(0.0, 1.6, 7.0), Vector3(0.0, 0.5, 0.0)]],
	["f8-port-engine-from-behind-laid-out", "rest", 1.04, ["engine", 0, Vector3(0.0, 1.6, 7.0), Vector3(0.0, 0.5, 0.0)]],
	["f9-root-and-brake-leaves-laid-out", "braked", 1.04, ["engine", 1, Vector3(2.0, 1.5, 3.3), Vector3(0.9, 0.5, 1.4)]],
	["f10-root-and-brake-leaves-tall", "braked", 0.48, ["engine", 1, Vector3(2.0, 1.5, 3.3), Vector3(0.9, 0.5, 1.4)]],
	["g1-chase-tall", "rest", 0.48, ["pod", Vector3(0.0, 2.6, 6.5), Vector3(0.0, 0.2, -11.0)]],
	["g2-chase-laid-out", "rest", 1.04, ["pod", Vector3(0.0, 2.6, 6.5), Vector3(0.0, 0.2, -11.0)]],
	["g3-seat-tall", "rest", 0.48, ["seat", 60.0, -7.0, 0.0]],
	["g4-seat-laid-out", "rest", 1.04, ["seat", 60.0, -7.0, 0.0]],
	["g5-from-ahead-tall", "rest", 0.48, ["pod", Vector3(0.0, 2.2, -24.0), Vector3(0.0, 0.3, -12.0)]],
	["g6-from-ahead-laid-out", "rest", 1.04, ["pod", Vector3(0.0, 2.2, -24.0), Vector3(0.0, 0.3, -12.0)]],
	["h1-flown-two-seconds-dry", "cruise", -1.0, ["pod", Vector3(3.2, 2.4, 6.5), Vector3(0.0, 0.0, -11.0)]],
	["h2-flown-four-seconds-on-the-burner", "burner", -1.0, ["pod", Vector3(3.2, 2.4, 6.5), Vector3(0.0, 0.0, -11.0)]],
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
	Seat._nose_loaded = true       # (the pilot's saved choices stay out of the pictures)
	if "--closed-nose" in OS.get_cmdline_user_args():      # the nose skinned over (the quick menu's NOSE line)
		preload("res://view/craft_model.gd").nose_closed = true
	Seat._slide_loaded = true
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	preload("res://view/livery.gd").pinned = true
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
	var chase_script := preload("res://view/network_chase.gd")
	chase_script.pinned = true
	chase_script.enabled = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.vehicle_override = "shrike"
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
	var craft = seat.craft
	var hinged: bool = "fin_parts" in craft and not craft.fin_parts.is_empty()
	print("SHRIKE_SHOT craft %s; fins %s" % [seat.sim.P.vehicle, "on their hinges" if hinged else "fixed"])
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		for frame in 480:      # (whatever the last view left pending runs out first)
			seat._process(STEP)
			if frame % 8 == 0:
				await process_frame
		_set_pose(0)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = wide
		for body in [seat.sim.eL, seat.sim.eR, seat.sim.pod]:
			body.heat = 0.3
			body.health = 1.0
		for frame in 320:      # standing: long enough for the fins' rams to bring them back
			seat._process(STEP)
			if frame % 8 == 0:
				await process_frame
		var drive: String = view[1]
		var total := 0 if drive in ["rest", "braked"] else (480 if drive == "burner" else 240)
		for frame in total:
			seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": drive == "burner"}
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		if drive == "braked":      # standing with both brakes held: the engines' leaves out
			seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}
			for frame in 90:
				seat._process(STEP)
				if frame % 4 == 0:
					await process_frame
		if hinged and float(view[2]) >= 0.0:
			craft.fin_cant = float(view[2])
			for k in craft.fin_parts.size():
				craft._place_fin(k, craft.fin_cant)
		var cam: Array = view[3]
		match str(cam[0]):
			"seat":
				seat.cam.fov = float(cam[1])
				seat.cam.rotation_degrees = Vector3(float(cam[2]), float(cam[3]), 0.0)
			"dash":
				var panel: Transform3D = (seat.dashboard as Node3D).global_transform
				seat.cam.global_position = panel * Vector3(float(cam[1]), float(cam[2]), float(cam[3]))
				seat.cam.look_at(panel * Vector3(float(cam[1]), float(cam[2]), 0.0), panel.basis.y)
				seat.cam.fov = float(cam[4])
			"shell":
				var frame: Transform3D = (seat.shell as Node3D).global_transform
				seat.cam.global_position = frame * (cam[1] as Vector3)
				seat.cam.look_at(frame * (cam[2] as Vector3), frame.basis.y)
				seat.cam.fov = float(cam[3])
			"pod":
				var frame: Transform3D = (seat.canopy as Node3D).global_transform
				seat.cam.global_position = frame * (cam[1] as Vector3)
				seat.cam.look_at(frame * (cam[2] as Vector3), frame.basis.y)
			"engine":
				var frame: Transform3D = (craft.engines[int(cam[1])] as Node3D).global_transform
				seat.cam.global_position = frame * (cam[2] as Vector3)
				seat.cam.look_at(frame * (cam[3] as Vector3), Vector3.UP)
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		print("SHRIKE_SHOT %s  %.0f mph%s" % [view[0], sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694,
			("  fins %.1f deg from upright, rods showing %.3f %.3f m" % [rad_to_deg(craft.fin_cant), craft.fin_ram[0], craft.fin_ram[1]]) if hinged else ""])
	seat.free()
	quit()
