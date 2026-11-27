## A headless bot clears real raids with each craft's weapon (the spec's Testing: "a headless bot clears a scripted raid
## with each craft's weapon"; stage 1's I9a, and stage 2's task 10: every craft clears every raid). In the VR seat on
## the Network (XR off), Raids pinned on, obstacles off as the menu has them, for each of the seven craft, two raids of
## a flight as the director makes them: its first (raiders and drones) and its third (raiders, drones and the gunship;
## the director's raid count set so the alarm is the flight's third: 6 raiders, 8 drones, the gunship):
##   alarm      railed along E3 at speed, the director's own alarm (first_after and the lull shortened): a city called
##   run-in     scripted: the craft put on the called city's road 9.6 km short of its town zone, heading in; the
##              director's own arrival puts the pack, the drones and the gunship down there
##   fight      the GUN armed (the cockpit's set_gun); each frame the bot plays the craft's weapon as a pilot could, from
##              what a pilot sees (where the threats are and how they go, the gunship's glow and its shots, a drone diving
##              at the craft, the weapon's own word: its locks, its heat, its charge, its orbs). The craft is railed along
##              the road under it (scripted: its speed along the road at most A_ALONG a second, its slide across at most
##              A_LAT, kept on the road; turning round is put down facing the other way, from rest), its nose pointed
##              the way it goes or, where the weapon is pointed by the craft, toward its threat (within NOSE_DEG of the
##              road's way). It weaves: a gunship's shot fired, or a drone diving, that would pass within DODGE_MISS of it
##              if both went on as they go (as a pilot judges one coming his way), and it slides hard across the way it was
##              not going (toward the road's middle near an edge) until it has passed. By weapon:
##                fixed guns (the Phaethon, the Talon), as stage 1's: the gunship in its run (its drop, its strafe, its
##                climb: 600 m behind it in its way, where its run is laid to be on their nose), and on its station they
##                wait 800 m behind it the way it faces (where it will run); else the nearest raider, held about 600 m
##                ahead; then the lowest drone (one diving, or one met far enough off to be inside the guns' 3 degrees:
##                held at its height over tan 2.2 degrees, 650 m to the guns' reach less 250); the trigger held while the
##                fire control's aim (its assist's) is on a threat
##                the turret (the Basilisk), as stage 1's: the nearest threat, a raider held 600 m ahead and a lane to
##                the right of the nose, a flyer 500 m; the gaze on it; the trigger held while the aim is on a threat
##                missiles (the Shrike): held 600 m off the nearest raider and 100 m across from it (1,000 m off a
##                flyer); the gaze laid on up to four threats in turn, nearest first, each until it locks (one with a
##                missile already homing on it passed over, but the gunship; one that will not lock in 1.5 s, passed over
##                4 s, and what is locked fired), then a press
##                the lance (the Kiln): closed to 350 m of the threat (the gunship on its station: 480 m, under the
##                cone's 25 degrees) and the gaze on it, the nose toward it; the trigger held while it is within the
##                beam's reach and the lance is not cooling
##                the pulse (the Vesper): driven into the densest group of threats; a press, charged, when at least one is
##                inside 400 m and that group is (or it is the nearest there is)
##                the orbs (the Orrery): armed, held 600 m off the nearest threat (the orbs take it on their own); sent at
##                the gunship (the gaze on it, a press) when no other threat is within their own reach
##   cleared    the director's own end: "cleared", with RAID_SPARE s or more of its time limit left (the director's
##              limit(): 120 s, or 180 s for a raid that came with the gunship, told on the dash at arrival); every threat shot
##              (its raiders, drones and gunship by kills_by: none fled), every kill of the weapon a threat, no commuter
##              knocked out by a weapon (each it struck, sparks only, still in traffic after the strike), every
##              raider kept within its town zone +-1 km throughout (I1). Told, not asserted: the hits taken by kind, the
##              commuters the raid took meanwhile, the weapon's shots and hits, the gunship's fight (how long from its
##              first hit, and where it fell: on station, its drop, its run, its climb, in transit; under the terminal's
##              roof or not)
## Options (after --): --craft=<id> one craft; --raid=1|3 one raid; --limit=S the raid's time limit set to S (to measure
## how long a craft takes); --gunfire=straight|weave the ruling AI measure instead (the gunship alone, no weapon: the
## craft shuttled along the zone's road at --speed=V m/s (GUNFIRE_V) through the gunship's reach, on to 1,500 m past it
## and turned round, straight and level, or weaving; --seconds of it, default 180: hits a minute in the open inside its
## reach).
## Run with --fixed-fps 120 (traffic and the director run on the engine's frame time). Prints RAID BOT PASS.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Flyers := preload("res://view/raid_flyers.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const G := 9.81
const KEEP_M := 1000.0           # m: a raider stays within its town zone by this
const RAID_SPARE := 20.0         # s of the time limit a raid is cleared with, at the least
const CRAFTS := [Pilot.STANDARD, Pilot.TALON, Pilot.BASILISK, Pilot.SHRIKE, Pilot.KILN, Pilot.VESPER, Pilot.ORRERY]
const RAIDS := [1, 3]            # a flight's first raid, and its third (the first with the gunship)
const V_MAX := 900.0             # m/s: the bot's fastest along the road
const A_ALONG := 10.0 * G        # m/s^2: its speed along the road changes no faster than this (the Phaethon's thrust is
                                 # some 24 g on its 2.9 t, its grip some 15 g) ...
const A_LAT := 4.0 * G           # ... and its slide across it (a hand's dodge, well inside the grip)
const LAT_V := 90.0              # m/s: its fastest across the road
const EDGE := 30.0               # m: it keeps this far inside the road's edges
const NOSE_DEG := 25.0           # its nose, pointed at a threat, at most this far off the road's way (the lance's: 45)
const TURN_GAP := 250.0          # m: a threat this far behind, it turns round ...
const TURN_EVERY := 2.0          # ... no sooner than this after the last time
const GUNFIRE_V := 300.0         # m/s: the ruling AI measure's speed through the gunship's reach
const DODGE_EVERY := 0.4         # s: a new dodge no sooner than this after the last began ...
const DODGE_MISS := 40.0         # ... for a shot or a dive that, going on as it goes, would pass this near the craft
var failures := 0
var sections := 0
var only_craft := ""
var only_raid := 0
var gunfire := ""
var seconds := 180.0
var limit := 0.0                 # --limit=S: the raid's time limit set to S (a measure of how long a craft takes; 0: the director's)
var gunfire_v := GUNFIRE_V       # --speed=V: the ruling AI measure's speed
var lines: Array = []            # the summary, one line a run (printed again at the end)


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--craft="):
			only_craft = arg.trim_prefix("--craft=")
		elif arg.begins_with("--raid="):
			only_raid = int(arg.trim_prefix("--raid="))
		elif arg.begins_with("--gunfire="):
			gunfire = arg.trim_prefix("--gunfire=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--limit="):
			limit = float(arg.trim_prefix("--limit="))
		elif arg.begins_with("--speed="):
			gunfire_v = float(arg.trim_prefix("--speed="))
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
	var runs := 0
	if gunfire != "":
		await _gunfire(Pilot.STANDARD, gunfire == "weave")
		runs = 1
	else:
		for id in CRAFTS:
			if only_craft != "" and id != only_craft:
				continue
			for n in RAIDS:
				if only_raid != 0 and n != only_raid:
					continue
				runs += 1
				await _clear_one(id, n)
	Seat.vehicle_override = ""
	Raids.pinned = false
	Raids.enabled = false
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	for l in lines:
		print("  " + l)
	_check("every run ran to its end (%d of %d)" % [sections, runs], sections == runs)
	print("RAID BOT %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


## One frame: the craft railed at `vel` (sims' frame, m/s) and pointed along `th`, the view stepped, a frame let pass.
func _frame(v, vel: Vector2, th: float) -> void:
	var sim = v.sim
	for b in sim.bodies:
		b.vx = vel.x
		b.vy = vel.y
		b.vz = 0.0
		b.th = th
		b.w = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	v._process(STEP)
	await process_frame


## The road's way under the pod, `dir` along it (a unit vector, sims' frame).
static func _along(sim, dir: int) -> Vector2:
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	return Vector2(R.tx[i], R.ty[i]) * dir


## The seat's eye looking at a point (render frame), as test_turret does; null: ahead, a little down the road.
static func _look(v, at) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Seat.EYE
	if at == null:
		cam.look_at(cam.global_position + rig.basis * Vector3(0.0, -0.03, -1.0).normalized(), rig.basis.y)
	elif cam.global_position.distance_to(at) > 1.0:
		cam.look_at(at, rig.basis.y)


## A threat's place, the sims' frame: a flyer's own, a raider's body (halfway up it).
static func _at(T, c) -> Vector3:
	return Vector3(c.x, c.y, c.z) if GunneryScript._is_flyer(c) else Vector3(c.x, c.y, T.body_height(c))


## The bot's state through one raid.
class Bot:
	var rail := 1                # its way along the road
	var speed := 0.0             # m/s along it
	var lat_v := 0.0             # m/s across it (+: to the right of its way)
	var dodge_t := 0.0           # s of a dodge left ...
	var dodge_dir := 1.0         # ... and its way across (+: right)
	var since_dodge := 9.0       # s since a dodge began
	var dodges := 0
	var turns := 0
	var since_turn := 9.0        # s since it last turned round
	var seen_shot := 0           # the gunship's last shot seen fired
	var press := false           # the trigger pressed this frame (a press is held one frame, let go the next)
	var looking = null           # missiles: the threat the gaze is laid on for its lock ...
	var look_t := 0.0            # ... and for how long
	var skip := {}               # ... threats passed over for a while (no lock in time): threat -> s left
	var stuck := false           # ... and a look ran out with locks held: they are fired


## One raid with craft `id`: its `n`th of a flight (1, or 3 with the gunship), from the alarm to the director's end.
func _clear_one(id: String, n: int) -> void:
	print("%s, raid %d" % [id, n])
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
	R._count = n - 1                      # (the flight's nth raid: its pack, its drones and its gunship are the director's for it)
	R._lull_len = 1.0
	if limit > 0.0:
		R.time_limit = limit
	var hits := {"raider": 0, "drone": 0, "gunship": 0}
	R.hit_taken.connect(func(source: String) -> void: hits[source] = int(hits.get(source, 0)) + 1)
	var lost_at: Array = []
	R.commuter_lost.connect(func(x: float, y: float) -> void: lost_at.append(Vector2(x, y)))
	# the alarm: railed along E3 at speed
	var t := 0.0
	while R.state != "called" and t < 5.0:
		var w := _along(sim, 1)
		await _frame(v, w * 1000.0, w.angle())
		t += STEP
	var called: bool = R.state == "called"
	var k: int = R.city
	if not called:
		_check("%s raid %d: the alarm in %.1f s at speed (state \"%s\")" % [id, n, t, R.state], false)
		v.queue_free()
		await process_frame
		return
	var city_name: String = sim.cities[k].name
	# the run-in (scripted): on the called city's road 9.6 km short of its town zone, heading in
	var zone: Dictionary = R._zone(k)
	var z: Vector2i = zone.z
	sim.respawn_on(int(zone.road), z.x - 400, 1)
	t = 0.0
	while R.state == "called" and t < 2.0:
		var w := _along(sim, 1)
		await _frame(v, w * 500.0, w.angle())
		t += STEP
	if R.state != "on":
		_check("%s raid %d: the pack arrived at %s (state \"%s\")" % [id, n, city_name, R.state], false)
		v.queue_free()
		await process_frame
		return
	var F = R.flyers
	var pack: Array = R.pack.duplicate()
	var n_drones: int = F.count("drone")
	var has_gs: bool = F.gunship() != null
	var lost_arrival: int = R.lost
	if limit <= 0.0:      # (the director's own limit: 120 s, or 180 for a raid that came with the gunship; the dash counts it down)
		var want_limit: float = Raids.TIME_LIMIT_GUNSHIP if has_gs else Raids.TIME_LIMIT
		var left_now := int(maxf(want_limit - R._t, 0.0))
		var clock := "%d:%02d" % [left_now / 60, left_now % 60]
		_check("%s raid %d: its time limit %.0f s (%s; want %.0f), the dash \"%s\" ends %s" % [id, n, R.limit(), "with the gunship" if has_gs else "no gunship", want_limit, R.text(), clock],
			is_equal_approx(R.limit(), want_limit) and R.text().ends_with(clock) and has_gs == (n >= 3))
	# the fight
	v.set_gun(true)
	var bot := Bot.new()
	bot.speed = 500.0
	var worst := 0.0
	var fight_t := 0.0
	var g = v.gunnery
	var shots0: int = g.shots if g != null else 0
	var hits0: int = g.hits if g != null else 0
	var strikes0: int = g.commuter_strikes if g != null else 0
	var bad_kills: Array = []         # weapon kills that were not a threat of the raid's
	var connected := false
	var struck: Array = []            # commuters the weapon struck this frame (sparks: it must leave each in traffic) ...
	var ko_weapon := 0                # ... and those of them gone from traffic after it, not run down by the raid
	var gs_first := -1.0              # s into the raid the gunship was first hit ...
	var gs_kill := -1.0               # ... and fell
	var gs_where := ""
	var gs_last = null
	var gs_strafes := 0
	var gs_state := ""
	var on_threat := 0
	var released0: int = int(v.craft.weapon.get("released")) if v.craft.weapon.get("released") != null else 0
	var shots_at_you := 0
	var gs_up_t := 0.0
	while R.state == "on" and fight_t < R.limit() + 5.0:
		g = v.gunnery
		if g != null and not connected:
			connected = true
			shots0 = g.shots
			hits0 = g.hits
			strikes0 = g.commuter_strikes
			g.killed.connect(_note_kill.bind(pack, bad_kills))
			g.struck_commuter.connect(func(c) -> void: struck.append(c))
		for c in R.pack:
			worst = maxf(worst, _outside(R, c, k))
		var gs = F.gunship()
		if gs != null:
			gs_up_t += STEP
			if gs_first < 0.0 and gs.hp < gs.hp_max:
				gs_first = R._t
			if gs.state == "strafe" and gs_state != "strafe":
				gs_strafes += 1
			gs_state = gs.state
			gs_last = gs
			gs_where = gs.state + (" (in the hall)" if F.world != null and F.world.roofed(gs.road, gs.f) > 0.0 else "")
		for s in F.shots:
			if int(s.n) > bot.seen_shot and bool(s.pilot):
				shots_at_you += 1
		var plan := _plan(v, bot, id)
		var vel := _drive(v, bot, plan)
		var th: float = plan.get("th", vel.angle() if vel.length() > 5.0 else sim.pod.th)
		_look(v, g.to_render(plan.look) if plan.get("look") != null and g != null else null)
		if g != null:
			g.hold_fire = bool(plan.get("fire", false))
			on_threat += int(g.hold_fire)
		lost_at.clear()
		struck.clear()
		await _frame(v, vel, th)
		fight_t += STEP
		if gs_last != null and gs_kill < 0.0 and F.gunship() == null and R.kills_by.gunship > 0:
			gs_kill = R._t
		for c in struck:
			if T.cars.has(c):
				continue
			var run_down := false
			for q: Vector2 in lost_at:
				run_down = run_down or q.distance_to(Vector2(c.x, c.y)) < 80.0
			if not run_down:
				ko_weapon += 1
				print("  a commuter (%d) the weapon struck is gone from traffic" % c.id)
	g = v.gunnery
	var shots: int = (g.shots - shots0) if g != null else -1
	var whits: int = (g.hits - hits0) if g != null else -1
	var strikes: int = (g.commuter_strikes - strikes0) if g != null else -1
	var in_traffic := 0
	for c in pack:
		in_traffic += int(T.cars.has(c))
	var kb: Dictionary = R.kills_by
	var all_shot: bool = int(kb.raider) == pack.size() and int(kb.drone) == n_drones and int(kb.gunship) == int(has_gs)
	var left: float = R.limit() - R._t
	var mount = v.craft.weapon
	var extra := ""
	if mount.get("released") != null:
		extra = ", %d pulses" % (int(mount.released) - released0)
	elif mount.get("sends") != null:
		extra = ", %d sends, %d orb strikes" % [int(mount.sends), int(mount.strikes)]
	var gs_line := ""
	if has_gs:
		gs_line = "; the gunship: %s" % ("first hit %.1f s in, fell %.1f s in (%.1f s after its first hit) %s, %d strafing runs begun, %d shots at the craft in %.0f s up (%.1f a minute), %d of them hits (%.1f a minute)" % [gs_first, gs_kill, gs_kill - gs_first, "on its " + gs_where, gs_strafes, shots_at_you, gs_up_t, shots_at_you * 60.0 / maxf(gs_up_t, 1.0), int(hits.gunship), int(hits.gunship) * 60.0 / maxf(gs_up_t, 1.0)] if gs_kill >= 0.0 else "not shot down (first hit %.1f s in), %d strafing runs begun" % [gs_first, gs_strafes])
	sections += 1
	var line := "%s raid %d at %s: \"%s\"%s in %.1f s, %.1f s left; kills %d raiders of %d, %d drones of %d, %d gunship of %d (fled %d, %d raiders left in traffic); hits taken: %d raider, %d drone, %d gunship; commuters: %d lost to the raid, %d struck by the weapon, %d knocked out by it; %d weapon kills not a threat; weapon: %d shots, %d hits%s, trigger held %d frames, %d dodges, %d turns round; farthest a raider was out of its zone %.0f m%s" % [
			id, n, city_name, R.result, " (%s)" % R._why if R._why != "" else "", R._t, left, int(kb.raider), pack.size(), int(kb.drone), n_drones, int(kb.gunship), int(has_gs),
			R.fled, in_traffic, int(hits.raider), int(hits.drone), int(hits.gunship), R.lost - lost_arrival, strikes, ko_weapon, bad_kills.size(), shots, whits, extra, on_threat, bot.dodges, bot.turns, worst, gs_line]
	lines.append(line)
	_check(line, R.result == "cleared" and left >= RAID_SPARE and all_shot and R.fled == 0 and in_traffic == 0 and ko_weapon == 0 and bad_kills.is_empty() and worst <= KEEP_M)
	v.queue_free()
	await process_frame


# --- the bot's play, by weapon ---------------------------------------------------------------------------------

## This frame's play: {"target": what it goes after (or a Vector2 place), "hold": m short of it along the road,
## "want": m across to its right it is kept, "look": where the gaze is laid (sims' frame) or null, "fire": the trigger,
## "th": the nose (omitted: the way it goes)}.
func _plan(v, bot: Bot, id: String) -> Dictionary:
	var R = v.raids
	var T = v.traffic_net
	var F = R.flyers
	var sim = v.sim
	var g = v.gunnery
	var at := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
	var threats: Array = R.threats()
	_weave(v, bot)
	if threats.is_empty() or g == null:
		return {"target": null}
	var gs = F.gunship()
	var raiders: Array = R.pack
	var drones: Array = []
	for f in F.all():
		if f.kind == "drone":
			drones.append(f)
	var mount = v.craft.weapon
	if id == Pilot.STANDARD or id == Pilot.TALON:
		var target = null
		var hold := 600.0
		var place = null
		if gs != null and gs.state in ["drop", "strafe", "climb"] and _flat(at, gs) < 4000.0:
			target = gs
			hold = 600.0
		elif gs != null and gs.state == "station" and _flat(at, gs) < 5000.0:      # (it will run its way: wait behind where it starts)
			place = Vector2(gs.x - gs.hx * 800.0, gs.y - gs.hy * 800.0)
			hold = 0.0
		elif not raiders.is_empty():
			target = _nearest(at, raiders)
		elif not drones.is_empty():      # (the lowest: one diving, or one circling low enough to be met far off)
			var reach_m: float = float(g.reach) - 250.0
			var best := INF
			for f in drones:
				var up: float = f.z - sim.pod.z
				var score: float = up + _flat(at, f) / 100.0
				if score < best:
					best = score
					target = f
			hold = clampf((target.z - sim.pod.z) / tan(deg_to_rad(2.2)), 650.0, reach_m)
		elif gs != null:      # (on its station, or on to its next: behind where its run will begin, its way)
			place = Vector2(gs.x - gs.hx * 800.0, gs.y - gs.hy * 800.0)
			hold = 0.0
		var plan := {"target": target if place == null else place, "hold": hold, "fire": g.aim_car != null and g.aim_car.hostile}
		if target != null:
			plan.th = _nose(v, bot, _at(T, target), NOSE_DEG)
		return plan
	if id == Pilot.BASILISK:
		var target = _nearest(at, threats)
		var flyer := GunneryScript._is_flyer(target)
		return {"target": target, "hold": 500.0 if flyer else 600.0, "want": 0.0 if flyer else 45.0, "look": _at(T, target),
			"fire": g.aim_car != null and g.aim_car.hostile}
	if id == Pilot.SHRIKE:
		return _missiles(v, bot, threats, gs)
	if id == Pilot.KILN:
		var target = _nearest(at, threats, true)
		var hold := 350.0
		if target == gs and gs.state in ["station", "transit"]:
			hold = 480.0
		var p := _at(T, target)
		var d := at.distance_to(p)
		var fwd := Vector3(cos(sim.pod.th), sin(sim.pod.th), 0.0)
		var cone: float = rad_to_deg(fwd.angle_to(p - at))
		return {"target": target, "hold": hold, "look": p, "th": _nose(v, bot, p, 45.0),
			"fire": d <= float(mount.reach) - 10.0 and cone <= 24.0 and float(mount.hot) <= 0.0}
	if id == Pilot.VESPER:
		return _pulse(v, bot, threats)
	if id == Pilot.ORRERY:
		var target = _nearest(at, threats, true)
		var plan := {"target": target, "hold": 600.0, "look": _at(T, target)}
		if gs != null and at.distance_to(Vector3(gs.x, gs.y, gs.z)) <= float(mount.send_reach) - 50.0:
			var other := false
			for c in threats:
				if c != gs and _reach_of(at, c) <= float(mount.reach):
					other = true
					break
			var in_orbit := false
			for o in mount.orbs:
				in_orbit = in_orbit or o.state == "orbit"
			if not other:
				plan.look = Vector3(gs.x, gs.y, gs.z)
				plan.fire = in_orbit and not bot.press and g.aim_car == gs
				bot.press = bool(plan.fire)
				return plan
		bot.press = false
		return plan
	return {"target": null}


## The Shrike: the gaze on up to four threats in turn, each until it locks, then a press.
func _missiles(v, bot: Bot, threats: Array, gs) -> Dictionary:
	var sim = v.sim
	var T = v.traffic_net
	var g = v.gunnery
	var mount = v.craft.weapon
	var at := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
	var target = _nearest(at, threats)
	var plan := {"target": target, "hold": 1000.0 if GunneryScript._is_flyer(target) else 600.0, "want": 0.0 if GunneryScript._is_flyer(target) else 100.0}
	for c in bot.skip.keys():
		bot.skip[c] = float(bot.skip[c]) - STEP
		if float(bot.skip[c]) <= 0.0:
			bot.skip.erase(c)
	var homed := {}
	for m in mount.missiles:
		if m.target != null:
			homed[m.target] = true
	var cands := []
	for c in threats:
		if mount.locks.has(c) or bot.skip.has(c) or (homed.has(c) and c != gs) or _reach_of(at, c) > float(mount.reach) - 100.0:
			continue
		cands.append(c)
	cands.sort_custom(func(a, b) -> bool: return _reach_of(at, a) < _reach_of(at, b))
	var want := mini(int(mount.max_locks), mount.locks.size() + cands.size())
	var locked: int = mount.locks.size()
	if bot.press:
		bot.press = false
		return plan
	if locked > 0 and (locked >= want or bot.stuck) and float(mount.reload) <= 0.0 and int(mount.loaded) >= locked:
		bot.stuck = false
		plan.fire = true
		bot.press = true
		bot.looking = null
		return plan
	if locked < want and not cands.is_empty():
		if bot.looking == null or not cands.has(bot.looking):
			bot.looking = cands[0]
			bot.look_t = 0.0
		bot.look_t += STEP
		if bot.look_t > 1.5:      # (no lock in time: something in front of it; the next, and this one later)
			print("  no lock in 1.5 s on a %s %.0f m off: the aim on %s %.0f m out (%s)" % ["raider" if not GunneryScript._is_flyer(bot.looking) else bot.looking.kind,
				_reach_of(at, bot.looking), g.aim_kind, g.aim_dist, "a commuter" if g.aim_car != null and not g.aim_car.hostile else ("it" if g.aim_car == bot.looking else ("another threat" if g.aim_car != null else "nothing"))])
			bot.skip[bot.looking] = 4.0
			bot.looking = null
			bot.stuck = true      # (fire what is locked: the next is behind the one locked, or behind traffic)
		else:
			plan.look = _at(T, bot.looking)
	return plan


## The Vesper: into the densest group of threats; a press, charged, with one inside 400 m and that group reached.
func _pulse(v, bot: Bot, threats: Array) -> Dictionary:
	var sim = v.sim
	var mount = v.craft.weapon
	var at := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
	var best = null
	var most := 0
	var bd := INF
	for c in threats:
		var p := Vector3(c.x, c.y, sim.pod.z)
		var m := 0
		for o in threats:
			m += int(_reach_of(p, o) <= 400.0)
		var d := _flat(at, c)
		if m > most or (m == most and d < bd):
			most = m
			best = c
			bd = d
	var here := 0
	for o in threats:
		here += int(_reach_of(at, o) <= 400.0)
	var plan := {"target": best, "hold": 0.0}
	if bot.press:
		bot.press = false
		return plan
	if float(mount.charge) <= 0.0 and float(mount.ring_t) < 0.0 and here >= 1 and (here >= most or bd > 1500.0):
		plan.fire = true
		bot.press = true
	return plan


## m from `at` to threat c as the weapons reach it: a flyer in the round, a raider over the ground.
static func _reach_of(at: Vector3, c) -> float:
	if GunneryScript._is_flyer(c):
		return at.distance_to(Vector3(c.x, c.y, c.z))
	return Vector2(c.x - at.x, c.y - at.y).length()


static func _flat(at: Vector3, c) -> float:
	return Vector2(c.x - at.x, c.y - at.y).length()


## The nearest of `of` to `at` (over the ground; `round`: a flyer in the round).
static func _nearest(at: Vector3, of: Array, round := false):
	var best = null
	var bd := INF
	for c in of:
		var d := _reach_of(at, c) if round else _flat(at, c)
		if d < bd:
			bd = d
			best = c
	return best


## The nose toward p (sims' frame), at most `most` degrees off the road's way.
func _nose(v, bot: Bot, p: Vector3, most: float) -> float:
	var sim = v.sim
	var h := _along(sim, bot.rail)
	var to := Vector2(p.x - sim.pod.x, p.y - sim.pod.y)
	if to.length() < 20.0:
		return h.angle()
	return h.angle() + clampf(h.angle_to(to), -deg_to_rad(most), deg_to_rad(most))


## The weave: a gunship's shot fired at the craft (seen leaving the muzzle, coming its way), or a drone diving straight at
## it, and it slides hard across the way it was not going (toward the road's middle when near an edge).
func _weave(v, bot: Bot) -> void:
	var sim = v.sim
	var F = v.raids.flyers
	var at := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
	var pv := Vector3(sim.pod.vx, sim.pod.vy, 0.0)
	bot.since_dodge += STEP
	bot.dodge_t = maxf(bot.dodge_t - STEP, 0.0)
	var incoming := -1.0      # s until it would be on the craft
	for s in F.shots:
		if int(s.n) <= bot.seen_shot:
			continue
		bot.seen_shot = int(s.n)
		var sp: Vector3 = s.p
		var sv: Vector3 = s.v
		if at.distance_to(sp) < 3000.0:
			incoming = maxf(incoming, _meets(sp - at, sv - pv, Flyers.SHOT_LIFE))
	for f in F.all():
		if f.kind == "drone" and f.state == "dive" and at.distance_to(Vector3(f.x, f.y, f.z)) < 700.0:
			incoming = maxf(incoming, _meets(Vector3(f.x, f.y, f.z) - at, Vector3(f.vx, f.vy, f.vz) - pv, 2.5))
	if incoming < 0.0 or bot.since_dodge < DODGE_EVERY:
		return
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	var lat := _lat(v, bot)
	var limit: float = R.w[i] * 0.5 - EDGE
	var dir := -signf(bot.lat_v) if absf(bot.lat_v) > 5.0 else (1.0 if bot.dodges % 2 == 0 else -1.0)
	if absf(lat) > limit * 0.5:
		dir = -signf(lat)
	bot.dodge_dir = dir
	bot.dodge_t = minf(incoming, 3.0) + 0.3
	bot.since_dodge = 0.0
	bot.dodges += 1


## Will something now at `rel` from the craft, going `rel_v` relative to it, pass within DODGE_MISS of it inside `most` s
## if both go on as they go (what a pilot judges of a shot or a dive coming his way)? -> s until it is nearest, or -1.
static func _meets(rel: Vector3, rel_v: Vector3, most: float) -> float:
	var vv := rel_v.length_squared()
	if vv < 1.0:
		return -1.0
	var t := clampf(-rel.dot(rel_v) / vv, 0.0, most)
	if t <= 0.0 or (rel + rel_v * t).length() > DODGE_MISS:
		return -1.0
	return t


## The craft's velocity for a plan: along the road toward its target, `hold` m short of it (turning round where it is
## behind), at most A_ALONG of change a second; across it into the target's line, or the dodge's way, at most A_LAT;
## kept on the road.
func _drive(v, bot: Bot, plan: Dictionary) -> Vector2:
	var sim = v.sim
	var target = plan.get("target")
	var h := _along(sim, bot.rail)
	var right := Vector2(h.y, -h.x)
	var want_v := 0.0
	var lat_want := 0.0
	bot.since_turn += STEP
	if target != null:
		var tp: Vector2 = target if target is Vector2 else Vector2(target.x, target.y)
		var its := Vector2.ZERO if target is Vector2 else Vector2(target.hx, target.hy) * float(target.v)
		var at := Vector2(sim.pod.x, sim.pod.y)
		var to := tp - at
		var gap := to.dot(h)
		var hold := float(plan.get("hold", 600.0))
		if gap < -TURN_GAP and bot.since_turn >= TURN_EVERY and not (hold <= 0.0 and gap > -400.0):      # (behind: turn round, scripted: put down facing the other way, from rest)
			bot.since_turn = 0.0
			bot.rail = -bot.rail
			bot.turns += 1
			plan.turned = true
			sim.respawn_on(sim.pod.path, sim.pod.hint, bot.rail)
			h = _along(sim, bot.rail)
			right = Vector2(h.y, -h.x)
			gap = to.dot(h)
			bot.speed = 0.0
			bot.lat_v = 0.0
		want_v = clampf(its.dot(h) + 1.2 * (gap - hold), 0.0, V_MAX)
		lat_want = clampf((to.dot(right) - float(plan.get("want", 0.0))) * 2.0, -LAT_V, LAT_V)
	if bot.dodge_t > 0.0:
		lat_want = bot.dodge_dir * LAT_V
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	var lat := _lat(v, bot)
	var limit: float = R.w[i] * 0.5 - EDGE
	if (lat >= limit and lat_want > 0.0) or (lat <= -limit and lat_want < 0.0):
		lat_want = 0.0           # (kept on the road)
		if bot.dodge_t > 0.0:
			bot.dodge_dir = -bot.dodge_dir
	if (lat >= limit and bot.lat_v > 0.0) or (lat <= -limit and bot.lat_v < 0.0):
		bot.lat_v = 0.0
	bot.speed = move_toward(bot.speed, want_v, A_ALONG * STEP)
	bot.lat_v = move_toward(bot.lat_v, lat_want, A_LAT * STEP)
	return h * bot.speed + right * bot.lat_v


## The pod's place across its road from the road's middle, m to the right of the bot's way.
static func _lat(v, bot: Bot) -> float:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	var h := Vector2(R.tx[i], R.ty[i]) * bot.rail
	return Vector2(sim.pod.x - R.px[i], sim.pod.y - R.py[i]).dot(Vector2(h.y, -h.x))


## A weapon's kill that is not one of the raid's threats (a raider of its pack, or a flyer) is noted.
static func _note_kill(c, pack: Array, bad: Array) -> void:
	if not (c.hostile and (pack.has(c) or GunneryScript._is_flyer(c))):
		bad.append(c)


## How far raider c is outside city k's town zone, m along its road (0 inside); INF off the zone's road.
static func _outside(R, c, k: int) -> float:
	var zone: Dictionary = R._zone(k)
	if c.road != int(zone.road):
		return INF
	var z: Vector2i = zone.z
	return maxf(maxf(float(z.x) - c.f, c.f - float(z.y)), 0.0) * 24.0


# --- ruling AI: the gunship's fire at a pilot in the open inside its reach ---------------------------------------

## The gunship alone (no raiders, no drones), the GUN safe; the craft shuttled along the zone's road at GUNFIRE_V
## through the gunship's reach (on past it to 1,500 m beyond over the ground, then turned round, scripted), straight and
## level, or weaving (`weave`: the bot's dodges); `seconds` of it. Hits a minute in the open inside its reach.
func _gunfire(id: String, weave: bool) -> void:
	print("gunfire, %s, %s" % [id, "weaving" if weave else "straight and level"])
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var sim = v.sim
	var T = v.traffic_net
	var R = v.raids
	sim.P.obstacleCollisions = false
	T.collide = false
	T._hw_time = -1.0e9
	R.first_after = 1.0
	R._count = 2
	R._lull_len = 1.0
	R.pack_size = Vector2i(0, 0)
	R.drones = Vector2i(0, 0)
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	var hits := {"gunship": 0}
	R.hit_taken.connect(func(source: String) -> void: hits[source] = int(hits.get(source, 0)) + 1)
	var t := 0.0
	while R.state != "called" and t < 5.0:
		var w := _along(sim, 1)
		await _frame(v, w * 1000.0, w.angle())
		t += STEP
	var zone: Dictionary = R._zone(R.city)
	sim.respawn_on(int(zone.road), zone.z.x - 400, 1)
	t = 0.0
	while R.state == "called" and t < 2.0:
		var w := _along(sim, 1)
		await _frame(v, w * 500.0, w.angle())
		t += STEP
	var F = R.flyers
	if R.state != "on" or F.gunship() == null:
		_check("gunfire: a raid with the gunship on (state \"%s\")" % R.state, false)
		v.queue_free()
		await process_frame
		return
	var bot := Bot.new()
	bot.speed = gunfire_v
	var exposed := 0.0         # s in the open inside its reach
	var at_you := 0
	t = 0.0
	while t < seconds and R.state == "on":
		var gs = F.gunship()
		var at := Vector3(sim.pod.x, sim.pod.y, sim.pod.z)
		var h := _along(sim, bot.rail)
		var to := Vector2(gs.x - at.x, gs.y - at.y)
		var turned := false
		if to.dot(h) < -1500.0:
			bot.rail = -bot.rail
			bot.turns += 1
			sim.respawn_on(sim.pod.path, sim.pod.hint, bot.rail)
			h = _along(sim, bot.rail)
			turned = true
		for s in F.shots:
			if int(s.n) > bot.seen_shot and bool(s.pilot):
				at_you += 1
		if weave:
			_weave(v, bot)
		else:
			for s in F.shots:
				bot.seen_shot = maxi(bot.seen_shot, int(s.n))
		var vel := _drive(v, bot, {"target": null})
		vel = h * gunfire_v + Vector2(h.y, -h.x) * bot.lat_v
		var d := at.distance_to(Vector3(gs.x, gs.y, gs.z))
		if d <= Flyers.SHOT_REACH and d > Flyers.HOLD_FIRE and not F._covered(at.x, at.y, at.z, gs.z):
			exposed += STEP
		await _frame(v, vel, h.angle() if not turned else _along(sim, bot.rail).angle())
		t += STEP
	sections += 1
	var line := "gunfire (%s at %.0f m/s, SHOT_EVERY %.2f s): %d hits taken in %.0f s in the open inside its reach (%.1f a minute), %d shots at the craft (%.1f a minute of it), %d dodges, %d turns round, %.0f s flown" % [
		"weaving" if weave else "straight and level", gunfire_v, Flyers.SHOT_EVERY, int(hits.gunship), exposed, int(hits.gunship) * 60.0 / maxf(exposed, 1.0), at_you, at_you * 60.0 / maxf(exposed, 1.0), bot.dodges, bot.turns, t]
	lines.append(line)
	print(line)
	R.reset()
	v.queue_free()
	await process_frame
