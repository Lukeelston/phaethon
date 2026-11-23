## Mount Hyperion's leaps from the pilot's seat (after render_hyperion.gd): the approach, the lane, the lip, the
## air, the landing field. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_hyperion_leaps.gd -- --mute --out=DIR [--views=a,b] [--time=night] [--weather=clear] [--tag=night]
## Each view parks the craft on a road's sample (or holds it in the air off a lane's lip), lets the roads, their
## land and the terrain build there, and looks where it is told.
extends "res://tests/render_terminal_art.gd"

# Name, road's name, sample (negative: from the road's end), m left of the centreline, where to look ([yaw (left +),
# pitch] in degrees from the nose), the head's offset from the seated eye (m), the way the craft faces (-1: down the
# samples), and for a view in the air: [m past the road's end along its line, m over the plain, speed mph, climb m/s].
const VIEWS := [
	["c01-summit-the-leap-board", "SHyperion", 5150, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["c02-brink-the-rails-down-the-wall", "SHyperion", 5228, -280.0, [0.0, 0.0], Vector3.ZERO, 1, []],
	["c03-run-out-the-lane-ahead", "SHyperion", 7250, -280.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["c04-foot-the-lane-leaves-the-deck", "SHyperion", 7600, -280.0, [0.0, 0.0], Vector3(0.0, 40.0, 0.0), 1, []],
	["c05-plain-way-beside-the-lane", "SHyperion", 8300, 0.0, [0.0, 0.0], Vector3.ZERO, 1, []],
	["c06-in-the-lane", "J21", 280, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["c07-the-climb", "J21", -260, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["c08-the-lip", "J21", -45, 0.0, [0.0, 0.0], Vector3.ZERO, 1, []],
	["c09-the-lip-from-outside", "J21", -30, 0.0, [62.0, -8.0], Vector3(420.0, 90.0, 260.0), 1, []],
	["c10-in-the-air-2-km-out", "J21", -1, 0.0, [0.0, -4.0], Vector3.ZERO, 1, [2000.0, 222.0, 10000.0, 34.0]],
	["c11-in-the-air-25-km-out", "J21", -1, 0.0, [0.0, -3.0], Vector3.ZERO, 1, [25000.0, 280.0, 10400.0, 2.0]],
	["c12-on-final-48-km-out", "J21", -1, 0.0, [0.0, -2.0], Vector3.ZERO, 1, [48000.0, 95.0, 10700.0, -62.0]],
	["c13-the-field-from-over-it", "K21", 1200, 0.0, [0.0, -24.0], Vector3(0.0, 900.0, 900.0), 1, []],
	["c14-landed", "K21", 2150, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["c15-the-fields-end", "K21", -420, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["r01-summit-the-leap-board", "SHyperion", 5080, 0.0, [0.0, 1.0], Vector3.ZERO, -1, []],
	["r02-ramp-foot-the-rails", "SHyperion", 1900, -280.0, [0.0, 0.0], Vector3.ZERO, -1, []],
	["r03-approach-the-lane-ahead", "SHyperion", 1100, -280.0, [0.0, 1.0], Vector3.ZERO, -1, []],
	["r04-climbing-past-the-lane", "SHyperion", 640, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["r05-in-the-lane", "J22", 290, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["r06-the-lip-e2-beyond", "J22", -45, 0.0, [0.0, 0.0], Vector3.ZERO, 1, []],
	["r07-the-lip-and-the-bridge-from-outside", "J22", -12, 0.0, [58.0, -10.0], Vector3(520.0, 130.0, 300.0), 1, []],
	["r08-in-the-air-over-e2", "J22", -1, 0.0, [0.0, -8.0], Vector3.ZERO, 1, [450.0, 204.0, 9600.0, 33.0]],
	["r09-in-the-air-25-km-out", "J22", -1, 0.0, [0.0, -3.0], Vector3.ZERO, 1, [25000.0, 270.0, 9900.0, 0.0]],
	["r10-on-final-44-km-out", "J22", -1, 0.0, [0.0, -2.0], Vector3.ZERO, 1, [44000.0, 100.0, 10300.0, -60.0]],
	["r11-landed", "K22", 2000, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["r12-the-bend-board", "K22", 3350, 0.0, [0.0, 1.0], Vector3.ZERO, 1, []],
	["r13-e2-under-the-bridge", "E2", 4700, 0.0, [0.0, 4.0], Vector3.ZERO, 1, []],
]

var _way := 1         # the way the craft faces along its road
var _air: Array = []  # a view in the air: [m past the road's end, m up, mph, climb m/s]


func _run() -> void:
	var only := PackedStringArray()
	var tag := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--tag="):
			tag = "-" + arg.trim_prefix("--tag=")
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
		var at := int(view[2])
		if at < 0:
			at = int(seat.sim.roads[road].N) + at
		city = {"road": road, "i": at}
		_way = int(view[6])
		_air = view[7]
		_park(float(view[3]))
		for i in 6000:
			world.sync(seat.sim.pod.x, seat.sim.pod.y)
			seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
			if i % 40 == 0:
				await process_frame
			var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
			if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
				break
		seat.cam.position = view[5]
		for frame in 60:
			_park(float(view[3]))
			seat._process(STEP)
			seat.cam.rotation_degrees = Vector3(view[4][1], view[4][0], 0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + tag + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var pod = seat.sim.pod
		print("LEAP_SHOT %s: %s sample %d%s; the pod %.0f m up; the dash says \"%s\"; %d draws and %d triangles; a chunk %.1f ms at most; %d road chunks" % [
			view[0], view[1], at, "" if _air.is_empty() else " and %.1f km on, in the air" % (float(_air[0]) / 1000.0), pod.z, seat._progress_text().replace("\n", " / "),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			world.build_ms_max, world.chunks.size()])
	seat.free()
	quit()


func _park(left: float) -> void:
	var sim = seat.sim
	sim.respawn_on(int(city.road), int(city.i), _way)
	seat._ride.clear()
	var R = sim.roads[int(city.road)]
	var i := int(city.i)
	for body in sim.bodies:
		body.x += R.nx[i] * left
		body.y += R.ny[i] * left
	if _air.is_empty():
		return
	# in the air off the road's end: so far along its line, so high, going so fast and climbing so
	var v: float = float(_air[2]) / 2.236936
	for body in sim.bodies:
		body.x += R.tx[i] * float(_air[0])
		body.y += R.ty[i] * float(_air[0])
		body.z = float(_air[1]) + float(sim.P.rideH)
		body.vx = R.tx[i] * v
		body.vy = R.ty[i] * v
		body.vz = float(_air[3])
		body.off_road = true
		body.lock = false
