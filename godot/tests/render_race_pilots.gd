## The racing pilots of the Eridanus track (view/race_pilots.gd), for looking at and for weighing.
## Run windowed, as render_terminal_art.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_race_pilots.gd -- --mute --out=DIR [--views=a,b] [--bench] [--no-racers] [--headset] [--film=start|pass]
## --film writes numbered frames (30 a second of the race) into DIR/film-NAME for ffmpeg: "start",
## nine seconds from the grid lights to the field getting away; "pass", from the seat on
## the loop as the quickest of them comes by.
## The pictures: the grid from the seat and from above, the start, a pilot coming by on the loop,
## the field through the first town bend, and the finish of the recorded lap. --bench times the seat on the grid and in the pack, a
## desktop eye (with --no-racers: the same frames without them, to weigh the field).
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Race := preload("res://view/race_pilots.gd")
const STEP := 1.0 / 120.0
const VIEWS := ["a1-the-grid-from-the-seat", "a2-the-grid-from-above", "b1-the-start-from-the-seat", "b2-the-start-from-above",
	"c1-a-pilot-coming-by-on-the-loop", "c2-and-gone-ahead", "d1-the-field-through-the-first-town-bend", "e1-the-finish-from-the-seat"]

var seat
var out_dir := ""
var duel_player_s := 0.0
var ext: Camera3D
var profile := preload("res://tests/race_review_settings.gd").new()
var failed := false


func _finalize() -> void:
	profile.restore()


func _initialize() -> void:
	profile.pin(Seat.PREFS)
	_run.call_deferred()


func _frames(count: int) -> void:
	for k in count:
		seat._process(STEP)
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		failed = true
		push_error("Couldn't save " + path)
	var race = seat.race
	print("RACE_SHOT %s | %s" % [name, race.line() if race else "no pilots"])


## The outside camera: at a place m ahead, m left and m up from a point of the course, looking at another.
func _outside(s_eye: float, left_eye: float, up_eye: float, s_at: float, left_at: float, up_at: float, fov := 50.0) -> void:
	var a := _course_point(s_eye, left_eye, up_eye)
	var b := _course_point(s_at, left_at, up_at)
	ext.fov = fov
	ext.look_at_from_position(a, b, Vector3.UP)
	ext.make_current()
	if seat.race:      # (they are drawn whole near where they are looked at from)
		seat.race.eye = Vector2(a.x + seat.org_x, -a.z + seat.org_y)


func _course_point(s: float, left: float, up: float) -> Vector3:
	var sim = seat.sim
	var total: float = sim.track_length
	var at := fposmod(s, total)
	var i := 0
	var run := 0.0
	while i < sim.N - 1 and run + sim.tlen[i] <= at:
		run += sim.tlen[i]
		i += 1
	var along := at - run
	# (over the banked road where that place is: the view's own w3 knows the road only round the pod)
	var bank: float = sim.tb[i] if not sim.tb.is_empty() else 0.0
	var h: float = sim.bank_height(float(sim.tw[i]) / 2.0, left, bank) + up
	return Vector3(sim.tpx[i] + sim.ttx[i] * along + sim.tnx[i] * left - seat.org_x, h, -(sim.tpy[i] + sim.tty[i] * along + sim.tny[i] * left - seat.org_y))


## His own getaway from this line (flight 17, a speed each second): Vector2(m from his grid place, m/s) at t s.
const HIS_START := [0.0, 38.0, 161.0, 273.0, 347.0, 391.0, 416.0, 429.0, 440.0, 450.0, 458.0, 465.0]


func _his_start(t: float) -> Vector2:
	var s := 0.0
	var k := 0
	while k + 1 < HIS_START.size() and t >= float(k + 1):
		s += 0.5 * (float(HIS_START[k]) + float(HIS_START[k + 1]))
		k += 1
	if k + 1 >= HIS_START.size():
		return Vector2(s + float(HIS_START[k]) * (t - k), float(HIS_START[k]))
	var u := t - k
	var v := lerpf(float(HIS_START[k]), float(HIS_START[k + 1]), u)
	return Vector2(s + 0.5 * (float(HIS_START[k]) + v) * u, v)


func _seat_camera() -> void:
	if seat.race:
		seat.race.eye = Vector2.INF
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation = Vector3.ZERO
	seat.cam.make_current()


## The pilot's craft set down at m along the course, m left of its middle, at that speed (a frame's pose).
func _pose_player(s: float, left: float, v: float) -> void:
	var sim = seat.sim
	var at := fposmod(s, sim.track_length)
	var i := 0
	var run := 0.0
	while i < sim.N - 1 and run + sim.tlen[i] <= at:
		run += sim.tlen[i]
		i += 1
	sim.respawn(-1, i)
	var along: float = at - run
	for body in sim.bodies:
		body.x += sim.ttx[i] * along + sim.tnx[i] * left
		body.y += sim.tty[i] * along + sim.tny[i] * left
		body.vx = sim.ttx[i] * v
		body.vy = sim.tty[i] * v
	sim.lap_start = 0.0
	seat._ride.clear()


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
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	if "--headset" in OS.get_cmdline_user_args():
		root.scaling_3d_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "eridanus"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat.cold_start = false
	Seat.school = false
	Race.forced = "off" if "--no-racers" in OS.get_cmdline_user_args() else "on"
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	ext = Camera3D.new()
	ext.far = 60000.0
	ext.near = 0.3
	root.add_child(ext)
	if root.use_xr:
		push_error("This needs a monoscopic viewport (--xr-mode off).")
		quit(1)
		return
	var race = seat.race
	_seat_camera()
	await _frames(240)      # the trackside and the valley stream in
	if "--bench" in OS.get_cmdline_user_args():
		await _bench("grid")
		await _bench("pack")
		seat.free()
		quit(int(failed))
		return
	if race == null:
		push_error("No pilots: nothing to picture.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--film="):
			await _film(arg.trim_prefix("--film="))
			seat.free()
			quit(int(failed))
			return
	for name in VIEWS:
		if not only.is_empty() and not only.has(name):
			continue
		match name:
			"a1-the-grid-from-the-seat":
				seat.sim.restart()
				race.grid()
				_seat_camera()
				await _frames(255)
				await _shot(name)
			"a2-the-grid-from-above":
				seat.sim.restart()
				race.grid()
				await _frames(4)
				_outside(-70.0, -34.0, 26.0, 70.0, 4.0, 1.0)
				await _frames(40)
				await _shot(name)
			"b1-the-start-from-the-seat", "b2-the-start-from-above":
				seat.sim.restart()
				race.grid()
				_seat_camera()
				await _frames(360)
				# (his craft set down a frame at a time along his own getaway from this line, flight 17's)
				for frame in int(3.2 / STEP):
					var away := _his_start((frame + 1) * STEP)
					_pose_player(away.x, 0.0, away.y)
					seat._process(STEP)
					await process_frame
				if name.begins_with("b2"):
					var here: float = float(race.me.s)
					_outside(here - 80.0, -30.0, 30.0, here + 140.0, 6.0, 1.0)
					await _frames(2)
				await _shot(name)
			"c1-a-pilot-coming-by-on-the-loop", "c2-and-gone-ahead":
				_duel_grid()
				var shot := false
				for frame in 780:
					_duel_step(frame * STEP)
					await process_frame
					var lead: float = race.pilots[4].prog - race.me.prog
					var beside: bool = name.begins_with("c1") and lead > 36.0 and race.page().contains("ALONGSIDE")
					var clear: bool = name.begins_with("c2") and lead > Race.LEN + Race.BEHIND
					if beside or clear:
						await _shot(name)
						shot = true
						break
				if not shot:
					failed = true
					push_error("The staged pass did not reach " + name)

			"e1-the-finish-from-the-seat":
				await _recorded_finish(name)
			"d1-the-field-through-the-first-town-bend":
				seat.sim.restart()
				race.grid()
				await _frames(4)
				seat.sim.lap_start = 0.0      # (he stays on the grid and the field goes: not a restart)
				race.go()
				_outside(4010.0, 6.0, 5.0, 3800.0, 36.0, 2.0, 55.0)
				var waited := 0
				while waited < 3000 and float(race.pilots[4].prog) < 3840.0:
					waited += 1
					seat._process(STEP)
					await process_frame
				await _shot(name)
	seat.free()
	quit(int(failed))


## Stage a named rival just behind the player, fighting for third. Only the player is
## posed frame by frame. The opponent makes its own passing and line decisions.
func _duel_grid() -> void:
	_seat_camera()
	var race = seat.race
	duel_player_s = 159000.0
	race.grid()
	race.go()
	race.clock = 111.0
	race._me_s = duel_player_s
	race.me.prog = duel_player_s
	var offsets := [2400.0, 900.0, -1250.0, -700.0, -68.0]
	for k in race.pilots.size():
		var p = race.pilots[k]
		p.s = duel_player_s + offsets[k]
		p.prog = p.s
		p.i = race._sample(p.s, 0)
		p.lat = race.nominal(p.i, p.lane)
		p.lat_v = 0.0
		p.v = p.f_loop * race.env[p.i]
		race._pose(p)


func _duel_step(t: float) -> void:
	var race = seat.race
	var p = race.pilots[4]
	# Leave a lane on the right and counterattack after its nose gets in front.
	var i: int = race._sample(duel_player_s, p.i)
	var left: float = race.nominal(i, p.lane) + 31.0
	var speed: float = p.v + (28.0 if t > 4.4 else -32.0)
	duel_player_s += speed * STEP / maxf(0.6, 1.0 - race.kap[i] * left)
	_pose_player(duel_player_s, left, speed)
	seat._process(STEP)
	# A seated glance toward the overlapping craft, through the right-hand canopy.
	seat.cam.rotation.y = deg_to_rad(-26.0) * smoothstep(0.7, 2.2, t)


## A real one-lap result from the replay, including the other finish times. Fast-forward
## just the sim and the race, then let the cockpit settle and photograph the player's page.
func _recorded_finish(label: String) -> void:
	seat._respawn()
	var race = seat.race
	race.lap_limit = 1
	race.go()
	var inputs: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/eridanus_inputs.json"))
	for u in inputs:
		var inp := {"thrL": u[0], "thrR": u[1], "brkL": u[2], "brkR": u[3], "repair": false, "reignite": true}
		if int(u[4]) > 0:
			inp.handling = ["", "speed", "starfighter"][int(u[4])]
		for k in 8:
			seat.sim.step(inp, 1.0 / 480.0)
		seat.sim.events.clear()
		race.step(1.0 / 60.0)
		race._feed_obstacles()
		if is_finite(race.you.finish):
			break
	if not is_finite(race.you.finish):
		failed = true
		push_error("Replay did not finish")
		return
	_seat_camera()
	await _frames(80)
	await _shot(label)


## Three passes of 240 frames from the seat, the last one timed: "grid" standing on the grid (all
## five within 150 m), "pack" in among them down the start straight.
func _bench(what: String) -> void:
	var race = seat.race
	var vp := root.get_viewport_rid()
	var gpu := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var prims := PackedFloat64Array()
	_seat_camera()
	for lap in 3:
		seat.sim.restart()
		if race:
			race.grid()
			if what == "pack":
				race.go()
		for frame in 240:
			if what == "pack":
				# in among them down the start straight: away from his own grid place as they are from theirs
				# (the same frames with or without them)
				var t := frame * STEP
				_pose_player(60.0 * t * t, 0.0, 120.0 * t)
			var begin := Time.get_ticks_usec()
			seat._process(STEP)
			var update_ms := (Time.get_ticks_usec() - begin) / 1000.0
			await process_frame
			if lap == 2:
				cpu.append(update_ms)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var result := {"what": what, "pilots": race.pilots.size() if race else 0, "viewport": str(root.size), "frames": cpu.size(),
		"view_update_ms": _stats(cpu), "viewport_gpu_ms": _stats(gpu), "draw_calls": _stats(draws), "primitives": _stats(prims)}
	print("RACE_BENCH ", JSON.stringify(result))
	var output := FileAccess.open(out_dir.path_join("timing-%s.json" % what), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))


func _stats(values: PackedFloat64Array) -> Dictionary:
	values.sort()
	return {"p50": values[int(values.size() * 0.50)], "p95": values[int(values.size() * 0.95)], "max": values[-1]}


func _film_frame(dir: String, k: int) -> void:
	await RenderingServer.frame_post_draw
	if k == 0:
		print("FIRST_FILM_FRAME ", Engine.get_frames_drawn())
	if root.get_texture().get_image().save_png(dir.path_join("f%04d.png" % k)) != OK:
		failed = true
		push_error("Could not write frame %d" % k)


func _film(what: String) -> void:
	var race = seat.race
	var dir := out_dir.path_join("film-" + what)
	DirAccess.make_dir_recursive_absolute(dir)
	var shot := 0
	if what == "start":
		seat.sim.restart()
		race.grid()
		_seat_camera()
		for frame in int(9.0 / STEP):
			var t := maxf(0.0, frame * STEP - Race.COUNTDOWN)
			if t > 0.0:      # (along his own getaway from this line)
				var away := _his_start(t)
				_pose_player(away.x, 0.0, away.y)
			seat._process(STEP)
			var here: float = float(race.me.s)
			if t > 1.75:
				_outside(here - 75.0, -30.0, 27.0, here + 120.0, 4.0, 1.0)
			await process_frame
			if frame % 4 == 0:
				await _film_frame(dir, shot)
				shot += 1
	elif what == "pass":
		_duel_grid()
		for frame in int(8.0 / STEP):
			_duel_step(frame * STEP)
			await process_frame
			if frame % 4 == 0:
				await _film_frame(dir, shot)
				shot += 1
	print("RACE_FILM %s: %d frames in %s" % [what, shot, dir])
