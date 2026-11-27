## The frames a pilot would feel (Raids stage 2, task 11): each first of a flight's raids, a whole frame (the view's
## _process and the frame drawn: resume to resume) against the frames before it. Windowed: the GPU's first draw of each
## new thing (its pipeline compiled, its mesh uploaded) is in it; headless none of that is. The bot of
## tests/test_raid_bot.gd flies (this extends it: its play, its rails) in the VR seat on the Network (XR off), Raids pinned
## on, obstacles off as the menu has them, one craft, from a cold start of the game: run each in its own process (the
## caller empties the profile's shader cache first, so nothing is compiled from an earlier run). In order:
##   alarm        railed along E3 at 1,000 m/s (60 frames of load, 240 more), then the director's alarm made (its _alarm,
##                as its clock would: its first), and 120 frames on along E3
##   run-in       the craft put on the called city's road 9.6 km short of its town zone, heading in (a scripted move,
##                marked: not a pilot's), the arrival held off (arrive_r 0) for 240 frames while the world there settles,
##                then let
##   arrival      the frame the pack and the drones are put down (the director's _arrive)
##   cruise       240 frames on toward the zone, the GUN safe
##   arm          the GUN thrown (the cockpit's set_gun) and the bot's play from there: the arms' deploy, then the fight
##   fight        the weapon's firsts as they come (by craft), the first drone's dive, the first hit taken, the first
##                commuter lost, the first kill; until those are in and 240 frames more, or --cap s of the raid
##   --then=3     then the raid set aside (the director's reset), its count set so its next is the flight's third, and
##                again from the alarm: its arrival with the gunship (the drones' batch made at the first), the
##                gunship's first glow and its first shot, its first hit taken
## Each first: the frame's time and its process, the median of the 30 frames before it, the difference; and the worst
## of the 3 frames after it (a first draw may come a frame late). Then the run's 12 worst frames, each with the firsts
## within 3 frames of it.
## Run windowed with sound on the Dummy driver (a flight has sound; none comes out of the machine):
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy -s res://tests/probe_raid_firsts.gd --
##   --craft=kiln [--then=3] [--cap=40]
## --cost (the cost at a full raid, the plan's budget): the director's third raid with its pack and its drones at their
## most (6 raiders, 10 drones, the gunship), the craft's weapon played by the bot from the arming on, every threat kept
## whole outside the timing (a raider's damage held far under its HP, each flyer's HP put back, each frame) so the raid
## stays full; the director (its update: raiders, flyers, the gunship's shots) and the fire control (its step: the
## weapon's own) timed by thin subclasses swapped in at load; from the arms out and the trigger's first pull, 120
## frames to settle, then --frames (600): their mean together and the worst single frame, the parts (the flyers' own update, the weapon's own figure),
## the whole frame's median. (The view's raid hooks are not in it: stage 1 measured them, 0.0x ms.)
##   With --pin=NEAR,APART the six are put along the aim's line each frame (outside the timing), NEAR m out and APART m
##   apart, PIN_DEG off it, as stage 1's whole-frame probe put them (for the fixed guns: 700,220; the pulse: 150,40), and the
##   window starts with the arms out.
##   With --size=WxH (4128x2208: a Quest 3's two eyes side by side) the view is drawn into an offscreen SubViewport that size,
##   MSAA 4x, and after the timing the GPU is read with the world held still: the raid's drawing (the flyers: the drones'
##   batch, the gunship and its glow; the raiders in traffic; the fire control's and the weapon's drawing) shown and hidden
##   turn about, 5 rounds of 30 frames a state, the viewport's own GPU time (the renderer's timer): its median with all
##   shown less all hidden (the budget: 0.3 ms), and each part's.
## Diagnostics (not the game's): --prime=arms|sight|beam|switch|gun|step|mount|fire|sounds|draw|status draws or steps one
## candidate at load, to see whether the first arming's frame is its first; --diag-shown lists what is drawn new in the
## arming frame (it costs frames: not for figures); --no-arm leaves the GUN safe. They found the Kiln's and the Vesper's.
## Prints "RAID FIRSTS ..." lines, then "RAID FIRSTS DONE". Nothing it prints is a headset's figure: one flat window,
## no stereo, no Link.
extends "res://tests/test_raid_bot.gd"

const LINE := 5.0                 # ms: a first frame more than this over the frames before it is over the line (Ruling D)
const BUDGET := 0.5               # ms a frame: the director, flyers and weapon together at a full raid (the plan)
const TIMED_RAIDS := """extends "res://view/network_raids.gd"
var spent_us := 0
func update(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super.update(delta)
	spent_us = Time.get_ticks_usec() - t0
"""
const TIMED_GUN := """extends "res://view/gunnery.gd"
var spent_us := 0
func step(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super.step(delta)
	spent_us = Time.get_ticks_usec() - t0
"""
var _cost := false
var _frames := 600
var _size := Vector2i.ZERO
var _pin_near := 0.0             # --pin=NEAR,APART: the six put on the aim's line each frame (outside the timing), as stage 1's
var _pin_apart := 0.0            # whole-frame probe: NEAR m out, APART m between, PIN_DEG off the line (0: not pinned)
const PIN_DEG := [1.0, -1.6, 1.3, -3.6, 2.4, 5.0]
var rows: Array = []              # each frame: {phase, cpu, wall}
var marks: Array = []             # [name, row index] in the order seen
var _seen := {}
var _last_us := 0
var _then := 0
var _cap := 40.0
var _hits := 0
var _lost := 0


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--then="):
			_then = int(arg.trim_prefix("--then="))
		elif arg.begins_with("--cap="):
			_cap = float(arg.trim_prefix("--cap="))
		elif arg == "--cost":
			_cost = true
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--pin="):
			var na := arg.trim_prefix("--pin=").split(",")
			_pin_near = float(na[0])
			_pin_apart = float(na[1])
		elif arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var prefs_existed := FileAccess.file_exists(PREFS)
	var prefs := FileAccess.get_file_as_bytes(PREFS) if prefs_existed else PackedByteArray()
	var id := only_craft if only_craft != "" else Pilot.KILN
	var ok: bool = (await _cost_run(id)) if _cost else (await _firsts(id))
	Seat.vehicle_override = ""
	Raids.pinned = false
	Raids.enabled = false
	if prefs_existed:
		var file := FileAccess.open(PREFS, FileAccess.WRITE)
		file.store_buffer(prefs)
		file.close()
	elif FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("RAID FIRSTS DONE" if ok else "RAID FIRSTS FAILED")
	quit(0 if ok else 1)


## One frame: the craft railed at `vel` and pointed along `th`, the view's _process timed, the frame drawn; recorded.
func _step(v, vel: Vector2, th: float, phase: String) -> void:
	var sim = v.sim
	for b in sim.bodies:
		b.vx = vel.x
		b.vy = vel.y
		b.vz = 0.0
		b.th = th
		b.w = 0.0
	v.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": false}
	var t0 := Time.get_ticks_usec()
	v._process(STEP)
	var cpu := (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	var now := Time.get_ticks_usec()
	var vp_rid: RID = root.get_viewport_rid()
	rows.append({"phase": phase, "cpu": cpu, "wall": (now - _last_us) / 1000.0,
		"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
		"pipes": "%d/%d/%d/%d/%d" % [Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE), Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)]})
	_last_us = now
	_watch(v)


func _mark(name: String, at := -1) -> void:
	if _seen.has(name):
		return
	_seen[name] = true
	marks.append([name, at if at >= 0 else rows.size() - 1])


## The firsts, looked for after each frame (each seen in the frame whose process made it, drawn in that frame).
func _watch(v) -> void:
	var R = v.raids
	var F = R.flyers
	if R.state == "on":
		_mark("arrival (raid %d)" % R._count)
	for f in F.all():
		if f.kind == "drone" and f.state == "dive":
			_mark("first drone dive")
	var gs = F.gunship()
	if gs != null:
		if float(gs.warn) >= 0.0:
			_mark("gunship's first glow (its muzzle)")
	if int(F.shots_made) > 0:
		_mark("gunship's first shot")
	if _hits > 0:
		_mark("first hit taken (the jolt)")
	if _lost > 0:
		_mark("first commuter lost (its burst)")
	if int(R.kills) > 0:
		_mark("first kill (its burst)")
	var mount = v.craft.weapon
	if mount == null or v.gunnery == null or not v.gun_wanted:
		return
	if mount.get("locks") != null and not (mount.locks as Array).is_empty():
		_mark("Shrike's first lock (its brackets)")
	if mount.get("missiles") != null and not (mount.missiles as Array).is_empty():
		_mark("Shrike's first volley")
	if mount.get("burning") != null and bool(mount.burning):
		_mark("Kiln's first burn")
	if mount.get("released") != null and int(mount.released) > 0:
		_mark("Vesper's first release")
	if mount.get("drawn_r") != null and float(mount.drawn_r) >= 0.0:
		_mark("Vesper's ring first shown")
	if mount.get("orbs") != null:
		for o in mount.orbs:
			if o.state == "orbit":
				_mark("Orrery's orbs first in orbit")
			elif o.state == "out":
				_mark("Orrery's first orb leaving")
	if mount.get("strikes") != null and int(mount.strikes) > 0:
		_mark("Orrery's first strike")
	if mount.get("sends") != null and int(mount.sends) > 0:
		_mark("Orrery's first send")


## --prime=arms|sight|beam (a diagnostic, not the game's): one candidate drawn for two frames at load, to see whether
## the first arming's frame is its first draw.
func _prime(v) -> void:
	var what := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prime="):
			what = arg.trim_prefix("--prime=")
	if what == "":
		return
	var g = v.gunnery
	var mount = v.craft.weapon
	print("RAID FIRSTS priming %s at load (a diagnostic)" % what)
	for i in 3:
		var on := i < 2
		if what.contains("arms") and mount.get("arms") != null and mount.arms != null:
			mount.arms.set_deploy(1.0 if on else 0.0)
		if what.contains("sight") and g != null:
			g.sight.visible = on
			if g.bore_ring != null:
				g.bore_ring.visible = on
		if what.contains("gun"):
			v.gun_wanted = on
		if what.contains("mount") and g != null and i == 0:
			mount.step(STEP, false, null, Vector3.FORWARD)
		if what.contains("fire") and g != null and i == 0:
			mount.fire(g, STEP, false)
		if what.contains("sounds") and g != null and i == 0:
			g._sounds_step(false)
		if what.contains("draw") and g != null and i == 0:
			g._draw(v.cam)
		if what.contains("status") and g != null and i == 0:
			g._status_step()
		if what.contains("step") and g != null and on:
			g.dormant = false
			g.want_out = false
			g.step(STEP)
			g.dormant = true
		if what.contains("switch") and v.gun_switch != null:
			v.gun_switch.show_state(not on, 0.0 if on else 1.0, false)
		if what.contains("beam") and mount.get("beam") != null:
			if mount.beam == null:
				mount._build_drawing(g)
			mount.beam.visible = on
		var w := _along(v.sim, 1)
		await _step(v, w * 1000.0, w.angle(), "prime")
	for i in 60:
		var w := _along(v.sim, 1)
		await _step(v, w * 1000.0, w.angle(), "load")


## --pin: the six put along the aim's line (the craft's road beneath, its way, a city's limit), outside the timing.
func _pin(v, R, g, near: float, apart: float) -> void:
	var sim = v.sim
	var T = v.traffic_net
	var road: int = sim.pod.path
	var Rd = sim.roads[road]
	var ray: Array = g.mount.aim_ray(v.cam)
	var o: Vector3 = g.to_sim(ray[0])
	var d: Vector3 = g.dir_to_sim(ray[1])
	var ahead := Vector2(d.x, d.y).normalized()
	var left := Vector2(-ahead.y, ahead.x)
	var way := int(T.oneway.get(road, 1))
	var hint := int(sim.pod.hint)
	for k in R.pack.size():
		var c = R.pack[k]
		var a: float = deg_to_rad(float(PIN_DEG[k % PIN_DEG.size()]))
		var at := Vector2(o.x, o.y) + (ahead * cos(a) + left * sin(a)) * (near + apart * float(k))
		var best := hint
		var nd := INF
		for i in range(maxi(0, hint - 10), mini(Rd.N - 1, hint + 110)):
			var dd: float = Vector2(Rd.px[i], Rd.py[i]).distance_squared_to(at)
			if dd < nd:
				nd = dd
				best = i
		c.road = road
		c.dir = way
		c.f = float(best) + ((at.x - Rd.px[best]) * Rd.tx[best] + (at.y - Rd.py[best]) * Rd.ty[best]) / float(Rd.len[best])
		c.lat = (at.x - Rd.px[best]) * Rd.nx[best] + (at.y - Rd.py[best]) * Rd.ny[best]
		c.v = 1150.0 / 2.236936
		T._place(c)


## --cost: the director and the fire control swapped for timed subclasses at load (before any raid), then a full raid.
func _cost_run(id: String) -> bool:
	print("RAID FIRSTS cost %s, window %s, vsync off%s" % [id, str(DisplayServer.window_get_size()), (", drawn offscreen %d x %d MSAA 4x" % [_size.x, _size.y]) if _size != Vector2i.ZERO else ""])
	Seat.vehicle_override = id
	var v = Seat.new()
	var vp: SubViewport = null
	if _size != Vector2i.ZERO:
		vp = SubViewport.new()
		vp.size = _size
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		vp.add_child(v)
	else:
		root.add_child(v)
	await process_frame
	v.set_process(false)
	v.cruise = 0.0
	var sim = v.sim
	var T = v.traffic_net
	sim.P.obstacleCollisions = false
	T.collide = false
	T._hw_time = -1.0e9
	for i in 30:
		var w := _along(sim, 1)
		await _step(v, w * 1000.0, w.angle(), "load")
	var TR := _source(TIMED_RAIDS)
	var TG := _source(TIMED_GUN)
	var old = v.raids
	v.remove_child(old)
	old.free()
	var R = TR.new()
	v.add_child(R)
	R.traffic = T
	R.build(v)
	T.raids = R
	R.hit_taken.connect(func(_source): v.jolt(1.0))
	R.hit_taken.connect(v._raid_hit)
	v.raids = R
	var og = v.gunnery
	var was_dormant: bool = og.dormant
	var mount = v.craft.weapon
	for p in [og._servo, og._own_loop] + og._gun_audio:      # (its players hang on the mount's node)
		if p != null and is_instance_valid(p):
			p.get_parent().remove_child(p)
			p.free()
	v.remove_child(og)
	og.free()
	for k in ["beam", "glow", "ring", "dart_batch", "streak_batch", "streaks"]:      # (the drawing made under the old one)
		if mount.get(k) != null:
			mount.set(k, null)
	if mount.get("brackets") != null:
		mount.brackets.clear()
	var g = TG.new()
	g.dormant = was_dormant
	v.add_child(g)
	g.build(v)
	if was_dormant:
		g.mount.prepare()
		g.mount.prepare_drawing(g)
	v.gunnery = g
	R.first_after = 1.0e9
	R.time_limit = 1.0e9
	R.away_t = 1.0e9
	R.pack_size = Vector2i(6, 6)
	R.drones = Vector2i(10, 10)
	R._count = 2
	for i in 120:
		var w := _along(sim, 1)
		await _step(v, w * 1000.0, w.angle(), "load")
	R._alarm()
	var zone: Dictionary = R._zone(R.city)
	var keep_r: float = R.arrive_r
	R.arrive_r = 0.0
	sim.respawn_on(int(zone.road), zone.z.x - 400, 1)
	for i in 240:
		var w := _along(sim, 1)
		await _step(v, w * 500.0, w.angle(), "run-in")
	R.arrive_r = keep_r
	var t := 0
	while R.state == "called" and t < 240:
		var w := _along(sim, 1)
		await _step(v, w * 500.0, w.angle(), "run-in")
		t += 1
	var F = R.flyers
	if R.state != "on":
		push_error("cost: the raid never arrived (%s)" % R.state)
		return false
	print("RAID FIRSTS cost raid %d at %s: %d raiders, %d drones, gunship %s" % [R._count, sim.cities[R.city].name, R.pack.size(), F.count("drone"), F.gunship() != null])
	v.set_gun(true)
	var bot := Bot.new()
	bot.speed = 500.0
	var timed := []
	var n := 0
	var out_at := -1
	var held := 0
	var fired := false
	var counts := []
	while R.state == "on" and (out_at < 0 or n - out_at < 120 + _frames) and n < 1800 + 120 + _frames:
		for c in R.pack:      # (the raid kept full: outside the timing)
			g._damage[c.id] = -1000000
		for f in F.all():
			f.hp = 1000000
		if _pin_near > 0.0 and g.mount != null:
			_pin(v, R, g, _pin_near, _pin_apart)
		var plan := _plan(v, bot, id)
		var vel := _drive(v, bot, plan)
		var th: float = plan.get("th", vel.angle() if vel.length() > 5.0 else sim.pod.th)
		_look(v, g.to_render(plan.look) if plan.get("look") != null else null)
		g.hold_fire = bool(plan.get("fire", false))
		await _step(v, vel, th, "cost")
		n += 1
		fired = fired or g.hold_fire
		if out_at < 0 and ((mount.is_out() and (fired or _pin_near > 0.0)) or n >= 1800):      # (from the arms out and the trigger first pulled; pinned: the arms out)
			out_at = n
		if out_at >= 0 and n - out_at >= 120:
			held += int(g.hold_fire)
			timed.append({"raids": R.spent_us / 1000.0, "gun": g.spent_us / 1000.0, "flyers": float(F.update_ms), "weapon": float(mount.get("cost_ms")) if mount.get("cost_ms") != null else 0.0,
				"wall": float(rows[-1].wall)})
			counts.append(R.pack.size() * 1000 + F.count("drone") * 10 + int(F.gunship() != null))
	if timed.size() < _frames:
		push_error("cost: %d frames timed of %d (the raid %s)" % [timed.size(), _frames, R.state])
		return false
	var together := timed.map(func(r): return float(r.raids) + float(r.gun))
	var worst_i := 0
	for k in together.size():
		if float(together[k]) > float(together[worst_i]):
			worst_i = k
	var c0: int = counts.min()
	var weapon_shots := ""
	for k in ["shots", "released", "sends", "strikes"]:
		if mount.get(k) != null:
			weapon_shots += " %s %d" % [k, int(mount.get(k))]
	print("RAID FIRSTS COST %s, %d frames of a full raid (the fewest up at once: %d raiders, %d drones, gunship %s), the trigger held %d of them, fire control shots %d hits %d%s: the director and the fire control together mean %.3f ms, worst frame %.3f ms (director %.3f, fire control %.3f), p95 %.3f; director mean %.3f (its flyers %.3f), fire control mean %.3f (the weapon's own %.3f); the whole frame median %.2f ms: %s (under %.1f ms)" % [
		id, timed.size(), c0 / 1000, (c0 / 10) % 100, c0 % 10 == 1, held, g.shots, g.hits, weapon_shots, _mean(together), float(together[worst_i]), float(timed[worst_i].raids), float(timed[worst_i].gun),
		_pct(together, 0.95), _mean(timed.map(func(r): return float(r.raids))), _mean(timed.map(func(r): return float(r.flyers))), _mean(timed.map(func(r): return float(r.gun))),
		_mean(timed.map(func(r): return float(r.weapon))), _median(timed.map(func(r): return float(r.wall))), "PASS" if _mean(together) < BUDGET else "FAIL", BUDGET])
	if vp != null:
		await _gpu(v, vp, R, F, g)
	v.queue_free()
	await process_frame
	return true


## The GPU, the world held still (the view no longer stepped): the raid's drawing shown and hidden turn about.
func _gpu(v, vp: SubViewport, R, F, g) -> void:
	var T = v.traffic_net
	var rid := vp.get_viewport_rid()
	var hostile: Array = R.pack.duplicate()
	var parts := ["flyers", "raiders", "weapon"]
	var states := ["none", "all"] + parts
	var times := {}
	var diffs := {}
	for s in states:
		times[s] = []
		diffs[s] = []
	var ship_up: bool = F.gunship() != null
	var mid := Vector3.ZERO      # (the head turned to the flyers' middle: the raid in view)
	for f in F.all():
		mid += g.to_render(Vector3(f.x, f.y, f.z))
	if not F.all().is_empty():
		_look(v, mid / F.all().size())
	for round in 5:
		var this := {}
		for s in states:
			var on := {}
			for part in parts:
				on[part] = s == "all" or s == part
			if F.batch != null:
				F.batch.visible = on.flyers
			if F.ship != null:
				F.ship.visible = on.flyers and ship_up
			if F._glow != null:
				F._glow.visible = on.flyers
			for c in hostile:
				T.cars.erase(c)
				if on.raiders:
					T.cars.append(c)
			T._render()
			g.visible = on.weapon
			for i in 10:
				await process_frame
			var got := []
			for i in 30:
				await process_frame
				got.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			times[s].append_array(got)
			this[s] = _median(got)
		for s in states:
			diffs[s].append(float(this[s]) - float(this.none))
	print("RAID FIRSTS GPU %s, %d x %d MSAA 4x, the world held still (%d raiders, %d drones, gunship %s, %d of its shots, %d bolts, the weapon %s), 5 rounds of 30 frames a state:" % [
		v.sim.P.vehicle, vp.size.x, vp.size.y, hostile.size(), F.count("drone"), ship_up, F.shots.size(), g._bolts.size(), v.craft.weapon.status()])
	for s in states:
		print("RAID FIRSTS GPU   %-8s median %.3f ms   less none, round by round: median %+.3f %s" % [s, _median(times[s]), _median(diffs[s]), str((diffs[s] as Array).map(func(x): return snappedf(x, 0.001)))])
	var added := _median(diffs["all"])
	print("RAID FIRSTS BUDGET GPU %s: the raid's drawing adds %.3f ms (all shown less all hidden, median of 5 rounds): %s (under 0.3 ms)" % [v.sim.P.vehicle, added, "PASS" if added < 0.3 else "FAIL"])


func _source(code: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = code
	if s.reload() != OK:
		push_error("A timed subclass did not compile")
	return s


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for x in values:
		total += float(x)
	return total / values.size()


func _firsts(id: String) -> bool:
	print("RAID FIRSTS %s%s, window %s, vsync off, cold start" % [id, " then raid 3" if _then == 3 else "", str(DisplayServer.window_get_size())])
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
		push_error("%s: no director (%s) or no weapon (%s)" % [id, R, v.craft.weapon])
		return false
	sim.P.obstacleCollisions = false      # (as the menu has them)
	T.collide = false
	T._hw_time = -1.0e9                   # (no street racer)
	R.first_after = 1.0e9                 # (the alarm made here, below)
	R.hit_taken.connect(func(_s: String) -> void: _hits += 1)
	R.commuter_lost.connect(func(_x: float, _y: float) -> void: _lost += 1)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_last_us = Time.get_ticks_usec()
	for i in 60:
		var w := _along(sim, 1)
		await _step(v, w * 1000.0, w.angle(), "load")
	await _prime(v)
	var ok := await _one_raid(v, id, 1)
	if ok and _then == 3:
		R.reset("probe")
		for i in 120:
			var w := _along(sim, 1)
			await _step(v, w * 500.0, w.angle(), "between")
		R._count = 2
		ok = await _one_raid(v, id, 3)
	_report()
	v.queue_free()
	await process_frame
	return ok


## One raid, from its alarm to its firsts (or --cap s of it).
func _one_raid(v, id: String, n: int) -> bool:
	var sim = v.sim
	var R = v.raids
	var F = R.flyers
	for i in 240:
		var w := _along(sim, 1)
		await _step(v, w * 1000.0, w.angle(), "alarm %d" % n)
	R._alarm()
	_mark("alarm (raid %d)" % R._count, rows.size())
	for i in 120:      # (on along the road it was on: the alarm's frames apart from the run-in's scripted move)
		var w := _along(sim, 1)
		await _step(v, w * 1000.0, w.angle(), "called %d" % n)
	if R.state != "called":
		push_error("raid %d: no call (state %s)" % [n, R.state])
		return false
	var zone: Dictionary = R._zone(R.city)
	var keep_r: float = R.arrive_r
	R.arrive_r = 0.0
	sim.respawn_on(int(zone.road), zone.z.x - 400, 1)
	_mark("(the scripted move to the run-in, raid %d: not a pilot's)" % R._count, rows.size())
	for i in 240:
		var w := _along(sim, 1)
		await _step(v, w * 500.0, w.angle(), "run-in %d" % n)
	R.arrive_r = keep_r
	var t := 0
	while R.state == "called" and t < 240:
		var w := _along(sim, 1)
		await _step(v, w * 500.0, w.angle(), "run-in %d" % n)
		t += 1
	if R.state != "on":
		push_error("raid %d: the pack never arrived (state %s)" % [n, R.state])
		return false
	print("RAID FIRSTS raid %d at %s: %d raiders, %d drones, gunship %s" % [R._count, sim.cities[R.city].name, R.pack.size(), F.count("drone"), F.gunship() != null])
	if n == 1:
		for i in 240:      # (on toward the zone, the GUN safe)
			var w := _along(sim, 1)
			await _step(v, w * 300.0, w.angle(), "cruise")
		var diag := OS.get_cmdline_user_args().has("--diag-shown")      # (a diagnostic: what is drawn new at the arming; it costs frames)
		var shown_before := _shown(v) if diag else {}
		if diag:
			_last_us = Time.get_ticks_usec()
		v.set_gun(not OS.get_cmdline_user_args().has("--no-arm"))      # (--no-arm: a diagnostic, the GUN left safe)
		_mark("first arming of the GUN", rows.size())
		var w1 := _along(sim, 1)
		await _step(v, w1 * 300.0, w1.angle(), "fight 1")
		if diag:
			_newly_shown("the arming frame", shown_before, _shown(v))
			_last_us = Time.get_ticks_usec()
	var bot := Bot.new()
	bot.speed = 300.0 if n == 1 else 500.0
	var fight_t := 0.0
	var done_t := -1.0
	var want: Array = _wanted(id, n)
	while R.state == "on" and fight_t < _cap:
		var g = v.gunnery
		var plan := _plan(v, bot, id)
		var vel := _drive(v, bot, plan)
		var th: float = plan.get("th", vel.angle() if vel.length() > 5.0 else sim.pod.th)
		_look(v, g.to_render(plan.look) if plan.get("look") != null and g != null else null)
		if g != null:
			g.hold_fire = bool(plan.get("fire", false))
		await _step(v, vel, th, "fight %d" % n)
		fight_t += STEP
		if done_t < 0.0:
			var all_in := true
			for k in want:
				var got := false
				for m in marks:
					got = got or String(m[0]).begins_with(k)
				all_in = all_in and got
			if all_in:
				done_t = fight_t
		elif fight_t - done_t >= 2.0:
			break
	print("RAID FIRSTS raid %d: %.1f s of fight, the raid %s, kills %d" % [n, fight_t, R.state, int(R.kills)])
	return true


## A material's shader-making features (what picks its pipeline), "" for none.
static func _sig(m: Material) -> String:
	if m == null:
		return ""
	if m is ShaderMaterial:
		return "S%s" % ((m as ShaderMaterial).shader.get_instance_id() if (m as ShaderMaterial).shader else 0)
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		return "B tr%d sh%d em%s nd%s bb%d cu%d vc%s tx%s dd%d" % [b.transparency, b.shading_mode, b.emission_enabled, b.no_depth_test, b.billboard_mode, b.cull_mode,
			b.vertex_color_use_as_albedo, b.albedo_texture != null, b.depth_draw_mode]
	return m.get_class()


## Every drawn thing under the view and whether it is drawn ({path: visible in tree}).
func _shown(v) -> Dictionary:
	var out := {}
	for n in root.find_children("*", "VisualInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mesh = n.get("mesh")
		var mm = n.get("multimesh")
		var mats := []
		if gi != null:
			mats.append(_sig(gi.material_override))
			mats.append(_sig(gi.material_overlay))
			mats.append("cast %d tr %.2f" % [gi.cast_shadow, gi.transparency])
		if n is MeshInstance3D and mesh != null:
			for s in (mesh as Mesh).get_surface_count():
				mats.append(_sig((n as MeshInstance3D).get_surface_override_material(s)))
				mats.append(_sig((mesh as Mesh).surface_get_material(s)))
				mats.append("fmt %d" % (mesh as Mesh).surface_get_format(s) if mesh is ArrayMesh else "")
		if n is Label3D or n is Sprite3D:
			mats.append("shaded %s alpha_cut %s nodepth %s dbl %s bill %s" % [n.shaded, n.alpha_cut, n.no_depth_test, n.double_sided, n.billboard])
		var what := "%s mesh %s mm %s mats %s" % [n.get_class(), mesh.get_instance_id() if mesh != null else 0, mm.get_instance_id() if mm != null else 0, "|".join(mats)]
		out[str(root.get_path_to(n))] = [(n as Node3D).is_visible_in_tree(), what]
	return out


func _newly_shown(when: String, a: Dictionary, b: Dictionary) -> void:
	var said := []
	for k in b:
		if not bool(b[k][0]):
			continue
		if not a.has(k):
			said.append("%s (new: %s)" % [k, b[k][1]])
		elif not bool(a[k][0]):
			said.append("%s (shown)" % k)
		elif String(a[k][1]) != String(b[k][1]):
			said.append("%s (changed: %s -> %s)" % [k, a[k][1], b[k][1]])
	print("RAID FIRSTS shown in %s that were not before: %d: %s" % [when, said.size(), ", ".join(said.slice(0, 40))])


## The firsts a run waits for before it stops.
static func _wanted(id: String, n: int) -> Array:
	if n == 3:
		return ["gunship's first shot"]
	var by := {Pilot.SHRIKE: ["Shrike's first volley"], Pilot.KILN: ["Kiln's first burn"],
		Pilot.VESPER: ["Vesper's ring first shown"], Pilot.ORRERY: ["Orrery's first strike"]}
	return (by.get(id, []) as Array) + ["first kill"]


func _report() -> void:
	for m in marks:
		var i: int = m[1]
		if i < 0 or i >= rows.size():
			print("RAID FIRSTS %-40s none" % m[0])
			continue
		var before := rows.slice(maxi(0, i - 30), i)
		var mid := _median(before.map(func(r): return float(r.wall)))
		var mid_cpu := _median(before.map(func(r): return float(r.cpu)))
		var r: Dictionary = rows[i]
		var worst_k := i
		for k in range(i, mini(rows.size(), i + 4)):
			if float(rows[k].wall) > float(rows[worst_k].wall):
				worst_k = k
		var over: float = float(r.wall) - mid
		var over_late: float = float(rows[worst_k].wall) - mid
		var said := "%s" % ("OVER THE LINE" if maxf(over, over_late) > LINE else "under the line")
		var mid_r := _median(before.map(func(q): return float(q.rcpu)))
		print("RAID FIRSTS %-40s frame %6.2f ms (process %6.2f, render cpu %6.2f, gpu %5.2f) against the 30 before it: median %5.2f (process %5.2f, render cpu %5.2f), difference %+6.2f ms; worst of it and the 3 after: +%d %6.2f ms (%+6.2f; render cpu %6.2f); %s [row %d, %s; pipelines canvas/mesh/surface/draw/specialization: before %s, this %s, after %s]" % [
			m[0], r.wall, r.cpu, r.rcpu, r.gpu, mid, mid_cpu, mid_r, over, worst_k - i, rows[worst_k].wall, over_late, rows[worst_k].rcpu, said, i, r.phase,
			rows[i - 1].pipes if i > 0 else "-", r.pipes, rows[i + 1].pipes if i + 1 < rows.size() else "-"])
	var order := range(rows.size())
	order.sort_custom(func(a, b) -> bool: return float(rows[a].wall) > float(rows[b].wall))
	var walls := rows.map(func(r): return float(r.wall))
	print("RAID FIRSTS the run: %d frames, frame median %.2f ms, p95 %.2f, max %.2f" % [rows.size(), _median(walls), _pct(walls, 0.95), _top(walls)])
	for j in mini(12, order.size()):
		var i: int = order[j]
		var near := []
		for m in marks:
			if absi(int(m[1]) - i) <= 3:
				near.append("%s (%+d)" % [m[0], i - int(m[1])])
		var before := rows.slice(maxi(0, i - 30), i)
		print("RAID FIRSTS worst %2d: row %5d %-10s frame %6.2f ms (process %6.2f, render cpu %6.2f), the 30 before median %5.2f; near: %s" % [j + 1, i, rows[i].phase, rows[i].wall, rows[i].cpu, rows[i].rcpu,
			_median(before.map(func(r): return float(r.wall))), ", ".join(near) if not near.is_empty() else "-"])


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return float(s[s.size() / 2])


static func _pct(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var s := values.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(s.size() * q))])


static func _top(values: Array) -> float:
	var top := 0.0
	for x in values:
		top = maxf(top, float(x))
	return top
