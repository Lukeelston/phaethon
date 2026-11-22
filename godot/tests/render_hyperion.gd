## Mount Hyperion from the pilot's seat and from outside (after render_codex_routes.gd). Run windowed, as
## render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_hyperion.gd -- --mute --out=DIR [--views=a,b] [--time=night] [--weather=clear] [--tag=night]
## Each view parks the craft on a road's sample, lets the road, its land and the terrain build there, and
## looks where it is told. Each prints what the frame cost to draw, with the mountain and without it.
extends "res://tests/render_terminal_art.gd"

const Hyperion := preload("res://view/hyperion.gd")

# Name, road's name, sample, m left of the centreline, where to look ([yaw (left +), pitch] in degrees
# from the nose, or a height in m on the mountain's middle to look straight at), the head's offset from
# the seated eye (m), a speed along the road (m/s), the way the craft faces (-1: down the samples).
const VIEWS := [
	["a1-from-e2-abeam", "E2", 6460, 0.0, 26000.0, Vector3.ZERO, 0.0, 1],
	["a2-from-e2-at-its-exit", "E2", 4300, 0.0, 24000.0, Vector3.ZERO, 0.0, 1],
	["a3-from-eridanus-132-km-off", "E2", 11040, 0.0, 22000.0, Vector3.ZERO, 0.0, 1],
	["a4-from-e3-122-km-off", "E3", 6617, 0.0, 22000.0, Vector3.ZERO, 0.0, 1],
	["a5-from-n3-317-km-off", "N3", 15625, 0.0, 20000.0, Vector3.ZERO, 0.0, 1],
	["a6-from-n1-75-km-off", "N1", 14700, 0.0, 24000.0, Vector3.ZERO, 0.0, 1],
	["b1-the-approach", "SHyperion", 800, 0.0, [0.0, 14.0], Vector3.ZERO, 0.0, 1],
	["b2-the-foot", "SHyperion", 1790, 0.0, [0.0, 16.0], Vector3.ZERO, 0.0, 1],
	["b3-the-foot-board", "SHyperion", 1700, 0.0, [0.0, 6.0], Vector3.ZERO, 0.0, 1],
	["c1-ramp-15-deg", "SHyperion", 2365, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["c2-ramp-30-deg", "SHyperion", 2840, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["c3-ramp-45-deg", "SHyperion", 3330, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["c4-ramp-45-deg-out-of-the-side", "SHyperion", 3330, 0.0, [-80.0, -6.0], Vector3.ZERO, 0.0, 1],
	["c5-ramp-60-deg", "SHyperion", 3820, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["c6-ramp-75-deg", "SHyperion", 4310, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["c7-ramp-75-deg-out-of-the-side", "SHyperion", 4310, 0.0, [-80.0, -6.0], Vector3.ZERO, 0.0, 1],
	["c8-ramp-75-deg-from-outside", "SHyperion", 4310, 0.0, [-70.0, -8.0], Vector3(260.0, 80.0, -80.0), 0.0, 1],
	["d1-braking-section-board", "SHyperion", 4735, 0.0, [0.0, 4.0], Vector3.ZERO, 0.0, 1],
	["d2-on-the-wall", "SHyperion", 4790, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["d3-on-the-wall-out-of-the-side", "SHyperion", 4790, 0.0, [-85.0, 0.0], Vector3.ZERO, 0.0, 1],
	["d4-the-crest", "SHyperion", 4930, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["d5-onto-the-summit", "SHyperion", 5005, 0.0, [0.0, 2.0], Vector3.ZERO, 0.0, 1],
	["e1-summit-stop-line", "SHyperion", 5200, 0.0, [0.0, -3.0], Vector3.ZERO, 0.0, 1],
	["e2-summit-looking-left", "SHyperion", 5200, 0.0, [88.0, -4.0], Vector3.ZERO, 0.0, 1],
	["e3-summit-looking-right", "SHyperion", 5200, 0.0, [-88.0, -4.0], Vector3.ZERO, 0.0, 1],
	["e4-summit-looking-back", "SHyperion", 5116, 0.0, [0.0, -6.0], Vector3.ZERO, 0.0, -1],
	["e5-summit-straight-up", "SHyperion", 5200, 0.0, [0.0, 70.0], Vector3.ZERO, 0.0, 1],
	["e6-summit-from-above", "SHyperion", 5116, 0.0, [0.0, -22.0], Vector3(0.0, 700.0, 1500.0), 0.0, 1],
	["e7-summit-over-the-side-down", "SHyperion", 5116, -330.0, [-88.0, -34.0], Vector3(0.0, 30.0, 0.0), 0.0, 1],
	["e8-summit-edge-looking-down-the-ramp", "SHyperion", 5020, 0.0, [0.0, -30.0], Vector3(0.0, 60.0, 0.0), 0.0, -1],
	["e9-the-mountain-from-20-km-over-its-summit", "SHyperion", 5116, 0.0, [0.0, -50.0], Vector3(0.0, 20000.0, 26000.0), 0.0, 1],
	["f1-the-lip-ahead", "SHyperion", 5210, 0.0, [0.0, -2.0], Vector3.ZERO, 0.0, 1],
	["f2-at-the-brink", "SHyperion", 5221, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["f2b-at-the-brink-out-of-the-left", "SHyperion", 5221, 0.0, [80.0, 0.0], Vector3.ZERO, 0.0, 1],
	["f2c-half-over", "SHyperion", 5226, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["f3-over-the-lip", "SHyperion", 5236, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["f4-over-the-lip-from-above", "SHyperion", 5230, 0.0, [0.0, -40.0], Vector3(0.0, 400.0, 500.0), 0.0, 1],
	["g1-the-drop", "SHyperion", 5700, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, 1],
	["g2-the-drop-out-of-the-side", "SHyperion", 5700, 0.0, [-85.0, 0.0], Vector3.ZERO, 0.0, 1],
	["g3-the-drop-looking-up", "SHyperion", 5700, 0.0, [0.0, 0.0], Vector3.ZERO, 0.0, -1],
	["g3b-the-drop-from-beside-it", "SHyperion", 5700, 0.0, [90.0, 0.0], Vector3(300.0, 60.0, 0.0), 0.0, 1],
	["g3c-the-drop-from-3-km-off-the-wall", "SHyperion", 5700, 0.0, [0.0, -89.0], Vector3(0.0, 3000.0, 0.0), 0.0, 1],
	["g3d-the-climb-from-beside-it", "SHyperion", 4790, 0.0, [90.0, 0.0], Vector3(300.0, 60.0, 0.0), 0.0, 1],
	["g4-the-run-out", "SHyperion", 7000, 0.0, [0.0, 2.0], Vector3.ZERO, 0.0, 1],
	["g5-the-cliff-from-the-far-straight", "SHyperion", 8600, 0.0, [0.0, 30.0], Vector3.ZERO, 0.0, -1],
	["h1-whole-from-the-south-east", "E2", 8000, 0.0, 20000.0, Vector3(0.0, 9000.0, 0.0), 0.0, 1],
]


func _run() -> void:
	var only := PackedStringArray()
	var tag := ""
	var no_roof := false
	var hide := PackedStringArray()      # --hide=clouds,ground,tiles,mesh,roads: to see what a thing in a picture is
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hide="):
			hide = arg.trim_prefix("--hide=").split(",")
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--tag="):
			tag = "-" + arg.trim_prefix("--tag=")
		if arg == "--open":
			no_roof = true
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	if no_roof:
		preload("res://view/canopy.gd").roofed = false
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
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var world = seat.network_world
	if not Hyperion.ready or seat.landscape == null or seat.landscape.hyperion == null:
		push_error("No Mount Hyperion in this world.")
		quit(1)
		return
	if hide.has("clouds"):
		seat.landscape.clouds.visible = false
	if hide.has("ground"):
		seat.ground.visible = false
	if hide.has("tiles"):
		seat.landscape._tile_root.visible = false
	if hide.has("roads"):
		world.far_roads.visible = false
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
		var speed: float = view[6] if view.size() > 6 else 0.0
		var cost := []
		for pass_i in 2:      # (with the mountain, then without it: what it costs to draw)
			seat.landscape.hyperion.visible = pass_i == 0
			seat.landscape.hyperion_summit.visible = pass_i == 0
			for frame in (60 if pass_i == 0 else 4):
				if speed > 0.0:
					_park(float(view[3]))
					var R = seat.sim.roads[road]
					for body in seat.sim.bodies:
						body.vx = R.tx[int(view[2])] * speed
						body.vy = R.ty[int(view[2])] * speed
				seat._process(STEP)
				if view[4] is Array:
					seat.cam.rotation_degrees = Vector3(view[4][1], view[4][0], 0.0)
				else:      # straight at the mountain's middle, so high up it
					var there: Vector3 = seat.landscape.hyperion.global_position + Vector3(0.0, float(view[4]), 0.0)
					seat.cam.look_at(there, Vector3.UP)
				await process_frame
			await RenderingServer.frame_post_draw
			cost.append([RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			if pass_i == 0:
				var path := out_dir.path_join(str(view[0]) + tag + ".png")
				if root.get_texture().get_image().save_png(path) != OK:
					push_error("Couldn't save " + path)
					quit(1)
					return
		seat.landscape.hyperion.visible = true
		seat.landscape.hyperion_summit.visible = true
		var pod = seat.sim.pod
		print("HYPERION_SHOT %s: %s sample %d, %.0f m up, %.0f km from the summit; pitch %.1f deg; %d draws and %d triangles (%d and %d without the mountain's mesh); land %.2f ms a slice at most, a chunk %.1f ms; %d road chunks, %d tiles" % [
			view[0], view[1], int(view[2]), seat.sim.net_height(road, float(view[2])), Vector2(pod.x, pod.y).distance_to(Hyperion.centre) / 1000.0,
			rad_to_deg(seat.sim.deck_pitch(pod)), cost[0][0], cost[0][1], cost[1][0], cost[1][1], seat.landscape.max_slice_ms, world.build_ms_max, world.chunks.size(), seat.landscape.tiles.size()])
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
