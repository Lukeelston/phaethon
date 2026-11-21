## Codex's backroads and stunt roads from the pilot seat (a copy of render_scenic_spike.gd with its own views).
## Realism spike: the scenic roads from the pilot seat (the coast road down the west edge, the drop
## down the east). Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_scenic_spike.gd -- --mute --out=DIR [--views=a,b] [--open]
## Each view parks the craft on a road's sample (a few metres to one side of its centreline), lets
## the road, its land and the terrain build there, and looks where it is told.
extends "res://tests/render_terminal_art.gd"

# Name, road's name, sample, m left of the centreline, [yaw (left +), pitch] in degrees from the
# nose, the head's offset from the seated eye (m: a long way up for a look at the lie of the land),
# and optionally a speed along the road (m/s): the Network's cockpit pitches with its own climb.
const VIEWS := [
	["w1-wash-sand", "SWash", 2000, 0.0, [0.0, -1.0], Vector3.ZERO],
	["w2-wash-sand-low-sun", "SWash", 3300, 30.0, [0.0, -2.0], Vector3.ZERO],
	["w3-wash-from-above", "SWash", 2600, 0.0, [0.0, -24.0], Vector3(0.0, 300.0, 260.0)],
	["f1-frost-climb", "SFrost", 2500, 0.0, [0.0, 1.0], Vector3.ZERO],
	["f2-frost-saddle", "SFrost", 3141, 30.0, [0.0, -2.0], Vector3.ZERO],
	["f3-frost-from-above", "SFrost", 3141, 0.0, [0.0, -22.0], Vector3(0.0, 500.0, 500.0)],
	["r1-reed-causeway", "SReed", 1500, 0.0, [0.0, -1.0], Vector3.ZERO],
	["r2-reed-over-the-rail", "SReed", 2200, 60.0, [62.0, -6.0], Vector3.ZERO],
	["r3-reed-from-above", "SReed", 2000, 0.0, [0.0, -24.0], Vector3(0.0, 260.0, 240.0)],
	["t1-red-table-gravel", "SRed", 2200, 0.0, [0.0, -1.0], Vector3.ZERO],
	["t2-red-table-mesa", "SRed", 4200, 30.0, [0.0, -2.0], Vector3.ZERO],
	["t3-red-table-from-above", "SRed", 3000, 0.0, [0.0, -24.0], Vector3(0.0, 300.0, 260.0)],
	["n1-needle-approach", "SNeedle", 330, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["n2-needle-quarter-roll", "SNeedle", 476, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["n3-needle-inverted", "SNeedle", 581, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["n4-needle-from-outside", "SNeedle", 581, 0.0, [-90.0, -6.0], Vector3(900.0, 120.0, 0.0)],
	["h1-hammer-crest", "SHammer", 450, 0.0, [0.0, -2.0], Vector3.ZERO, 900.0],
	["h2-hammer-drop", "SHammer", 590, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["h3-hammer-from-the-side", "SHammer", 600, 0.0, [-90.0, -8.0], Vector3(2600.0, 300.0, 0.0)],
	["j1-mesa-launch-ramp", "J20", 150, 0.0, [0.0, 2.0], Vector3.ZERO, 1400.0],
	["j2-mesa-landing-deck", "K20", 420, 0.0, [0.0, -2.0], Vector3.ZERO],
	["j3-mesa-gap-from-the-side", "J20", 330, 0.0, [-90.0, 6.0], Vector3(5200.0, 900.0, -2600.0)],
	# their boards on the highways (an eighth entry: the way the craft faces along the road, -1 for down it)
	["g1-wash-board-on-e3", "E3", 4380, -60.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["g2-needle-board-on-e2", "E2", 6090, -60.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["g3-hammer-board-on-n2", "N2", 13510, -60.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	# Helios (--time= and --weather= as the engine harness has them): from the highway, up its road, over the clouds, on top
	["m1-helios-from-e3-abeam", "E3", 15650, 0.0, [80.0, 7.0], Vector3.ZERO],
	["m2-helios-from-its-turning", "E3", 13200, 0.0, [28.0, 5.0], Vector3.ZERO],
	["m3-helios-the-foot", "SHelios", 1560, 0.0, [0.0, 4.0], Vector3.ZERO],
	["m4-helios-lower-slopes", "SHelios", 2600, 0.0, [0.0, 2.0], Vector3.ZERO],
	["m5-helios-over-the-edge", "SHelios", 4300, 40.0, [72.0, -9.0], Vector3.ZERO],
	["m6-helios-over-the-clouds", "SHelios", 6400, 40.0, [72.0, -9.0], Vector3.ZERO],
	["m7-helios-the-summit", "SHelios", 8220, 0.0, [0.0, -5.0], Vector3.ZERO],
	["m8-helios-summit-all-round", "SHelios", 8220, 0.0, [120.0, -12.0], Vector3(0.0, 40.0, 0.0)],
	["m9-helios-the-bench-from-above", "SHelios", 5200, 0.0, [0.0, -32.0], Vector3(0.0, 900.0, 1300.0)],
	["m10-helios-coming-down", "SHelios", 10400, 0.0, [0.0, -4.0], Vector3.ZERO],
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
	if "--open" in OS.get_cmdline_user_args():
		preload("res://view/canopy.gd").roofed = false
	var outlook := preload("res://view/outlook.gd")     # (the saved hour and weather stay out of the pictures: a fair afternoon unless asked)
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
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var world = seat.network_world
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		var road := -1
		for r in seat.sim.roads.size():
			if seat.sim.roads[r].name == view[1]:
				road = r
		if road < 0:
			push_error("No road called %s." % view[1])
			quit(1)
			return
		city = {"road": road, "i": int(view[2])}
		_way = int(view[7]) if view.size() > 7 else 1
		_park(float(view[3]))
		for i in 6000:
			world.sync(seat.sim.pod.x, seat.sim.pod.y)
			seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
			if i % 40 == 0:
				await process_frame
			var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
			if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
				break
		_park(float(view[3]))
		seat.cam.position = view[5]
		seat.cam.rotation_degrees = Vector3(view[4][1], view[4][0], 0.0)
		var speed: float = view[6] if view.size() > 6 else 0.0
		for frame in 60:
			if speed > 0.0:
				_park(float(view[3]))
				var R = seat.sim.roads[road]
				for body in seat.sim.bodies:
					body.vx = R.tx[int(view[2])] * speed
					body.vy = R.ty[int(view[2])] * speed
			seat._process(STEP)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		print("ROUTE_SHOT %s: %s sample %d, %.0f m up; land %.2f ms a slice at most, a chunk %.1f ms" % [view[0], view[1], int(view[2]),
			seat.sim.net_height(road, float(view[2])), seat.landscape.max_slice_ms, world.build_ms_max])
	seat.free()
	quit()


var _way := 1   # the way the craft faces along its road


func _park(left: float) -> void:
	seat.sim.respawn_on(int(city.road), int(city.i), _way)
	seat._ride.clear()
	var R = seat.sim.roads[int(city.road)]
	var i := int(city.i)
	for body in seat.sim.bodies:
		body.x += R.nx[i] * left
		body.y += R.ny[i] * left
