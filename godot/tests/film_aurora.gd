## A film of the Aurora line's takeoff and landing areas (view/aurora_stations.gd), for looking at
## without a headset: one scene a run, recorded by the engine's movie writer with the game's own
## sound, as tests/film_unflown.gd is. Run windowed:
## --xr-mode off --resolution 1280x720 --fixed-fps 60 --write-movie FILE.avi
## -s res://tests/film_aurora.gd -- --out=DIR --scene=takeoff|arrival [--time=night]
##   takeoff   to the southwest lock by road, stopped under the gate, the lock's cycle, and away
##             into the tube
##   arrival   set down inside the tube 20 km from the northeast lock's bar at CRUISE mph, the most
##             the craft holds there as the sim stands (the film does not fly the whole line, and it
##             puts in the run's time itself), braked by the rings, out through the seal and
##             stopped under the gate
## Both are flown through the sim by a hand on the levers and the air brakes. FILM_BEGIN and
## FILM_END give the seconds of the film to keep, FILM lines the captions, FILMT lines where the
## craft was twice a second. A flat picture from the seat is not the headset: this shows what is
## there, not how it feels.
extends "res://tests/render_terminal_art.gd"

const Sim := preload("res://sim/craft_sim.gd")
const Stations := preload("res://view/aurora_stations.gd")
const DT := 1.0 / 60.0
const LEVEL := Vector3(4, 0, 0)
const TURN := 54.0       # frames a turn of the head takes
const CRUISE := 5300.0   # mph: what full levers hold in the tube today (tests/probe_aurora_brakes.gd's sim)
const SAMPLE_M := 24.0   # the Aurora road's samples are about this far apart (_begin checks it: a scene only has to begin near enough)
var levers := [0.0, 0.0]
var brakes := [0.0, 0.0]
var caption: Label
var frames := 0          # frames shown since the run began: the film's clock
var st
var road_i := 0
var road
var ends := []


func _frame() -> void:
	frames += 1
	await process_frame


func _say(text: String) -> void:
	caption.text = text
	caption.visible = not text.is_empty()
	print("FILM %.2f s: %s" % [frames * DT, text])


func _mph() -> float:
	var b = seat.sim.pod
	return sqrt(b.vx * b.vx + b.vy * b.vy) * 2.23694


## One frame in the cockpit, the craft flown on `levers` and `brakes`.
func _tick() -> void:
	var s = seat.startup
	seat.inp = {"thrL": levers[0], "thrR": levers[1], "brkL": brakes[0], "brkR": brakes[1], "repair": false, "reignite": false}
	if s != null:
		s.gears = true
		s.step(DT, levers, 1)
		seat._apply_startup(DT)
	seat._process(DT)
	if seat.approach_display != null:
		seat.approach_display._process(DT)
	if frames % 30 == 0:
		var lock: Dictionary = st.locks[0] if seat.sim.pod.hint < (int(ends[0]) + int(ends[1])) / 2 else st.locks[1]
		print("FILMT %.2f s: sample %d, %.0f mph, levers %.2f, brakes %.2f, lock state %d at %.1f s, braking %d" % [frames * DT, seat.sim.pod.hint, _mph(), levers[0], brakes[0], lock.state, lock.t, st.braking])
	await _frame()


## A stretch of time, the head turned toward `look` (degrees: up, left) over its first second.
func _roll(seconds: float, look = null) -> void:
	var from: Vector3 = seat.cam.rotation_degrees
	for f in roundi(seconds / DT):
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN)))
		await _tick()


## Metres still to go to lock k's bar, for a craft heading in (by road) or coming out (through the tube).
func _to_bar(k: int, heading_in: bool) -> float:
	var inside: float = st.craft_at(k)[0]
	return -(inside + Stations.BAR) if heading_in else inside + Stations.BAR


## The last of the way to a bar: a hand that slows the craft at about 1 g over the last of the road
## and stops it on the bar. True once it is stopped on the pad.
func _stop_at_bar(k: int, heading_in: bool, cap: float, look = null, limit := 40.0) -> bool:
	var from: Vector3 = seat.cam.rotation_degrees
	for f in roundi(limit / DT):
		var go := _to_bar(k, heading_in)
		var v: float = st.craft_at(k)[3]
		var want := minf(sqrt(2.0 * 10.0 * maxf(go - 2.0, 0.0)), cap)
		var lever := clampf((want - v) / 250.0, 0.0, 0.15) if want > v + 0.5 else 0.0
		var brake := clampf((v - want) / 8.0, 0.0, 1.0) if v > want + 0.5 else 0.0
		if go < 6.0:
			lever = 0.0
			brake = 1.0
		levers = [lever, lever]
		brakes = [brake, brake]
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN)))
		await _tick()
		if go < 12.0 and v < Stations.STOPPED * 0.6:
			levers = [0.0, 0.0]
			brakes = [1.0, 1.0]
			return true
	return false


## The speed (mph) a craft `metres` short of the bar may still have and stop on it in five eighths
## of the way (the rings stay amber for a hand that brakes like this, and never turn red).
func _may(metres: float) -> float:
	var lo := 0.0
	var hi := 12000.0
	for i in 24:
		var mid := (lo + hi) * 0.5
		if Stations.stop_km(mid) * 1600.0 < metres:
			lo = mid
		else:
			hi = mid
	return lo


## A new flight on the Aurora road at a sample, heading northeast, the world brought in round it.
func _begin(sample: int) -> bool:
	Seat._nose_loaded = true
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = "SAurora@%d" % sample
	Seat.pad_start = false
	Seat.best_dir = out_dir.path_join("review_")
	Seat.cold_start = true
	Seat.cold_on_entry = false
	seat = Seat.new()
	root.add_child(seat)
	var line = seat.network_world.pressure_line if seat.network_world != null else null
	if seat.cam == null or line == null or line.get("stations") == null:
		push_error("This needs the cockpit on the Network, and the Aurora line with its stations.")
		return false
	st = line.stations
	road_i = int(Sim.NET_PRESSURE[0])
	road = seat.sim.roads[road_i]
	ends = [int(Sim.NET_PRESSURE[1]), int(Sim.NET_PRESSURE[2])]
	if absf(float(road.len[sample]) - SAMPLE_M) > 0.25:
		push_error("The Aurora road's samples are %.2f m apart here, not %.0f." % [float(road.len[sample]), SAMPLE_M])
		return false
	seat.set_process(false)
	if seat.approach_display != null:
		seat.approach_display.process_mode = Node.PROCESS_MODE_DISABLED      # (stepped in _tick)
	seat.cruise = 0.0
	seat.sim.respawn_on(road_i, sample, 1)
	seat._ride.clear()
	st.reset()
	var world = seat.network_world
	for i in 6000:
		world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 60 == 0:
			await _frame()
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation_degrees = LEVEL
	return true


func _run() -> void:
	var scene := "takeoff"
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 24)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.6)
	box.set_content_margin_all(9)
	caption.add_theme_stylebox_override("normal", box)
	caption.position = Vector2(28, root.size.y - 62)
	caption.visible = false
	layer.add_child(caption)
	var ok := true
	match scene:
		"takeoff":
			ok = await _takeoff()
		"arrival":
			ok = await _arrival()
		_:
			push_error("No such scene: " + scene)
			ok = false
	if ok:
		print("FILM_END %.3f" % (frames * DT))
	if seat:
		seat.free()
	quit(0 if ok else 1)


## To the southwest lock by road, stopped under the gate, the cycle, and away.
func _takeoff() -> bool:
	if not await _begin(int(Sim.NET_PRESSURE[1]) - roundi((Stations.BAR + 760.0) / SAMPLE_M)):
		return false
	var lock: Dictionary = st.locks[0]
	await _roll(0.5)
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("The Aurora line's southwest lock, by road. The sign over the road says where to stop.")
	var from: Vector3 = seat.cam.rotation_degrees
	var f := 0
	while _to_bar(0, true) > 330.0 and f < 1500:      # up the road at a steady 140 mph
		var lever := clampf((62.0 - float(st.craft_at(0)[3])) / 250.0, 0.0, 0.15)
		levers = [lever, lever]
		brakes = [0.0, 0.0]
		seat.cam.rotation_degrees = from.lerp(Vector3(9, 0, 0), smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN)))
		await _tick()
		f += 1
	_say("The red gate stands over the stop bar, 400 m short of the seal.")
	if not await _stop_at_bar(0, true, 62.0, Vector3(8, 0, 0)):
		push_error("The craft did not stop on the southwest pad (%.0f m to go at %.0f mph)." % [_to_bar(0, true), _mph()])
		return false
	_say("Stopped under it: bar, gate and pylons go green, and the lock's rings turn and latch.")
	f = 0
	while int(lock.state) != Stations.CYCLE and f < 240:
		await _tick()
		f += 1
	if int(lock.state) != Stations.CYCLE:
		push_error("The lock did not begin its cycle for a craft stopped on the pad.")
		return false
	await _roll(Stations.LATCH_S, Vector3(15, 0, 0))
	_say("An iris of light closes across the bore.")
	await _roll(Stations.SEAL_S)
	_say("The pressure comes up to 101 kPa: the arc of lights over the lock fills.")
	await _roll(Stations.FILL_S, Vector3(24, 0, 0))
	_say("The iris opens. Clear.")
	await _roll(Stations.OPEN_S + 1.6, Vector3(13, 0, 0))
	if int(lock.state) != Stations.CLEAR:
		push_error("The lock was not clear after its cycle (state %d)." % int(lock.state))
		return false
	_say("Both levers forward: through the seal and into the tube.")
	brakes = [0.0, 0.0]
	levers = [1.0, 1.0]
	await _roll(1.2, LEVEL)
	f = 0
	while float(st.craft_at(0)[0]) < 2600.0 and f < 900:
		await _tick()
		f += 1
	return true


## Out of the tube at the northeast lock: braked by the rings, through the seal, stopped under the gate.
func _arrival() -> bool:
	var start := int(Sim.NET_PRESSURE[2]) - roundi((20000.0 - Stations.BAR) / SAMPLE_M)
	if not await _begin(start):
		return false
	var lock: Dictionary = st.locks[1]
	var v := CRUISE * 0.44704
	for b in seat.sim.bodies:
		b.vx = road.tx[start] * v
		b.vy = road.ty[start] * v
	# (the run this would have been the end of, at that speed: the film says so)
	st.trip = {"from": 0, "t0": float(seat.sim.time) - 768000.0 / v, "top": CRUISE}
	levers = [1.0, 1.0]
	await _tick()
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("In the tube at %s mph, 20 km from the northeast lock's bar (set down here: the film does not fly the line)." % st._thousands(roundi(CRUISE)))
	var said := {}
	var f := 0
	while _to_bar(1, false) > 420.0 and f < 3600:
		var go := _to_bar(1, false)
		var mph := _mph()
		var may := minf(maxf(_may(go), 140.0), CRUISE)
		if go < 1500.0:                      # ... and gently through the seal
			may = minf(may, 150.0 + go * 0.35)
		var brake := clampf((mph - may) / (0.05 * may + 30.0), 0.0, 1.0)
		var lever := clampf((may - mph) / 300.0, 0.0, 1.0) if go > 1500.0 else clampf((may - mph - 40.0) / 2000.0, 0.0, 0.15)
		levers = [lever, lever]
		brakes = [brake, brake]
		if st.braking == 1 and not said.has("amber"):
			said.amber = true
			_say("Rings round the hull count down to the bar: 10 km, 5, 2, 1. Amber: brake now.")
		if brake > 0.3 and not said.has("brakes"):
			said.brakes = true
			_say("Levers shut, air brakes out. The rings stay amber while there is road enough to stop.")
		if go < 2300.0 and not said.has("two"):
			said.two = true
			_say("2 km. Strips of light under the glass run to the bar.")
		if float(st.craft_at(1)[0]) < 40.0 and not said.has("seal"):
			said.seal = true
			_say("Out through the seal. The red gate is the bar, 400 m on.")
		await _tick()
		f += 1
	if not said.has("seal"):
		_say("Out through the seal. The red gate is the bar, 400 m on.")
	if not await _stop_at_bar(1, false, 70.0, Vector3(9, 0, 0)):
		push_error("The craft did not stop on the northeast pad (%.0f m to go at %.0f mph)." % [_to_bar(1, false), _mph()])
		return false
	f = 0
	while int(lock.state) != Stations.LANDED and f < 240:
		await _tick()
		f += 1
	if int(lock.state) != Stations.LANDED:
		push_error("The lock did not take the craft as landed (state %d, arrival %s)." % [int(lock.state), st.arrival])
		return false
	_say("Stopped on the pad: landed. (The time shown is the film's own: it did not fly the line.)")
	await _roll(5.5, Vector3(15, 0, 0))
	return true
