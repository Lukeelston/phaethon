## The fire control's targets (view/gunnery.gd: alive, hp_of, damage, threats) and the hook for a weapon that fires for
## itself (view/weapons/weapon_mount.gd: own_fire, fire, status). In the VR seat on the Network (XR off), the Basilisk,
## Raids pinned on (the director made at load); once the seat has flown a few frames the world is held still (traffic
## emptied, the view no longer stepped) and the fire control is asked, or stepped, on its own:
##   check_damage_commuter  damage(commuter, 9, at) returns false, the commuter is still in traffic, one strike counted
##                          and told (struck_commuter), a spark drawn; with quiet, nothing at all (no strike, no hit, no
##                          spark, no signal)
##   check_damage_raider    a raider of the raid's pack, among threats(), its full HP 6, takes five hits and is alive; the
##                          sixth returns true, killed told once while it was still in traffic, then it is gone from
##                          traffic, kills one more, in a burst of fire and smoke
##   check_fake_flyer       a flyer (a script-made object with a flyer's fields, hp_max 2) in a stub flyers module set on
##                          the director: alive, its full HP 2, led along its own climb from its own height (not the
##                          aim's); damage(f, 2, at) returns true, the stub's hit called once with 2, killed told once, and
##                          it is no longer alive; a gunship's burst is three times a raider's
##   check_own_fire_hook    a mount whose own_fire() is true has fire() called every stepped frame with the frame's delta,
##                          pulling following the trigger while it is ready to fire (and not while it is not), and no bolt
##                          is made while the trigger is held; the same mount not firing for itself makes bolts. Its
##                          status word is said on the strip (view._power_say) when it changes to a word, never twice
##                          running, never when it goes blank
## Headless: --xr-mode off --audio-driver Dummy -s res://tests/test_gun_targets.gd -- --mute
## Prints GUN TARGETS PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 90.0
const SECTIONS := 4
## A flyer as the fire control reads one (Task 2's raid_flyers.gd Flyer): a Car's fields and a flyer's own.
const FLYER := """extends RefCounted
var id := 0
var kind := "drone"
var x := 0.0
var y := 0.0
var z := 0.0
var hx := 1.0
var hy := 0.0
var v := 0.0
var vz := 0.0
var hostile := true
var flyer := true
var hp := 2
var hp_max := 2
var r := 6.0
"""
## A flyers module as the fire control asks one: has(f), and hit(f, n) (the module counts a flyer's hits: at 0 HP it is
## destroyed, and hit says so). It keeps every call.
const FLYERS := """extends RefCounted
var kept: Array = []
var calls: Array = []
func has(f) -> bool:
	return kept.has(f)
func hit(f, n: int) -> bool:
	calls.append([f, n])
	f.hp -= n
	if f.hp <= 0:
		kept.erase(f)
		return true
	return false
"""
const TARGET_LAYER := ["alive", "hp_of", "damage", "threats", "add_fx", "play"]
const MOUNT_HOOK := ["own_fire", "fire", "status"]
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var _next_id := 991000


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + label)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var raids_were := [Raids.pinned, Raids.enabled]
	var chase_were := [Chase.pinned, Chase.enabled]
	Raids.pinned = true      # (on: the director is made at load, and its flyers are where the fire control asks)
	Raids.enabled = true
	Chase.pinned = true
	Chase.enabled = false
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = OS.get_user_data_dir().path_join("test_gun_targets_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	var v = await _seat(Pilot.BASILISK)
	var g = v.gunnery
	var missing := []
	if g != null:
		for m: String in TARGET_LAYER:
			if not g.has_method(m):
				missing.append("g." + m)
		for m: String in MOUNT_HOOK:
			if not g.mount.has_method(m):
				missing.append("mount." + m)
	if v.raids != null and not ("flyers" in v.raids):
		missing.append("raids.flyers")
	check("the Basilisk's fire control (%s), the raid's director (%s), the target layer and the mount's hook (missing: %s)" % [g != null,
		v.raids != null, missing], g != null and v.raids != null and missing.is_empty())
	if g != null and v.raids != null and missing.is_empty():
		# From here the world is still: the fire control is asked or stepped alone, every vehicle where the test puts it.
		v.traffic_net.cars.clear()
		v.raids.pack.clear()
		g.power = 1.0
		check_damage_commuter(v, g)
		sections += 1
		check_damage_raider(v, g)
		sections += 1
		check_fake_flyer(v, g)
		sections += 1
		check_own_fire_hook(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	Seat.vehicle_override = ""
	Raids.pinned = raids_were[0]
	Raids.enabled = raids_were[1]
	Chase.pinned = chase_were[0]
	Chase.enabled = chase_were[1]
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	check("every section ran to its end (%d of %d)" % [sections, SECTIONS], sections == SECTIONS)
	print("GUN TARGETS %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


## The VR seat in `id` on the Network, a few frames flown (the view then no longer stepped).
func _seat(id: String):
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for i in 10:
		v._process(DT)
	return v


## A vehicle on the craft's road `ahead` m on, standing still: a commuter, or a raider of the raid's pack.
func _car(v, hostile: bool, ahead := 300.0):
	var T = v.traffic_net
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var c = T.Car.new()
	_next_id += 1
	c.id = _next_id
	c.kind = T.CAR
	c.road = sim.pod.path
	c.dir = 1
	c.f = clampf(float(sim.pod.hint) + ahead / float(Sim.NET_STEP), 0.0, R.N - 2.0)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = hostile
	T._place(c)
	c.v = 0.0
	T.cars.append(c)
	if hostile:
		v.raids.pack.append(c)
	return c


## The burst's sizes in the fire control's effects: {kind: size} of its fire, smoke and flash.
static func _burst_sizes(g) -> Dictionary:
	var out := {}
	for f: Dictionary in g._fx:
		if f.kind in ["fireball", "smoke", "flash"]:
			out[f.kind] = float(f.size)
	return out


# --- the checks ----------------------------------------------------------------------------------------------

func check_damage_commuter(v, g) -> void:
	var T = v.traffic_net
	var c = _car(v, false)
	var at := Vector3(c.x, c.y, T.body_height(c))
	var told := []
	var on_struck := func(car) -> void: told.append(car)
	g.struck_commuter.connect(on_struck)
	g._fx.clear()
	var strikes: int = g.commuter_strikes
	var hits: int = g.hits
	var killed: bool = g.damage(c, 9, at)
	var sparks: int = g._fx.filter(func(f): return f.kind == "spark").size()
	check("damage(commuter, 9, at) returns %s (false); still in traffic (%s) and alive (%s); strikes %d -> %d (one more), told %d time(s), %d spark(s), hits %d -> %d" % [
		killed, T.cars.has(c), g.alive(c), strikes, g.commuter_strikes, told.size(), sparks, hits, g.hits],
		not killed and T.cars.has(c) and g.alive(c) and g.commuter_strikes == strikes + 1 and told == [c] and sparks == 1 and g.hits == hits + 1)
	g._fx.clear()
	strikes = g.commuter_strikes
	hits = g.hits
	var quiet_killed: bool = g.damage(c, 9, at, true)
	check("... quiet: returns %s (false), strikes %d -> %d (unmoved), told %d time(s) (still once), hits %d -> %d, %d effect(s) drawn, still in traffic (%s)" % [
		quiet_killed, strikes, g.commuter_strikes, told.size(), hits, g.hits, g._fx.size(), T.cars.has(c)],
		not quiet_killed and g.commuter_strikes == strikes and told.size() == 1 and g.hits == hits and g._fx.is_empty() and T.cars.has(c))
	g.struck_commuter.disconnect(on_struck)
	T.cars.erase(c)


func check_damage_raider(v, g) -> void:
	var T = v.traffic_net
	var c = _car(v, true)
	var at := Vector3(c.x, c.y, T.body_height(c))
	var told := []                  # [the car, still in traffic when told]
	var on_killed := func(car) -> void: told.append([car, T.cars.has(car)])
	g.killed.connect(on_killed)
	var threats: Array = g.threats()
	var kills: int = g.kills
	var early := []
	for k in 5:
		early.append(g.damage(c, 1, at))
	var alive_after_five: bool = g.alive(c)
	g._fx.clear()
	var sixth: bool = g.damage(c, 1, at)
	var burst := _burst_sizes(g)
	check("a raider among threats() (%s), its full HP %d (6): five hits %s leave it alive (%s); the sixth returns %s, killed told %s, gone from traffic (%s), kills %d -> %d, a burst (%s)" % [
		threats.has(c), g.hp_of(c), early, alive_after_five, sixth, told, not T.cars.has(c), kills, g.kills, burst],
		threats.has(c) and g.hp_of(c) == 6 and early == [false, false, false, false, false] and alive_after_five and sixth
		and told == [[c, true]] and not T.cars.has(c) and not g.alive(c) and g.kills == kills + 1 and burst.has("fireball") and burst.has("smoke"))
	g.killed.disconnect(on_killed)
	v.raids.pack.erase(c)


func check_fake_flyer(v, g) -> void:
	var flyer_script := GDScript.new()
	flyer_script.source_code = FLYER
	var flyers_script := GDScript.new()
	flyers_script.source_code = FLYERS
	if flyer_script.reload() != OK or flyers_script.reload() != OK:
		check("the stub flyer and flyers module compile", false)
		return
	var stub = flyers_script.new()
	var was = v.raids.flyers
	v.raids.flyers = stub
	var sim = v.sim
	var f = flyer_script.new()
	f.id = 7001
	f.x = sim.pod.x + 400.0
	f.y = sim.pod.y + 150.0
	f.z = sim.pod.z + 120.0
	f.hx = 0.6
	f.hy = 0.8
	f.v = 90.0
	f.vz = 25.0
	stub.kept.append(f)
	var told := []
	var on_killed := func(t) -> void: told.append(t)
	g.killed.connect(on_killed)
	# Led along its own climb from its own height: the aim's height set far from it.
	g.aim_sim = Vector3(f.x, f.y, f.z - 300.0)
	var lead: Vector3 = g._lead(f)
	var way := Vector3(f.hx * f.v, f.hy * f.v, f.vz)
	var off: Vector3 = lead - Vector3(f.x, f.y, f.z)
	check("a flyer in the module is alive (%s), its full HP %d (2); led %.1f m along its own way and climb (%.4f of it), from its own height (lead %.1f m up; it %.1f, the aim %.1f)" % [
		g.alive(f), g.hp_of(f), off.length(), off.normalized().dot(way.normalized()), lead.z, f.z, g.aim_sim.z],
		g.alive(f) and g.hp_of(f) == 2 and off.length() > 1.0 and off.normalized().dot(way.normalized()) > 0.9999 and lead.z > f.z)
	var kills: int = g.kills
	g._fx.clear()
	var at := Vector3(f.x, f.y, f.z)
	var killed: bool = g.damage(f, 2, at)
	var drone_burst := _burst_sizes(g)
	check("damage(flyer, 2, at) returns %s (true); the module's hit called %s (once, with 2), killed told %d time(s) (once, it), alive %s, kills %d -> %d, a burst (%s)" % [
		killed, stub.calls.map(func(c): return c[1]), told.size(), g.alive(f), kills, g.kills, drone_burst],
		killed and stub.calls.size() == 1 and stub.calls[0][0] == f and stub.calls[0][1] == 2 and told == [f] and not g.alive(f)
		and g.kills == kills + 1 and drone_burst.has("fireball") and drone_burst.has("smoke") and drone_burst.has("flash"))
	var gun = flyer_script.new()
	gun.id = 7002
	gun.kind = "gunship"
	gun.x = f.x
	gun.y = f.y
	gun.z = f.z
	stub.kept.append(gun)
	g._fx.clear()
	var gun_killed: bool = g.damage(gun, 2, Vector3(gun.x, gun.y, gun.z))
	var gun_burst := _burst_sizes(g)
	var thrice := not drone_burst.is_empty() and gun_burst.size() == drone_burst.size()
	for k in drone_burst:
		thrice = thrice and gun_burst.has(k) and is_equal_approx(float(gun_burst[k]), 3.0 * float(drone_burst[k]))
	check("a gunship shot down (%s): its burst %s, three times a raider's %s (%s)" % [gun_killed, gun_burst, drone_burst, thrice], gun_killed and thrice)
	g.killed.disconnect(on_killed)
	v.raids.flyers = was


## A mount that fires for itself (missiles, a beam, a pulse, orbs: Tasks 5 to 8), or not (`own` false: the fire
## control's bolts): always out, on its aim, and ready to fire while `ready`; it keeps each fire() call.
class OwnFire extends "res://view/weapons/weapon_mount.gd":
	var own := true
	var ready := true
	var word := ""
	var at := Vector3.ZERO      # its muzzle (global)
	var calls: Array = []       # [delta, pulling] a call

	func own_fire() -> bool:
		return own

	func fire(_g, delta: float, pulling: bool) -> void:
		calls.append([delta, pulling])

	func status() -> String:
		return word

	func is_out() -> bool:
		return true

	func ready_to_fire() -> bool:
		return ready

	func deploy_t() -> float:
		return 1.0

	func on_aim(_target_render: Vector3) -> bool:
		return true

	func muzzles() -> Array:
		return [at]

	func origin() -> Vector3:
		return at


func check_own_fire_hook(v, g) -> void:
	var real = g.mount
	var m := OwnFire.new()
	m.at = v.cam.global_position - v.cam.global_transform.basis.z * 3.0
	g.mount = m
	g.want_out = true
	g.hold_fire = false
	g.trigger = false
	g._bolts.clear()
	var shots: int = g.shots
	# The trigger: off, held, held while the mount is not ready, off.
	var held := []
	var ready := []
	for i in 40:
		held.append(i >= 10 and i < 30)
		ready.append(i < 20 or i >= 30)
	var bolts_held := 0
	for i in held.size():
		g.trigger = held[i]
		m.ready = ready[i]
		g.step(DT)
		if held[i]:
			bolts_held = maxi(bolts_held, g._bolts.size())
	g.trigger = false
	m.ready = true
	var want := []
	for i in held.size():
		want.append(held[i] and ready[i])
	var pulls: Array = m.calls.map(func(c): return c[1])
	var deltas_ok: bool = m.calls.all(func(c): return is_equal_approx(float(c[0]), DT))
	check("own_fire: fire() called on every stepped frame (%d of %d) with its delta (%s), pulling following the trigger while ready (%s), no bolt while it was held (%d in flight, %d shots)" % [
		m.calls.size(), held.size(), deltas_ok, pulls == want, bolts_held, g.shots - shots],
		m.calls.size() == held.size() and deltas_ok and pulls == want and bolts_held == 0 and g.shots == shots)
	# The same mount not firing for itself: the fire control's bolts, and no fire() call.
	m.own = false
	m.calls.clear()
	shots = g.shots
	g.trigger = true
	for i in 20:
		g.step(DT)
	g.trigger = false
	check("... the same mount not firing for itself fires the fire control's bolts (%d shots in 20 frames held), fire() not called (%d)" % [g.shots - shots, m.calls.size()],
		g.shots > shots and m.calls.is_empty())
	m.own = true
	# Its status word on the strip: said when it changes to a word, not again while it stands, not when it goes blank.
	var said := []
	for w: String in ["LOCK 3", "LOCK 3", "", "RELOAD", "RELOAD"]:
		m.word = w
		v._power_note = ""
		g.step(DT)
		said.append(v._power_note)
	check("its status words LOCK 3, LOCK 3, (none), RELOAD, RELOAD are said on the strip as %s (LOCK 3, -, -, RELOAD, -)" % [said],
		said == ["LOCK 3", "", "", "RELOAD", ""])
	g.mount = real
	for i in int(2.0 / DT):      # (the bolts in flight land)
		g.step(DT)
