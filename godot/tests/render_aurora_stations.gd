## The Aurora line's takeoff and landing areas, for looking at (view/aurora_stations.gd): from the
## seat coming to a lock by road and stopped on its pad through the lock's cycle, coming to the far
## lock from inside the tube, and each pad from above. Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_aurora_stations.gd -- --mute --out=DIR [--views=a,b] [--time=night]
extends "res://tests/render_terminal_art.gd"

const Sim := preload("res://sim/craft_sim.gd")
const Stations := preload("res://view/aurora_stations.gd")
const BAR := Stations.BAR
# Name, the lock (0 southwest, 1 northeast), what the craft is doing, where the head is turned
# (degrees: up, left), and for a view that is not from the seat a camera in the lock's own frame
# (metres left of the road's middle, over the keel, inside the seal): [eye, what it looks at].
# "road:D": stopped D metres short of the bar, heading in. "cycle:T:D": stopped on the pad D metres
# short of the bar heading in, T seconds after it stopped. "coming:D:MPH": D metres short of the
# bar, coming out of the tube at MPH. "landed:D": stopped D metres short of the bar having come through.
const VIEWS := [
	["a1-by-road-900-m-from-the-bar", 0, "road:900", Vector3(7, 0, 0)],
	["a2-the-gate-250-m-ahead", 0, "road:250", Vector3(9, 0, 0)],
	["a3-stopped-latching", 0, "cycle:0.8:30", Vector3(15, 0, 0)],
	["a4-sealing", 0, "cycle:2.3:30", Vector3(15, 0, 0)],
	["a5-equalising", 0, "cycle:4.4:30", Vector3(21, 0, 0)],
	["a6-opening", 0, "cycle:6.3:30", Vector3(15, 0, 0)],
	["a7-clear", 0, "cycle:8.5:30", Vector3(15, 0, 0)],
	["a8-the-pad-from-above-equalising", 0, "cycle:4.4:30", Vector3.ZERO, [Vector3(-130, 150, -BAR - 520), Vector3(0, 40, -BAR + 150)]],
	["b1-10-km-out-at-10000-mph", 1, "coming:10700:10000", Vector3(5, 0, 0)],
	["b2-5-km-out-at-4000-mph", 1, "coming:5700:4000", Vector3(5, 0, 0)],
	["b3-5-km-out-too-fast-at-6000-mph", 1, "coming:5700:6000", Vector3(5, 0, 0)],
	["b4-2-km-out-at-1300-mph", 1, "coming:2600:1300", Vector3(5, 0, 0)],
	["b5-the-last-kilometre", 1, "coming:1300:600", Vector3(4, 0, 0)],
	["b6-out-of-the-seal", 1, "coming:330:150", Vector3(8, 0, 0)],
	["b7-landed", 1, "landed:60", Vector3(15, 0, 0)],
	["b8-landed-from-beside-the-lock", 1, "landed:60", Vector3.ZERO, [Vector3(-330, 250, -40), Vector3(0, 30, -BAR - 60)]],
	["c1-northeast-lock-by-road", 1, "road:250", Vector3(9, 0, 0)],
	["c2-northeast-lock-equalising", 1, "cycle:4.4:30", Vector3(21, 0, 0)],
	["d1-southwest-lock-5-km-out-at-4000-mph", 0, "coming:5700:4000", Vector3(5, 0, 0)],
	["d2-southwest-lock-landed", 0, "landed:60", Vector3(15, 0, 0)],
	["e1-30-km-out-at-15000-mph-in-overdrive", 1, "coming:30700:15000", Vector3(5, 0, 0)],   # (the line doubles a craft's speed: amber from 38 km at this speed)
]


func _stream() -> void:
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 60 == 0:
			await process_frame
		var W = seat.network_world
		if i > 300 and W.wanted == 0 and W._job.is_empty() and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break


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
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat._nose_loaded = true
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var sim = seat.sim
	var line = seat.network_world.pressure_line if seat.network_world != null else null
	if line == null or line.get("stations") == null or root.use_xr:
		push_error("This needs the Network's Aurora line with its stations, and a monoscopic viewport.")
		quit(1)
		return
	var st = line.stations
	st.set_process(false)          # (stepped here, so a view is the same view every time)
	var above := Camera3D.new()    # for the views that are not from the seat
	above.fov = 62.0
	above.near = 1.0
	above.far = 60000.0
	root.add_child(above)
	var r := int(Sim.NET_PRESSURE[0])
	var R = sim.roads[r]
	var ends := [int(Sim.NET_PRESSURE[1]), int(Sim.NET_PRESSURE[2])]
	var step: float = R.len[ends[0]]
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		var k: int = view[1]
		var what := String(view[2]).split(":")
		var into := 1 if k == 0 else -1                  # the way along the road that goes into the tube at this lock
		var inside := -BAR                                # metres inside the seal
		var way := into
		var mph := 0.0
		match what[0]:
			"road":
				inside = -BAR - float(what[1])
			"cycle":
				inside = -BAR - float(what[2])
			"coming":
				inside = float(what[1]) - BAR
				way = -into
				mph = float(what[2])
			"landed":
				inside = float(what[1]) - BAR
				way = -into
		var sample: int = int(ends[k]) + into * roundi(inside / step)
		sim.respawn_on(r, sample, way)
		seat._ride.clear()
		st.reset()
		st.step(0.05)
		await _stream()
		for b in sim.bodies:
			b.vx = R.tx[sample] * way * mph * 0.44704
			b.vy = R.ty[sample] * way * mph * 0.44704
		if what[0] == "landed":
			st.arrival = {"lock": k, "from": 1 - k, "seconds": 171.6, "top": 9987.0, "at": float(sim.time)}
		var seconds := float(what[1]) if what[0] == "cycle" else 0.3
		for n in roundi(seconds / 0.05):
			st.step(0.05)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation_degrees = view[3]
		for frame in 6:
			seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
			seat._process(STEP)
			st.step(STEP)
			if view.size() > 4:
				var frame_of: Transform3D = (st.locks[k].node as Node3D).global_transform
				above.look_at_from_position(frame_of * (view[4][0] as Vector3), frame_of * (view[4][1] as Vector3), Vector3.UP)
				above.make_current()
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		if view.size() > 4:
			seat.cam.make_current()
		var lock: Dictionary = st.locks[k]
		print("AURORA_SHOT %s: lock %d state %d at %.1f s, braking %d, board \"%s\", beyond the pad \"%s\", craft %.0f m inside the seal at %.0f mph" % [view[0], k, lock.state, lock.t, st.braking,
			String(lock.said).replace("\n", " / "), String(lock.told).replace("\n", " / "), st.craft_at(k)[0], float(st.craft_at(k)[3]) * 2.23694])
	seat.free()
	quit()
