## Fixed guns (view/weapons/fixed_guns_mount.gd on view/arms/<craft>_arms.gd, fired by view/gunnery.gd): the Phaethon's
## engine-nose cannons and the Talon's wing guns fire straight ahead, aimed by pointing the craft; an assist bends the
## bolts onto a raider within the craft's assistDeg (3 degrees) of the bore. In the VR seat on the Network, the craft
## on a straight at 1,500 mph; once the gun is armed the world is held still and the fire control stepped on its own,
## so each vehicle stands exactly where it is put, at its angle off the bore (its `hold_fire` as if the trigger held).
## Raids are off, so no raid is called; a raider put down is a raid's: the pack of a director of the test's own, made
## once the gun is armed (the assist looks among the raid's pack):
##   lazy                   no fire control until the GUN is first armed; armed, one is made, the craft's own figures
##                          on it, and its arms are out in 1 s
##   bore                   the aim runs along the heading of what the guns ride (the Phaethon's engines, the Talon's
##                          pod: Ruling 13), level with the road, not down the drawn barrels; in a 10 degree slide it
##                          stays on the heading, the slip off it
##   check_dead_ahead_kill  a raider 800 m ahead within 1 degree of the bore is knocked out within 2 s
##   check_assist_cone      one at 2.5 degrees is hit, the lead pip on it; one at 6 degrees, on the road as that one
##                          is, takes no hit in 2 s of fire, and with the cone opened to 8 degrees the same one is hit
##                          (so the cone spares it, not the ground)
##   check_line_of_sight    one in the cone behind a crest (a ridge across the bore, in a fire control whose ground
##                          has one) is not taken, nor hit, in 2 s; the crest gone, it is hit within 2 s
##   check_commuter_ahead   a commuter dead ahead is struck (sparks), never knocked out
##   check_heat             held on for fireS s it overheats; it fires again coolS s later
##   check_talon_rate       the Talon fires 18 shots a second (within 10%)
##   check_stowed_no_fire   thrown to SAFE it fires nothing, stowing or stowed
## Run with --fixed-fps 120: --headless --xr-mode off --fixed-fps 120 --audio-driver Dummy -s res://tests/test_fixed_guns.gd -- --mute
## Prints FIXED GUNS PASS.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Sim := preload("res://sim/craft_sim.gd")
const GunneryScript := preload("res://view/gunnery.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PREFS := "user://vr_prefs.json"
const DT := 1.0 / 120.0
const MPH := 0.44704
const SPEED := 1500.0 * MPH     # m/s
const STRAIGHT := 1600.0        # m of road ahead that must run straight and level
const SECTIONS := 2             # the Phaethon, the Talon
## A fire control whose ground has a ridge across the bore (check_line_of_sight): crest_half m either side of crest_at
## along crest_along (the sims' plane), crest_top high.
const CREST_GUN := """extends "res://view/gunnery.gd"
var crest_at := Vector2.INF
var crest_along := Vector2.ZERO
var crest_half := 25.0
var crest_top := -INF
func ground_at(x: float, y: float) -> float:
	var h := super.ground_at(x, y)
	if crest_at != Vector2.INF and absf((Vector2(x, y) - crest_at).dot(crest_along)) <= crest_half:
		h = maxf(h, crest_top)
	return h
"""
var failures := 0
var checks := 0
var sections := 0               # (a section that dies on a script error never counts itself: the verdict then fails)
var _next_id := 990000
var _way := 1


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
	Raids.pinned = true      # (no raid of its own: the test puts each vehicle where it wants it)
	Raids.enabled = false
	Chase.pinned = true
	Chase.enabled = false
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = OS.get_user_data_dir().path_join("test_fixed_guns_")
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	print("phaethon")
	var v = await _seat(Pilot.STANDARD)
	var g = _arm(v, "phaethon", {"rate": 10.0, "boltV": 1300.0, "reach": 2600.0})
	if g != null:
		check_bore(v, g, "phaethon")
		check_dead_ahead_kill(v, g)
		check_assist_cone(v, g)
		check_commuter_ahead(v, g)
		check_heat(v, g)
		check_stowed_no_fire(v, g)
		check_slide(v, g, "phaethon")
		check_line_of_sight(v, g)
		sections += 1
	v.queue_free()
	await process_frame
	print("talon")
	v = await _seat(Pilot.TALON)
	g = _arm(v, "talon", {"rate": 18.0, "boltV": 1400.0, "reach": 2200.0})
	if g != null:
		check_bore(v, g, "talon")
		check_talon_rate(v, g)
		check_slide(v, g, "talon")
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
	print("FIXED GUNS %s (%d checks, %d failed)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


# --- the flight ------------------------------------------------------------------------------------------

## The VR seat in `id` on the Network, on a straight at 1,500 mph, a few frames flown.
func _seat(id: String):
	Seat.vehicle_override = id
	var v = Seat.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	_on_a_straight(v)
	for i in 10:
		_hold_speed(v)
		v._process(DT)
	_hold_speed(v)
	return v


## Put the craft at the start of a straight, level stretch of its road (STRAIGHT m of it ahead).
func _on_a_straight(v) -> void:
	var sim = v.sim
	var span := int(ceil(STRAIGHT / float(Sim.NET_STEP)))
	var roads := [int(sim.pod.path)]
	for r in sim.roads.size():
		if r != roads[0]:
			roads.append(r)
	for r: int in roads:
		var R = sim.roads[r]
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 200:
			continue
		var from := clampi(int(sim.pod.hint), 100, R.N - span - 100) if r == roads[0] else 100
		for i in range(from, R.N - span - 100, 6):
			var th := atan2(R.ty[i], R.tx[i])
			var h0: float = sim.road_h(r, float(i))
			var ok := true
			for k in range(i, i + span + 1, 2):
				if absf(angle_difference(th, atan2(R.ty[k], R.tx[k]))) > deg_to_rad(0.15) or absf(sim.road_h(r, float(k)) - h0) > 1.0 \
						or sim.in_pressure(r, k):
					ok = false
					break
			if ok:
				sim.respawn_on(r, i, 1)
				_way = 1
				print("  on road %s at sample %d: %.1f km straight and level ahead, %.0f m wide" % [R.name, i, STRAIGHT / 1000.0, R.w[i]])
				return
	print("  (no straight found: flying where it starts)")


## All three bodies at 1,500 mph along the road under the pod, level.
func _hold_speed(v) -> void:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * _way * SPEED
		b.vy = R.ty[i] * _way * SPEED
		b.vz = 0.0


## Arm the GUN (the first time: the fire control is made then), hold the world still, and bring the guns out.
## The fire control, or null (its failure told).
func _arm(v, id: String, want: Dictionary):
	check("%s: with the GUN never armed no fire control is made (%s)" % [id, v.gunnery], v.gunnery == null)
	v.gun_wanted = true
	v._process(DT)
	var g = v.gunnery
	var mount = g.mount if g != null else null
	var script_path: String = (mount.get_script() as Script).resource_path if mount != null else ""
	check("%s: armed, its fire control is made, firing through its fixed guns (%s) on its arms" % [id, script_path],
		g != null and script_path.ends_with("fixed_guns_mount.gd") and mount.get("arms") == v.craft.arms and v.craft.weapon == mount)
	if g == null or not script_path.ends_with("fixed_guns_mount.gd"):
		return null
	var got := {"rate": g.get("rate"), "boltV": g.get("bolt_v"), "reach": g.get("reach")}
	check("%s: the gun's figures are the craft's own (%s; want %s), its assist %.1f deg" % [id, got, want, mount.assist_deg()],
		got == want and is_equal_approx(mount.assist_deg(), 3.0))
	# From here the world is still: the fire control is stepped alone, every vehicle where the test puts it.
	v.traffic_net.cars.clear()
	if v.raids == null:      # (its raiders are a raid's pack, as in a flight: a director of the test's own, never updated)
		var director = Raids.new()
		v.add_child(director)
		director.traffic = v.traffic_net
		director.build(v)
		v.raids = director
		v.traffic_net.raids = director
	_hold_speed(v)
	g.want_out = true
	var frames := 0
	while not mount.is_out() and frames < int(2.0 / DT):
		g.step(DT)
		frames += 1
	check("%s: out in %.2f s (1.0), the barrels run out of their ports (deploy %.2f)" % [id, frames * DT, mount.deploy_t()],
		mount.is_out() and absf(frames * DT - 1.0) <= 2.0 * DT)
	return g


## The bore: where the aim is looked for along, in the sims' frame.
static func _bore(v, g) -> Array:
	var ray: Array = g.mount.aim_ray(v.cam)
	return [g.to_sim(ray[0]), GunneryScript.dir_to_sim(ray[1])]


## A vehicle `dist` m out along the bore, `deg` degrees to its left, at a standstill (the world is still).
func _put(v, g, deg: float, dist: float, hostile: bool):
	var T = v.traffic_net
	var sim = v.sim
	var bore := _bore(v, g)
	var o: Vector3 = bore[0]
	var d: Vector3 = bore[1]
	var ahead := Vector2(d.x, d.y).normalized()
	var left := Vector2(-ahead.y, ahead.x)
	var at := Vector2(o.x, o.y) + (ahead * cos(deg_to_rad(deg)) + left * sin(deg_to_rad(deg))) * dist
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var near := int(sim.pod.hint)
	for i in range(maxi(0, int(sim.pod.hint) - 10), mini(R.N - 1, int(sim.pod.hint) + int(3000.0 / float(Sim.NET_STEP)))):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	_next_id += 1
	c.id = _next_id
	c.kind = T.CAR
	c.road = road
	c.dir = _way
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = hostile
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	if hostile and v.raids != null:
		v.raids.pack.append(c)
	return c


## Hold fire for `seconds` (the trigger let go first, so the gun's count of fire on end starts again); `until`
## ends it early. Returns the frames held.
static func _fire(g, seconds: float, until := Callable()) -> int:
	g.hold_fire = false
	g.step(DT)
	g.hold_fire = true
	var frames := 0
	while frames < int(seconds / DT):
		g.step(DT)
		frames += 1
		if until.is_valid() and until.call():
			break
	g.hold_fire = false
	return frames


## Let the bolts in flight land, and the vehicles go.
static func _clear(v, g) -> void:
	g.hold_fire = false
	for i in int(2.0 / DT):
		g.step(DT)
	v.traffic_net.cars.clear()
	if v.raids != null:
		v.raids.pack.clear()
	g._damage.clear()


# --- the checks ----------------------------------------------------------------------------------------------

## The heading of what the guns ride (sims' plane, a unit vector): the Phaethon's engines (between their two), the
## Talon's pod.
static func _heading(v, id: String) -> Vector2:
	var sim = v.sim
	if id == "phaethon":
		return Vector2(cos(sim.eL.th) + cos(sim.eR.th), sin(sim.eL.th) + sin(sim.eR.th)).normalized()
	return Vector2(cos(sim.pod.th), sin(sim.pod.th))


func check_bore(v, g, id: String) -> void:
	var sim = v.sim
	var bore := _bore(v, g)
	var head := _heading(v, id)
	var travel := Vector3(head.x, head.y, 0.0)      # (level: the craft held level along a level road)
	var barrels := Vector3.ZERO
	for m: Transform3D in v.craft.arms.muzzles():
		barrels += -m.basis.z
	var barrels_sim := GunneryScript.dir_to_sim(barrels.normalized())
	var off := rad_to_deg((bore[1] as Vector3).angle_to(travel))
	print("  (%s in the VR seat: its drawn barrels stand %.2f deg off its way, %s)" % [id, rad_to_deg(barrels_sim.angle_to(travel)),
		"below" if barrels_sim.z < travel.z else "above"])
	var mid := Vector3.ZERO
	for p: Vector3 in g.mount.muzzles():
		mid += p
	mid /= maxf(1.0, g.mount.muzzles().size())
	check("%s: the bore runs along the heading of what the guns ride, level with the road (%.4f deg off it), from between its muzzles (%.3f m)" % [id, off,
		g.to_render(bore[0]).distance_to(mid)], off < 0.01 and g.to_render(bore[0]).distance_to(mid) < 0.01 and g.mount.muzzles().size() == 2)


## Ruling 13: in a slide (the craft's way 10 degrees off its heading) the bore stays on the heading of what the guns
## ride, the slip off it: the bolts leave the nose.
func check_slide(v, g, id: String) -> void:
	var sim = v.sim
	var head := _heading(v, id)
	var slip := deg_to_rad(10.0)
	var way := Vector2(head.x * cos(slip) - head.y * sin(slip), head.x * sin(slip) + head.y * cos(slip))
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = way.x * SPEED
		b.vy = way.y * SPEED
		b.vz = 0.0
	var d: Vector3 = _bore(v, g)[1]
	var off_head := rad_to_deg(Vector2(d.x, d.y).angle_to(head))
	var off_way := rad_to_deg(Vector2(d.x, d.y).angle_to(way))
	_hold_speed(v)
	check("%s: in a 10 degree slide the bore stays on the heading (%.3f deg off it), %.2f deg off the way it goes" % [id, absf(off_head), absf(off_way)],
		absf(off_head) < 0.01 and absf(absf(off_way) - 10.0) < 0.05)


## A raider in the cone behind a crest is not taken (the assist's line of sight): a fire control whose ground has a
## ridge across the bore halfway out, 15 m over the bore, in place of the craft's own; then the ridge taken away.
func check_line_of_sight(v, g) -> void:
	var script := GDScript.new()
	script.source_code = CREST_GUN
	if script.reload() != OK:
		check("the crest fire control compiles", false)
		return
	for p in [g._servo] + g._gun_audio:      # (its players hang on the arms)
		if is_instance_valid(p):
			p.get_parent().remove_child(p)
			p.free()
	v.remove_child(g)
	g.free()
	var cg = script.new()
	v.add_child(cg)
	cg.build(v)
	v.gunnery = cg
	cg.want_out = true
	var frames := 0
	while not cg.mount.is_out() and frames < int(2.0 / DT):
		cg.step(DT)
		frames += 1
	var hw: float = v.sim.roads[v.sim.pod.path].w[int(v.sim.pod.hint)] * 0.5
	var dist := minf(800.0, 0.8 * hw / tan(deg_to_rad(2.5)))
	var raider = _put(v, cg, 2.5, dist, true)
	var bore := _bore(v, cg)
	var o: Vector3 = bore[0]
	var d: Vector3 = bore[1]
	cg.crest_along = Vector2(d.x, d.y).normalized()
	cg.crest_at = Vector2(o.x, o.y) + cg.crest_along * dist * 0.5
	cg.crest_top = o.z + 15.0
	var hits: int = cg.hits
	var taken := {"any": false}
	_fire(cg, 2.0, func() -> bool:
		taken.any = taken.any or cg.aim_car == raider
		return false)
	var behind_hits: int = cg.hits - hits
	cg.crest_at = Vector2.INF
	hits = cg.hits
	var frames_clear := _fire(cg, 2.0, func() -> bool: return cg.hits > hits)
	check("a raider %.0f m out at 2.5 deg behind a crest is not taken (%s) nor hit (%d hits in 2 s); the crest gone, it is hit after %.2f s" % [dist,
		taken.any, behind_hits, frames_clear * DT], not taken.any and behind_hits == 0 and cg.hits > hits)
	_clear(v, cg)


func check_dead_ahead_kill(v, g) -> void:
	var car = _put(v, g, 0.5, 800.0, true)
	var kills: int = g.kills
	var shots: int = g.shots
	var frames := _fire(g, 2.0, func() -> bool: return not v.traffic_net.cars.has(car))
	check("a raider 800 m ahead, 0.5 deg off the bore, is knocked out in %.2f s (want under 2): %d shots, %d out, gone from traffic %s" % [frames * DT,
		g.shots - shots, g.kills - kills, not v.traffic_net.cars.has(car)], not v.traffic_net.cars.has(car) and g.kills == kills + 1 and frames * DT < 2.0)
	_clear(v, g)


func check_assist_cone(v, g) -> void:
	var T = v.traffic_net
	var hw: float = v.sim.roads[v.sim.pod.path].w[int(v.sim.pod.hint)] * 0.5
	var dist := minf(800.0, 0.8 * hw / tan(deg_to_rad(2.5)))     # (on the road: the line to it over the road's own deck)
	var near = _put(v, g, 2.5, dist, true)
	var hits: int = g.hits
	var seen := {"pip": false, "ring": false}      # (a lambda's locals are copies: what it sees goes in here)
	var frames := _fire(g, 2.0, func() -> bool:
		seen.pip = seen.pip or (g.sight.visible and g.aim_car == near)
		seen.ring = seen.ring or (g.get("bore_ring") != null and g.bore_ring.visible)
		return g.hits > hits)
	check("a raider %.0f m out at 2.5 deg is hit (%d hits in %.2f s), the lead pip on it (%s), the boresight ring shown (%s)" % [dist, g.hits - hits,
		frames * DT, seen.pip, seen.ring], g.hits > hits and seen.pip and seen.ring)
	_clear(v, g)
	var wide_dist := minf(800.0, 0.8 * hw / tan(deg_to_rad(6.0)))     # (on the road as the 2.5 degree one is: the ground does not spare it)
	var wide = _put(v, g, 6.0, wide_dist, true)
	hits = g.hits
	var shots: int = g.shots
	var wide_seen := {"pip": false}
	_fire(g, 2.0, func() -> bool:
		wide_seen.pip = wide_seen.pip or g.sight.visible
		return false)
	var wide_hits: int = g.hits - hits
	var wide_shots: int = g.shots - shots
	# the same one with the cone opened to 8 degrees: hit (it was the cone that spared it)
	var cone_was: float = g.mount._assist
	g.mount._assist = 8.0
	hits = g.hits
	var opened := _fire(g, 2.0, func() -> bool: return g.hits > hits)
	var opened_hits: int = g.hits - hits
	g.mount._assist = cone_was
	_clear(v, g)
	check("one %.0f m out at 6 deg, on the road, takes no hit in 2 s (%d hits; the guns fired %d down the bore), no pip on it (%s); with the cone opened to 8 deg it is hit after %.2f s (%d)" % [
		wide_dist, wide_hits, wide_shots, wide_seen.pip, opened * DT, opened_hits],
		wide_hits == 0 and wide_shots > 10 and not wide_seen.pip and opened_hits > 0)
	T.cars.erase(wide)
	v.raids.pack.erase(wide)


func check_commuter_ahead(v, g) -> void:
	var car = _put(v, g, 0.0, 500.0, false)
	var struck: int = g.commuter_strikes
	var kills: int = g.kills
	var told := []
	var on_struck := func(c) -> void: told.append(c)
	g.struck_commuter.connect(on_struck)
	_fire(g, 2.0)
	check("a commuter 500 m dead ahead is struck (%d strikes, told %d), never knocked out (%d out, still in traffic %s)" % [g.commuter_strikes - struck,
		told.size(), g.kills - kills, v.traffic_net.cars.has(car)],
		g.commuter_strikes > struck and g.kills == kills and v.traffic_net.cars.has(car) and told.size() == g.commuter_strikes - struck)
	g.struck_commuter.disconnect(on_struck)
	_clear(v, g)


func check_heat(v, g) -> void:
	var row: Dictionary = Pilot.traits(Pilot.STANDARD).weapon
	g.hold_fire = false
	for i in int(1.0 / DT):      # (cooled: a pause, then the trigger held on and on)
		g.step(DT)
	g.hold_fire = true
	var t := 0.0
	var hot_at := -1.0
	var again_at := -1.0
	var while_hot := 0          # shots on frames that began hot
	while t < float(row.fireS) + float(row.coolS) + 1.0 and again_at < 0.0:
		var shots: int = g.shots
		var was_hot: bool = g.hot > 0.0
		g.step(DT)
		t += DT
		if was_hot:
			while_hot += g.shots - shots
		if hot_at < 0.0 and g.hot > 0.0:
			hot_at = t
		elif hot_at > 0.0 and not was_hot and g.shots > shots:
			again_at = t
	g.hold_fire = false
	check("held on, the Phaethon's cannons overheat after %.2f s of fire (%.1f) and fire again %.2f s later (%.1f); none while hot (%d)" % [hot_at, row.fireS,
		again_at - hot_at, row.coolS, while_hot],
		absf(hot_at - float(row.fireS)) <= 2.0 * DT and absf(again_at - hot_at - float(row.coolS)) <= 3.0 * DT and while_hot == 0)
	_clear(v, g)


func check_talon_rate(v, g) -> void:
	var shots: int = g.shots
	var frames := _fire(g, 2.0)
	var rate: float = (g.shots - shots) / (frames * DT)
	check("the Talon's wing guns fire %.1f shots a second (18, within 10%%)" % rate, absf(rate - 18.0) <= 1.8)
	_clear(v, g)


func check_stowed_no_fire(v, g) -> void:
	_put(v, g, 0.5, 800.0, true)
	g.want_out = false          # (the GUN switch thrown to SAFE)
	var shots: int = g.shots
	_fire(g, 0.5)
	var stowing: int = g.shots - shots
	_fire(g, 1.5)
	var ring_shown: bool = g.get("bore_ring") != null and g.bore_ring.visible
	check("thrown to SAFE it fires nothing, stowing or stowed (%d shots in 2 s with a raider ahead; deploy %.2f), no sight (%s, %s)" % [g.shots - shots,
		g.mount.deploy_t(), g.sight.visible, ring_shown],
		g.shots == shots and stowing == 0 and g.mount.deploy_t() == 0.0 and not g.sight.visible and not ring_shown)
	_clear(v, g)
