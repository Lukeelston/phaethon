## Realism spike: the sky, the city and the air from the pilot seat on the Eridanus Network road.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_environment_spike.gd -- --mute --out=DIR [--views=a,b] [--as-flown]
## --as-flown leaves out the land brought up beside the road and the sky bridges' fins (the
## first spike flight's world), for comparisons.
## Parked views look at the sky and the towers; the "speed" views hold both levers forward for a
## few seconds first, so the exhaust, the road spray and the shock cone are in the picture.
extends "res://tests/render_terminal_art.gd"

# Name, road sample past the city's, where to look, seconds at full throttle first, and
# (optionally) the field of view for a long-lens look.
# Looking: [yaw, pitch] in degrees from the craft's nose, or "sun" with degrees [right, up] of the primary sun.
const VIEWS := [
	["e1-ahead", 98, [0.0, 2.0], 0.0],
	["e2-sunward", 98, "sun:-8,-12", 0.0],
	["e3-overhead", 98, [0.0, 58.0], 0.0],
	["e4-down-sun", 98, "sun:180,-22", 0.0],
	["e5-towers-port", 98, [58.0, 9.0], 0.0],
	["e6-towers-starboard", 98, [-64.0, 12.0], 0.0],
	["e7-landmark", 124, [0.0, 6.0], 0.0],
	["e8-downrange", 180, [0.0, 0.0], 0.0],
	["e9-speed-ahead", 180, [0.0, -4.0], 3.5],
	["e10-speed-engine", 180, [24.0, -9.0], 3.5],
	["e11-speed-aft", 180, [148.0, -6.0], 3.5],
	["e12-fast", 180, [0.0, -3.0], 9.0],
	["e13-towers-zoom", 98, [-66.0, 9.0], 0.0, 26.0],
	["e14-city-zoom", 98, [52.0, 5.0], 0.0, 22.0],
	["e15-engines-zoom", 180, [0.0, -5.5], 3.5, 16.0],
	["e16-engines-idle-zoom", 180, [0.0, -5.5], 0.0, 16.0],
	# out on the open highway (a sixth entry: "far" goes to open country, "deck" to a sky bridge; the road is built there first)
	["e17-highway", 520, [0.0, 0.0], 0.0, 0.0, "far"],
	["e18-highway-port", 520, [48.0, 3.0], 0.0, 0.0, "far"],
	["e19-highway-speed", 520, [0.0, -2.0], 4.0, 0.0, "far"],
	["e20-clouds-low", 520, [35.0, 16.0], 0.0, 0.0, "far"],
	["e21-deck", 0, [0.0, 0.0], 0.0, 0.0, "deck"],
	["e22-deck-port", 0, [50.0, 4.0], 0.0, 0.0, "deck"],
	["e23-deck-speed", 0, [0.0, -2.0], 4.0, 0.0, "deck"],
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
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	if "--as-flown" in OS.get_cmdline_user_args():
		seat.network_world.banks = false
		seat.network_world.fins = false
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr:
		push_error("This review requires the Eridanus Network road and a monoscopic viewport.")
		quit(1)
		return
	var sun: DirectionalLight3D
	for light in seat.find_children("*", "DirectionalLight3D", true, false):
		if (light as DirectionalLight3D).shadow_enabled:
			sun = light
	var wide: float = seat.cam.fov
	_set_pose(98)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	for view in VIEWS:
		if not only.is_empty() and not only.has(view[0]):
			continue
		_set_pose(int(view[1]))
		if view.size() > 5:
			var place := _deck() if str(view[5]) == "deck" else _open_country()
			if place.is_empty():
				push_error("Nowhere found for " + str(view[0]))
				continue
			seat.sim.respawn_on(int(place[0]), int(place[1]), 1)
			seat._ride.clear()
			for i in 1600:   # build the road and the land round the new place
				seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
				seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
				if i % 40 == 0:
					await process_frame
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = float(view[4]) if view.size() > 4 and float(view[4]) > 0.0 else wide
		seat.cruise = 0.0
		for frame in 40:
			seat._process(STEP)
			await process_frame
		# (cruise only stops the view reading controllers; the levers themselves are the input record)
		var push := 1.0 if float(view[3]) > 0.0 else 0.0
		seat.inp = {"thrL": push, "thrR": push, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": push > 0.0}
		for frame in int(float(view[3]) * 120.0):
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		var look = view[2]
		if look is String:
			var turn: PackedStringArray = str(look).trim_prefix("sun:").split(",")
			var to_sun: Vector3 = sun.global_basis.z if sun else Vector3(0.68, 0.5, 0.53)
			var aim := Basis.looking_at(-to_sun, Vector3.UP) * Basis.from_euler(Vector3(deg_to_rad(float(turn[1])), deg_to_rad(float(turn[0])), 0.0))
			seat._process(STEP)
			seat.cam.global_basis = Basis.looking_at(aim * Vector3(0, 0, 1), Vector3.UP)
		else:
			seat.cam.rotation_degrees = Vector3(float(look[1]), float(look[0]), 0.0)
		for frame in 3:
			seat._process(STEP)
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(str(view[0]) + ".png")
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			quit(1)
			return
		var p = seat.sim.pod
		print("ENVIRONMENT_SHOT %s  %.0f mph  mode %s" % [view[0], sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694, seat.sim.mode])
	print("ENVIRONMENT chunks with a bank: %d of %d built; banks took %.2f ms a chunk that has one" % [seat.network_world.bank_chunks, seat.network_world.built,
		seat.network_world.bank_us / 1000.0 / maxf(1.0, seat.network_world.bank_chunks)])
	seat.free()
	quit()


## Open country: [road, sample] on a plain ground-level road with no town within 2.4 km along it
## and no other road in the grid squares round it (or [] with none).
func _open_country() -> Array:
	var sim = seat.sim
	for r in sim.roads.size():
		var R = sim.roads[r]
		if R.role != "" or R.N < 600:
			continue
		for i in range(300, R.N - 300, 40):
			var clear: bool = sim.net_height(r, float(i)) < 0.5 and sim.net_height(r, float(i + 200)) < 0.5
			for k in range(-100, 240, 20):
				clear = clear and R.mode[i + k] != 0
			for ahead in [0, 80, 160]:   # along the two miles the picture looks down
				var cx := int(floor(R.px[i + ahead] / CraftSim.NET_CELL))
				var cy := int(floor(R.py[i + ahead] / CraftSim.NET_CELL))
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						for run in sim._net_cells.get((cx + dx) * 4096 + cy + dy, []):
							clear = clear and int(run[0]) == r
			if clear:
				print("ENVIRONMENT open country: road %d sample %d" % [r, i])
				return [r, i]
	return []


## A sky bridge to look along: [road, sample] in the middle of the longest level stretch of plain
## road at least 150 m up (or [] with none).
func _deck() -> Array:
	var best := []
	var longest := 0
	for r in seat.sim.roads.size():
		var R = seat.sim.roads[r]
		if R.role != "" or not seat.sim._net_h.has(r):
			continue
		var start := -1
		for i in range(0, R.N, 4):
			var high: bool = seat.sim.net_height(r, float(i)) >= 150.0 and R.mode[i] != 0
			if high and start < 0:
				start = i
			if (not high or i + 4 >= R.N) and start >= 0:
				if i - start > longest:
					longest = i - start
					best = [r, start + (i - start) / 3]
				start = -1
	if not best.is_empty():
		print("ENVIRONMENT sky bridge: road %d sample %d, %d samples long, %.0f m up" % [best[0], best[1], longest, seat.sim.net_height(int(best[0]), float(best[1]))])
	return best
