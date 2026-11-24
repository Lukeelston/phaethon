## Raids: the jolt (view/network_raids.gd hit_taken; craft_view.gd and vr_cockpit.gd jolt; the stage 1 plan, task 10).
##   one hit per grace   a raider held overlapping the craft gives one hit_taken a GRACE: 1 in 0.9 s, 3 in 2.1 s;
##                       one clear of every body (further than CONTACT_CRAFT) gives none
##   buzz both           jolt buzzes both controllers
##   camera still        in the VR cockpit jolt(1.0) moves neither the camera, the headset's origin nor the rig, over 0.3 s
##   thump               the jolt's thump is a synthesised stream, played when the flight has sound and not when muted
##   bump not double     with obstacle collisions on, a ram that also gives bump events gives hit_taken once in 0.9 s
##   end reason          the last raider shot gives "cleared" with no reason
##   flat shake          in the flat view the jolt shakes for at most 0.15 s and then rests
##   raids off           with raids off nothing is created
## Run with --fixed-fps 120. Prints RAID JOLT PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const STEP := 1.0 / 120.0
var failures := 0
var hits := 0
var _ids := 0
var _lat := 0.0            # the craft's lateral place on its road, which a raider on it shares


## A cockpit that notes what it is told to buzz and which bumps it feels.
class Spy extends "res://vr/vr_cockpit.gd":
	var buzzed := []
	var bump_hits := 0

	func _buzz(c: XRController3D, amp: float, dur: float, delay := 0.0) -> void:
		buzzed.append([c, amp, dur, delay])
		super(c, amp, dur, delay)

	func _on_hit(who: String, strength: float) -> void:
		if strength == 0.5:
			bump_hits += 1
		super(who, strength)


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = "E3@9000"
	View.best_dir = OS.get_user_data_dir().path_join("test_raid_jolt_")
	DirAccess.remove_absolute(View.best_dir + "network.json")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = "ember"
	Chase.pinned = true
	Chase.enabled = false
	Raids.pinned = true
	Raids.enabled = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _cockpit():
	var v = Spy.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	v.muted = false       # (the runner passes --mute: this test hears the thump)
	return v


## A raider on `road` at sample f, at rest, in lane 0, as the director's own are made.
func _raider(T, road: int, f: float):
	var c = T.Car.new()
	_ids += 1
	c.id = 960700 + _ids
	c.road = road
	c.dir = 1
	c.f = f
	c.v = 0.0
	c.vdes = 0.0
	c.turn_p = 0.0
	c.nsp_road = -1
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.kind = T.DEMON
	c.visual = T.DEMON
	c.hostile = true
	c.name = "RAIDER"
	c.a_up = 3.0 * T.G
	c.a_lat = 11.0 * T.G
	c.headway = 0.45
	c.col = T.HOSTILE_COL
	T._place(c)
	T.cars.append(c)
	return c


## Fly `seconds` with the craft and the raider `c` held where they are.
func _hold(v, c, f: float, seconds: float) -> void:
	var T = v.traffic_net
	var t := 0.0
	while t < seconds - 1.0e-6:
		for body in v.sim.bodies:
			body.vx = 0.0
			body.vy = 0.0
		c.f = f
		c.lat = _lat
		c.v = 0.0
		v.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
		v._process(STEP)
		await process_frame
		for o in T.cars.duplicate():
			if o != c:
				T.cars.erase(o)
		t += STEP


## The craft at rest on its road, raids reset and then on with one raider `gap` samples ahead of it.
func _stage(v, gap: float):
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	R.reset()
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	sim.respawn_on(int(sim.pod.path), int(sim.pod.hint), 1)
	T.cars.clear()
	T.race_state = "raid"
	R.state = "on"
	R.city = 0
	var pc = T._pod_as_car()
	_lat = pc.lat
	var c = _raider(T, pc.road, pc.f + gap)
	c.lat = _lat
	T._place(c)
	R.pack = [c]
	return c


func _state(v) -> Array:
	return [v.rig.transform, v.origin.transform, v.cam.transform]


func _same(a: Array, b: Array) -> bool:
	for k in a.size():
		var x: Transform3D = a[k]
		var y: Transform3D = b[k]
		if (x.origin - y.origin).length() > 1.0e-6:
			return false
		for j in 3:
			if (x.basis[j] - y.basis[j]).length() > 1.0e-6:
				return false
	return true


func _run() -> void:
	var v = await _cockpit()
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	if R == null or not R.has_signal("hit_taken"):
		_check("raids pinned on and the director has hit_taken", false)
		print("RAID JOLT FAIL (%d failures)" % failures)
		quit(1)
		return
	T._hw_time = -1.0e9
	R.hit_taken.connect(func(_s): hits += 1)

	# one hit per grace window
	var c = _stage(v, 0.0)
	hits = 0
	await _hold(v, c, c.f, 0.9)
	var h09 := hits
	c = _stage(v, 0.0)
	hits = 0
	await _hold(v, c, c.f, 2.1)
	var h21 := hits
	c = _stage(v, 200.0)         # (200 samples is some 4.8 km: far clear of every body)
	hits = 0
	await _hold(v, c, c.f, 0.5)
	var hfar := hits
	_check("a raider on the craft: %d hit in 0.9 s (want 1), %d in 2.1 s (want 3); one 4.8 km off: %d (want 0)" % [h09, h21, hfar],
		h09 == 1 and h21 == 3 and hfar == 0)

	# the buzz: both hands
	v.buzzed.clear()
	v.jolt(1.0)
	var both: bool = v.buzzed.any(func(b): return b[0] == v.hands.left) and v.buzzed.any(func(b): return b[0] == v.hands.right)
	_check("jolt buzzes both controllers (%d pulses)" % v.buzzed.size(), both)

	# the camera and rig stay still through it
	var still := true
	c = _stage(v, 200.0)
	await _hold(v, c, c.f, 0.1)
	var before := _state(v)
	v.jolt(1.0)
	var t := 0.0
	while t < 0.3 - 1.0e-6:
		await _hold(v, c, c.f, STEP)
		t += STEP
		if not _same(before, _state(v)):
			still = false
	_check("over 0.3 s of the jolt the VR rig, origin and camera do not move", still)

	# the thump
	var played: bool = v.thump != null and v.thump.stream is AudioStreamWAV
	var len_s: float = v.thump.stream.get_length() if played else -1.0
	_check("the thump is a synthesised stream (%.2f s) on a player%s" % [len_s, "" if played else " (none)"], played and len_s > 0.1 and len_s < 1.0)
	if v.thump != null:
		v.thump.queue_free()
		v.thump = null
	v.muted = true
	v.jolt(1.0)
	_check("muted: the jolt makes no sound", v.thump == null)
	v.muted = false

	# a ram with obstacle collisions on: bumps do not make it two
	sim.P.obstacleCollisions = true
	T.collide = true
	c = _stage(v, 0.0)
	hits = 0
	v.bump_hits = 0
	await _hold(v, c, c.f, 0.9)
	_check("obstacle collisions on, a ram: %d hit_taken in 0.9 s (want 1) with %d bump events felt (want some)" % [hits, v.bump_hits],
		hits == 1 and v.bump_hits > 0)
	sim.P.obstacleCollisions = false
	T.collide = false

	# the end: the last raider shot is a clean "cleared"
	c = _stage(v, 200.0)
	R.on_kill(c)
	T.cars.erase(c)
	R.update(STEP)
	_check("the last raider shot: result \"%s\", reason \"%s\"" % [R.result, R._why], R.result == "cleared" and R._why == "")

	v.queue_free()
	await process_frame

	# the flat view: a brief shake, then rest; raids off: nothing
	var f = View.new()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	var flat_ok: bool = f.has_method("jolt")
	var shaken := false
	var rest := true
	if flat_ok:
		f.jolt(1.0)
		for i in roundi(0.14 / STEP):
			f._process(STEP)
			if absf(f.cam.h_offset) > 1.0e-6 or absf(f.cam.v_offset) > 1.0e-6:
				shaken = true
		for i in roundi(0.1 / STEP):
			f._process(STEP)
		rest = f.cam.h_offset == 0.0 and f.cam.v_offset == 0.0
	_check("flat view: shakes (%s) within 0.15 s, at rest after (%s)" % [shaken, rest], flat_ok and shaken and rest)
	f.queue_free()
	await process_frame
	Raids.enabled = false
	var o = View.new()
	root.add_child(o)
	await process_frame
	_check("raids off: no director, no thump player", o.raids == null and o.thump == null)
	o.queue_free()
	await process_frame
	Raids.enabled = true

	print("RAID JOLT %s" % ("PASS" if failures == 0 else "FAIL (%d failures)" % failures))
	quit(1 if failures else 0)
