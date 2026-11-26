## Raids' drones (view/raid_flyers.gd; the stage 2 plan, task 2). In the VR seat on the Network (XR off), the Phaethon,
## Raids pinned on (but for the first), each raid put down by the director's own arrival (an alarm, its city set to
## the first ground city that is not the start's, a frame: as test_raid_hunt.gd's _raid_on):
##   check_off_builds_nothing   Raids off: no director, no flyers node; 60 frames flown, the drone's model not loaded
##   check_spawn                the first raid's arrival puts down 6 drones, the second's 7; each within its town zone
##                              +-1 km and DRONE_ALT above its road, in groups of two to four; 3 s on, each still
##                              within the zone +-1 km, and each still circling at its height
##   check_dive_kills_commuter  drones alone (no raiders), the pilot still in the zone: within 30 s a dive ends on a
##                              commuter, within DIVE_HIT of it: it is out of traffic, the raid's lost one more,
##                              commuter_lost at its place
##   check_dive_on_pilot        the pilot parked under a group, every dive at the pilot (pilot_share 1): a dive takes at
##                              least 1.5 s from its start to the pod's height, drawn every frame of it where its figures
##                              say and nose first (its model's -Z, the lamp's end, along its way); hit_taken "drone" as
##                              it ends, on the craft but short of the pod (DIVE_SHORT: never
##                              through the cockpit); then three dives (a, b, c) of the group's own, made to land 0.3 s
##                              and 1.2 s after the first: b's, landing on the craft, adds no hit (the shared grace), c's
##                              does
##   check_shot_down            a drone takes one hit and is still there; g.damage(drone, 2, at) returns true: it is gone
##                              from the module, kills_by.drone 1, kills one more, one fewer drawn
##   check_pick_and_lead        a ray down through a drone's centre: ray_pick returns it at its distance less its pick
##                              radius (within 1 m); 7 m off its centre, {}; the fire control's _find takes it (over the
##                              ground under it), and a locked one 8 m off the ray is held in the lock's gate (ray_flyer);
##                              g._lead_at(drone, 0.0) on a diving drone lies ahead of it along its velocity by the bolt's
##                              flight time, its z included; the gaze sight's brackets round a drone are 2.5 x its pick
##                              radius (15 m), a vehicle's still its kind's (a car 30 m, a transport 46)
##   check_cleared_needs_all    every raider killed, drones left: the raid is still on, and the dash's line is not empty
##                              and says no "0 RAIDERS"; the last drone killed: "cleared", nothing left drawn
##   check_far_origin           the floating origin moved 30 km and back: each drone drawn within 0.5 m of where its
##                              figures say (Vector3(x - org_x, z, -(y - org_y))); then a restart (reset): none left, none
##                              drawn
##   check_away_counts_flyers   the pilot beyond R_KEEP of the town but within it of a drone: the away clock does not
##                              run; that drone's group gone, it runs and the raid is lost ("away"): the rest gone, none drawn
##   check_cost                 ten drones over 600 frames, diving on the commuters about: the module's update, mean
##                              and worst (told; the mean under COST_MS), and the commuters they took; the fastest any
##                              drone flew (its place frame to frame) at most DIVE_V_MAX
##   check_speed_cap            a group with one commuter under it, the pilot far off: the commuter at the group's point
##                              going away (its meeting place 1 km on, out of DIVE_V_MAX x DIVE_S): for 1 s every drone
##                              of the group circles on, looking; the same commuter 0.9 km short of the point (its meeting
##                              place 0.1 km past it): one dives on it within LOOK_EVERY frames
##   (and at the end: over every frame of the test, scripted dives too, no drone flew faster than DIVE_V_MAX)
## Run with --fixed-fps 120 (traffic and the director run on the engine's frame time; a frame is let pass for every
## step). Prints RAID FLYERS PASS. Puts user://vr_prefs.json back as it found it.
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Art := preload("res://view/raid_flyer_art.gd")
const PREFS := "user://vr_prefs.json"
const STEP := 1.0 / 120.0
const KEEP_M := 1000.0           # m: a drone stays within its town zone by this
const COST_MS := 0.1             # ms a frame: ten drones' update, mean (the plan's 0.5 ms is the director, flyers and weapons together)
const SECTIONS := 11
const SPEED_MARGIN := 0.5        # m/s: the cap's numeric margin (a drone's speed is read from its place frame to frame)
var failures := 0
var sections := 0                # (a section that dies on a script error never counts itself: the verdict then fails)
var last_ms := 0.0               # the view's _process on the last frame (told for the arrivals: the first loads the drone's model)
var track_speed := true          # each frame, every drone's speed read from its place before and after it (not while the test moves them)
var fastest := 0.0               # m/s: the fastest any drone flew a frame, the whole test
var fastest_since := 0.0         # ... since a check set it to 0


func _initialize() -> void:
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.spot_override = "E3@9000"
	Cockpit.vehicle_override = Pilot.STANDARD
	Cockpit.best_dir = OS.get_user_data_dir().path_join("test_raid_flyers_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Chase.pinned = true
	Chase.enabled = false
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _run() -> void:
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	await check_off_builds_nothing()
	Raids.pinned = true
	Raids.enabled = true
	var v = await _cockpit()
	var R = v.raids
	if R == null or not ("flyers" in R):
		_check("raids pinned on: the cockpit has a director (%s) with flyers" % [R], false)
	else:
		v.traffic_net._hw_time = -1.0e9      # (no street racer drops in: it would hold traffic's floor)
		await check_spawn(v)
		await check_dive_kills_commuter(v)
		await check_dive_on_pilot(v)
		await check_shot_down(v)
		await check_pick_and_lead(v)
		await check_cleared_needs_all(v)
		await check_cost(v)              # (while traffic is about the zone: the drones dive)
		await check_speed_cap(v)
		await check_far_origin(v)
		await check_away_counts_flyers(v)
		R.reset()
		var cap: float = R.flyers.DIVE_V_MAX
		_check("over every frame of this test (but those the test moved them on), scripted dives too: the fastest any drone flew %.1f m/s (DIVE_V_MAX %.0f)" % [fastest, cap],
			fastest > 0.0 and fastest <= cap + SPEED_MARGIN)
	_check("every section ran to its end (%d of %d)" % [sections, SECTIONS], sections == SECTIONS)
	v.queue_free()
	await process_frame
	Raids.pinned = false
	Raids.enabled = false
	Cockpit.vehicle_override = ""
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID FLYERS %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


# --- the stage ---------------------------------------------------------------------------------------------------

func _cockpit():
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	return v


## One frame: the craft held still (or at `speed` along its road), the view stepped, a frame let pass.
func _frame(v, speed := 0.0) -> void:
	var sim = v.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in sim.bodies:
		b.vx = R.tx[i] * speed
		b.vy = R.ty[i] * speed
		b.vz = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	var F = v.raids.flyers if v.raids != null else null
	var was := []
	if F != null and track_speed:
		for f in F.all():
			was.append([f, f.x, f.y, f.z])
	var t0 := Time.get_ticks_usec()
	v._process(STEP)
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0
	for w in was:
		var f = w[0]
		if F.has(f):
			var dx: float = f.x - w[1]
			var dy: float = f.y - w[2]
			var dz: float = f.z - w[3]
			var flown := sqrt(dx * dx + dy * dy + dz * dz) / STEP
			fastest = maxf(fastest, flown)
			fastest_since = maxf(fastest_since, flown)
	await process_frame


func _fly(v, seconds: float) -> void:
	for i in maxi(1, roundi(seconds / STEP)):
		await _frame(v)


## The raid's city: the first ground city that is not the start's.
func _city(v) -> int:
	var sim = v.sim
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## The craft still in the middle of city k's town zone, on its road; `settle` frames flown (traffic fills in).
func _in_zone(v, k: int, settle := 0) -> void:
	var zone: Dictionary = v.raids._zone(k)
	v.sim.respawn_on(int(zone.road), (int(zone.z.x) + int(zone.z.y)) / 2, 1)
	for i in settle:
		await _frame(v)


## A raid called on city k and arrived (the director's own arrival puts the pack and the drones down): the next frame.
func _raid_on(v, k: int) -> void:
	var R = v.raids
	R.reset()
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R._alarm()
	R.city = k                   # (whichever it picked: this one)
	await _frame(v)


## Drone f's place as drawn: its instance (the batch draws the drones in all()'s order) in the batch's buffer.
static func _drawn(F, k: int) -> Vector3:
	var buf: PackedFloat32Array = F.batch.multimesh.buffer
	return Vector3(buf[k * 12 + 3], buf[k * 12 + 7], buf[k * 12 + 11])


## Drone k's nose as drawn (its model's -Z, where its lamp is), a unit vector in the render frame.
static func _drawn_nose(F, k: int) -> Vector3:
	var buf: PackedFloat32Array = F.batch.multimesh.buffer
	return -Vector3(buf[k * 12 + 2], buf[k * 12 + 6], buf[k * 12 + 10]).normalized()


## Where drone f should be drawn: its place in the sims' frame about the view's floating origin.
static func _render(v, f) -> Vector3:
	return Vector3(f.x - v.org_x, f.z, -(f.y - v.org_y))


## The worst of the drones' drawn places against their figures, m; INF if the batch does not draw them all.
static func _drawn_worst(v, F) -> float:
	if F.batch == null or F.batch.multimesh.visible_instance_count != F.count("drone"):
		return INF
	var worst := 0.0
	var k := 0
	for f in F.all():
		if f.kind != "drone":
			continue
		worst = maxf(worst, _drawn(F, k).distance_to(_render(v, f)))
		k += 1
	return worst


## Drone f against city k's town zone: [m outside it (0 within), m above the road at the zone's sample nearest it].
static func _against_zone(v, f, k: int) -> Array:
	var sim = v.sim
	var zone: Dictionary = v.raids._zone(k)
	var road: int = zone.road
	var z: Vector2i = zone.z
	var R = sim.roads[road]
	var near := z.x
	var nd := INF
	for i in range(z.x, z.y + 1):
		var d := Vector2(R.px[i] - f.x, R.py[i] - f.y).length_squared()
		if d < nd:
			nd = d
			near = i
	return [sqrt(nd), float(f.z) - sim.net_height(road, float(near))]


# --- the checks --------------------------------------------------------------------------------------------------

func check_off_builds_nothing() -> void:
	Raids.pinned = true
	Raids.enabled = false
	var v = await _cockpit()
	for i in 60:
		await _frame(v, 800.0)
	var node = v.find_child("raid_flyers", true, false)
	var cached := ResourceLoader.has_cached(Art.DRONE_PATH)
	sections += 1
	_check("Raids off: no director (%s), no flyers node (%s), after 60 frames the drone's model not loaded (cached %s)" % [v.raids, node, cached],
		v.raids == null and node == null and not cached)
	v.queue_free()
	await process_frame


func check_spawn(v) -> void:
	var R = v.raids
	var k := _city(v)
	await _in_zone(v, k, 240)
	var said := []
	var ok := true
	var counts := []
	var F = null
	for raid in 2:
		await _raid_on(v, k)
		F = R.flyers
		if F == null:
			_check("the director has its flyers (%s)" % [F], false)
			return
		counts.append(F.count("drone"))
		var out := 0.0
		var lo := INF
		var hi := -INF
		var groups := {}
		for f in F.all():
			var at := _against_zone(v, f, k)
			out = maxf(out, at[0])
			lo = minf(lo, at[1])
			hi = maxf(hi, at[1])
			groups[f.group] = int(groups.get(f.group, 0)) + 1
		var sizes: Array = groups.values()
		var sized: bool = not sizes.is_empty() and sizes.all(func(n): return n >= 2 and n <= 4)
		ok = ok and out <= KEEP_M and lo >= F.DRONE_ALT.x - 2.0 and hi <= F.DRONE_ALT.y + 2.0 and sized and R.state == "on"
		said.append("raid %d: %d drones, the farthest %.0f m from the zone's road (within %.0f), %.0f to %.0f m above it (DRONE_ALT %s), groups %s (the arrival's frame %.2f ms)" % [
			R._count, F.count("drone"), out, KEEP_M, lo, hi, F.DRONE_ALT, sizes, last_ms])
	# 3 s on: within the zone still; those circling at their height
	await _fly(v, 3.0)
	var out3 := 0.0
	var lo3 := INF
	var hi3 := -INF
	var circling := 0
	for f in F.all():
		var at := _against_zone(v, f, k)
		out3 = maxf(out3, at[0])
		if f.state == "circle":
			circling += 1
			lo3 = minf(lo3, at[1])
			hi3 = maxf(hi3, at[1])
	sections += 1
	_check("%s; 3 s on, the farthest %.0f m from the zone's road, the %d circling %.0f to %.0f m above it" % ["; ".join(said), out3, circling, lo3, hi3],
		ok and counts == [6, 7] and out3 <= KEEP_M and circling > 0 and lo3 >= F.DRONE_ALT.x - 2.0 and hi3 <= F.DRONE_ALT.y + 2.0)


func check_dive_kills_commuter(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)      # (drones alone: only a dive loses a commuter)
	await _in_zone(v, k, 60)
	await _raid_on(v, k)
	var F = R.flyers
	var sig := []
	var on_lost := func(x: float, y: float): sig.append(Vector2(x, y))
	R.commuter_lost.connect(on_lost)
	var t := 0.0
	var got := {}
	var dives := 0
	while t < 30.0 and got.is_empty():
		var diving := {}
		for f in F.all():
			if f.state == "dive" and f.prey != null:
				diving[f] = f.prey
		var lost0: int = R.lost
		var sig0 := sig.size()
		await _frame(v)
		t += STEP
		var taken := 0                 # (dives that took their commuter this frame: each is one lost)
		for f in diving:
			if f.state == "dive":
				continue
			dives += 1
			var p = diving[f]
			if T.cars.has(p):
				continue
			taken += 1
			if got.is_empty():
				var body := Vector3(p.x, p.y, T.body_height(p))
				got = {"at": Vector2(p.x, p.y), "gap": Vector3(f.x, f.y, f.z).distance_to(body), "t": t}
		if not got.is_empty():
			got["lost"] = R.lost - lost0 - (taken - 1)      # (this one's share of the frame's losses: one)
			got["said"] = sig.slice(sig0)
	R.commuter_lost.disconnect(on_lost)
	var told: bool = not got.is_empty() and got.said.any(func(p: Vector2): return p.distance_to(got.at) < 3.0)
	sections += 1
	_check("drones alone over %s's zone: %d dives on commuters ended in %.1f s; the first to take one %s: %s m from it at the end (DIVE_HIT %.0f), lost %s more (want 1), commuter_lost %s at its place (%s)" % [
			v.sim.cities[k].name, dives, t, "at %.1f s" % got.t if not got.is_empty() else "(none)", "%.1f" % got.gap if not got.is_empty() else "-",
			F.DIVE_HIT, got.get("lost", "-"), got.get("said", []), told],
		not got.is_empty() and got.lost == 1 and told and got.gap <= F.DIVE_HIT and t <= 30.0)


func check_dive_on_pilot(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)      # (no raider to ram the pilot: every hit is a drone's)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	F.pilot_share = 1.0
	for f in F.all():
		f.at_pod = true               # (every drone's next dive at the pilot, as one ready with pilot_share 1 is)
		f.rest = minf(f.rest, 1.0)    # (off its rest within a second: DIVE_REST's first stagger runs to 18 s)
	# the pilot parked under a group
	var G = F._groups[0]
	sim.respawn_on(int(G.road), int(G.f), 1)
	var hits := []
	var on_hit := func(source: String): hits.append(source)
	R.hit_taken.connect(on_hit)
	await _frame(v)
	var t := 0.0
	var diver = null
	var to_height := -1.0
	var dive_t := 0.0
	var drawn_worst := 0.0
	var drawn_frames := 0
	var ended := false
	var end_gap := INF
	var nose_worst := 1.0
	while t < 15.0 and not ended:
		await _frame(v)
		t += STEP
		if diver == null:
			for f in F.all():
				if f.state == "dive" and f.at_pod:
					diver = f
					break
			continue
		dive_t += STEP
		drawn_worst = maxf(drawn_worst, _drawn_worst(v, F))
		drawn_frames += 1
		var slot: int = F.all().filter(func(o): return o.kind == "drone").find(diver)
		var way := Vector3(diver.vx, diver.vz, -diver.vy)
		if slot >= 0 and way.length() > 1.0:
			nose_worst = minf(nose_worst, _drawn_nose(F, slot).dot(way.normalized()))
		if to_height < 0.0 and diver.z <= sim.pod.z + 0.5:
			to_height = dive_t
		if diver.state != "dive":
			ended = true
			end_gap = Vector3(diver.x, diver.y, diver.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	var first_hits := hits.duplicate()
	var natural: bool = diver != null and to_height >= 1.5 and to_height <= F.DIVE_S + 2.0 * STEP and drawn_worst <= 0.5 and first_hits == ["drone"] \
		and end_gap >= F.DIVE_SHORT - 0.5 and end_gap <= F.DIVE_HIT and nose_worst > 0.99
	var said := "the first dive on the pilot %s: at the pod's height %.2f s from its start (at least 1.5), drawn on %d frames of it (the worst %.2f m off its figures; its nose along its way, the least cosine %.4f), ending %.1f m from the pod (DIVE_SHORT %.0f, DIVE_HIT %.0f), hits %s" % [
		"seen" if diver != null else "NOT seen", to_height, drawn_frames, drawn_worst, nose_worst, end_gap, F.DIVE_SHORT, F.DIVE_HIT, first_hits]
	# three dives made to land 0.3 s and 1.2 s after a first: the grace takes the second
	for f in F.all():
		f.rest = 1.0e9                # (no other dive)
	await _fly(v, F.DIVE_S + 1.5)      # (every dive ended; the grace run out)
	var waited := 0.0
	while waited < 10.0 and F.all().any(func(f): return f.group == 0 and f.state != "circle"):
		await _frame(v)                # (the group's back in its circle)
		waited += STEP
	hits.clear()
	var trio := []
	for f in F.all():
		if f.group == 0 and f.state == "circle" and trio.size() < 3:
			trio.append(f)
	var gaps := [INF, INF, INF]
	var when := [0, roundi(0.3 / STEP), roundi(1.2 / STEP)]
	var hit_at := []
	var n := 0
	while trio.size() == 3 and n < when[2] + roundi(F.DIVE_S / STEP) + 30:
		for j in 3:
			if n == when[j]:
				F._dive(trio[j], null, true)
		var was := []
		for f in trio:
			was.append(f.state)
		var hit0 := hits.size()
		await _frame(v)
		n += 1
		if hits.size() > hit0:
			hit_at.append(n)
		for j in 3:
			if was[j] == "dive" and trio[j].state != "dive":
				var gap := INF
				for b in sim.bodies:
					gap = minf(gap, Vector3(trio[j].x, trio[j].y, trio[j].z).distance_to(Vector3(b.x, b.y, b.z)))
				gaps[j] = gap
	R.hit_taken.disconnect(on_hit)
	var landed: bool = gaps.all(func(gap): return gap <= F.DIVE_HIT)
	var want_at := [when[0] + roundi(F.DIVE_S / STEP), when[2] + roundi(F.DIVE_S / STEP)]
	var timed: bool = hit_at.size() == 2 and absi(hit_at[0] - want_at[0]) <= 2 and absi(hit_at[1] - want_at[1]) <= 2
	sections += 1
	_check("%s; then three dives landing at 0, 0.3 and 1.2 s (%d drones): each within DIVE_HIT of the craft at its end (%s m), hits %s at frames %s (want two, at %s: the second's taken by the grace)" % [
			said, trio.size(), gaps.map(func(gap): return snappedf(gap, 0.1)), hits, hit_at, want_at],
		natural and trio.size() == 3 and landed and hits == ["drone", "drone"] and timed)
	F.pilot_share = F.PILOT_SHARE


func check_shot_down(v) -> void:
	var R = v.raids
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	var g = v.gunnery
	if g == null or F.count("drone") < 2:
		sections += 1
		_check("a fire control (%s) and two drones (%d)" % [g, F.count("drone")], false)
		return
	var a = F.all()[0]
	var b = F.all()[1]
	var once: bool = g.damage(a, 1, Vector3(a.x, a.y, a.z))
	var a_kept: bool = F.has(a)
	var kills0: int = R.kills
	var by0: int = int(R.kills_by.drone)
	var shown0: int = F.batch.multimesh.visible_instance_count
	var killed: bool = g.damage(b, 2, Vector3(b.x, b.y, b.z))
	await _frame(v)
	var shown1: int = F.batch.multimesh.visible_instance_count
	sections += 1
	_check("a drone's HP %d: one hit (%s) leaves it (%s, hp %d); g.damage(drone, 2, at) returns %s: gone from the module (%s), kills_by.drone %d -> %d (want 1), kills %d -> %d, drawn %d -> %d" % [
			a.hp_max, once, a_kept, a.hp, killed, not F.has(b), by0, R.kills_by.drone, kills0, R.kills, shown0, shown1],
		a.hp_max == F.DRONE_HP and not once and a_kept and killed and not F.has(b) and int(R.kills_by.drone) == 1 and by0 == 0 and R.kills == kills0 + 1
			and shown1 == shown0 - 1 and shown1 == F.count("drone"))


func check_pick_and_lead(v) -> void:
	var R = v.raids
	var F = R.flyers
	var g = v.gunnery
	var d = null
	for f in F.all():
		if f.state == "circle":
			d = f
			break
	if d == null or g == null:
		sections += 1
		_check("a circling drone (%s) and a fire control (%s)" % [d, g], false)
		return
	# straight down through its centre from 300 m above it
	var o := Vector3(d.x, d.y, d.z + 300.0)
	var down := Vector3(0, 0, -1)
	var hit: Dictionary = F.ray_pick(o, down, 2600.0)
	var on_it: bool = not hit.is_empty() and hit.car == d and absf(float(hit.t) - (300.0 - d.r)) < 1.0
	var off: Dictionary = F.ray_pick(o + Vector3(7, 0, 0), down, 2600.0)
	g._lock_car = null
	g.lock = 0.0
	g._find(o, down, STEP)
	var found: bool = g.aim_car == d and g.aim_kind == "vehicle" and absf(g.aim_dist - (300.0 - d.r)) < 1.0
	g._find(o, down, STEP)        # (the lock builds on it)
	g._find(o + Vector3(8, 0, 0), down, STEP)
	var held: bool = g.aim_car == d and g._lock_car == d
	g._lock_car = null
	g.lock = 0.0
	# the lead on a diving drone (the circling one nearest the pilot, diving on it)
	var e = null
	var ed := INF
	for f in F.all():
		var fd := Vector2(f.x - v.sim.pod.x, f.y - v.sim.pod.y).length()
		if f.state == "circle" and f != d and fd < ed:
			e = f
			ed = fd
	var lead_ok := false
	var lead_said := "no second drone"
	if e != null:
		F._dive(e, null, true)
		await _fly(v, 0.6)
		if F.has(e) and e.state == "dive":
			var at := Vector3(e.x, e.y, e.z)
			var vel := Vector3(e.hx * e.v, e.hy * e.v, e.vz)
			var lead: Vector3 = g._lead_at(e, 0.0)
			var from: Vector3 = g.to_sim(g.mount.origin())
			var speed: float = g._bolt_speed((at - from).normalized())
			var want := at
			for round in 2:      # (the bolt's flight to where it will be, reckoned again from there: as a raider's lead is)
				want = at + vel * (from.distance_to(want) / speed)
			var led := lead - at
			lead_ok = vel.length() > 1.0 and absf(e.vz) > 1.0 and led.normalized().dot(vel.normalized()) > 0.9999 and lead.distance_to(want) < 0.5 \
				and absf((lead.z - e.z) - e.vz * led.length() / vel.length()) < 0.5
			lead_said = "a diving drone %.0f m off led %.1f m along its way (%.5f of it; want %.1f, %.3f m apart), %+.1f m in height (its climb %.1f m/s)" % [ed,
				led.length(), led.normalized().dot(vel.normalized()), (want - at).length(), lead.distance_to(want), lead.z - e.z, e.vz]
		else:
			lead_said = "the dive was over (%s)" % e.state
	# the gaze sight's brackets (a turret's sight; here drawn through a mount that is out, from 150 m off): a drone's from
	# its pick radius, a vehicle's by its kind
	var brackets := {}
	if F.has(d):
		var T = v.traffic_net
		var car = T.Car.new()
		car.kind = T.CAR
		var transport = T.Car.new()
		transport.kind = T.TRANSPORT
		var real = g.mount
		var was_out: bool = g.want_out
		g.mount = OutMount.new()
		g.want_out = true
		for t in [["drone", d], ["car", car], ["transport", transport]]:
			var it = t[1]
			it.x = d.x
			it.y = d.y
			g.aim_kind = "vehicle"
			g.aim_car = it
			g.aim_sim = Vector3(d.x, d.y, d.z)
			g._draw_gaze_sight(g.to_render(g.aim_sim) + Vector3(150.0, 0.0, 0.0), v.cam)
			brackets[t[0]] = snappedf(g.sight.global_transform.basis.x.length(), 0.01)
		g.mount = real
		g.want_out = was_out
		g.aim_car = null
		g.sight.visible = false
	var sized: bool = brackets.get("drone", -1.0) == snappedf(2.5 * d.r, 0.01) and brackets.get("car", -1.0) == 30.0 and brackets.get("transport", -1.0) == 46.0
	sections += 1
	_check("a ray down through a drone's centre: picked %s at %.1f m (want %.1f, its pick radius %.0f off); 7 m off its centre %s; the fire control's aim on it (%s, \"%s\", %.1f m); held in the lock's gate 8 m off (%s); %s; the gaze sight's brackets from 150 m: %s m (a drone 2.5 x %.0f, a car 30, a transport 46)" % [
			on_it, float(hit.get("t", -1.0)), 300.0 - d.r, d.r, off, found, g.aim_kind, g.aim_dist, held, lead_said, brackets, d.r],
		on_it and off.is_empty() and found and held and lead_ok and sized)


## A mount that is out (for the gaze sight's drawing: its brackets), no bore.
class OutMount extends "res://view/weapons/weapon_mount.gd":
	func is_out() -> bool:
		return true

	func deploy_t() -> float:
		return 1.0


func check_cleared_needs_all(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	var g = v.gunnery
	var raiders: Array = R.pack.duplicate()
	for c in raiders:
		R.on_kill(c)
		T.knock_out(c)
	await _frame(v)
	var still: bool = R.state == "on" and R.result == "" and F.count("drone") > 0
	var line: String = R.text()
	var cleared0: int = int(R.tally.cleared)
	var shot := 0
	for f in F.all().duplicate():
		shot += int(g.damage(f, f.hp, Vector3(f.x, f.y, f.z)))
	await _frame(v)
	sections += 1
	_check("every raider killed (%d), %d drones left: still on (%s), the dash \"%s\"; the %d drones shot down: \"%s\" (tally cleared %d -> %d), none left (%d), none drawn (%d), kills %s" % [
			raiders.size(), shot, still, line, shot, R.result, cleared0, R.tally.cleared, F.all().size(), F.batch.multimesh.visible_instance_count, R.kills_by],
		raiders.size() > 0 and still and line != "" and not line.contains("0 RAIDERS") and shot > 0 and R.result == "cleared" and int(R.tally.cleared) == cleared0 + 1
			and F.all().is_empty() and F.batch.multimesh.visible_instance_count == 0 and int(R.kills_by.drone) == shot and int(R.kills_by.raider) == raiders.size()
			and R.kills == shot + raiders.size())


func check_far_origin(v) -> void:
	var R = v.raids
	var sim = v.sim
	var k := _city(v)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	await _frame(v)
	var org0 := Vector2(v.org_x, v.org_y)
	var here := [int(sim.pod.path), int(sim.pod.hint)]
	var there := []
	for r in sim.roads.size():
		var Rd = sim.roads[r]
		if Rd.shaft or not v.traffic_net._public_road(Rd):
			continue
		for i in range(2, Rd.N - 2, 8):
			if absf(Vector2(Rd.px[i] - sim.pod.x, Rd.py[i] - sim.pod.y).length() - 30000.0) < 300.0:
				there = [r, i]
				break
		if not there.is_empty():
			break
	var at0 := _drawn_worst(v, F)
	sim.respawn_on(there[0], there[1], 1)
	await _frame(v)
	var moved := Vector2(v.org_x, v.org_y).distance_to(org0)
	var at30 := _drawn_worst(v, F)
	sim.respawn_on(here[0], here[1], 1)
	await _frame(v)
	var back := Vector2(v.org_x, v.org_y).distance_to(org0)
	var at_back := _drawn_worst(v, F)
	var up: int = F.count("drone")
	R.reset()
	var after_reset := [F.all().size(), F.batch.multimesh.visible_instance_count]
	sections += 1
	_check("%d drones drawn within %.3f m of their figures; the floating origin moved %.1f km: within %.3f m; back (%.1f m from where it was): within %.3f m (each within 0.5); a restart: %s left, %s drawn" % [
			up, at0, moved / 1000.0, at30, back, at_back, after_reset[0], after_reset[1]],
		up > 0 and at0 <= 0.5 and moved > 29000.0 and at30 <= 0.5 and back < 100.0 and at_back <= 0.5 and after_reset == [0, 0])


func check_away_counts_flyers(v) -> void:
	var R = v.raids
	var sim = v.sim
	var T = v.traffic_net
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)      # (drones alone: a raider is not what keeps it on)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	R.away_t = 3.0
	var F = R.flyers
	track_speed = false                # (the test carries a group 170 km: not a flight)
	var e3 := [-1, -1]
	for r in sim.roads.size():
		if sim.roads[r].name == "E3":
			e3 = [r, 9000 / 24]
	sim.respawn_on(e3[0], e3[1], 1)
	# one group of drones brought to the pilot, 300 m off, held circling there
	var G = F._groups[0]
	G.x = sim.pod.x + 300.0
	G.y = sim.pod.y
	G.deck = sim.pod.z
	var near := []
	for f in F.all():
		if f.group == 0:
			f.state = "circle"
			f.prey = null
			f.rest = 1.0e9
			near.append(f)
	var far_km: float = R._gap(k) / 1000.0
	var t := 0.0
	var worst := 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
		worst = maxf(worst, R._away)
	var stayed: bool = R.state == "on"
	var nearest := INF
	for f in near:
		nearest = minf(nearest, Vector2(f.x - sim.pod.x, f.y - sim.pod.y).length())
	for f in near:
		F.destroy(f)
	var left: int = F.count("drone")
	t = 0.0
	while t < 4.0 and R.state == "on":
		await _frame(v)
		t += STEP
	sections += 1
	_check("the pilot %.0f km from the zone (beyond R_KEEP %.0f) with %d drones %.0f m off for 4 s: still on (%s), its away clock at most %.2f s; those drones gone (%d left in the zone), %.2f s later: \"%s\" (%s; away_t %.1f), %d left, %d drawn" % [
			far_km, T.R_KEEP / 1000.0, near.size(), nearest, stayed, worst, left, t, R.result, R._why, R.away_t, F.all().size(), F.batch.multimesh.visible_instance_count],
		far_km * 1000.0 > T.R_KEEP and near.size() > 0 and nearest < T.R_KEEP and stayed and worst == 0.0 and left > 0 and R.result == "lost" and R._why == "away"
			and t <= R.away_t + 0.25 and F.all().is_empty() and F.batch.multimesh.visible_instance_count == 0)
	track_speed = true


func check_cost(v) -> void:
	var R = v.raids
	var k := _city(v)
	R.pack_size = Vector2i(4, 6)
	R.drones = Vector2i(10, 10)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	var ms := []
	fastest_since = 0.0
	for j in F.all().size():
		F.all()[j].rest = 0.2 * j      # (all ten off their first rest within 2 s, so the 600 frames have their dives)
	for i in 600:
		await _frame(v)
		ms.append(float(F.update_ms))
	var mean := 0.0
	var worst := 0.0
	for x in ms:
		mean += x
		worst = maxf(worst, x)
	mean /= maxf(1.0, ms.size())
	var states := {}
	for f in F.all():
		states[f.state] = int(states.get(f.state, 0)) + 1
	sections += 1
	_check("ten drones (%d; %s at the end), 600 frames: their update %.4f ms a frame mean (under %.2f), the worst %.3f ms; %d commuters lost (to them and the raiders); the fastest any drone flew %.1f m/s (DIVE_V_MAX %.0f)" % [
			F.count("drone"), states, mean, COST_MS, worst, R.lost, fastest_since, F.DIVE_V_MAX],
		F.count("drone") == 10 and mean < COST_MS and R.lost > 0 and fastest_since > F.CIRCLE_V + 1.0 and fastest_since <= F.DIVE_V_MAX + SPEED_MARGIN)
	R.drones = Vector2i(6, 10)


func check_speed_cap(v) -> void:
	var R = v.raids
	var T = v.traffic_net
	var sim = v.sim
	var k := _city(v)
	R.pack_size = Vector2i(0, 0)
	await _in_zone(v, k, 0)
	await _raid_on(v, k)
	var F = R.flyers
	var G = F._groups[0]
	var group := []
	for f in F.all():
		f.rest = 1.0e9                 # (the other groups hold)
		f.at_pod = false
		if f.group == 0:
			group.append(f)
	# the pilot 5 km along the road from the group's point: beyond PILOT_REACH of every one of it, and traffic's own
	# spawning (R_SPAWN, 11 km and more from the pilot) at least 6 km from it, so the commuter is the only one under it
	var Rd = sim.roads[int(G.road)]
	var per: float = float(Rd.len[clampi(int(G.f), 0, Rd.N - 1)])
	var off := roundi(5000.0 / per)
	var at_i: int = int(G.f) + off if int(G.f) + off < Rd.N - 3 else int(G.f) - off
	sim.respawn_on(int(G.road), clampi(at_i, 2, Rd.N - 3), 1)
	var pilot_m := INF
	var c = T.Car.new()
	c.id = 950901
	c.kind = T.CAR
	c.road = int(G.road)
	c.dir = 1
	c.lane = 1
	c.lat = T._lane_lat(c, 1)
	c.turn_p = 0.0
	c.nsp_road = -1
	var away_states := {}
	var meet_m := INF
	for phase in 2:
		# 0: at the group's point going away (its meeting place 2 s on: 1 km past it); 1: 0.9 km short of it (within PREY_REACH; its meeting place 0.1 km past the point)
		var at_f: float = G.f if phase == 0 else G.f - 900.0 / per
		var frames := 0
		var dived := false
		while frames < (120 if phase == 0 else F.LOOK_EVERY + 2) and not dived:
			c.f = at_f
			c.dir = 1
			c.v = T.SF_V
			c.vdes = T.SF_V
			c.cruise = T.SF_V
			T._place(c)
			T.cars.clear()
			T.cars.append(c)
			for f in group:
				if f.state == "circle":
					f.rest = 0.0       # (ready: it looks at its turn)
			await _frame(v)
			frames += 1
			for f in group:
				pilot_m = minf(pilot_m, Vector2(f.x - sim.pod.x, f.y - sim.pod.y).length())
				if phase == 0:
					away_states[f.state] = int(away_states.get(f.state, 0)) + 1
					var mx: float = c.x + c.hx * c.v * F.DIVE_S - f.x
					var my: float = c.y + c.hy * c.v * F.DIVE_S - f.y
					meet_m = minf(meet_m, sqrt(mx * mx + my * my))
				elif f.state == "dive" and f.prey == c:
					dived = true
		if phase == 0:
			away_states["frames"] = frames
		else:
			away_states["dived after"] = frames if dived else -1
	T.cars.clear()
	R.reset()
	var held: bool = away_states.keys().all(func(s): return s in ["circle", "frames", "dived after"])
	sections += 1
	_check("a group of %d, the pilot %.1f km off: one commuter at its point going away at the town's limit, its meeting place at least %.0f m from each (reach %.0f): for %s frames every one circles on, looking (%s); the same commuter 0.9 km short of the point: one dives on it after %s frame(s) (within %d)" % [
			group.size(), pilot_m / 1000.0, meet_m, F.DIVE_V_MAX * F.DIVE_S, away_states.get("frames", 0), away_states, away_states.get("dived after", -1), F.LOOK_EVERY + 1],
		group.size() >= 2 and pilot_m > F.PILOT_REACH and pilot_m < 7000.0 and meet_m > F.DIVE_V_MAX * F.DIVE_S and held and int(away_states.get("frames", 0)) == 120
			and int(away_states.get("dived after", -1)) > 0 and int(away_states.get("dived after", -1)) <= F.LOOK_EVERY + 1)
