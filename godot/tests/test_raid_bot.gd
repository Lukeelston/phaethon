## A headless bot clears a scripted raid with each craft's weapon (the spec's Testing: "a headless bot clears a
## scripted raid with each craft's weapon"; the final review's I9a): the Phaethon's engine-nose cannons, the Talon's
## wing guns, the Basilisk's gaze turret. In the VR seat on the Network (XR off), Raids pinned on, obstacles off as
## the menu has them, for each craft:
##   alarm      railed along E3 at speed, the director's own alarm (first_after shortened): a city called
##   run-in     scripted: the craft put on the called city's road 9.6 km short of its town zone, heading in; the
##              director's own arrival puts the pack down there
##   fight      the GUN armed (the cockpit's set_gun); each frame the bot takes the nearest raider still in the pack,
##              rails the craft along the road toward it (turning round where it is behind), holds it about 600 m
##              ahead, steers across into its line (the Basilisk's: a lane's width to its left, so the turret's line
##              clears its own engines), points the craft the way it goes, and for the turret looks at it; it holds
##              the trigger only while the fire control's aim is on a raider
##   cleared    the director's own end: "cleared", every raider of the pack shot (none fled), no commuter knocked out
##              by the weapon, every raider kept within its town zone +-1 km throughout (I1); the commuters the pack
##              ran down meanwhile are told (I2)
## Run with --fixed-fps 120 (traffic and the director run on the engine's frame time). Prints RAID BOT PASS.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const MPH := 2.236936
const HOLD_AT := 600.0           # m: the bot holds its raider this far ahead
const KEEP_M := 1000.0           # m: a raider stays within its town zone by this
const CRAFTS := [Pilot.STANDARD, Pilot.TALON, Pilot.BASILISK]
var failures := 0
var sections := 0


func _initialize() -> void:
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = "E3@9000"
	Seat.best_dir = OS.get_user_data_dir().path_join("test_raid_bot_")
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


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	for id in CRAFTS:
		await _clear_one(id)
	Seat.vehicle_override = ""
	Raids.pinned = false
	Raids.enabled = false
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	_check("every craft's raid ran to its end (%d of %d)" % [sections, CRAFTS.size()], sections == CRAFTS.size())
	print("RAID BOT %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


## One frame: the craft railed at `vel` (sims' frame, m/s) and pointed the way it goes, the view stepped, a frame let pass.
func _frame(v, vel: Vector2) -> void:
	var sim = v.sim
	for b in sim.bodies:
		b.vx = vel.x
		b.vy = vel.y
		b.vz = 0.0
		if vel.length() > 5.0:
			b.th = atan2(vel.y, vel.x)
			b.w = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	v._process(STEP)
	await process_frame


## The road's way under the pod, `dir` along it (a unit vector, sims' frame).
static func _along(sim, dir: int) -> Vector2:
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	return Vector2(R.tx[i], R.ty[i]) * dir


## The seat's eye looking at a point (render frame), as test_turret does: the gaze the Basilisk's turret is slaved to.
static func _look(v, at: Vector3) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if cam.global_position.distance_to(at) > 1.0:
		cam.look_at(at, rig.basis.y)


func _clear_one(id: String) -> void:
	print(id)
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var sim = v.sim
	var T = v.traffic_net
	var R = v.raids
	if R == null or v.craft.weapon == null:
		_check("%s: a director (%s) and a weapon (%s)" % [id, R, v.craft.weapon], false)
		v.queue_free()
		await process_frame
		return
	sim.P.obstacleCollisions = false      # (as the menu has them)
	T.collide = false
	T._hw_time = -1.0e9                   # (no street racer: it would hold traffic's floor)
	R.first_after = 1.0
	# the alarm: railed along E3 at speed
	var t := 0.0
	while R.state != "called" and t < 5.0:
		await _frame(v, _along(sim, 1) * 1000.0)
		t += STEP
	var called: bool = R.state == "called"
	var k: int = R.city
	if not called:
		_check("%s: the alarm in %.1f s at speed (state \"%s\")" % [id, t, R.state], false)
		v.queue_free()
		await process_frame
		return
	var city_name: String = sim.cities[k].name
	var lost_called: int = R.lost
	# the run-in (scripted): on the called city's road 9.6 km short of its town zone, heading in
	var zone: Dictionary = R._zone(k)
	var road: int = zone.road
	var z: Vector2i = zone.z
	sim.respawn_on(road, z.x - 400, 1)
	var rail := 1
	t = 0.0
	while R.state == "called" and t < 2.0:
		await _frame(v, _along(sim, rail) * 500.0)
		t += STEP
	if R.state != "on":
		_check("%s: the pack arrived at %s (state \"%s\")" % [id, city_name, R.state], false)
		v.queue_free()
		await process_frame
		return
	var pack: Array = R.pack.duplicate()
	var lost_arrival: int = R.lost
	var kills0: int = R.kills
	# the fight
	v.set_gun(true)
	var g = v.gunnery
	var turret: bool = id == Pilot.BASILISK
	var worst := 0.0
	var fight_t := 0.0
	var turns := 0
	var on_raider := 0
	var strikes0: int = g.commuter_strikes if g != null else 0
	var shots0: int = g.shots if g != null else 0
	while R.state == "on" and fight_t < 115.0:
		g = v.gunnery
		var target = null
		var near := INF
		var at := Vector2(sim.pod.x, sim.pod.y)
		for c in R.pack:
			worst = maxf(worst, _outside(R, c, k))
			var d := at.distance_to(Vector2(c.x, c.y))
			if T.cars.has(c) and d < near:
				near = d
				target = c
		var vel := Vector2.ZERO
		if target != null:
			var h := _along(sim, rail)
			var to := Vector2(target.x, target.y) - at
			var gap := to.dot(h)
			if gap < -80.0:          # behind: turn round (scripted: the craft put down facing the other way)
				rail = -rail
				turns += 1
				sim.respawn_on(sim.pod.path, sim.pod.hint, rail)
				h = _along(sim, rail)
				gap = -gap
			var its := Vector2(float(target.hx), float(target.hy)) * float(target.v)
			var speed := clampf(its.dot(h) + 1.2 * (gap - HOLD_AT), 0.0, 900.0)
			var right := Vector2(h.y, -h.x)
			var want := 0.0 if not turret else 45.0      # (the turret: the raider a lane to the right of its nose)
			var across := to.dot(right) - want
			var Rd = sim.roads[sim.pod.path]
			var i := clampi(int(sim.pod.hint), 0, Rd.N - 1)
			var lat: float = (sim.pod.x - Rd.px[i]) * Rd.nx[i] + (sim.pod.y - Rd.py[i]) * Rd.ny[i]
			var side := clampf(across * 2.0, -90.0, 90.0)
			var left_n := Vector2(Rd.nx[i], Rd.ny[i])
			var limit: float = Rd.w[i] * 0.5 - 30.0
			if (lat >= limit and (right * side).dot(left_n) > 0.0) or (lat <= -limit and (right * side).dot(left_n) < 0.0):
				side = 0.0           # (kept on the road)
			vel = h * speed + right * side
			if turret and g != null:
				_look(v, g.to_render(Vector3(target.x, target.y, T.body_height(target))))
		if g != null:
			g.hold_fire = g.aim_car != null and g.aim_car.hostile
			on_raider += int(g.hold_fire)
		await _frame(v, vel)
		fight_t += STEP
	g = v.gunnery
	var strikes: int = (g.commuter_strikes - strikes0) if g != null else -1
	var shots: int = (g.shots - shots0) if g != null else -1
	var in_traffic := 0
	for c in pack:
		in_traffic += int(T.cars.has(c))
	sections += 1
	_check("%s on %s: alarm (%d lost on the way), arrived with %d raiders; %.1f s of fight (%d shots, the aim on a raider %d frames, %d turns round): \"%s\"%s, %d shot (fled %d), %d left in traffic, %d commuters struck and none knocked out by the gun (%d gun kills, all raiders), %d run down by the pack meanwhile; the farthest a raider was out of its zone %.0f m (within %.0f)" % [
			id, city_name, lost_called, pack.size(), fight_t, shots, on_raider, turns, R.result, " (%s)" % R._why if R._why != "" else "",
			R.kills - kills0, R.fled, in_traffic, strikes, g.kills if g != null else -1, R.lost - lost_arrival, worst, KEEP_M],
		called and R.result == "cleared" and R.kills - kills0 == pack.size() and R.fled == 0 and in_traffic == 0 and g != null and g.kills == pack.size() and worst <= KEEP_M)
	v.queue_free()
	await process_frame


## How far raider c is outside city k's town zone, m along its road (0 inside); INF off the zone's road.
static func _outside(R, c, k: int) -> float:
	var zone: Dictionary = R._zone(k)
	if c.road != int(zone.road):
		return INF
	var z: Vector2i = zone.z
	return maxf(maxf(float(z.x) - c.f, c.f - float(z.y)), 0.0) * 24.0
