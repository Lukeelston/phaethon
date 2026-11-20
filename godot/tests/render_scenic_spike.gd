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
	["s1-coast-arrival", "SCoast", 2010, 0.0, [0.0, 0.0], Vector3.ZERO],
	["s2-coast-bay", "SCoast", 2650, 40.0, [0.0, -1.0], Vector3.ZERO],
	["s3-coast-bay-seaward", "SCoast", 2700, 55.0, [62.0, -4.0], Vector3.ZERO],
	["s4-coast-climb", "SCoast", 2980, 0.0, [0.0, 1.0], Vector3.ZERO],
	["s5-coast-headland", "SCoast", 3200, 40.0, [0.0, -2.0], Vector3.ZERO],
	["s6-coast-headland-seaward", "SCoast", 4170, 55.0, [58.0, -6.0], Vector3.ZERO],
	["s7-coast-mountain", "SCoast", 4170, -30.0, [-55.0, 12.0], Vector3.ZERO],
	["s8-coast-descent", "SCoast", 4330, 30.0, [0.0, -3.0], Vector3.ZERO],
	["s9-coast-from-above", "SCoast", 3100, 0.0, [0.0, -24.0], Vector3(0.0, 420.0, 300.0)],
	["d1-drop-climb", "SDrop", 2280, 30.0, [0.0, 2.0], Vector3.ZERO],
	["d2-drop-climb-valley", "SDrop", 2700, 50.0, [60.0, -8.0], Vector3.ZERO],
	["d3-drop-rim", "SDrop", 3818, 40.0, [0.0, -1.0], Vector3.ZERO],
	["d4-drop-rim-valley", "SDrop", 3900, 55.0, [62.0, -12.0], Vector3.ZERO],
	["d5-drop-brink", "SDrop", 4380, 0.0, [0.0, -3.0], Vector3.ZERO],
	["d6-drop-over", "SDrop", 4470, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["d7-drop-dive", "SDrop", 4600, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["d8-drop-dive-side", "SDrop", 4600, 50.0, [70.0, -14.0], Vector3.ZERO, 900.0],
	["d12-drop-pullout", "SDrop", 4820, 0.0, [0.0, 0.0], Vector3.ZERO, 900.0],
	["d13-drop-dive-from-behind", "SDrop", 4560, 0.0, [0.0, -14.0], Vector3(0.0, 160.0, 420.0)],
	["d9-drop-valley", "SDrop", 5200, 0.0, [0.0, 2.0], Vector3.ZERO],
	["d10-drop-from-above", "SDrop", 4330, 0.0, [0.0, -22.0], Vector3(0.0, 500.0, 500.0)],
	["d11-drop-from-the-side", "SDrop", 4640, 0.0, [-90.0, -8.0], Vector3(2600.0, 300.0, 0.0)],
	# their boards on the highways (an eighth entry: the way the craft faces along the road, -1 for down it)
	["g1-coast-board-two-miles", "E1", 1200, 60.0, [0.0, 4.0], Vector3.ZERO, 0.0, -1],
	["g2-coast-board-at-the-exit", "E1", 1085, 60.0, [0.0, 5.0], Vector3.ZERO, 0.0, -1],
	["g3-drop-board-two-miles", "E3", 21630, -60.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["g4-drop-board-at-the-exit", "E3", 21760, -60.0, [0.0, 5.0], Vector3.ZERO, 0.0, 1],
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
		print("SCENIC_SHOT %s: %s sample %d, %.0f m up; land %.2f ms a slice at most, a chunk %.1f ms" % [view[0], view[1], int(view[2]),
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
