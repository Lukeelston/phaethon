## The g-meter from the pilot's seat (vr/gauge_cluster.gd: the sub-dial on the centre face, and its
## figure, slip bar and peak on the status strip): stills at rest, off the line, in an air-brake turn
## as it is flown, just after one, and on full air brakes. Run windowed, as render_engine_spike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_g_meter.gd -- --mute --out=DIR [--views=a,b]
extends "res://tests/render_terminal_art.gd"

# Name; what the craft is doing when the picture is taken; and the camera: "seat" with a field of
# view (38 degrees up and down is about what a headset shows of it, pixel for pixel) and the head's
# pitch, or ["pod", eye, target] in the canopy's own frame, or ["dash", eye, target] in the cluster's.
const VIEWS := [
	["g1-seat-at-rest", "rest", "seat", 38.0, -26.0],
	["g2-seat-off-the-line", "launch", "seat", 38.0, -26.0],
	["g3-seat-left-turn", "turn", "seat", 38.0, -26.0],
	["g4-seat-after-the-turn", "after", "seat", 38.0, -26.0],
	["g5-seat-full-air-brakes", "brake", "seat", 38.0, -26.0],
	["g6-close-at-rest", "rest", ["pod", Vector3(0.0, -0.12, 0.12), Vector3(0.0, -0.36, -0.35)]],
	["g7-close-left-turn", "turn", ["pod", Vector3(0.0, -0.12, 0.12), Vector3(0.0, -0.36, -0.35)]],
	["g8-close-after-the-turn", "after", ["pod", Vector3(0.0, -0.12, 0.12), Vector3(0.0, -0.36, -0.35)]],
	["g9-dial-right-turn", "turn-right", ["dash", Vector3(0.02, 0.03, 0.34), Vector3(0.02, 0.03, 0.05)]],
	["g11-dial-at-rest", "rest", ["dash", Vector3(0.02, 0.03, 0.34), Vector3(0.02, 0.03, 0.05)]],
	["g12-dial-after-the-turn", "after", ["dash", Vector3(0.02, 0.03, 0.34), Vector3(0.02, 0.03, 0.05)]],
	["g13-strip-left-turn", "turn", ["dash", Vector3(-0.2, -0.1, 0.36), Vector3(-0.2, -0.11, 0.02)]],
	["g10-seat-wide-left-turn", "turn", "seat", 0.0, -13.0],
]


## Fly for some seconds with these levers and brakes (the burner lit with full levers).
func _fly(seconds: float, thr: Array, brk: Array) -> void:
	for frame in int(seconds * 120.0):
		seat.inp = {"thrL": thr[0], "thrR": thr[1], "brkL": brk[0], "brkR": brk[1], "repair": false, "reignite": true,
			"burner": float(thr[0]) >= 1.0 or float(thr[1]) >= 1.0}
		seat._process(STEP)
		if frame % 4 == 0:
			await process_frame


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
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	preload("res://view/livery.gd").pinned = true
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
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
		await _fly(0.1, [0.0, 0.0], [0.0, 0.0])
		seat.dashboard.g_peak = 1.0      # (each view begins with the tell-tale down)
		await _fly(0.4, [0.0, 0.0], [0.0, 0.0])
		match str(view[1]):
			"launch":
				await _fly(0.8, [1.0, 1.0], [0.0, 0.0])
			"turn", "after", "turn-right":      # an air-brake turn as the eighth flight's log has one: a grip a third in
				await _fly(4.0, [1.0, 1.0], [0.0, 0.0])
				if str(view[1]) == "turn-right":
					await _fly(1.2, [1.0, 0.74], [0.10, 0.16])
				elif str(view[1]) == "after":       # left, then right to run straight down the road again, and on for a second
					await _fly(0.8, [0.74, 1.0], [0.16, 0.10])
					await _fly(0.8, [1.0, 0.74], [0.10, 0.16])
					await _fly(1.0, [1.0, 1.0], [0.0, 0.0])
				else:
					await _fly(1.2, [0.74, 1.0], [0.16, 0.10])
			"brake":
				await _fly(6.0, [1.0, 1.0], [0.0, 0.0])
				await _fly(0.3, [0.0, 0.0], [1.0, 1.0])
		if view[2] is String:
			seat.cam.fov = float(view[3]) if float(view[3]) > 0.0 else wide
			seat.cam.rotation_degrees = Vector3(float(view[4]), 0.0, 0.0)
		else:
			var frame: Transform3D = (seat.canopy as Node3D).global_transform if str(view[2][0]) == "pod" else (seat.dashboard as Node3D).global_transform
			seat.cam.fov = 40.0
			seat.cam.global_position = frame * (view[2][1] as Vector3)
			seat.cam.look_at(frame * (view[2][2] as Vector3), frame.basis.y)
		for read in 3:      # (the strip's figures are read by the wall's clock, which a harness outruns: read them now)
			seat.dashboard.settle(0.1)
		for frame in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		var d = seat.dashboard
		print("G_SHOT %s  %.0f mph  along %.1f g  across %.1f g  whole %.1f g  needle %.2f  tell-tale %.1f g  strip \"%s\" \"%s\"%s" % [view[0], sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694,
			seat.g_along, seat.g_across, seat.g_load(), d.values.g, d.g_peak, d.labels.g.text, d.labels.g_peak.text, "" if d.labels.g.visible else " (hidden)"])
	seat.free()
	quit()
