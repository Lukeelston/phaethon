## The exhaust, looked at: the nozzles close to, the jets from the seat and from outside, the
## burner lighting, and a turn as it is flown. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_exhaust.gd -- --mute --handling=speed --out=DIR [--views=a,b] [--twilight]
## Each view starts from rest on an open highway, holds the levers as told for some seconds, then
## flies its last stretch as told ("turn"), and looks at the engines.
extends "res://tests/render_terminal_art.gd"

# name; seconds flown; mode ("dry", "burner", "ramjet", or "light": dry, then the burner lit this
# many seconds before the picture); the last stretch [seconds, kind]: "" none, "squeeze-right" an
# air-brake turn as the flights' logs have one (one grip a third in, both levers up), "hard-right"
# / "hard-left" a lever and a full brake; the camera: ["seat", field of view, head pitch], or
# [m right of the engines' middle, m up, m behind the nozzles, (m right, m up, m behind) it looks at]
const VIEWS := [
	["a1-nozzle-dry", 2.5, "dry", [0.0, ""], [4.6, 1.1, 2.6, 3.0, 0.0, -0.3]],
	["a2-nozzle-burner", 4.0, "burner", [0.0, ""], [4.6, 1.1, 2.6, 3.0, 0.0, -0.3]],
	["a3-up-the-pipe-burner", 4.0, "burner", [0.0, ""], [3.0, 0.5, 5.5, 3.0, 0.0, -0.3]],
	["a4-up-the-pipe-dry", 2.5, "dry", [0.0, ""], [3.0, 0.5, 5.5, 3.0, 0.0, -0.3]],
	["a5-nozzle-hard-right-from-above", 4.0, "burner", [0.5, "hard-right"], [3.0, 3.2, 1.6, 3.0, 0.0, 0.4]],
	["a6-nozzle-dry-hard-left-from-above", 2.5, "dry", [0.5, "hard-left"], [3.0, 3.2, 1.6, 3.0, 0.0, 0.4]],
	["h1-hardware-behind", 1.0, "dry", [0.0, ""], [3.0, 0.15, 3.2, 3.0, 0.0, -0.3]],
	["h2-hardware-above-behind", 1.0, "dry", [0.0, ""], [3.9, 1.6, 2.0, 3.0, 0.0, -0.2]],
	["h3-hardware-side", 1.0, "dry", [0.0, ""], [6.0, 0.3, 0.2, 3.0, 0.0, 0.0]],
	["h4-hardware-below-behind", 1.0, "dry", [0.0, ""], [3.9, -0.55, 2.0, 3.0, 0.0, -0.2]],
	["a7-nozzle-ramjet", 4.0, "ramjet", [0.0, ""], [4.6, 1.1, 2.6, 3.0, 0.0, -0.3]],
	["b1-seat-dry", 2.5, "dry", [0.0, ""], ["seat", 96.0, -6.0]],
	["b2-seat-burner", 4.0, "burner", [0.0, ""], ["seat", 96.0, -6.0]],
	["b3-seat-ramjet", 4.0, "ramjet", [0.0, ""], ["seat", 96.0, -6.0]],
	["b4-seat-burner-long-lens", 4.0, "burner", [0.0, ""], ["seat", 30.0, -5.0]],
	["b5-seat-dry-long-lens", 2.5, "dry", [0.0, ""], ["seat", 30.0, -5.0]],
	["b6-seat-ramjet-long-lens", 4.0, "ramjet", [0.0, ""], ["seat", 30.0, -5.0]],
	["b7-seat-squeeze-right", 5.0, "burner", [1.2, "squeeze-right"], ["seat", 96.0, -6.0]],
	["b8-seat-squeeze-right-long-lens", 5.0, "burner", [1.2, "squeeze-right"], ["seat", 30.0, -5.0]],
	["c1-behind-burner", 4.0, "burner", [0.0, ""], [0.0, 2.2, 7.0, 0.0, 0.0, 2.5]],
	["c2-side-burner", 4.0, "burner", [0.0, ""], [13.0, 1.2, 4.0, 0.0, 0.0, 2.5]],
	["c3-above-burner", 4.0, "burner", [0.0, ""], [0.0, 16.0, 5.0, 0.0, 0.0, 2.5]],
	["c4-above-burner-hard-right", 4.0, "burner", [0.9, "hard-right"], [0.0, 16.0, 5.0, 0.0, 0.0, 2.5]],
	["c5-above-squeeze-right", 5.0, "burner", [1.2, "squeeze-right"], [0.0, 16.0, 5.0, 0.0, 0.0, 2.5]],
	["c6-side-dry", 2.5, "dry", [0.0, ""], [13.0, 1.2, 4.0, 0.0, 0.0, 2.5]],
	["c7-behind-ramjet", 4.0, "ramjet", [0.0, ""], [2.5, 2.4, 8.0, 0.0, 0.0, 2.5]],
	["c8-side-ramjet", 4.0, "ramjet", [0.0, ""], [13.0, 1.2, 4.0, 0.0, 0.0, 2.5]],
	["c9-chase-burner-hard-left", 4.0, "burner", [0.9, "hard-left"], [-1.0, 5.0, 16.0, 0.0, 0.0, 2.5]],
	["c10-side-close-burner", 4.0, "burner", [0.0, ""], [9.0, 0.6, 2.5, 3.0, 0.0, 3.0]],
	["c11-above-standing-hard-right", 0.35, "burner", [0.3, "hard-right"], [0.0, 16.0, 5.0, 0.0, 0.0, 2.5]],
	["l1-light-0.05s", 2.5, "light", [0.05, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l2-light-0.15s", 2.5, "light", [0.15, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l3-light-0.30s", 2.5, "light", [0.30, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l4-light-0.60s", 2.5, "light", [0.60, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l5-light-1.50s", 2.5, "light", [1.50, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l6-out-0.20s", 4.0, "out", [0.20, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
	["l7-out-1.50s", 4.0, "out", [1.50, ""], [4.6, 1.3, 5.0, 3.0, 0.0, 1.5]],
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
	Seat._camera_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	if "--headset" in OS.get_cmdline_user_args():
		root.scaling_3d_scale = 2.0
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
		var name := str(view[0])
		if not only.is_empty() and not only.has(name):
			continue
		_set_pose(0)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = wide
		for frame in 20:
			seat._process(STEP)
			await process_frame
		var mode := str(view[2])
		var last: Array = view[3]
		var total := int(float(view[1]) * 120.0)
		var tail := int(float(last[0]) * 120.0)
		var kind := str(last[1])
		for frame in total:
			var ending: bool = frame >= total - tail
			var lit: bool = mode == "burner" or mode == "ramjet" or (mode == "light" and ending) or (mode == "out" and not ending)
			seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": lit}
			if ending and kind.begins_with("squeeze"):      # as the flights' logs have an air-brake turn
				var side := "L" if kind.ends_with("left") else "R"
				seat.inp["thr" + side] = 0.74
				seat.inp["brk" + side] = 0.16
				seat.inp["brk" + ("R" if side == "L" else "L")] = 0.10
			elif ending and kind == "hard-left":
				seat.inp.thrL = 0.25
				seat.inp.brkL = 1.0
			elif ending and kind == "hard-right":
				seat.inp.thrR = 0.25
				seat.inp.brkR = 1.0
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		if mode == "ramjet":      # (the ramjet wants Mach 5: show its fire without the run-up)
			seat.sim.mode = "ramjet"
			for frame in 240:
				seat.craft.sync(seat.sim, seat.inp, 1.0 / 120.0)
		var craft = seat.craft
		var cam: Array = view[4]
		if str(cam[0]) == "seat":
			seat.cam.fov = float(cam[1])
			seat.cam.rotation_degrees = Vector3(float(cam[2]), 0.0, 0.0)
		else:
			# outside: against the engines' nozzles, in the engines' own frame
			var mid: Vector3 = ((craft.engines[0] as Node3D).global_position + (craft.engines[1] as Node3D).global_position) * 0.5
			var basis: Basis = (craft.engines[0] as Node3D).global_basis
			var nozzle: Vector3 = mid + basis.z * 4.3
			seat.cam.global_position = nozzle + basis.x * float(cam[0]) + Vector3.UP * float(cam[1]) + basis.z * float(cam[2])
			seat.cam.look_at(nozzle + basis.x * float(cam[3]) + Vector3.UP * float(cam[4]) + basis.z * float(cam[5]), Vector3.UP if float(cam[1]) < 10.0 else -basis.z)
			seat.cam.fov = 50.0 if float(cam[2]) < 6.0 and float(cam[1]) < 4.0 else wide
		if "--cold" in OS.get_cmdline_user_args() or name.begins_with("h"):   # the hardware alone: no gas, no fire
			for f in craft.flames:
				(f as Node3D).visible = false
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(name + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		var extra := ""
		if "jets" in craft:
			var j = craft.jets[1]
			extra = "  exit %.2f m  lit %.2f  metal %.0f K  cell %.2f m  J %.2f  jet turned %.1f deg" % [j.exit * 2.0, j.lit, j.metal, j.cell, j.j, rad_to_deg(craft.vane_angle) * craft.Jets.turning(j.lit)]
		print("EXHAUST %s  %.0f mph  mode %s  thrust %.2f %.2f  vane %.1f deg  plume %.1f m  load %.0f g%s" % [name, sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694, seat.sim.mode,
			seat.sim.eL.thrust, seat.sim.eR.thrust, rad_to_deg(craft.vane_angle), craft.plume_len[1], seat._slide_load, extra])
	seat.free()
	quit()
