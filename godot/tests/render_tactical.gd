## The tactical display (view/tactical_display.gd), for looking at and for weighing.
##   --mode=shots   stills from the pilot's seat, each with it off and on: a highway's hardest bend at 3,000
##                  and at 5,000 mph, traffic ahead, an exit coming, an interchange, and the bend and the
##                  traffic at night; and the quick menu's OPTIONS page, both panels. Each is a pose, not a flight: the craft is stood on the road with her
##                  speed told, the vehicles of the traffic picture are stood where its caption says, and the
##                  display is given a second and a half of its own clock, so a pair differs by the display
##                  alone. Two views of each: the flat camera's own wide one, and one 38 degrees high (about
##                  what a headset shows pixel for pixel) at the road's far end.
##   --mode=film    thirty seconds of a highway from the seat with it on, flown by the autopilot through the
##                  road's own traffic (FILM_BEGIN and FILM_END give the seconds to keep). Run with the
##                  engine's movie writer: --fixed-fps 60 --write-movie FILE.avi
##   --mode=cost    what it costs: the same stretch of busy highway near a city flown on a rail at 5,000 mph
##                  with it off, on, and on but undrawn (its work without its drawing), turn about, three
##                  rounds after one thrown away, with both eyes' worth of pixels in the one flat view (as
##                  render_terminal_art.gd --two-eyes). A turn is 300 frames, the last 240 timed: the GPU's
##                  time for the view, the renderer's own CPU time, the cockpit's whole frame on the main
##                  thread, and the display's own share of that. cost.json.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_tactical.gd -- --mute --out=DIR --mode=shots|film|cost [--only=bend,traffic,...]
extends "res://tests/render_terminal_art.gd"

const Tactical := preload("res://view/tactical_display.gd")
const Hour := preload("res://view/outlook.gd")
const MPH := 2.236936
var sim
var e1 := -1
var n1 := -1
var _bend := [-1, 0, 0.0]      # the highways' hardest bend: [road, sample, 1 / m]
var _cross := -1               # E1's sample where N1 crosses over it
var _mouth := -1               # ... and its first exit's mouth, going up its samples
const TRAFFIC := [[1400.0, 22.5, 2400.0], [2600.0, 22.5, 1300.0], [3800.0, 67.5, 2800.0], [5200.0, -22.5, 2600.0], [7500.0, 22.5, 3000.0], [9000.0, -112.5, 2500.0], [12000.0, 112.5, 2900.0]]


func _named(road_name: String) -> int:
	for r in sim.roads.size():
		if String(sim.roads[r].name) == road_name:
			return r
	return -1


func _settle() -> void:
	var world = seat.network_world
	for i in 6000:
		world.sync(sim.pod.x, sim.pod.y)
		seat.landscape.sync(sim.pod.x, sim.pod.y)
		if i % 40 == 0:
			await process_frame
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break


## The craft stood on sample i of a road going `dir` at `mph`, `left` m left of its middle that way.
func _stand(road: int, i: int, dir: int, mph: float, left := 0.0) -> void:
	sim.respawn_on(road, i, dir, -left)
	seat._ride.clear()
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = R.tx[i] * dir * mph / MPH
		body.vy = R.ty[i] * dir * mph / MPH
	seat.inp = {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}


## The world drawn where she stands (no time passes: the sim is not stepped), and the display given `clock`
## seconds of its own.
func _show(clock := 1.5) -> void:
	for frame in 6:
		seat._process(0.0)
		await process_frame
	if seat.tactical != null:
		for frame in int(clock * 120.0):
			seat.tactical.sync(1.0 / 120.0, seat._rush_flow, true)
	for read in 3:
		seat.dashboard.settle(0.1)


func _shot(shot_name: String) -> bool:
	for view in [["wide", 0.0, 0.0], ["eye", 38.0, 1.5]]:
		seat.cam.position = Vector3.ZERO
		seat.cam.fov = float(view[1]) if float(view[1]) > 0.0 else _wide
		seat.cam.rotation_degrees = Vector3(float(view[2]), 0.0, 0.0)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("%s-%s.png" % [shot_name, view[0]])
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Couldn't save " + path)
			return false
	seat.cam.fov = _wide
	seat.cam.rotation_degrees = Vector3.ZERO
	return true


var _wide := 70.0


## A scene with the display off, then on: `pose` stands the craft (and whatever the scene needs).
func _pair(scene: String, pose: Callable) -> bool:
	for on in [false, true]:
		Tactical.wanted = on
		pose.call()
		await _settle()
		await _show()
		if not await _shot("%s-%s" % [scene, "on" if on else "off"]):
			return false
		var t = seat.tactical
		print("TACTICAL_SHOT %s %s  %.0f mph  %s" % [scene, "on" if on else "off", seat._kmh() / 1.609344,
			"" if t == null else "rails %d stations to %.1f km, the hardest bend's ask %.2f of what she holds; %d lines (%d candidates thinned: %s); %d chevrons for %d exits and joins; the number \"%s\"" % [
				t.st_s.size(), (t.st_s[t.st_s.size() - 1] - t.pod_s) / 1000.0 if t.st_s.size() > 0 else 0.0, t.worst_load(seat._kmh() / 3.6, 12.0), t.line_count, t.marks.size(), t.thinned, t.chevron_count, t.exits.size(), t.number.text]])
	return true


## The highways' hardest bend: [road, sample, 1 / m].
func _hardest_bend() -> Array:
	var best := [-1, 0, 0.0]
	for r in sim.roads.size():
		var R = sim.roads[r]
		if R.shaft or R.deck or String(R.role) != "" or int(R.N) < 4000 or not (String(R.name).begins_with("E") or String(R.name).begins_with("N")):
			continue
		for i in range(400, int(R.N) - 400, 4):
			var turn: float = absf(angle_difference(atan2(R.ty[i], R.tx[i]), atan2(R.ty[i + 4], R.tx[i + 4]))) / 96.0
			if turn > float(best[2]):
				best = [r, i, turn]
	return best


## Vehicles of the road's own traffic stood ahead of her: each [m ahead, m left of the road's middle, mph].
func _traffic_ahead(road: int, dir: int, rows: Array) -> void:
	var net = seat.traffic_net
	var here: float = sim._road_f(sim.pod)
	var tries := 0
	while net.cars.size() < rows.size() and tries < 4000:      # (the traffic's own vehicles, as it makes them)
		net._spawn(sim.pod.x, sim.pod.y, true)
		tries += 1
	for k in net.cars.size():
		var c = net.cars[k]
		if k >= rows.size():      # the rest: far off down another road
			c.road = n1 if road != n1 else e1
			c.f = 200.0 + k
			c.lat = 0.0
		else:
			c.road = road
			c.dir = dir
			c.f = here + dir * float(rows[k][0]) / 24.0
			c.lat = float(rows[k][1]) * dir
			c.v = float(rows[k][2]) / MPH
			c.vdes = c.v
			c.cruise = c.v
		c.owed = 0.0
		c.flat_road = -1
		c.place(sim.roads[c.road])


func _run() -> void:
	var mode := "shots"
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Hour.pinned = true
	Hour.time = "afternoon"
	Hour.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	if mode == "cost":      # both eyes' worth of pixels in the one flat view (render_terminal_art.gd --two-eyes)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(2434, 1302)
		root.scaling_3d_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._school_loaded = true
	Seat.school = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._rush_loaded = true
	Seat._options_loaded = true
	Seat.consumables = false
	Seat.power_ups_on = false
	Tactical.wanted = false
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	seat = Seat.new()
	root.add_child(seat)
	if seat.cam == null:
		push_error("The cockpit did not build.")
		quit(1)
		return
	seat.set_process(false)
	sim = seat.sim
	if mode != "film":      # (a pose keeps the levers it is given; the film is flown by the autopilot)
		seat.cruise = 0.0
	_wide = seat.cam.fov
	e1 = _named("E1")
	n1 = _named("N1")
	var ok := true
	match mode:
		"shots": ok = await _shots(only)
		"film": await _film()
		"cost": await _cost()
		_:
			push_error("--mode= shots, film or cost")
			ok = false
	Tactical.wanted = false
	seat.queue_free()
	await process_frame
	if prefs_before == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Seat.PREFS))
	else:
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("TACTICAL RENDER DONE" if ok else "TACTICAL RENDER FAILED")
	quit(0 if ok else 1)


func _pose_bend_3000() -> void:
	_stand(int(_bend[0]), int(_bend[1]) - 220, 1, 3000.0)


func _pose_bend_5000() -> void:
	_stand(int(_bend[0]), int(_bend[1]) - 220, 1, 5000.0)


func _pose_traffic() -> void:
	_stand(e1, 4000, 1, 5000.0, 22.5)
	_traffic_ahead(e1, 1, TRAFFIC)


## (the chevrons laid where they would have been, at the mouth's lead, and then she is stood nearer)
func _lay_from(i: int, mph: float) -> void:
	_stand(e1, i, 1, mph)
	seat._process(0.0)
	if seat.tactical != null:
		for frame in 24:
			seat.tactical.sync(1.0 / 120.0, seat._rush_flow, true)


func _pose_exit() -> void:
	_lay_from(_mouth - int((Tactical.exit_lead(5000.0 / MPH) - 400.0) / 24.0), 5000.0)
	_stand(e1, _mouth - int(7000.0 / 24.0), 1, 5000.0)


## The interchange where N1 crosses E1: 5 km short of its exits' mouths.
func _pose_junction() -> void:
	var mouth := -1
	for row in seat.network_world.exit_lanes.get(e1, []):
		if int(row[2]) == 1 and int(row[5]) >= 0 and int(row[4]) < _cross and int(row[4]) > mouth:
			mouth = int(row[4])
	_lay_from(mouth - int((Tactical.exit_lead(4000.0 / MPH) - 400.0) / 24.0), 4000.0)
	_stand(e1, mouth - int(5000.0 / 24.0), 1, 4000.0, 22.5)
	_traffic_ahead(e1, 1, [[1800.0, 22.5, 2000.0], [3200.0, -67.5, 2400.0], [4400.0, 112.5, 2600.0]])


func _shots(only: PackedStringArray) -> bool:
	var bend := _hardest_bend()
	_bend = bend
	var grip: float = Tactical.grip(sim)
	print("TACTICAL_BEND %s sample %d: a radius of %.1f km, held to %.0f mph (%.2f g); 3,000 mph asks %.2f of that, 5,000 mph %.2f" % [sim.roads[int(bend[0])].name, int(bend[1]), 0.001 / float(bend[2]),
		sqrt(grip / float(bend[2])) * MPH, grip / 9.81, Tactical.load_of(sim, float(bend[2]), 3000.0 / MPH), Tactical.load_of(sim, float(bend[2]), 5000.0 / MPH)])
	var E = sim.roads[e1]
	# where N1 crosses E1, and E1's first exit up its samples before that
	var cross := -1
	for i in range(200, int(E.N) - 200, 2):
		for near in sim.net_near(E.px[i], E.py[i]):
			if int(near[0]) == n1 and absf(float(near[2])) < 30.0 and cross < 0:
				cross = i
		if cross >= 0:
			break
	var mouth := -1
	for row in seat.network_world.exit_lanes.get(e1, []):
		if int(row[2]) == 1 and int(row[5]) >= 0 and int(row[4]) > 3000 and (mouth < 0 or int(row[4]) < mouth):
			mouth = int(row[4])
	print("TACTICAL_PLACES N1 crosses E1 at its sample %d; E1's first exit going up its samples is at %d" % [cross, mouth])
	_cross = cross
	_mouth = mouth
	var scenes := {"bend-3000": _pose_bend_3000, "bend-5000": _pose_bend_5000, "traffic": _pose_traffic, "exit": _pose_exit, "junction": _pose_junction}
	for scene in scenes:
		if not only.is_empty() and not only.has(scene):
			continue
		if not await _pair(scene, scenes[scene]):
			return false
	# the quick menu's OPTIONS page: its first panel, and the next, where the switch is
	if only.is_empty() or only.has("menu"):
		Tactical.wanted = true
		_pose_bend_3000()
		await _settle()
		await _show()
		seat.menu_open(true)
		for k in seat.menu.items.size():
			if String(seat.menu.items[k].key) == "options":
				seat.menu.at = k
		seat.menu_choose()
		if not await _shot("menu-options-1"):
			return false
		for k in seat.menu.items.size():      # down its lines and on past BACK
			seat.menu.move(1)
		seat._menu_show()
		if not await _shot("menu-options-2"):
			return false
		print("TACTICAL_SHOT menu: \"%s\", the cursor on %s" % [seat.menu.text().get_slice("\n", 0), seat.menu.key()])
		seat.menu_open(false)
		seat._await_neutral_controls = false
	# at night
	Hour.time = "night"
	Hour.apply(seat)
	for scene in ["bend-5000", "traffic"]:
		if not only.is_empty() and not only.has("night"):
			continue
		if not await _pair("night-" + scene, scenes[scene]):
			return false
	Hour.time = "afternoon"
	Hour.apply(seat)
	return true


## Thirty seconds flown by the autopilot through the road's own traffic, the display on.
func _film() -> void:
	var E = sim.roads[e1]
	var cross := -1
	for i in range(200, int(E.N) - 200, 2):
		for near in sim.net_near(E.px[i], E.py[i]):
			if int(near[0]) == n1 and absf(float(near[2])) < 30.0 and cross < 0:
				cross = i
		if cross >= 0:
			break
	Tactical.wanted = true
	_stand(e1, maxi(400, cross - int(45000.0 / 24.0)), 1, 4000.0)
	await _settle()
	var took: bool = seat.set_autopilot(true)
	seat.autopilot.set_cruise(4300.0 / MPH)
	print("FILM autopilot %s: %s" % [took, seat.autopilot.message().replace("\n", " / ")])
	var shown := 0
	for frame in 60 * 38:
		seat._process(1.0 / 60.0)
		seat.approach_display._process(1.0 / 60.0)
		await process_frame
		shown += 1
		if frame == 60 * 6:
			print("FILM_BEGIN %.2f" % (shown / 60.0))
		if frame % 120 == 0:
			var t = seat.tactical
			print("FILMT %.1f s: %s sample %d, %.0f mph, %d vehicles, %d lines, %d chevrons, rails to %.1f km, ask %.2f" % [shown / 60.0, sim.roads[sim.pod.path].name, sim.pod.hint, seat._kmh() / 1.609344,
				seat.traffic_net.cars.size(), t.line_count if t else 0, t.chevron_count if t else 0, (t.st_s[t.st_s.size() - 1] - t.pod_s) / 1000.0 if t and t.st_s.size() > 0 else 0.0, t.number_load if t else 0.0])
	print("FILM_END %.2f" % (shown / 60.0))
	seat.set_autopilot(false)


## What it costs (see the header).
func _cost() -> void:
	# a highway near a city: the traffic at its thickest
	var city: Dictionary = sim.cities[0]
	for c in sim.cities:
		if String(c.name) == "GLACIER":
			city = c
	var road := int(city.road)
	var R = sim.roads[road]
	var start := maxi(400, mini(int(city.i) + 300, int(R.N) - 700))      # 7 km out of the city: clear of its hall, in its traffic
	_stand(road, start, 1, 5000.0)
	await _settle()
	var net = seat.traffic_net
	for frame in 400:      # the road's traffic, filled and driving
		seat._process(STEP)
		_stand(road, start, 1, 5000.0)
		if frame % 4 == 0:
			await process_frame
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var per_frame := 5000.0 / MPH * STEP / 24.0      # samples a frame at 5,000 mph
	var kept := {}
	var order := ["off", "on", "undrawn"]
	var cars_seen := 0
	var lines_seen := 0
	for turn in 4:
		for variant in order:
			Tactical.wanted = variant != "off"
			Tactical.drawn = variant != "undrawn"
			var got := {"gpu": [], "rcpu": [], "frame": [], "own": []}
			for frame in 300:
				var at := float(frame) * per_frame
				var i := start + int(at)
				_stand(road, i, 1, 5000.0)
				var rest := (at - floorf(at)) * 24.0
				for body in sim.bodies:
					body.x += R.tx[i] * rest
					body.y += R.ty[i] * rest
				Tactical.probe_usec = 0
				var t0 := Time.get_ticks_usec()
				seat._process(STEP)
				var took := Time.get_ticks_usec() - t0
				await process_frame
				if frame < 60:
					continue
				(got.gpu as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				(got.rcpu as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
				(got.frame as Array).append(took / 1000.0)
				(got.own as Array).append(Tactical.probe_usec / 1000.0)
				cars_seen = maxi(cars_seen, net.cars.size())
				if seat.tactical != null:
					lines_seen = maxi(lines_seen, int(seat.tactical.line_count))
			if turn == 0:
				continue
			if not kept.has(variant):
				kept[variant] = {}
			for key in got:
				var values: Array = got[key]
				values.sort()
				var mean := 0.0
				for value in values:
					mean += float(value)
				if not (kept[variant] as Dictionary).has(key):
					kept[variant][key] = []
				(kept[variant][key] as Array).append([values[values.size() / 2], mean / float(values.size()), values[int(values.size() * 0.99)]])
			var last: Dictionary = kept[variant]
			print("TACTICAL_COST round %d %-8s gpu %.3f ms | render cpu %.3f | the cockpit's frame %.3f (mean %.3f, 99%% %.3f) | the display's own %.4f (mean %.4f, 99%% %.4f)" % [turn, variant,
				last.gpu[-1][0], last.rcpu[-1][0], last.frame[-1][0], last.frame[-1][1], last.frame[-1][2], last.own[-1][0], last.own[-1][1], last.own[-1][2]])
	Tactical.drawn = true
	var result := {"vehicles": cars_seen, "lines": lines_seen, "pixels": "%d x %d" % [root.content_scale_size.x * 2, root.content_scale_size.y * 2]}
	for variant in order:
		var line := {}
		for key in kept[variant]:
			var rounds: Array = kept[variant][key]
			rounds.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
			line[key] = snappedf(float(rounds[rounds.size() / 2][0]), 0.0001)
			line[key + "_mean"] = snappedf(float(rounds[rounds.size() / 2][1]), 0.0001)
		result[variant] = line
	var base: Dictionary = result["off"]
	for variant in order:
		var line: Dictionary = result[variant]
		print("TACTICAL_COST %-8s gpu %.3f ms (%+.3f) | render cpu %.3f (%+.3f) | the cockpit's frame %.3f (%+.3f; mean %.3f, %+.3f) | the display's own %.4f (mean %.4f)" % [variant, line.gpu, float(line.gpu) - float(base.gpu),
			line.rcpu, float(line.rcpu) - float(base.rcpu), line.frame, float(line.frame) - float(base.frame), line.frame_mean, float(line.frame_mean) - float(base.frame_mean), line.own, line.own_mean])
	print("TACTICAL_COST on %s at 5,000 mph near %s: %d vehicles round her, %d lines at most; the view %s pixels, MSAA 4x; three rounds, the middle one's medians" % [R.name, city.name, cars_seen, lines_seen, result.pixels])
	var output := FileAccess.open(out_dir.path_join("cost.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))
