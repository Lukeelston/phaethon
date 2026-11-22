## Realism spike: the tow links and the bullring (view/tow_link.gd), from the pilot's seat and from
## outside. Run windowed, as render_engine_spike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_tow_links.gd -- --mute --out=DIR [--views=a,b] [--time=night] [--vehicle=shrike]
## Each view starts from rest on an open highway, is flown as its drive says, and is looked at from
## where its camera says. It reads nothing the ropes did not have too (the two ends of each link),
## so the same pictures can be taken of the craft as it was.
extends "res://tests/render_terminal_art.gd"

# Name; how it is flown ("rest": standing; "cruise": 2 s at full dry thrust; "burner": 4 s on the
# burner; "left": that, the last 0.9 s a hard left; "slack": cruise, then the right engine set back
# 2.5 m toward the pod; "limit": cruise, then the left engine sent ahead faster until its link's
# tension reads as the limit); and the camera:
#   ["seat", field of view, degrees of head pitch]
#   ["pod", eye, target]                          in the canopy's own frame
#   ["engine", which, eye, target]                in that engine's frame
#   ["link", which, m along it from the pod, m right, m up, m back toward the pod]
const VIEWS := [
	["a1-seat-at-rest", "rest", ["seat", 60.0, -7.0]],
	["a2-seat-flat-out", "burner", ["seat", 60.0, -7.0]],
	["a3-seat-hard-left", "left", ["seat", 60.0, -7.0]],
	["a4-seat-right-link-slack", "slack", ["seat", 60.0, -7.0]],
	["a5-seat-left-link-at-the-limit", "limit", ["seat", 60.0, -7.0]],
	["a6-seat-headset-field", "cruise", ["seat", 96.0, -10.0]],
	["a7-seat-looking-at-the-left-link", "cruise", ["seat", 28.0, -5.0, 6.0]],
	["b1-bullring-from-ahead", "cruise", ["pod", Vector3(0.75, 0.42, -3.1), Vector3(0.0, 0.0, -2.1)]],
	["b2-bullring-from-above", "cruise", ["pod", Vector3(-0.35, 0.75, -1.55), Vector3(0.05, 0.0, -2.25)]],
	["b3-bullring-in-a-hard-left", "left", ["pod", Vector3(0.75, 0.42, -3.1), Vector3(0.0, 0.0, -2.1)]],
	["c1-engine-lug", "cruise", ["engine", 0, Vector3(1.15, -0.7, 4.75), Vector3(0.0, -0.93, 3.6)]],
	["c2-engine-lug-in-a-hard-left", "left", ["engine", 0, Vector3(1.15, -0.7, 4.75), Vector3(0.0, -0.93, 3.6)]],
	["d1-barrel-mouth", "cruise", ["link", 0, 5.0, 1.0, 0.45, 0.9]],
	["d2-barrel-mouth-right-link-slack", "slack", ["link", 1, 5.0, -1.0, 0.45, 0.9]],
	["e1-chase", "cruise", ["pod", Vector3(2.6, 2.4, 7.5), Vector3(0.0, -0.3, -9.0)]],
	["e2-chase-hard-left", "left", ["pod", Vector3(2.6, 2.4, 7.5), Vector3(0.0, -0.3, -9.0)]],
	["e3-from-the-side", "cruise", ["pod", Vector3(-12.0, 0.6, -10.0), Vector3(-1.5, -1.0, -10.0)]],
	["e4-from-above", "cruise", ["pod", Vector3(0.0, 15.0, -9.5), Vector3(0.0, 0.0, -10.0)]],
	["e5-chase-right-link-slack", "slack", ["pod", Vector3(2.6, 2.4, 7.5), Vector3(0.0, -0.3, -9.0)]],
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
	Seat._slide_loaded = true
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
	print("TOW_SHOT craft %s; link nodes %s" % [seat.sim.P.vehicle, "there" if "link_parts" in craft else "none (ropes)"])
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		for frame in 480:      # (whatever the last view left pending runs out first: a hard turn that ends in the wall puts the craft back seconds later)
			seat._process(STEP)
			if frame % 8 == 0:
				await process_frame
		_set_pose(0)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = wide
		for body in [seat.sim.eL, seat.sim.eR, seat.sim.pod]:      # each view from a cold, whole craft: an engine left hot or
			body.heat = 0.3                                        # knocked by the last view's turn cuts out part way through this one
			body.health = 1.0
		var idle := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		seat.inp = idle
		for frame in 40:
			seat._process(STEP)
			if frame % 2 == 0:
				await process_frame
		var drive: String = view[1]
		var total := 0 if drive == "rest" else (480 if drive in ["burner", "left"] else 240)
		for frame in total:
			seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": drive in ["burner", "left"]}
			if drive == "left" and frame >= total - 108:
				seat.inp.thrL = 0.25
				seat.inp.brkL = 1.0
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		if drive == "slack":
			seat.sim.eR.x -= 2.5 * cos(seat.sim.pair_th)
			seat.sim.eR.y -= 2.5 * sin(seat.sim.pair_th)
			seat._process(STEP)
		elif drive == "limit":      # the left engine sent ahead faster, harder each frame, until its link's tension reads as the limit
			for push in 12:
				if craft.cable_strain[0] >= 1.03:
					break
				seat.sim.eL.vx += (3.0 + push) * cos(seat.sim.pair_th)
				seat.sim.eL.vy += (3.0 + push) * sin(seat.sim.pair_th)
				seat._process(STEP)
		var cam: Array = view[2]
		var ends: Array = craft.cable_ends
		if str(cam[0]) == "seat":
			seat.cam.fov = float(cam[1])
			seat.cam.rotation_degrees = Vector3(float(cam[2]), float(cam[3]) if cam.size() > 3 else 0.0, 0.0)
		elif str(cam[0]) == "pod":
			var frame: Transform3D = (seat.canopy as Node3D).global_transform
			seat.cam.global_position = frame * (cam[1] as Vector3)
			seat.cam.look_at(frame * (cam[2] as Vector3), frame.basis.y)
		elif str(cam[0]) == "engine":
			var frame: Transform3D = (craft.engines[int(cam[1])] as Node3D).global_transform
			seat.cam.global_position = frame * (cam[2] as Vector3)
			seat.cam.look_at(frame * (cam[3] as Vector3), Vector3.UP)
		else:
			var to_world: Transform3D = (craft as Node3D).global_transform
			var from: Vector3 = to_world * (ends[int(cam[1])][1] as Vector3)
			var to: Vector3 = to_world * (ends[int(cam[1])][0] as Vector3)
			var along := (to - from).normalized()
			var right := along.cross(Vector3.UP).normalized()
			var at := from + along * float(cam[2])
			seat.cam.global_position = at + right * float(cam[3]) + Vector3.UP * float(cam[4]) - along * float(cam[5])
			seat.cam.look_at(at, Vector3.UP)
			seat.cam.fov = 50.0
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		var spans := []
		for k in 2:
			var cab: Dictionary = seat.sim.cables[k]
			spans.append("%.2f m%s" % [Vector2(cab.ex - cab.px, cab.ey - cab.py).length(), " slack" if cab.slack else ""])
		print("TOW_SHOT %s  %.0f mph  thrust %.2f %.2f  strain %.2f %.2f  the sim's spans %s, %s  glow %.1f %.1f%s" % [view[0], sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694,
			seat.sim.eL.thrust, seat.sim.eR.thrust, craft.cable_strain[0], craft.cable_strain[1], spans[0], spans[1],
			craft.cable_mats[0].emission_energy_multiplier, craft.cable_mats[1].emission_energy_multiplier,
			("  rod showing %.2f %.2f m" % [craft.link_exposed[0], craft.link_exposed[1]]) if "link_exposed" in craft else ""])
	seat.free()
	quit()
