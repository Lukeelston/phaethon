## The raid's sounds (audio/raid_sounds.gd), heard: the VR seat (XR off) parked on the Network, so the engine's movie
## writer records what the game itself mixes. The picture is the seat's, small; the sound is the point. Run windowed:
## --xr-mode off --resolution 320x180 --fixed-fps 120 --audio-driver Dummy --write-movie FILE.avi
## -s res://tests/record_raid_sounds.gd -- --plan=levels|arrival|weapons
## and take the sound out of the film (ffmpeg -i FILE.avi -vn FILE.wav). No --mute. The movie writer mixes for the film
## alone: nothing is played out of the machine.
##   --plan=levels   every bus but Master muted (the engines, the wind, the cockpit's, traffic's: the raid's sounds play
##                   on Master): the jolt's thump, the turret's shot and its servo at 1.35 (the hum's stand-in) through the
##                   Kiln's gun pool, then the four weapons' own through it, the lance's hum held 2.5 s, the drones' whine
##                   and the gunship's drone at their most (50 and 100 m off) and a shot's report at 100 m and at 1 km,
##                   each alone, 0.6 s of silence between: for the level table
##   --plan=arrival  the Kiln parked at a group's point in a raided town, the full mix: the alarm, the drones and the
##                   gunship put down, every dive at the pilot, 22 s
##   --plan=weapons  the full mix, each craft parked under a raid's drones: the Kiln's lance burned 2.5 s, the Shrike's
##                   volley of four, the Vesper's pulse, the Orrery's orbs striking on their own
##   --plan=close    (the whole-branch review's findings 2 and 3) every bus but Master muted, the Vesper parked and armed,
##                   then the world held still (its fire control stepped alone): the jolt's thump; a kill's burst 30 m
##                   ahead as it was (its player's most 3 dB) and as it is (a raider killed there: BURST_MOST_DB); the
##                   pulse's stand-in as it was (the burst at 0.55) and as it is (the impact at 0.45), through the gun
##                   pool; a release among six raiders 50 to 150 m off as it was (its boom and six bursts at 3 dB, each
##                   when the ring would reach it) and as it is (a real release: its boom, its kills' bursts, stepped
##                   down one after another: view/gunnery.gd BURST_STEP_DB); then a release with one raider 50 m off
##                   (its boom and one burst: what any stepping leaves)
## REC lines give each stage's time from the start of the film's sound (its frames / 120).
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const RaidSounds := preload("res://audio/raid_sounds.gd")
const STEP := 1.0 / 120.0

var plan := "levels"
var seat


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--plan="):
			plan = a.trim_prefix("--plan=")
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = "E3@9000"
	Seat.best_dir = OS.get_user_data_dir().path_join("record_raid_sounds_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Chase.pinned = true
	Chase.enabled = false
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _clock() -> float:
	return Engine.get_process_frames() * STEP


func _rec(what: String) -> void:
	print("REC %.3f s: %s" % [_clock(), what])


func _seat(id: String):
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	if root.use_xr or not RaidSounds.heard(v):
		push_error("This needs a monoscopic viewport and sound (no --mute).")
		quit(1)
		return null
	v.traffic_net._hw_time = -1.0e9
	return v


func _frame() -> void:
	for b in seat.sim.bodies:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0
	seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	seat._process(STEP)
	await process_frame


func _for(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		await _frame()


func _city() -> int:
	var sim = seat.sim
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## A raid on the first other city: `drones` of them, the gunship or not, no raiders; the craft put down at its drones'
## first group's point once they are up (or the zone's middle with none).
func _raid(drones: int, gunship: bool) -> void:
	var R = seat.raids
	var k := _city()
	R.reset()
	var zone: Dictionary = R._zone(k)
	seat.sim.respawn_on(int(zone.road), (int(zone.z.x) + int(zone.z.y)) / 2, 1)
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(drones, drones)
	R.gunship_from = 1 if gunship else 1 << 30
	R.gunship_every = 1
	R._alarm()
	R.city = k
	await _frame()
	await _frame()
	var F = R.flyers
	if not F._groups.is_empty():
		var G = F._groups[0]
		seat.sim.respawn_on(int(G.road), clampi(int(G.f), 2, seat.sim.roads[int(G.road)].N - 3), 1)


func _arm() -> void:
	seat.gun_wanted = true
	for i in int(2.0 / STEP):
		await _frame()
		if seat.gunnery != null and seat.gunnery.mount.is_out():
			return


func _run() -> void:
	match plan:
		"levels":
			await _levels()
		"arrival":
			await _arrival()
		"weapons":
			await _weapons()
		"close":
			await _close()
	quit()


func _levels() -> void:
	seat = await _seat(Pilot.KILN)
	if seat == null:
		return
	await _arm()      # (its servo's sound out of the way first)
	await _for(1.5)
	for i in range(1, AudioServer.bus_count):
		AudioServer.set_bus_mute(i, true)
	var g = seat.gunnery
	for n: String in ["missile_launch", "pulse_boom", "orb_strike"]:
		g._sounds[n] = RaidSounds.make(n)      # (the other craft's, through this gun pool: the same players at the mount)
	var eye: Vector3 = root.get_viewport().get_camera_3d().global_position
	var F = seat.raids.flyers
	print("REC_BEGIN")
	await _for(1.0)
	_rec("thump")
	seat.jolt(1.0)
	await _for(1.0)
	_rec("turret fire")
	g.play("gun", "fire")
	await _for(1.0)
	_rec("turret deploy x1.35")
	g.play("gun", "deploy", Vector3.INF, 1.35)
	await _for(1.6)
	for n: String in ["missile_launch", "pulse_boom", "orb_strike"]:
		_rec(n)
		g.play_own("gun", n)
		await _for(2.2 if n == "pulse_boom" else 1.4)
	_rec("lance_hum")
	g.hold_fire = true
	await _for(2.4)
	g.hold_fire = false
	await _for(0.8)
	_rec("drone_whine at 50 m")
	F.whine.global_position = eye + Vector3(0.0, 20.0, -46.0)
	F.whine.play()
	await _for(2.4)
	F.whine.stop()
	await _for(0.6)
	_rec("gunship_drone at 100 m")
	F.hull_drone.global_position = eye + Vector3(0.0, 60.0, -80.0)
	F.hull_drone.play()
	await _for(3.2)
	F.hull_drone.stop()
	await _for(0.6)
	_rec("gunship_shot at 100 m")
	F._report(eye + Vector3(0.0, 60.0, -80.0))
	await _for(1.6)
	_rec("gunship_shot at 1 km")
	F._report(eye + Vector3(0.0, 200.0, -980.0))
	await _for(1.6)
	_rec("end")


func _arrival() -> void:
	seat = await _seat(Pilot.KILN)
	if seat == null:
		return
	await _for(2.0)
	print("REC_BEGIN")
	_rec("parked, engines idling")
	await _for(2.0)
	_rec("the alarm, the drones and the gunship put down")
	await _raid(8, true)
	seat.raids.flyers.pilot_share = 1.0
	for d in seat.raids.flyers.all():
		if d.kind == "drone":
			d.at_pod = true
	await _for(20.0)
	_rec("the raid set aside (a restart's reset)")
	seat.raids.reset()
	await _for(2.0)
	_rec("end")


## `seconds` of the still world: the fire control stepped alone, the film's frames let pass.
func _still(g, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		g.step(STEP)
		await process_frame


## A raider of the director's pack standing still at `at` (the sims' plane), on the craft's road's nearest sample.
func _raider_at(at: Vector2):
	var T = seat.traffic_net
	var sim = seat.sim
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var h := int(sim.pod.hint)
	var near := h
	for i in range(maxi(0, h - 400), mini(R.N - 1, h + 400)):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	c.id = 998000 + T.cars.size()
	c.kind = T.CAR
	c.road = road
	c.dir = 1
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = true
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	seat.raids.pack.append(c)
	return c


func _close() -> void:
	seat = await _seat(Pilot.VESPER)
	if seat == null:
		return
	await _arm()
	await _for(1.5)
	for i in range(1, AudioServer.bus_count):
		AudioServer.set_bus_mute(i, true)
	var g = seat.gunnery
	seat.traffic_net.cars.clear()
	seat.raids.pack.clear()
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var eye: Vector3 = g.to_sim(cam.global_position)
	var fw: Vector3 = g.dir_to_sim(-cam.global_transform.basis.z)
	var way := Vector2(fw.x, fw.y).normalized()
	var at30 := Vector2(eye.x, eye.y) + way * 30.0
	var six := []      # [m off, the sims' plane]
	for k in 6:
		var d := 50.0 + 20.0 * k
		six.append([d, Vector2(eye.x, eye.y) + way.rotated(deg_to_rad(-50.0 + 20.0 * k)) * d])
	print("REC_BEGIN")
	await _still(g, 1.0)
	_rec("thump")
	seat.jolt(1.0)
	await _still(g, 1.2)
	_rec("burst 30 m ahead, as it was (most 3 dB)")
	g._play(g._world_audio, "burst", g.to_render(Vector3(at30.x, at30.y, eye.z - 1.0)), 1.0, 3.0)
	await _still(g, 3.0)
	_rec("burst 30 m ahead, as it is (a raider killed there)")
	var c = _raider_at(at30)
	g.damage(c, g.HOSTILE_HP, Vector3(c.x, c.y, seat.traffic_net.body_height(c)), false, true)
	await _still(g, 3.0)
	_rec("the pulse's stand-in as it was (burst at 0.55)")
	g.play("gun", "burst", Vector3.INF, 0.55)
	await _still(g, 5.0)
	_rec("the pulse's stand-in as it is (impact at 0.45)")
	g.play("gun", "impact", Vector3.INF, 0.45)
	await _still(g, 2.0)
	_rec("a release among six raiders 50 to 150 m off, as it was (bursts at 3 dB)")
	g.play_own("gun", "pulse_boom")
	var due := []
	for s: Array in six:
		due.append([float(s[0]) / 900.0, s[1]])      # (the ring: 450 m in 0.5 s)
	for k in roundi(3.2 / STEP):
		for i in range(due.size() - 1, -1, -1):
			if float(due[i][0]) <= k * STEP:
				var p: Vector2 = due[i][1]
				g._play(g._world_audio, "burst", g.to_render(Vector3(p.x, p.y, eye.z - 1.0)), 1.0, 3.0)
				due.remove_at(i)
		g.step(STEP)
		await process_frame
	_rec("a release among six raiders 50 to 150 m off, as it is")
	for s: Array in six:
		_raider_at(s[1])
	var kills: int = g.kills
	g.hold_fire = true
	g.step(STEP)
	await process_frame
	g.hold_fire = false
	await _still(g, 3.2)
	_rec("a release with one raider 50 m off (%d killed by the last)" % (g.kills - kills))
	g.mount.charge = 0.0      # (its charge given back by hand: the recharge is the tests')
	_raider_at(six[0][1])
	kills = g.kills
	g.hold_fire = true
	g.step(STEP)
	await process_frame
	g.hold_fire = false
	await _still(g, 3.2)
	_rec("end (%d killed by the release)" % (g.kills - kills))


func _weapons() -> void:
	for id: String in [Pilot.KILN, Pilot.SHRIKE, Pilot.VESPER, Pilot.ORRERY]:
		seat = await _seat(id)
		if seat == null:
			return
		await _raid(6, false)
		await _arm()
		await _for(1.0)
		var g = seat.gunnery
		match id:
			Pilot.KILN:
				_rec("the Kiln's lance held 2.5 s, to overheating")
				g.hold_fire = true
				await _for(3.0)
				g.hold_fire = false
				await _for(1.0)
			Pilot.SHRIKE:
				var four := []
				for f in seat.raids.flyers.all():
					if four.size() < 4 and not g.mount._beyond(f, seat.sim.pod):
						four.append(f)
				g.mount.locks = four
				_rec("the Shrike's volley of %d" % four.size())
				g.hold_fire = true
				await _frame()
				g.hold_fire = false
				await _for(3.0)
			Pilot.VESPER:
				_rec("the Vesper's pulse")
				g.hold_fire = true
				await _frame()
				g.hold_fire = false
				await _for(3.0)
			Pilot.ORRERY:
				_rec("the Orrery's orbs, on their own")
				await _for(5.0)
		seat.raids.reset()
		seat.queue_free()
		await process_frame
	_rec("end")
