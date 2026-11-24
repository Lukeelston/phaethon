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
##   --mode=approach  an exit flown up to (Luke, 2026-11-23: "the same size arrows for a few miles then a turn out of
##                  nowhere"): a still from the seat, 38 degrees high, at each of --at=7,6,5,... seconds before
##                  its mouth at --mph=3500, the seconds written on the frame. Its marks are laid where a flight
##                  would have laid them (at their lead) and she is then stood nearer, on the line she came up
##                  (--left=M left of the road's middle; --left=lane: in the exit's own lane). --exit=N: E1's
##                  N-th exit going up its samples; --join: the first join past it instead; --tag=WORDS: on the
##                  frames and in their names. approach.json: what stood where at each. --film: flown up to
##                  instead, from --from=7.5 seconds before the mouth to just past it at --mph, the seconds written
##                  on each frame (run with --fixed-fps 30 --write-movie FILE.avi).
##   --mode=bend    the highways' hardest bend from the seat, --ahead=3 seconds short of it, at each of
##                  --mph=6500,8000,9300 (a still each, the bend's ask of what she holds written on it; --tag=WORDS).
##                  Uses only what every version of the display has, so the same run shows an older one.
##   --mode=rails   the rails' colours, for choosing: one pose by an exit with vehicles ahead whose lines are
##                  calm, amber and red, by day, at dawn, at dusk, at night and in a city's hall; in each the
##                  whole of the rails is shown calm, near the limit and past it (the shader's thresholds are
##                  moved for the picture; nothing else is), for each of --schemes=NAME,... (SCHEMES below;
##                  "now": the display's own).
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_tactical.gd -- --mute --out=DIR --mode=shots|film|cost|approach|rails|bend [--only=bend,traffic,...]
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
## The rails' colours tried (--mode=rails): [calm, near the limit, past it].
const SCHEMES := {
	"old": [Color(0.0, 0.8, 1.0), Color(1.0, 0.7, 0.1), Color(1.0, 0.16, 0.08)],                # as flown on 2026-11-23: the vehicles' own
	"violet": [Color(0.66, 0.56, 1.0), Color(0.8, 0.36, 1.0), Color(1.0, 0.2, 0.9)],             # lavender, violet, magenta
	"ice": [Color(0.86, 0.9, 1.0), Color(0.7, 0.5, 1.0), Color(1.0, 0.2, 0.9)],                  # white, violet, magenta
	"indigo": [Color(0.38, 0.42, 1.0), Color(0.7, 0.36, 1.0), Color(1.0, 0.3, 0.85)],            # a deep blue, violet, pink
	"white": [Color(0.9, 0.92, 1.0), Color(0.9, 0.92, 1.0), Color(0.9, 0.92, 1.0)],              # one white: the curtain and the line alone say how hard
}
var _caption: Label


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


## Words written on the frames that follow (none: nothing).
func _say(words: String) -> void:
	if _caption == null:
		var layer := CanvasLayer.new()
		layer.layer = 60
		root.add_child(layer)
		_caption = Label.new()
		_caption.position = Vector2(22.0, 12.0)
		_caption.add_theme_font_size_override("font_size", 30)
		_caption.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		_caption.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		_caption.add_theme_constant_override("outline_size", 9)
		layer.add_child(_caption)
	_caption.text = words


## One still from the seat, 38 degrees high (about what a headset shows pixel for pixel).
func _eye_shot(shot_name: String) -> bool:
	seat.cam.position = Vector3.ZERO
	seat.cam.fov = 38.0
	seat.cam.rotation_degrees = Vector3(1.5, 0.0, 0.0)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(shot_name + ".png")
	var saved := root.get_texture().get_image().save_png(path) == OK
	if not saved:
		push_error("Couldn't save " + path)
	seat.cam.fov = _wide
	seat.cam.rotation_degrees = Vector3.ZERO
	return saved


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
		"approach": ok = await _approach()
		"rails": ok = await _rails()
		"bend": ok = await _bend_speeds()
		_:
			push_error("--mode= shots, film, cost, approach, rails or bend")
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


## E1's exits (or the joins) going up its samples, past sample 3000: exit_lanes' rows, by their mouths.
func _lanes_up(joins: bool) -> Array:
	var out: Array = []
	for row in seat.network_world.exit_lanes.get(e1, []):
		if int(row[5]) >= 0 and int(row[4]) > 3000 and (int(row[2]) == 1) != joins:
			out.append(row)
	out.sort_custom(func(a, b): return int(a[4]) < int(b[4]))
	return out


## What the display has laid for the exits, in words and in numbers (as far as this copy of it says).
func _laid() -> Dictionary:
	var t = seat.tactical
	var out := {"chevrons": 0, "exits": 0}
	if t == null:
		return out
	out.chevrons = int(t.chevron_count)
	out.exits = t.exits.size()
	var to_mouth := []
	for laid in t.chev_laid:
		to_mouth.append(snappedf(float(laid[2]), 1.0))
	out["to_mouth"] = to_mouth
	if "chev_kind" in t:
		out["kinds"] = Array(t.chev_kind)
	return out


## An exit flown up to (see the header).
func _approach() -> bool:
	var mph := 3500.0
	var times := PackedFloat64Array([7.0, 6.0, 5.0, 4.0, 3.0, 2.5, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25])
	var left_arg := "22.5"
	var nth := 0
	var join := false
	var tag := ""
	var film := false
	var from_s := 7.5
	for arg in OS.get_cmdline_user_args():
		if arg == "--film":
			film = true
		if arg.begins_with("--from="):
			from_s = float(arg.trim_prefix("--from="))
		if arg.begins_with("--mph="):
			mph = float(arg.trim_prefix("--mph="))
		if arg.begins_with("--at="):
			times = PackedFloat64Array()
			for word in arg.trim_prefix("--at=").split(","):
				times.append(float(word))
		if arg.begins_with("--left="):
			left_arg = arg.trim_prefix("--left=")
		if arg.begins_with("--exit="):
			nth = int(arg.trim_prefix("--exit="))
		if arg == "--join":
			join = true
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
	var lanes := _lanes_up(join)
	if nth >= lanes.size():
		push_error("E1 has %d such lanes going up its samples" % lanes.size())
		return false
	var lane: Array = lanes[nth]
	var mouth := int(lane[4])
	var E = sim.roads[e1]
	var speed := mph / MPH
	var left := float(lane[3]) if left_arg == "lane" else float(left_arg)
	var lead := Tactical.exit_lead(speed)
	print("APPROACH %s of E1 at its sample %d to %s: its lane %.1f m left of the road's middle (the road %.0f m wide there), her line %.1f m left; %.0f mph, its lead %.2f km (%.1f s)" % ["join" if join else "exit", mouth,
		sim.roads[int(lane[5])].name, float(lane[3]), E.w[mouth], left, mph, lead / 1000.0, lead / speed])
	Tactical.wanted = true
	# laid where a flight would have laid them: as the mouth comes inside its lead (a join: inside its own look)
	var first := (Tactical.JOIN_LOOK if join else lead) - 100.0
	_stand(e1, mouth - int(first / 24.0), 1, mph, left)
	await _settle()
	seat._process(0.0)
	if seat.tactical != null:
		for frame in 24:
			seat.tactical.sync(1.0 / 120.0, seat._rush_flow, true)
	var record := {"mph": mph, "mouth": mouth, "join": join, "lane_left": float(lane[3]), "her_left": left, "lead_m": lead, "laid": _laid(), "frames": []}
	print("APPROACH laid %s" % [record.laid])
	var name_tag := "" if tag.is_empty() else tag.to_lower().replace(" ", "-") + "-"
	if film:      # flown up to, a frame at a time, at the engine's fixed rate
		var fps := 30.0      # (run with --fixed-fps 30)
		seat.cam.position = Vector3.ZERO
		seat.cam.fov = 38.0
		seat.cam.rotation_degrees = Vector3(1.5, 0.0, 0.0)
		var frames := int((from_s + 0.4) * fps)
		for frame in frames:
			var left_s := from_s - float(frame) / fps
			var back_m := left_s * speed
			var i := mouth - int(floorf(back_m / 24.0))
			var rest := float(mouth - i) * 24.0 - back_m      # m on past sample i
			_stand(e1, i, 1, mph, left)
			for body in sim.bodies:
				body.x += E.tx[i] * rest
				body.y += E.ty[i] * rest
			# a pose a frame, as the stills are (the sim is not stepped: a step of its own would turn her), the world
			# streamed in round her and the display given the frame's time on its own clock
			for sweep in 3:
				seat.network_world.sync(sim.pod.x, sim.pod.y)
				seat.landscape.sync(sim.pod.x, sim.pod.y)
			seat._process(0.0)
			if seat.tactical != null:
				seat.tactical.sync(1.0 / fps, seat._rush_flow, true)
			seat.cam.position = Vector3.ZERO
			seat.cam.fov = 38.0
			seat.cam.rotation_degrees = Vector3(1.5, 0.0, 0.0)
			var to_go: float = (float(mouth) - float(sim._road_f(sim.pod))) * 24.0
			_say("%s%.2f s to the mouth   %.1f km   %s mph" % ["" if tag.is_empty() else tag + "   ", to_go / speed, to_go / 1000.0, seat.tactical.number.text if seat.tactical != null else str(int(mph))])
			await process_frame
			if frame % int(fps) == 0:
				print("APPROACH_FILM %.2f s to the mouth, %d chevrons laid" % [to_go / speed, int(seat.tactical.chevron_count) if seat.tactical != null else 0])
		_say("")
		return true
	for k in times.size():
		var back := roundi(float(times[k]) * speed / 24.0)
		_stand(e1, mouth - back, 1, mph, left)
		await _settle()
		await _show(1.0)
		var to_go: float = (float(mouth) - float(sim._road_f(sim.pod))) * 24.0
		var words := "%s%.2f s to the mouth   %.1f km   %s mph" % ["" if tag.is_empty() else tag + "   ", to_go / speed, to_go / 1000.0, seat.tactical.number.text if seat.tactical != null else str(int(mph))]
		_say(words)
		var shot := "%s%02d-%05dms" % [name_tag, k, roundi(float(times[k]) * 1000.0)]
		if not await _eye_shot(shot):
			return false
		(record.frames as Array).append({"file": shot + ".png", "seconds": snappedf(to_go / speed, 0.001), "metres": snappedf(to_go, 1.0), "chevrons": int(seat.tactical.chevron_count) if seat.tactical != null else 0})
		print("APPROACH_SHOT %s  %s  (%d chevrons laid)" % [shot, words, int(seat.tactical.chevron_count) if seat.tactical != null else 0])
	_say("")
	var output := FileAccess.open(out_dir.path_join(name_tag + "approach.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(record, "\t"))
	return true


## The highways' hardest bend at several speeds (see the header).
func _bend_speeds() -> bool:
	var speeds := PackedFloat64Array([6500.0, 8000.0, 9300.0])
	var ahead_s := 3.0
	var tag := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mph="):
			speeds = PackedFloat64Array()
			for word in arg.trim_prefix("--mph=").split(","):
				speeds.append(float(word))
		if arg.begins_with("--ahead="):
			ahead_s = float(arg.trim_prefix("--ahead="))
		if arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
	var bend := _hardest_bend()
	var grip: float = Tactical.grip(sim)
	var held := sqrt(grip / float(bend[2])) * MPH
	print("BEND %s sample %d: a radius of %.1f km, held to %.0f mph (%.2f g)" % [sim.roads[int(bend[0])].name, int(bend[1]), 0.001 / float(bend[2]), held, grip / 9.81])
	Tactical.wanted = true
	var name_tag := "" if tag.is_empty() else tag.to_lower().replace(" ", "-") + "-"
	for k in speeds.size():
		var mph: float = speeds[k]
		var speed := mph / MPH
		_stand(int(bend[0]), int(bend[1]) - roundi(ahead_s * speed / 24.0), 1, mph)
		await _settle()
		await _show()
		var ask: float = Tactical.load_of(sim, float(bend[2]), speed)
		var t = seat.tactical
		var hue: String = t.number.modulate.to_html(false) if t != null else "-"
		var banked: float = t.number_load if t != null else 0.0      # (with the bend's own bank, as the rails have it)
		_say("%s%.0f mph   the bend %.0f s ahead asks %.2f of what she holds with its bank (%.2f flat)   number #%s" % ["" if tag.is_empty() else tag + "   ", mph, ahead_s, banked, ask, hue])
		var shot := "%sbend-%05dmph" % [name_tag, int(mph)]
		if not await _eye_shot(shot):
			return false
		print("BEND_SHOT %s  %.0f mph, ask %.2f, the hardest within six seconds %.2f, the number %s #%s" % [shot, mph, ask, t.number_load if t != null else 0.0, t.number.text if t != null else "-", hue])
	_say("")
	return true


## The rails' colours, for choosing (see the header).
func _rails() -> bool:
	var names := PackedStringArray(["old", "violet"])
	var lights := PackedStringArray(["afternoon", "dawn", "dusk", "night", "hall"])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--schemes="):
			names = arg.trim_prefix("--schemes=").split(",")
		if arg.begins_with("--lights="):
			lights = arg.trim_prefix("--lights=").split(",")
	var lanes := _lanes_up(false)
	var mouth := int(lanes[0][4])
	var mph := 3500.0
	var speed := mph / MPH
	# vehicles in her way whose lines are calm, amber and red: [m ahead, m left of the road's middle, mph]
	var slow := 1500.0
	var closing := (mph - slow) / MPH
	var cars := [[closing * 1.0, 22.5, slow], [closing * 2.4, -22.5, slow], [closing * 6.0, 67.5, slow]]
	Tactical.wanted = true
	for light in lights:
		var hall: bool = light == "hall"
		Hour.time = "afternoon" if hall else light
		Hour.apply(seat)
		if hall:      # the departure city's hall, a kilometre inside it
			var lit = seat.terminal_lighting
			_stand(int(lit.road_id), int(lit.first_sample) + 40, 1, mph, 22.5)
			await _settle()
			_traffic_ahead(int(lit.road_id), 1, cars)
		else:         # 4.5 s short of an exit's mouth, its chevrons laid where a flight would have laid them
			_stand(e1, mouth - int((Tactical.exit_lead(speed) - 100.0) / 24.0), 1, mph, 22.5)
			await _settle()
			seat._process(0.0)
			for frame in 24:
				seat.tactical.sync(1.0 / 120.0, seat._rush_flow, true)
			_stand(e1, mouth - int(4.5 * speed / 24.0), 1, mph, 22.5)
			await _settle()
			_traffic_ahead(e1, 1, cars)
		await _show()
		var t = seat.tactical
		print("RAILS %s: %s sample %d, enclosure %.2f, darkness %.2f; %d lines, %d chevrons" % [light, sim.roads[sim.pod.path].name, sim.pod.hint,
			float(seat.terminal_lighting.enclosure) if seat.terminal_lighting != null else 0.0, Hour.darkness(), t.line_count, t.chevron_count])
		for scheme in names:
			var colours: Array = SCHEMES.get(scheme, [])
			if scheme == "now":
				colours = [t.rail_mat.get_shader_parameter("calm"), t.rail_mat.get_shader_parameter("warm"), t.rail_mat.get_shader_parameter("hot")]
			if colours.is_empty():
				push_error("no scheme named " + scheme)
				return false
			var was := [t.rail_mat.get_shader_parameter("calm"), t.rail_mat.get_shader_parameter("warm"), t.rail_mat.get_shader_parameter("hot"), t.rail_mat.get_shader_parameter("at_load")]
			t.rail_mat.set_shader_parameter("calm", colours[0])
			t.rail_mat.set_shader_parameter("warm", colours[1])
			t.rail_mat.set_shader_parameter("hot", colours[2])
			for level in 3:      # the whole of the rails calm, near the limit, past it: the thresholds moved under a straight road's nothing
				t.rail_mat.set_shader_parameter("at_load", [Vector4(5.0, 6.0, 7.0, 8.0), Vector4(-2.0, -1.0, 7.0, 8.0), Vector4(-4.0, -3.0, -2.0, -1.0)][level])
				var tint: Color = colours[level]
				tint.a = t.number.modulate.a
				t.number.modulate = tint
				_say("%s   %s   the road %s" % [scheme, light, ["calm", "near the limit", "past it"][level]])
				if not await _eye_shot("rails-%s-%s-%d" % [light, scheme, level]):
					return false
			t.rail_mat.set_shader_parameter("calm", was[0])
			t.rail_mat.set_shader_parameter("warm", was[1])
			t.rail_mat.set_shader_parameter("hot", was[2])
			t.rail_mat.set_shader_parameter("at_load", was[3])
			t._number_tint = Color(0, 0, 0, 0)      # (the number takes its own colour again at its next frame)
	_say("")
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
