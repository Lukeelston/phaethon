## The trailer's flying scenes (tools/trailer/README.md): the game flown through the sim and filmed from the seat and
## from outside, after film_unflown.gd, whose seat, hands and world set-up it uses. One scene a run, recorded by the
## engine's movie writer with the game's own sound:
##   --xr-mode off --resolution 1280x720 --fixed-fps 30 --write-movie DIR/f.png
##   -s res://tests/film_trailer.gd -- --out=DIR --scene=NAME [--preview=N]
## The sim is stepped at 60 a second and a picture drawn every second step (--fixed-fps 30: the film's 30).
## --preview=N draws only every Nth picture and saves it as DIR/<shot>-NNNN.jpg, without the movie writer.
## Each shot prints SHOT <name> begin|end <frame> (the engine's process frames: the movie's own numbering).
## Outside views are a camera carried with the craft, in the craft's own level frame: x to its right, y up, z aft
## (the engines are ahead of the pod, at about -16); the pilot in the seat is garage/pilot_model.gd's, as the flat view's.
## What is flown is the sim's own: levers, air brakes, the game's autopilot, the GUN switch and its trigger. What is
## staged is said where it is staged (a raid's pack put ahead on the craft's road, as tests/render_raids.gd puts it).
extends "res://tests/film_unflown.gd"

const RaidsScript := preload("res://view/network_raids.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const PilotModel := preload("res://garage/pilot_model.gd")
const MPH := 2.236936
const SUB := 2           # sim steps a picture

var preview := 0
var _shot := ""
var _shot_t := 0.0
var _view := Callable()  # an outside view's camera this step; empty: the seat's own
var _pilot: Node3D
var _seat_fov := 75.0
var _pictures := 0
var _heading := Basis.IDENTITY
var _fire := false       # the trigger held (view/gunnery.gd hold_fire)
var _gaze = null         # a raider the head is kept on (the Basilisk's turret follows the gaze)


func _frame() -> void:
	frames += 1
	_shot_t += DT
	if seat and seat.gunnery:
		seat.gunnery.hold_fire = _fire
	if _view.is_valid():
		_view.call(_shot_t)
	elif _gaze != null and seat.traffic_net.cars.has(_gaze):
		var rig: Transform3D = seat.rig.global_transform
		seat.cam.global_position = rig * Seat.EYE
		seat.cam.look_at(_gaze.lamp_position, rig.basis.y)
	if frames % SUB != 0:
		return
	if preview > 0:
		_pictures += 1
		var draw := _pictures % preview == 0 and not _shot.is_empty()
		RenderingServer.render_loop_enabled = draw
		await process_frame
		if draw:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_jpg(out_dir.path_join("%s-%04d.jpg" % [_shot, _pictures]), 0.9)
	else:
		await process_frame


## One step in the cockpit. With the game's autopilot flying, the cockpit reads its own (empty) hands and the autopilot's
## levers are what fly her (tests/render_autopilot.gd steps it so); otherwise film_unflown.gd's: flown on `levers`.
func _tick() -> void:
	if seat.autopilot != null and seat.autopilot.on:
		seat._process(DT)
		seat.approach_display._process(DT)
		await _frame()
	else:
		await super()


func _say(text: String) -> void:
	print("FILM %.2f s: %s" % [frames * DT, text])


# --- shots --------------------------------------------------------------------------------------------------------

func _cut(name: String, view := Callable(), lens := 0.0) -> void:
	if not _shot.is_empty():
		print("SHOT %s end %d" % [_shot, Engine.get_process_frames()])
	_shot = name
	_shot_t = 0.0
	_view = view
	var outside := view.is_valid()
	Seat.speed_rush = not outside
	if _pilot:
		_pilot.visible = outside
	if seat.chase_hud:
		seat.chase_hud.visible = false
	if not outside:
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation_degrees = LEVEL
		seat.cam.fov = lens if lens > 0.0 else _seat_fov
	if not name.is_empty():
		print("SHOT %s begin %d  (%.0f mph)" % [name, Engine.get_process_frames(), _mph()])


## The craft's level frame: at the cockpit's floor, heading the way the craft goes (eased, so a wag of the pod is seen
## as a wag); `level` false: the cockpit's own frame, for a wall or a shaft.
func _craft_frame(level: bool) -> Transform3D:
	var rig: Transform3D = seat.rig.global_transform
	if not level:
		return Transform3D(rig.basis.orthonormalized(), rig.origin)
	var fwd := -rig.basis.z
	fwd.y = 0.0
	var want := Basis.looking_at(fwd.normalized(), Vector3.UP) if fwd.length() > 0.05 else _heading
	_heading = _heading.slerp(want, 0.08).orthonormalized()
	return Transform3D(_heading, rig.origin)


## An outside view: the camera at `from` looking at `at` (the craft's frame), drifting to `to_from` and `to_at`
## over `secs`.
func _out(from: Vector3, at: Vector3, fov := 45.0, to_from = null, to_at = null, secs := 4.0, level := true) -> Callable:
	return func(t: float) -> void:
		var k := clampf(t / secs, 0.0, 1.0)
		var F := _craft_frame(level)
		var a: Vector3 = F * from.lerp(to_from if to_from != null else from, k)
		var b: Vector3 = F * at.lerp(to_at if to_at != null else at, k)
		seat.cam.global_transform = Transform3D(Basis.looking_at(b - a, F.basis.y), a)
		seat.cam.fov = fov


## An outside view in an engine's own frame (k 0 port, 1 starboard: x to its right, y up, z aft).
func _eng(k: int, from: Vector3, at: Vector3, fov := 45.0, to_from = null, secs := 4.0) -> Callable:
	return func(t: float) -> void:
		var E: Transform3D = seat.craft.engines[k].global_transform.orthonormalized()
		var a: Vector3 = E * from.lerp(to_from if to_from != null else from, clampf(t / secs, 0.0, 1.0))
		seat.cam.global_transform = Transform3D(Basis.looking_at(E * at - a, Vector3.UP), a)
		seat.cam.fov = fov


## An outside view from `from` (the craft's frame) looking at the raider the gaze is on: the turret is laid on the
## middle of the camera's view, so this is also where it fires.
func _out_gaze(from: Vector3, fov := 45.0, to_from = null, secs := 4.0) -> Callable:
	return func(t: float) -> void:
		var F := _craft_frame(true)
		var a: Vector3 = F * from.lerp(to_from if to_from != null else from, clampf(t / secs, 0.0, 1.0))
		var at: Vector3 = F * Vector3(0.0, 0.5, -300.0)
		if _gaze != null and seat.traffic_net.cars.has(_gaze):
			at = _gaze.lamp_position
		seat.cam.global_transform = Transform3D(Basis.looking_at(at - a, Vector3.UP), a)
		seat.cam.fov = fov


## From the seat, the head on a point of the cockpit (a switch), the lens narrowed.
func _seat_on(node: Node3D, fov := 38.0) -> Callable:
	return func(_t: float) -> void:
		var rig: Transform3D = seat.rig.global_transform
		seat.cam.global_position = rig * Seat.EYE
		seat.cam.look_at(node.global_position, rig.basis.y)
		seat.cam.fov = fov


# --- a flight -----------------------------------------------------------------------------------------------------

## A new flight at a spot (film_unflown.gd _begin), in a craft and a paint, at a time and in a weather, raids on or off.
func _open(spot: String, opts := {}) -> bool:
	Outlook.pinned = true
	Outlook.time = opts.get("time", "afternoon")
	Outlook.weather = opts.get("weather", "fair")
	Livery.pinned = true
	Livery.current = opts.get("paint", Livery.FACTORY)
	Chase.pinned = true
	Chase.enabled = false
	RaidsScript.pinned = true
	RaidsScript.enabled = bool(opts.get("raids", false))
	Seat.vehicle_override = opts.get("vehicle", "phaethon")
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat.map_whole = false
	Seat._school_loaded = true
	Seat.school = false
	Seat._rush_loaded = true
	Seat.speed_rush = true
	Seat._options_loaded = true
	Seat.consumables = false
	if not await _begin(spot, bool(opts.get("cold", false)), bool(opts.get("pad", false))):
		return false
	for child in seat.get_children():
		if child is CanvasLayer:
			child.hide()
	_seat_fov = float(opts.get("fov", 78.0))
	seat.cam.fov = _seat_fov
	_pilot = PilotModel.new()
	_pilot.name = "FilmPilot"
	_pilot.set_seat_vehicle(seat.sim.P.vehicle)
	_pilot.set_seated(true)
	seat.rig.add_child(_pilot)
	_pilot.position = Seat.EYE - _pilot.SEATED_EYE
	_pilot.visible = false
	_heading = Basis.looking_at(-(seat.rig.global_transform.basis.z * Vector3(1, 0, 1)).normalized(), Vector3.UP)
	print("FILM opened %s in %s (%s), %s %s; the seat's lens %.0f" % [spot, seat.sim.P.vehicle, Livery.current, Outlook.time, Outlook.weather, _seat_fov])
	return true


## Both levers at `lever` for `seconds` (1.0: through the burner's gate).
func _push(seconds: float, lever := 0.87, brake := 0.0) -> void:
	levers = [lever, lever]
	brakes = [brake, brake]
	await _roll(seconds)


## A hand holding `mph` for `seconds`.
func _keep(mph: float, seconds: float) -> void:
	for f in roundi(seconds / DT):
		var v := _mph()
		var lever := clampf(0.45 + (mph - v) / 300.0, 0.0, 1.0)
		var brake := clampf((v - mph - 120.0) / 300.0, 0.0, 1.0)
		levers = [lever, lever]
		brakes = [brake, brake]
		await _tick()


## The craft set going at `mph` along its road, as a flight arriving at a scene.
func _at_speed(mph: float) -> void:
	var sim = seat.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	var way := 1.0
	if absf(ShaftSim.wrap_angle(sim.pod.th - atan2(R.ty[i], R.tx[i]))) > PI / 2.0:
		way = -1.0
	for b in sim.bodies:
		b.vx = way * R.tx[i] * mph / MPH
		b.vy = way * R.ty[i] * mph / MPH


## The game's autopilot takes her, at `mph`.
func _auto(mph: float) -> bool:
	seat.cruise = -1.0      # (film_unflown.gd flies on given levers, which the cockpit takes as a cruise: no autopilot under one)
	var took: bool = seat.set_autopilot(true)
	seat.autopilot.set_cruise(mph / MPH)
	print("FILM autopilot %s: %s" % ["taken" if took else "REFUSED", seat.autopilot.message().replace("\n", " / ")])
	return took


# --- the run ------------------------------------------------------------------------------------------------------

func _run() -> void:
	var scene := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--scene="):
			scene = arg.trim_prefix("--scene=")
		elif arg.begins_with("--preview="):
			preview = int(arg.trim_prefix("--preview="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.visible = false
	layer.add_child(caption)
	var prefs_before := FileAccess.get_file_as_string(Seat.PREFS) if FileAccess.file_exists(Seat.PREFS) else ""
	var ok := false
	if has_method("_scene_" + scene):
		ok = await call("_scene_" + scene)
	else:
		push_error("No such scene: " + scene)
	_cut("")
	RenderingServer.render_loop_enabled = true
	if seat:
		seat.free()
	if prefs_before != "":
		var out := FileAccess.open(Seat.PREFS, FileAccess.WRITE)
		out.store_string(prefs_before)
		out.close()
	print("TRAILER %s %s" % [scene, "done" if ok else "FAILED"])
	quit(0 if ok else 1)


# --- scenes -------------------------------------------------------------------------------------------------------

## Stills round the craft at speed on E3, to choose the outside views from (not in the film).
func _scene_scout() -> bool:
	if not await _open("E3@9000", {"vehicle": "phaethon"}):
		return false
	_at_speed(2400.0)
	await _keep(2400.0, 2.0)
	var views := {
		"chase-low": [Vector3(0.0, 0.6, 9.0), Vector3(0.0, 0.8, -14.0), 62.0],
		"chase-high": [Vector3(4.0, 5.0, 16.0), Vector3(0.0, 0.0, -12.0), 55.0],
		"side": [Vector3(22.0, 1.0, -8.0), Vector3(0.0, 0.6, -8.0), 40.0],
		"side-low": [Vector3(12.0, -1.0, -3.0), Vector3(0.0, 0.8, -12.0), 55.0],
		"front34": [Vector3(11.0, 1.5, -34.0), Vector3(0.0, 0.5, -10.0), 42.0],
		"nose-low": [Vector3(2.0, -0.9, -30.0), Vector3(0.0, 0.8, -12.0), 50.0],
		"engine": [Vector3(6.5, 1.2, -11.0), Vector3(3.6, 0.2, -16.0), 50.0],
		"top": [Vector3(0.0, 26.0, -4.0), Vector3(0.0, 0.0, -9.0), 50.0],
		"pilot": [Vector3(2.6, 1.3, -3.2), Vector3(0.0, 0.9, 0.2), 50.0],
	}
	for name: String in views:
		var v: Array = views[name]
		_cut("scout-" + name, _out(v[0], v[1], v[2]))
		await _keep(2400.0, 2.0 * SUB * DT * maxi(preview, 1))
	_cut("scout-seat")
	await _keep(2400.0, 2.0 * SUB * DT * maxi(preview, 1))
	return true


## Out of the terminal at Eridanus: from the seat, the levers pushed through to the stop, then from outside.
func _scene_launch() -> bool:
	if not await _open("city:ERIDANUS", {"vehicle": "phaethon"}):
		return false
	await _push(0.6, 0.0, 1.0)
	_cut("launch-seat")
	await _push(1.0, 0.0, 1.0)
	await _push(3.6, 1.0)
	_cut("launch-low", _out(Vector3(5.5, 0.2, 8.0), Vector3(0.0, 0.6, -16.0), 56.0, Vector3(3.0, 1.2, 14.0), null, 3.0))
	await _push(3.0, 1.0)
	_cut("launch-side", _out(Vector3(15.0, 0.4, -30.0), Vector3(0.0, 0.6, -10.0), 42.0, Vector3(19.0, 1.6, 6.0), null, 3.2))
	await _push(3.2, 1.0)
	_cut("launch-seat-fast")
	await _push(3.0, 1.0)
	return true


## A highway at 3,000 mph and more, the game's autopilot flying her through the traffic: outside, and from the seat.
func _scene_highway() -> bool:
	if not await _open("N3@1500", {"vehicle": "phaethon"}):
		return false
	_at_speed(2600.0)
	if not _auto(3200.0):
		return false
	await _roll(4.0)
	_cut("highway-chase", _out(Vector3(5.0, 3.2, 20.0), Vector3(0.0, 0.6, -14.0), 55.0, Vector3(-4.0, 1.0, 11.0), null, 3.2))
	await _roll(3.2)
	_cut("highway-front", _out(Vector3(9.0, 0.8, -40.0), Vector3(0.0, 0.8, -10.0), 40.0, Vector3(3.0, -0.4, -30.0), null, 3.0))
	await _roll(3.0)
	_cut("highway-seat")
	await _roll(3.0)
	_cut("highway-side", _out(Vector3(24.0, 1.4, -14.0), Vector3(0.0, 0.6, -9.0), 38.0, Vector3(20.0, 0.6, 2.0), null, 3.0))
	await _roll(3.0)
	_cut("highway-pilot", _out(Vector3(2.8, 1.3, -3.6), Vector3(0.0, 0.9, 0.2), 50.0, Vector3(3.4, 1.0, -1.6), null, 2.6))
	await _roll(2.6)
	_cut("highway-top", _out(Vector3(0.0, 30.0, 6.0), Vector3(0.0, 0.0, -12.0), 55.0, Vector3(0.0, 16.0, 14.0), null, 2.6))
	await _roll(2.6)
	return true


## The face of Helios (film_unflown.gd _climb's stretch), from outside: the craft on a 75 degree wall.
func _scene_climb() -> bool:
	if not await _open("SHelios@6900", {"vehicle": "vesper", "paint": "star_command"}):
		return false
	await _roll(0.5)
	_cut("climb-foot")
	await _fly_to(6925, 1500.0, null, 3.0)
	_cut("climb-wall-side", _out(Vector3(26.0, 3.0, -4.0), Vector3(0.0, 0.5, -9.0), 46.0, Vector3(18.0, 1.0, 10.0), null, 5.0, false))
	await _fly_to(6990, 950.0, null, 4.0)
	_cut("climb-wall-seat")
	await _fly_to(7015, 850.0, Vector3(8, 82, 0), 3.5)
	_cut("climb-rim", _out(Vector3(-7.0, 2.5, 18.0), Vector3(0.0, 1.0, -12.0), 58.0, Vector3(5.0, 1.2, 12.0), null, 5.0, false))
	await _fly_to(7185, 1200.0, null, 3.5)
	return true


## One of Mount Hyperion's leaps (film_hyperion_leap.gd's): off the lip at 10,000 mph, from outside and from the seat.
func _scene_leap() -> bool:
	var sim_script = load("res://sim/craft_sim.gd")
	var lp: Array = sim_script.NET_LEAPS[0]
	var lane := int(lp[0])
	var lane_name: String = sim_script.NET_ROADS[lane][0]
	var probe = sim_script.new({"track": "network"})
	var from: int = int(probe.roads[lane].N) - 200
	probe = null
	if not await _open("%s@%d" % [lane_name, from], {"vehicle": "phaethon", "paint": "cobalt"}):
		return false
	var sim = seat.sim
	var R = sim.roads[lane]
	var v := 10000.0 / MPH
	sim.armed = true
	var flat := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": true, "gearOverdrive": true, "thrMul": 1.0, "gearIndex": 4}
	await _roll(0.5)
	for b in sim.bodies:
		b.vx = v * R.tx[from]
		b.vy = v * R.ty[from]
	_cut("leap-lane", _out(Vector3(4.0, 2.2, 15.0), Vector3(0.0, 0.8, -14.0), 62.0))
	var air := -1.0
	var caught := -1.0
	var t := 0.0
	var plan := [[0.8, "leap-side", _out(Vector3(34.0, 2.0, -20.0), Vector3(0.0, 0.0, -8.0), 40.0, Vector3(26.0, 6.0, 8.0), null, 3.4)],
		[4.2, "leap-seat", Callable()],
		[7.2, "leap-under", _out(Vector3(-10.0, -5.0, 10.0), Vector3(0.0, 0.5, -10.0), 55.0, Vector3(8.0, -3.0, 16.0), null, 3.2)],
		[10.4, "leap-high", _out(Vector3(6.0, 9.0, 24.0), Vector3(0.0, -1.0, -12.0), 50.0)]]
	while t < 26.0:
		await _leap_step(flat)
		t += DT
		var pod = sim.pod
		if air < 0.0 and not pod.off_road and int(pod.path) == lane:      # held to the figure as far as the lip
			var k := v / maxf(1.0, Vector2(pod.vx, pod.vy).length())
			for b in sim.bodies:
				b.vx *= k
				b.vy *= k
		if air < 0.0 and pod.off_road:
			air = t
			print("FILM off the lip at %.2f s" % t)
		if air >= 0.0 and not plan.is_empty() and t - air >= float(plan[0][0]):
			var step: Array = plan.pop_front()
			_cut(step[1], step[2])
		if air >= 0.0 and caught < 0.0 and not pod.off_road:
			caught = t
			print("FILM caught at %.2f s, %.1f s in the air" % [t, t - air])
			_cut("leap-caught", _out(Vector3(5.0, 3.0, 18.0), Vector3(0.0, 0.5, -14.0), 58.0))
		if (caught >= 0.0 and t - caught > 3.0) or (air >= 0.0 and t - air > 13.4):
			break
		if sim.crash_t > 0.0:
			print("FILM WRECKED")
			break
	return air >= 0.0


func _leap_step(inp: Dictionary) -> void:
	seat.inp = inp
	seat.startup.gears = true
	seat.startup.step(DT, [float(inp.thrL), float(inp.thrR)], 1)
	seat._apply_startup(DT)
	seat._process(DT)
	seat.approach_display._process(DT)
	await _frame()


# --- a raid -------------------------------------------------------------------------------------------------------

## The first raid city's town zone (tests/render_raids.gd _town).
func _town(sim) -> Dictionary:
	var k := -1
	for c in sim.cities.size():
		if String(sim.cities[c].get("kind", "")) != "orbit" and c != int(sim.net.from):
			k = c
			break
	var city: Dictionary = sim.cities[k]
	var road := int(city.road)
	var R = sim.roads[road]
	var i := clampi(int(city.i), 0, R.N - 1)
	var at := -1
	for d in R.N:
		if i - d >= 0 and R.mode[i - d] == 0:
			at = i - d
			break
		if i + d < R.N and R.mode[i + d] == 0:
			at = i + d
			break
	var z := Vector2i(maxi(i - 40, 0), mini(i + 40, R.N - 1))
	if at >= 0:
		z = Vector2i(at, at)
		while z.x > 0 and R.mode[z.x - 1] == 0:
			z.x -= 1
		while z.y < R.N - 1 and R.mode[z.y + 1] == 0:
			z.y += 1
	return {"city": k, "name": String(city.name), "road": road, "z": z}


## A raid begun for the film: on E3, a dead straight highway (nothing here steers: fixed guns are aimed by the craft's
## own way), the alarm is called and the pack of six, as soon as the director has placed it in its town, is moved onto
## the craft's own road `near` m ahead and `apart` m between them (tests/render_raids.gd moves it so for its pictures).
## From there the raiders, the traffic they hunt, the fire control and the bursts are the game's.
func _raid(vehicle: String, opts: Dictionary, near := 200.0, apart := 60.0) -> bool:
	opts["raids"] = true
	opts["vehicle"] = vehicle
	if not await _open("E3@9000", opts):
		return false
	var R = seat.raids
	if R == null:
		push_error("No raid director")
		return false
	R.pack_size = Vector2i(6, 6)
	R.arrive_r = 0.0
	R.tick_every = 1.0e9
	R.away_t = 1.0e9
	R.time_limit = 1.0e9
	_at_speed(2000.0)
	await _keep(2000.0, 2.0)
	_cut("raid-alarm-" + vehicle)
	R._alarm()
	await _keep(2000.0, 0.3)
	R.arrive_r = 1.0e9
	var n := 0
	while R.state != "on" and n < 600:
		await _keep(2000.0, DT)
		n += 1
	if R.state != "on":
		push_error("The pack never arrived")
		return false
	_pack_ahead(near, apart)
	print("FILM raid: %d raiders, the dash \"%s\"" % [R.pack.size(), seat._net_text()])
	return true


## The pack moved `near` to `near` + 5 x `apart` m ahead on the craft's own road (tests/render_raids.gd _pack_ahead),
## and across the road to where the craft is, a few metres either side of it: fixed guns take a raider within 3 degrees
## of their bore. From there each raider goes its own way (its lane, its prey).
func _pack_ahead(near: float, apart: float) -> void:
	var sim = seat.sim
	var R = seat.raids
	var T = seat.traffic_net
	var road: int = sim.pod.path
	var Rd = sim.roads[road]
	var nl: int = T._lanes[road].size()
	var way := int(T.oneway.get(road, 1))
	var here := clampf(float(sim._road_f(sim.pod)), 2.0, Rd.N - 3.0)
	var spread := [0.0, 4.0, -4.0, 7.0, -7.0, 2.0]
	var k := 0
	for c in R.pack:
		if not T.cars.has(c):
			continue
		c.road = road
		c.dir = way
		c.lane = clampi(nl / 2 + (k % 2) - 1, 0, nl - 1)
		# where the craft is across the road, in traffic's own measure: two trial placings at the pod's sample
		c.f = here
		c.lat = 0.0
		T._place(c)
		var p0 := Vector2(c.x, c.y)
		c.lat = 1.0
		T._place(c)
		var across := Vector2(c.x, c.y) - p0
		var mine := (Vector2(sim.pod.x, sim.pod.y) - p0).dot(across) / maxf(across.length_squared(), 1e-6)
		var m := near + apart * float(k)
		c.f = clampf(here + way * m / float(Rd.len[clampi(int(here), 0, Rd.N - 1)]), 2.0, Rd.N - 3.0)
		c.lat = mine + float(spread[k % spread.size()])
		c.v = clampf(_mph(), 900.0, 3200.0) / MPH
		T._place(c)
		k += 1
	print("FILM pack of %d put %0.f m ahead" % [k, near])


## How far ahead of the pod a raider is, m, along the way the craft goes (behind: negative); `across` the same to its side.
func _ahead_m(c, across := false) -> float:
	var pod = seat.sim.pod
	var way := Vector2(pod.vx, pod.vy)
	way = way.normalized() if way.length() > 5.0 else Vector2(cos(pod.th), sin(pod.th))
	var d := Vector2(c.x - pod.x, c.y - pod.y)
	return d.cross(way) if across else d.dot(way)


## The nearest raider ahead of the craft on its road (none ahead: null).
func _raider_ahead():
	var best = null
	for c in seat.raids.pack:
		if seat.traffic_net.cars.has(c) and _ahead_m(c) > 20.0 and absf(_ahead_m(c, true)) < 200.0 and (best == null or _ahead_m(c) < _ahead_m(best)):
			best = c
	return best


## A hand holding the craft `gap` m behind the nearest raider ahead, for `seconds`: at the raider's own speed, and at
## most 350 mph over it to close up (with none ahead, 2,000 mph).
func _trail(gap: float, seconds: float) -> void:
	for f in roundi(seconds / DT):
		var c = _raider_ahead()
		var want := 2000.0
		if c != null:
			want = clampf(float(c.v) * MPH + clampf((_ahead_m(c) - gap) * 1.5, -350.0, 350.0), 400.0, 3200.0)
		var v := _mph()
		levers = [clampf(0.45 + (want - v) / 150.0, 0.0, 1.0), clampf(0.45 + (want - v) / 150.0, 0.0, 1.0)]
		brakes = [clampf((v - want - 30.0) / 150.0, 0.0, 1.0), clampf((v - want - 30.0) / 150.0, 0.0, 1.0)]
		if _gaze != null and not seat.traffic_net.cars.has(_gaze):
			_gaze = c
		await _tick()
	var g = seat.gunnery
	var near = _raider_ahead()
	print("FILM %s: %.0f mph, sample %d, nearest raider ahead %.0f m at %.0f mph; guns %d shots, %d hits, %d out; %d raiders left" % [_shot, _mph(), int(seat.sim.pod.hint),
		_ahead_m(near) if near != null else -1.0, float(near.v) * MPH if near != null else 0.0, g.shots if g else 0, g.hits if g else 0, g.kills if g else 0, seat.raids.pack.size()])


## The Phaethon's cannons against a raid on DUNES. They fire for 5 s and cool for 3: each burst is under that.
func _scene_raid() -> bool:
	if not await _raid("phaethon", {}):
		return false
	_cut("raid-pack-seat", Callable(), 40.0)
	await _trail(170.0, 3.0)
	seat.set_gun(true)
	_cut("raid-guns-out", _eng(1, Vector3(3.2, 1.3, -9.5), Vector3(0.0, 0.0, -3.5), 42.0, Vector3(2.2, 0.9, -8.0), 3.0))
	await _trail(170.0, 3.0)
	_pack_ahead(170.0, 50.0)
	_cut("raid-fire-seat", Callable(), 30.0)
	_fire = true
	await _trail(170.0, 4.4)
	_fire = false
	_cut("raid-front", _out(Vector3(7.0, 1.2, -36.0), Vector3(0.0, 0.6, -14.0), 44.0, Vector3(11.0, 2.2, -31.0), null, 3.0))
	await _trail(170.0, 3.0)
	_pack_ahead(170.0, 50.0)
	_cut("raid-fire-out", _out(Vector3(7.0, 4.0, 14.0), Vector3(0.0, 0.5, -60.0), 46.0, Vector3(4.0, 2.6, 9.0), null, 4.0))
	_fire = true
	await _trail(170.0, 4.2)
	_fire = false
	_cut("raid-side", _out(Vector3(17.0, 1.6, -24.0), Vector3(0.0, 0.8, -16.0), 44.0, Vector3(15.0, 1.0, -12.0), null, 3.0))
	await _trail(170.0, 3.0)
	_pack_ahead(150.0, 45.0)
	_cut("raid-fire-seat-2", Callable(), 24.0)
	_fire = true
	await _trail(170.0, 4.4)
	_fire = false
	return true


## The Basilisk's turret, laid where the pilot looks.
func _scene_basilisk() -> bool:
	if not await _raid("basilisk", {"time": "dusk"}):
		return false
	_cut("basilisk-turret-up", _out(Vector3(5.0, 2.6, 4.5), Vector3(0.6, 1.0, -1.5), 50.0, Vector3(6.0, 2.2, 1.0), null, 3.5))
	await _trail(170.0, 0.8)
	_gaze = _raider_ahead()
	seat.set_gun(true)
	await _trail(170.0, 2.7)
	_pack_ahead(170.0, 50.0)
	_gaze = _raider_ahead()
	_cut("basilisk-seat", Callable(), 46.0)
	_fire = true
	await _trail(170.0, 4.0)
	_cut("basilisk-fire-out", _out_gaze(Vector3(6.0, 4.5, 15.0), 46.0, Vector3(-3.0, 3.0, 11.0), 3.5))
	await _trail(170.0, 3.5)
	_fire = false
	_cut("basilisk-side", _out(Vector3(13.0, 1.8, -6.0), Vector3(0.0, 1.0, -4.0), 46.0, Vector3(9.0, 1.4, 2.0), null, 2.6))
	await _trail(170.0, 2.6)
	_pack_ahead(160.0, 45.0)
	_gaze = _raider_ahead()
	_cut("basilisk-fire-close", _out_gaze(Vector3(3.6, 2.3, 4.6), 50.0, Vector3(2.8, 2.6, 6.0), 3.4))
	_fire = true
	await _trail(170.0, 3.4)
	_cut("basilisk-seat-2", Callable(), 30.0)
	await _trail(170.0, 3.0)
	_fire = false
	return true


## The Talon's wing guns. They fire for 4 s and cool for 2.5.
func _scene_talon() -> bool:
	if not await _raid("talon", {"time": "dawn"}):
		return false
	seat.set_gun(true)
	_cut("talon-out", _out(Vector3(-9.0, 2.0, 8.0), Vector3(0.0, 0.6, -10.0), 50.0, Vector3(-12.0, 3.0, -6.0), null, 2.6))
	await _trail(170.0, 2.6)
	_pack_ahead(170.0, 50.0)
	_cut("talon-fire-seat", Callable(), 30.0)
	_fire = true
	await _trail(170.0, 3.6)
	_fire = false
	_cut("talon-high", _out(Vector3(0.0, 12.0, 20.0), Vector3(0.0, 0.0, -40.0), 55.0, Vector3(3.0, 6.0, 12.0), null, 2.6))
	await _trail(170.0, 2.6)
	_pack_ahead(160.0, 45.0)
	_cut("talon-fire-front", _out(Vector3(-8.0, 1.0, -34.0), Vector3(0.0, 0.6, -10.0), 44.0, Vector3(-3.0, 0.4, -28.0), null, 3.4))
	_fire = true
	await _trail(170.0, 3.4)
	_fire = false
	return true


## Dusk on the approach to DUNES, the Shrike in crimson: the towers' windows lit ahead, the game's autopilot flying.
func _scene_dusk() -> bool:
	if not await _open("E3@9000", {"vehicle": "shrike", "paint": "crimson", "time": "dusk"}):
		return false
	var t := _town(seat.sim)
	seat.sim.respawn_on(int(t.road), int(t.z.x) - 420, 1)
	seat._ride.clear()
	_at_speed(2200.0)
	await _settle()
	_at_speed(2200.0)
	var auto := _auto(2400.0)
	await _roll(2.0)
	_cut("dusk-front", _out(Vector3(-8.0, 0.6, -38.0), Vector3(0.0, 0.8, -10.0), 42.0, Vector3(-2.5, -0.3, -29.0), null, 3.0))
	await _roll(3.0)
	_cut("dusk-seat")
	await _roll(2.6)
	_cut("dusk-chase", _out(Vector3(-4.5, 2.2, 15.0), Vector3(0.0, 1.0, -16.0), 55.0, Vector3(4.0, 1.2, 11.0), null, 3.4))
	await _roll(3.4)
	_cut("dusk-engine", _eng(0, Vector3(-3.4, 1.0, 6.5), Vector3(0.0, 0.0, -2.0), 48.0, Vector3(-2.4, 0.7, 4.5), 2.6))
	await _roll(2.6)
	return auto


## A shaft (film_unflown.gd _shaft's: the vertical turnaround at E3's west end) at 3,800 mph: up the wall and over the
## top upside down, from the seat and from outside.
func _scene_shaft() -> bool:
	var road := -1
	for r in ShaftSim.NET_SHAFTS.size():
		if int(ShaftSim.NET_SHAFTS[r][0]) == 51:
			road = r
	var foot := int(ShaftSim.NET_SHAFTS[road][1])
	var landing := int(ShaftSim.NET_SHAFTS[road][2])
	if not await _open("TE3-@%d" % (foot - 50), {"vehicle": "orrery"}):
		return false
	_at_speed(3600.0)
	await _roll(0.5)
	_cut("shaft-foot-seat")
	await _fly_to(foot + 30, 3800.0, null, 3.0)
	_cut("shaft-wall-out", _out(Vector3(7.0, 3.0, 16.0), Vector3(0.0, 0.8, -14.0), 58.0, Vector3(-5.0, 1.5, 11.0), null, 4.0, false))
	await _fly_to(foot + (landing - foot) / 4, 3800.0, null, 4.0)
	_cut("shaft-top-seat")
	await _fly_to(foot + (landing - foot) * 3 / 5, 3800.0, Vector3(40, 0, 0), 4.0)
	_cut("shaft-down-out", _out(Vector3(-9.0, 4.0, 20.0), Vector3(0.0, 0.5, -14.0), 55.0, null, null, 4.0, false))
	await _fly_to(landing - 40, 3800.0, null, 3.0)
	return true
