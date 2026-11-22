## A film of what has been built and not yet flown, for looking at without a headset: one scene a
## run, recorded by the engine's movie writer with the game's own sound. Run windowed:
## --xr-mode off --resolution 1280x720 --fixed-fps 60 --write-movie FILE.avi
## -s res://tests/film_unflown.gd -- --out=DIR --scene=start|climb|snow|sweep|hyperion
## The world streams in before the scene begins: FILM_BEGIN and FILM_END give the seconds of the film
## to keep, FILM lines the captions and FILMT lines where the craft was, twice a second.
## start is worked through the start-up's own calls and then flown on the levers; climb is flown
## through the sim by a hand that holds a speed (levers and air brakes); snow is a camera pass along
## the road, not a flight (its caption says so). A flat picture from the seat is not the headset:
## this shows what is there, not how it feels.
extends "res://tests/render_terminal_art.gd"

const Sequence := preload("res://vr/startup_sequence.gd")
const Controls := preload("res://input/quest_controls.gd")
const DT := 1.0 / 60.0
const LEVEL := Vector3(3, 0, 0)
const TURN := 54.0       # frames a turn of the head takes
var levers := [0.0, 0.0]
var brakes := [0.0, 0.0]
var caption: Label
var frames := 0          # frames shown since the run began: the film's clock
var _busiest := 0.0      # the road builder's longest frame since the last FILMT line (ms), and the most chunks it had waiting
var _waiting := 0


func _frame() -> void:
	frames += 1
	await process_frame


func _say(text: String) -> void:
	caption.text = text
	caption.visible = not text.is_empty()
	print("FILM %.2f s: %s" % [frames * DT, text])


## One frame in the cockpit: the start-up stepped as the hands would step it, the craft flown on
## `levers` and `brakes`.
func _tick() -> void:
	var s = seat.startup
	seat.inp = {"thrL": levers[0], "thrR": levers[1], "brkL": brakes[0], "brkR": brakes[1], "repair": false, "reignite": false}
	s.gears = true
	s.step(DT, levers, 1)
	seat._apply_startup(DT)
	seat._process(DT)
	seat.approach_display._process(DT)
	if seat.network_world != null:
		_busiest = maxf(_busiest, float(seat.network_world.sync_ms))
		_waiting = maxi(_waiting, int(seat.network_world.wanted))
	if frames % 30 == 0:      # where the craft is, twice a second (for timing the scenes)
		var b = seat.sim.pod
		print("FILMT %.2f s: %s sample %d, deck %.0f m%s, %.0f mph, levers %.2f, brakes %.2f; roads %.1f ms a frame at most, %d chunks waiting" % [frames * DT, seat.sim.roads[b.path].name, b.hint,
			seat.sim.net_height(b.path, float(b.hint)), " (off the road)" if b.off_road else "", _mph(), levers[0], brakes[0], _busiest, _waiting])
		_busiest = 0.0
		_waiting = 0
	await _frame()


func _mph() -> float:
	var b = seat.sim.pod
	return sqrt(b.vx * b.vx + b.vy * b.vy) * 2.23694


## A stretch of time, the head turned toward `look` (degrees: up, left) and leant to `lean` (metres
## from the seated eye) over its first second.
func _roll(seconds: float, look = null, lean = null) -> void:
	var from: Vector3 = seat.cam.rotation_degrees
	var from_at: Vector3 = seat.cam.position
	for f in roundi(seconds / DT):
		var k := smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN))
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, k)
		if lean != null:
			seat.cam.position = from_at.lerp(lean, k)
		await _tick()


## Fly on to a sample of the road the craft is on, a hand on the levers and air brakes holding `mph`.
func _fly_to(sample: int, mph: float, look = null, limit := 40.0) -> void:
	var from: Vector3 = seat.cam.rotation_degrees
	var f := 0
	while seat.sim.pod.hint < sample and f < roundi(limit / DT):
		var v := _mph()
		var lever := clampf(0.45 + (mph - v) / 300.0, 0.0, 1.0)
		var brake := clampf((v - mph - 120.0) / 300.0, 0.0, 1.0)
		levers = [lever, lever]
		brakes = [brake, brake]
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN)))
		await _tick()
		f += 1


## Fly on to a sample of the road the craft is on and stop there: a hand that holds the speed a steady
## 25 m/s2 of braking would stop from in the distance left.
func _stop_at(sample: int, look = null, limit := 40.0) -> void:
	var from: Vector3 = seat.cam.rotation_degrees
	var f := 0
	while f < roundi(limit / DT):
		var left: float = (float(sample) - float(seat.sim._road_f(seat.sim.pod))) * float(seat.sim.NET_STEP)
		var v := _mph() * 0.44704
		if left < 0.5 or (left < 6.0 and v < 0.5):
			break
		var want := sqrt(50.0 * maxf(left, 0.0))
		levers = [clampf((want - v) / 20.0, 0.0, 0.5), clampf((want - v) / 20.0, 0.0, 0.5)]
		brakes = [clampf((v - want) / 12.0, 0.0, 1.0), clampf((v - want) / 12.0, 0.0, 1.0)]
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, smoothstep(0.0, 1.0, minf(1.0, (f + 1) / TURN)))
		await _tick()
		f += 1
	levers = [0.0, 0.0]
	brakes = [1.0, 1.0]


## The camera carried along a road at a steady speed, `right` metres off its centre line (no flight:
## the craft is set down afresh each frame).
func _glide(road_i: int, from_i: float, to_i: float, mph: float, right: float, look = null) -> void:
	var road = seat.sim.roads[road_i]
	var from: Vector3 = seat.cam.rotation_degrees
	var at := from_i
	var f := 0
	while at < to_i and int(at) + 2 < road.N:
		var i := int(at)
		var dx: float = road.px[i + 1] - road.px[i]
		var dy: float = road.py[i + 1] - road.py[i]
		var d := maxf(sqrt(dx * dx + dy * dy), 0.01)
		var v := mph * 0.44704
		seat.sim.respawn_on(road_i, i, 1, right)
		seat._ride.clear()
		for body in seat.sim.bodies:
			body.x += dx * (at - i)
			body.y += dy * (at - i)
			body.vx = dx / d * v
			body.vy = dy / d * v
		if look != null:
			seat.cam.rotation_degrees = from.lerp(look, smoothstep(0.0, 1.0, minf(1.0, f / TURN)))
		seat.inp = {"thrL": 0.5, "thrR": 0.5, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false}
		seat._process(DT)
		await _frame()
		at += v * DT / d
		f += 1


## A new flight at a spot, as a menu would start it, and the world brought in round it.
func _begin(spot: String, cold: bool, pad: bool) -> bool:
	Seat._nose_loaded = true
	Seat._camera_loaded = true
	Seat._startup_loaded = true
	Seat.camera = "cockpit"
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = spot
	Seat.pad_start = pad
	Seat.best_dir = out_dir.path_join("review_")
	Seat.cold_start = true
	Seat.cold_on_entry = cold
	seat = Seat.new()
	root.add_child(seat)
	if seat.cam == null or seat.overhead == null or seat.startup_audio == null or (pad and seat.pad == null):
		push_error("This needs the roofed cockpit, its sound, and a pad where one was asked for.")
		return false
	seat.set_process(false)
	seat.approach_display.process_mode = Node.PROCESS_MODE_DISABLED      # (stepped in _tick)
	seat.cruise = 0.0
	await _settle()
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation_degrees = LEVEL
	return true


func _settle() -> void:
	var world = seat.network_world
	for i in 6000:
		world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 60 == 0:
			await _frame()
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break


func _run() -> void:
	var scene := "start"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "snow" if scene == "snow" else "fair"
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
		"start":
			ok = await _start()
		"climb":
			ok = await _climb()
		"snow":
			ok = await _snow()
		"sweep":
			ok = await _sweep()
		"hyperion":
			ok = await _hyperion()
		_:
			push_error("No such scene: " + scene)
			ok = false
	if ok:
		print("FILM_END %.3f" % (frames * DT))
	if seat:
		seat.free()
	quit(0 if ok else 1)


## A cold start on a pad at the foot of Helios, worked switch by switch, and away.
func _start() -> bool:
	if not await _begin("SHelios@1540", true, true):
		return false
	var s = seat.startup
	seat._turbine_lamp = false
	await _roll(0.4)
	print("FILM_BEGIN %.3f" % (frames * DT))
	var left_pod := [Vector3(40, 30, 0), Vector3(-0.1, 0.13, -0.1)]       # the head tipped back and leant toward a pod
	var right_pod := [Vector3(40, -30, 0), Vector3(0.1, 0.13, -0.1)]
	var dash := Vector3(-11, 0, 0)
	_say("A cold start on a starting pad. Everything is dark but the standby lamp.")
	await _roll(2.2, left_pod[0], left_pod[1])
	_say("1 BATT: the contactor, the fans winding up, the self-test.")
	await _roll(0.9)
	s.flick("batt", 1)
	await _roll(1.5)
	await _roll(Sequence.SELFTEST_S + 0.4, dash, Vector3.ZERO)
	_say("2 ENGINE: lift the red guard, throw the switch. Fuel pumps prime, the binder strikes.")
	await _roll(1.4, left_pod[0], left_pod[1])
	s.flick("engine", 1)
	await _roll(1.0)
	s.flick("engine", 1)
	await _roll(Sequence.GUARD_AFTER_S + 1.4)
	_say("3 START: the left engine, then the right.")
	await _roll(1.3, right_pod[0], right_pod[1])
	s.press_start(0.0)
	await _roll(1.1)
	await _roll(Sequence.STAGGER_S + Sequence.CRANK_S + Sequence.CATCH_S + 1.4, Vector3(8, 0, 0), Vector3.ZERO)
	_say("4 The run-up: both levers held against the parking brake.")
	levers = [1.0, 1.0]
	await _roll(Sequence.TURBINE_UP_S + 0.6, dash)
	for key in s.checks:
		s.checks[key] = true
	levers = [0.0, 0.0]
	await _roll(Sequence.TURBINE_DOWN_S + 0.5, LEVEL)
	_say("5 PARK released: cleared.")
	await _roll(1.2, right_pod[0], right_pod[1])
	s.flick("park", -1)
	await _roll(1.6)
	_say("Both levers forward. The g-meter is the small dial on the centre gauge.")
	await _roll(1.0, dash, Vector3.ZERO)
	levers = [1.0, 1.0]
	await _roll(2.6)
	await _roll(1.5, LEVEL)
	return true


## Up the face of Helios, over the rim, and across the plateau under the Sun Gate. (The face begins
## at about sample 6,887 of its road and is steepest near 7,000; the rim is at 7,104, the plateau's
## centre and the gate at 7,244.)
func _climb() -> bool:
	if not await _begin("SHelios@6850", false, false):
		return false
	await _roll(0.5)
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("Helios, from the foot of its face at 9 km. The road goes straight up it.")
	await _roll(2.2)
	await _fly_to(6925, 1500.0)
	_say("The face steepens from 15 degrees to a 75 degree wall.")
	await _fly_to(6962, 950.0)
	_say("On the wall. Ahead it reads as road; the height shows out of the side.")
	await _fly_to(7015, 850.0, Vector3(8, 82, 0))
	await _fly_to(7060, 850.0, LEVEL)
	_say("Over the rim, onto the plateau at 16 km. The Sun Gate is ahead.")
	await _fly_to(7185, 1200.0)
	await _fly_to(7225, 420.0)
	_say("The roof is open overhead. Up here the sky is dark and the stars are out by day.")
	await _fly_to(7262, 420.0, Vector3(58, 0, 0))
	await _fly_to(7290, 420.0, LEVEL)
	return true


## Snow, and an exit's lane: a camera pass down the lane on a main road, through the exit's mouth and on
## along the exit's own road, where the rails go.
func _snow() -> bool:
	if not await _begin("N3@300", false, false):
		return false
	var best := []
	var where := -1
	for r: int in seat.network_world.exit_lanes:
		var name := String(seat.sim.roads[r].name)
		if not (name.begins_with("N") or name.begins_with("E")):
			continue
		for lane: Array in seat.network_world.exit_lanes[r]:
			# (an exit taken the way the road's samples run, onto a road that begins there)
			if int(lane[2]) > 0 and int(lane[4]) == int(lane[1]) and int(lane[5]) >= 0 and (best.is_empty() or int(lane[1]) - int(lane[0]) > int(best[1]) - int(best[0])):
				for on: Array in seat.network_world.exit_lanes.get(int(lane[5]), []):
					if int(on[5]) < 0 and int(on[0]) == 0:
						best = lane
						where = r
	if best.is_empty():
		push_error("No exit lane found to film.")
		return false
	var first := maxf(float(best[0]) - 12.0, 2.0)
	var mouth := float(best[4])
	var exit_road := int(best[5])
	var in_lane: float = -float(best[3])      # (the lane's middle is given in metres left of the centre line; the craft is set down in metres right)
	print("FILM lane on %s: samples %d to %d, mouth %d, %.0f m right of the centre line, on to %s" % [seat.sim.roads[where].name, best[0], best[1], best[4], in_lane, seat.sim.roads[exit_road].name])
	seat.sim.respawn_on(where, int(first), 1)
	await _settle()
	seat.cam.rotation_degrees = LEVEL
	await _glide(where, first, first + 2.0, 900.0, 0.0)
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("Snow, the sixth weather. (A camera pass, not a flight.)")
	var third := (mouth - first) / 3.0
	await _glide(where, first + 2.0, first + third, 1400.0, 0.0)
	_say("An exit's lane: green rails and arrows for 8 km before it, solid for the last 3.")
	await _glide(where, first + third, mouth, 1400.0, in_lane)
	_say("The rails carry on along the exit itself: held, they take the craft off the highway.")
	await _glide(exit_road, 0.0, 150.0, 1100.0, 0.0)
	return true


## Mount Hyperion, flown through the sim from 2 km short of its ramp: the ramp (its foot is sample 1,874
## of its road, 30 degrees at 2,856, 45 at 3,347, 60 at 3,838, 75 at 4,329), the braking section (the wall
## from 4,754, the crest from 4,824), the summit (5,016 to 5,216, the stop line at 5,116), the lip (to
## 5,235; the stop line at 5,204, the brink's mark at 5,221), the wall down (to 6,580) and the run-out (to
## 7,604). How long each takes is the point: the craft's speed is its speed along the deck there.
func _hyperion() -> bool:
	if not await _begin("SHyperion@1790", false, false):
		return false
	var out_left := Vector3(-4, 78, 0)
	await _roll(0.5)
	print("FILM_BEGIN %.3f" % (frames * DT))
	_say("Mount Hyperion, 48 km high, from 2 km short of its ramp. The road goes straight over it.")
	await _roll(3.0, Vector3(14, 0, 0))
	await _fly_to(2100, 4600.0, LEVEL, 30.0)
	_say("The ramp: 69 km of deck, its pitch rising by the same angle every metre, to 88 degrees.")
	await _fly_to(2856, 4600.0, null, 40.0)
	_say("30 degrees, 6 km up. The speed on the dial is the speed along the deck.")
	await _fly_to(3200, 4600.0, null, 30.0)
	_say("45 degrees, 13 km up. Out of the left side.")
	await _fly_to(3520, 4600.0, out_left, 30.0)
	await _fly_to(3838, 4600.0, LEVEL, 30.0)
	_say("60 degrees, 22 km up.")
	await _fly_to(4329, 4600.0, null, 30.0)
	_say("75 degrees, 33 km up. The sky is black and the stars are out.")
	await _fly_to(4560, 4600.0, Vector3(30, 0, 0), 30.0)
	await _fly_to(4735, 4600.0, LEVEL, 30.0)
	_say("The braking section: the last of the wall and the crest, 6.3 km. Boards count down to the summit.")
	await _fly_to(4930, 1500.0, null, 30.0)
	await _fly_to(5016, 600.0, null, 30.0)
	_say("Over the crest onto the summit, 48 km up: 4.8 km of level road to the cliff.")
	await _fly_to(5110, 700.0, null, 40.0)
	await _stop_at(5203)
	_say("The stop line, 290 m short of the cliff. Over the air the sky is black to a thin line of it.")
	await _roll(3.5, Vector3(0, 80, 0))
	_say("Out of the right side.")
	await _roll(3.5, Vector3(0, -80, 0))
	_say("Straight up.")
	await _roll(3.0, Vector3(70, 0, 0))
	brakes = [0.0, 0.0]
	_say("Creeping on to the brink.")
	await _fly_to(5212, 60.0, LEVEL, 40.0)
	await _stop_at(5221)
	_say("The brink, 24 degrees nose down on the lip: the country, 48 km below.")
	await _roll(4.0)
	_say("Out of the left side.")
	await _roll(3.0, Vector3(-4, 80, 0))
	await _roll(1.2, LEVEL)
	brakes = [0.0, 0.0]
	_say("Over the lip at 60 mph: a quarter turn in 460 m of deck.")
	await _fly_to(5237, 60.0, null, 60.0)
	_say("88 degrees down, and 47 km of wall under the nose.")
	await _roll(2.0)
	await _fly_to(5700, 4800.0, null, 40.0)
	_say("The wall down: 32 km of it.")
	await _fly_to(6100, 4800.0, out_left, 30.0)
	await _fly_to(6580, 4800.0, LEVEL, 30.0)
	_say("The run-out: 25 km to level.")
	await _fly_to(7604, 4800.0, null, 40.0)
	_say("Level again, and 114 km of straight to E3.")
	await _fly_to(7800, 4000.0, null, 20.0)
	return true


## The engines against speed, for listening: full levers held and the craft carried along a straight
## main road with its speed swept evenly from rest to 5,600 mph in 45 s, the trigger scheme's gearbox
## shifted up at each gear's top speed as a pilot shifts it (a camera pass: the sound follows the
## levers, the gears and the speed it is given, the craft does not fly). Gear and speed are in the caption.
func _sweep() -> bool:
	if not await _begin("E3@9000", false, false):
		return false
	var road_i := -1
	for r in seat.sim.roads.size():
		if String(seat.sim.roads[r].name) == "E3":
			road_i = r
	var road = seat.sim.roads[road_i]
	var at := 9000.0
	seat.cam.rotation_degrees = LEVEL
	print("FILM_BEGIN %.3f" % (frames * DT))
	var total := roundi(45.0 / DT)
	for f in total:
		var mph := 5600.0 * f / float(total)
		var i := int(at)
		var dx: float = road.px[i + 1] - road.px[i]
		var dy: float = road.py[i + 1] - road.py[i]
		var d := maxf(sqrt(dx * dx + dy * dy), 0.01)
		var v := mph * 0.44704
		seat.sim.respawn_on(road_i, i, 1)
		seat._ride.clear()
		for body in seat.sim.bodies:
			body.x += dx * (at - i)
			body.y += dy * (at - i)
			body.vx = dx / d * v
			body.vy = dy / d * v
		# the trigger scheme's gearbox as a pilot works it: up a gear at each gear's top speed, fourth winding on
		var gear := 4
		for g in range(1, 5):
			if v <= float(Controls.GEARS[g][2]) * Controls.V_TOP_SPEED:
				gear = g
				break
		var x: float = v / (float(Controls.GEARS[gear][2]) * Controls.V_TOP_SPEED)
		var revs: float = x if gear < 4 or x <= 1.0 else 1.0 + log(x)
		var lever: float = seat.sim.P.gate * 0.995
		seat.inp = {"thrL": lever, "thrR": lever, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": false,
			"gearRpm": revs, "gearIndex": gear, "gearOverdrive": gear == 4, "thrMul": 1.0}
		seat._process(DT)
		if f % 30 == 0:
			_say("Full levers, gear %d, %d mph" % [gear, roundi(mph / 100.0) * 100])
			var ea = seat.engine_audio
			print("FILMS %.2f s: %.0f mph, gear %d revs %.2f, stage %.2f, temper %.2f, turbines on %s, v8 at %.0f rpm" % [frames * DT, mph, gear, revs, ea.stage, ea.anger, ea.turbines_on, float(ea.voices[0].at.v8)])
		await _frame()
		at += v * DT / d
		if int(at) + 3 >= road.N:
			break
	return true
