## What Raids cost (the stage 1 plan, task 13), measured as the CPU frame probe measures a flight: the game's own VR
## cockpit with XR off, drawn into an offscreen SubViewport the size of both of a Quest 3's eyes side by side
## (4128 x 2208, MSAA 4x), the sim paced at 120 Hz (--fixed-fps 120: one _process of 1/120 s a frame, driven from here),
## the craft railed along a city's road (its speed set every frame), obstacles off as the menu has them.
##   --mode=off   Raids off and the GUN never armed. Asserts there is no director (no network_raids node) and no fire
##                control (gunnery == null), then times every frame from 9.6 km short of the first raid city's town zone
##                on into it at 1,500 mph: the view's _process (CPU), the renderer's CPU, the GPU. It reads nothing the
##                base (8e601ab) lacks: run on the base by absolute path for the figure before. Other Godot jobs share
##                the machine: alternate the two, compare medians.
##   --mode=raid  Raids on (the head only), the Phaethon (--vehicle=talon: the Talon). In order:
##                waiting     the director waiting to call one (first_after shortened to 1.5 s), at 3,000 mph
##                alarm       the frame it calls one, and the frames after it (its city's town zone is read then)
##                called      on the way in (its off-screen ticks)
##                arrival     the frame the pack is put down (a full pack: pack_size 6)
##                hunting     the six moved 1.1-2.4 km ahead on the craft's road, hunting; the craft held at their speed;
##                            the GUN safe
##                first arm   the frame the GUN is first armed (the fire control made: batches, sights, players) and the
##                            frames after it, through the arms' deploy (--arm=split: view/gunnery.gd frame's four
##                            steps, new, add_child, build and the first step, made here by hand and timed one by one)
##                first fire  the frames of the first shots (the bolts', flashes' and smoke's batches first drawn)
##                firing      the fire control swapped for a timed one (a thin subclass), the six put back 0.7-1.8 km
##                            ahead (the craft held at the nearest one's speed), 120 frames to settle, then
##                            --frames (1200 by default) of fire on the pack: the director's update (its prey search
##                            timed inside it only), the fire control's step and the
##                            view's raid hooks (_raid_sync, _raid_result, _raid_target, _jolt_tick, _gun_controls),
##                            each timed by a thin subclass; the raiders kept whole (their damage cleared each frame,
##                            outside the timing) so the pack stays six; the trigger let go one frame in 360 (a pilot's
##                            bursts: the barrels never overheat)
##                first hit   a ram, if none came by then (hit_taken emitted, as the director does): that frame and the
##                            next ones (the jolt's thump and vignette are made at the first)
##                gpu         the world held still mid-fire, a commuter's burst laid 1.2 km on; the raid's drawing
##                            shown and hidden turn about: the gun's bolts, flashes, smoke and sights; the arms out or
##                            stowed; the burst; the jolt's vignette at full; the six raiders in traffic. The viewport's
##                            GPU time (medians, and each part's median difference from all hidden, round by round)
##                kills       then the damage is let stand: the frames the raiders are shot down
##   --mode=whole The whole frame, Raids on against Raids off at the same seat and place (--raids=on|off; the head
##                only, for both): the plain game, no timed subclass. Both rail the craft at 1,150 mph (a city's cap)
##                from 100 samples into DUNES's town zone; on, a full raid there and the GUN armed and firing on it:
##                the six put 0.7-1.8 km out along the bore, PIN_DEG off it (four inside the assist's 3 degree cone,
##                two outside: the road there bends, so its lanes alone would leave the cone empty), on the road
##                beneath, and put back each frame and kept whole, outside the timing; off, nothing (no director, the
##                GUN never armed). 240 frames to warm, 120 to settle, then --frames timed: the view's _process, the
##                renderer's CPU, the GPU. Alternate the two; the difference is what a raid costs.
## Run windowed (a small window: the work is offscreen), with sound (a flight has it) on the Dummy driver:
## --xr-mode off --resolution 640x360 --fixed-fps 120 --audio-driver Dummy -s res://tests/probe_raid_cost.gd --
##   --mode=off|raid|whole [--frames=1200] [--vehicle=phaethon|talon] [--size=4128x2208] [--arm=split] [--raids=on|off]
## Prints "RAID COST ..." lines, then "RAID COST DONE". Nothing it prints is a headset's figure: one flat wide view.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const Tactical := preload("res://view/tactical_display.gd")
const DT := 1.0 / 120.0
const MPH := 2.236936
const RAIDS_PATH := "res://view/network_raids.gd"
const BUDGET_CPU := 0.5          # ms a frame: the director, flyers and weapons together, at a full raid (the plan)
const BUDGET_GPU := 0.3          # ms: no new GPU cost over this
const PIN_DEG := [1.0, -1.6, 1.3, -3.6, 2.4, 5.0]   # --mode=whole: the six, degrees left of the bore, 700 m on and 220 m apart

# Thin subclasses, made from source at run time so that this file still loads on the base, which has no director.
const TIMED_SEAT := """extends "res://vr/vr_cockpit.gd"
var hooks_us := 0
func _raid_sync() -> void:
	var t0 := Time.get_ticks_usec()
	super._raid_sync()
	hooks_us += Time.get_ticks_usec() - t0
func _raid_result() -> void:
	var t0 := Time.get_ticks_usec()
	super._raid_result()
	hooks_us += Time.get_ticks_usec() - t0
func _raid_target() -> void:
	var t0 := Time.get_ticks_usec()
	super._raid_target()
	hooks_us += Time.get_ticks_usec() - t0
func _jolt_tick(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super._jolt_tick(delta)
	hooks_us += Time.get_ticks_usec() - t0
func _gun_controls() -> void:
	var t0 := Time.get_ticks_usec()
	super._gun_controls()
	hooks_us += Time.get_ticks_usec() - t0
"""
const TIMED_RAIDS := """extends "res://view/network_raids.gd"
var spent_us := 0
var part_us := {"prey": 0, "contact": 0, "gap": 0}
var _in_update := false
func update(delta: float) -> void:
	for k in part_us:
		part_us[k] = 0
	var t0 := Time.get_ticks_usec()
	_in_update = true
	super.update(delta)
	_in_update = false
	spent_us = Time.get_ticks_usec() - t0
func prey_of(c) -> Variant:
	var t0 := Time.get_ticks_usec()
	var p = super.prey_of(c)
	if _in_update:
		part_us["prey"] += Time.get_ticks_usec() - t0
	return p
func _in_contact() -> bool:
	var t0 := Time.get_ticks_usec()
	var on := super._in_contact()
	part_us["contact"] += Time.get_ticks_usec() - t0
	return on
func _gap(k: int) -> float:
	var t0 := Time.get_ticks_usec()
	var d := super._gap(k)
	part_us["gap"] += Time.get_ticks_usec() - t0
	return d
"""
const TIMED_GUN := """extends "res://view/gunnery.gd"
var spent_us := 0
var build_us := 0
var part_us := {"find": 0, "assist": 0, "fly": 0, "draw": 0}
func build(v) -> void:
	var t0 := Time.get_ticks_usec()
	super.build(v)
	build_us = Time.get_ticks_usec() - t0
func step(delta: float) -> void:
	for k in part_us:
		part_us[k] = 0
	var t0 := Time.get_ticks_usec()
	super.step(delta)
	spent_us = Time.get_ticks_usec() - t0
func _find(o: Vector3, d: Vector3, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super._find(o, d, delta)
	part_us["find"] += Time.get_ticks_usec() - t0
func _assist(o: Vector3, d: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	super._assist(o, d)
	part_us["assist"] += Time.get_ticks_usec() - t0
func _fly(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super._fly(delta)
	part_us["fly"] += Time.get_ticks_usec() - t0
func _draw(cam: Camera3D) -> void:
	var t0 := Time.get_ticks_usec()
	super._draw(cam)
	part_us["draw"] += Time.get_ticks_usec() - t0
"""

var size := Vector2i(4128, 2208)
var frames := 1200
var vehicle := "phaethon"
var arm_split := false           # --arm=split: the first arm's steps made by hand, timed one by one
var raids_on := true             # --mode=whole: --raids=on|off
var vp: SubViewport
var vp_rid: RID
var game
var _last_us := 0
var _rows: Array = []            # each frame: {phase, cpu, wall, rcpu, gpu, raids, gun, hooks, traffic, march}
var _hits: Array = []            # frames a raider rammed the craft (hit_taken)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The raid cost probe needs a rendering display (it times the GPU).")
		quit(1)
		return
	var mode := "off"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--vehicle="):
			vehicle = arg.trim_prefix("--vehicle=")
		elif arg == "--arm=split":
			arm_split = true
		elif arg.begins_with("--raids="):
			raids_on = arg.trim_prefix("--raids=") == "on"
		elif arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ok := true
	if mode == "off":
		ok = await _off()
	elif mode == "raid":
		ok = await _raid()
	elif mode == "whole":
		ok = await _whole()
	else:
		push_error("--mode=off, --mode=raid or --mode=whole")
		ok = false
	if game:
		game.free()
	await process_frame
	print("RAID COST DONE" if ok else "RAID COST FAILED")
	quit(0 if ok else 1)


# --- setting up --------------------------------------------------------------------------------------------------

## The game's VR cockpit (or a subclass of it) in the offscreen viewport, Raids on or off, the saved choices kept out.
func _make(raids_on: bool, seat_script) -> void:
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Chase.pinned = true
	Chase.enabled = false
	var raids_said := "no director in this build"
	if ResourceLoader.exists(RAIDS_PATH):
		var R: GDScript = load(RAIDS_PATH)
		R.set("pinned", true)
		R.set("enabled", raids_on)
		raids_said = "Raids pinned %s (reads back enabled=%s)" % ["on" if raids_on else "off", R.get("enabled")]
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Seat._rush_loaded = true
	Seat.vehicle_override = vehicle
	Seat.best_dir = OS.get_user_data_dir().path_join("raid_cost_")
	Tactical.wanted = true
	vp = SubViewport.new()
	vp.size = size
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp_rid = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	game = seat_script.new()
	vp.add_child(game)
	game.set_process(false)
	game.sim.P.obstacleCollisions = false      # (as the menu has them; a railed craft would plough through traffic)
	game.traffic_net.collide = false
	print("RAID COST set up: %s, %s, %d x %d MSAA 4x offscreen" % [game.sim.P.vehicle, raids_said, size.x, size.y])


## The first raid city's town zone, found as view/network_raids.gd _zone finds it (copied: the base has no director):
## the first ground city that is not the start's, its road, and the run of STARFIGHTER samples about its terminal.
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


func _hold(speed: float) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * speed
		b.vy = R.ty[i] * speed
		b.vz = 0.0


## One frame: the craft held at `speed`, the view's _process timed, then the frame drawn. Recorded under `phase`.
func _frame(phase: String, speed: float) -> Dictionary:
	_hold(speed)
	var R = game.get("raids")
	var g = game.get("gunnery")
	var t0 := Time.get_ticks_usec()
	game._process(DT)
	var cpu := (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	var now := Time.get_ticks_usec()
	var row := {"phase": phase, "cpu": cpu, "wall": (now - _last_us) / 1000.0,
		"rcpu": RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu(),
		"gpu": RenderingServer.viewport_get_measured_render_time_gpu(vp_rid),
		"raids": (R.spent_us / 1000.0) if R != null and "spent_us" in R else 0.0,
		"gun": (g.spent_us / 1000.0) if g != null and "spent_us" in g else 0.0,
		"hooks": (game.hooks_us / 1000.0) if "hooks_us" in game else 0.0,
		"traffic": float(game.traffic_net.update_ms), "march": float(g.march_ms) if g != null else 0.0,
		"cars": game.traffic_net.cars.size(), "crash": game.sim.crash_t > 0.0, "off_road": bool(game.sim.pod.off_road),
		"state": String(R.state) if R != null else ""}
	for part in ["prey", "contact", "gap"]:
		row[part] = (R.part_us[part] / 1000.0) if R != null and "part_us" in R else 0.0
	for part in ["find", "assist", "fly", "draw"]:
		row[part] = (g.part_us[part] / 1000.0) if g != null and "part_us" in g else 0.0
	if "hooks_us" in game:
		game.hooks_us = 0
	_last_us = now
	_rows.append(row)
	return row


# --- Raids off ---------------------------------------------------------------------------------------------------

func _off() -> bool:
	_make(false, Seat)
	var sim = game.sim
	var t := _town(sim)
	sim.respawn_on(int(t.road), maxi(int(t.z.x) - 400, 10), 1)
	var speed := 1500.0 / MPH
	var ok := _nothing_new("at the start")
	_last_us = Time.get_ticks_usec()
	for i in 240:
		await _frame("warm", speed)
	for i in frames:
		await _frame("off", speed)
	ok = _nothing_new("after %d frames" % (240 + frames)) and ok
	var rows := _phase("off")
	var bad := 0
	for r in rows:
		bad += int(r.crash) + int(r.off_road)
	print("RAID COST off rail: %s's road (%s), from %d samples short of its town zone at 1,500 mph; %d frames crashed or off the road" % [t.name,
		sim.roads[int(t.road)].name, 400, bad])
	_report("off", rows)
	return ok and bad == 0


## Raids off and the GUN never armed: no director, no network_raids node, no fire control.
func _nothing_new(when: String) -> bool:
	var director = game.get("raids")
	var node = game.find_child("network_raids", true, false)
	var gun = game.get("gunnery")
	var fine: bool = director == null and node == null and gun == null
	print("RAID COST off %s: director %s, network_raids node %s, fire control %s, GUN wanted %s: %s" % [when, director, node, gun,
		game.get("gun_wanted"), "nothing new exists" if fine else "FAIL something was made"])
	return fine


# --- the whole frame, Raids on against off -----------------------------------------------------------------------

func _whole() -> bool:
	if raids_on and not ResourceLoader.exists(RAIDS_PATH):
		push_error("This build has no raids: --mode=whole --raids=on is for the head")
		return false
	_make(raids_on, Seat)
	var sim = game.sim
	var T = game.traffic_net
	var t := _town(sim)
	var zone: Vector2i = t.z
	sim.respawn_on(int(t.road), int(zone.x) + 100, 1)
	var speed := 1150.0 / MPH
	_last_us = Time.get_ticks_usec()
	for i in 240:
		await _frame("warm", speed)
	var R = game.get("raids")
	var g = null
	if raids_on:
		if R == null:
			push_error("No director with Raids pinned on")
			return false
		R.pack_size = Vector2i(6, 6)
		R.time_limit = 1.0e9
		R._alarm()
		R.city = int(t.city)
		await _frame("arrive", speed)
		if R.state != "on":
			push_error("The pack never arrived (state %s)" % R.state)
			return false
		_pack_ahead(R, T, 700.0, 220.0)
		game.gun_wanted = true
		for i in 150:                  # (the arms out: 1 s)
			await _frame("deploy", speed)
		g = game.gunnery
		if g == null:
			push_error("No fire control on arming")
			return false
		g.hold_fire = true
	else:
		if not _nothing_new("at the start"):
			return false
	var on_raider := 0
	for i in 120 + frames:
		if g != null:
			g._damage.clear()          # (the six kept whole, and where they were put: outside the timing)
			_pin_on_bore(R, T, g)
		await _frame("whole" if i >= 120 else "settle", speed)
		if g != null and i >= 120 and g.aim_car != null and g.aim_car.hostile:
			on_raider += 1
	var rows := _phase("whole")
	var bad := 0
	for r in rows:
		bad += int(r.crash) + int(r.off_road)
	var ok := bad == 0
	if raids_on:
		ok = ok and R.state == "on" and R.pack.size() == 6
		print("RAID COST whole on: %d raiders, %d shots, the aim on a raider %d of %d frames, %d commuters lost" % [R.pack.size(), g.shots, on_raider, frames, R.lost])
	else:
		ok = _nothing_new("after %d frames" % (360 + frames)) and ok
	var cpu := rows.map(func(r): return float(r.cpu))
	print("RAID COST WHOLE %s %s %d frames from %d samples into %s's zone at 1,150 mph: process mean %.3f p50 %.3f p95 %.3f max %.3f ms; render cpu mean %.3f; gpu p50 %.3f; traffic %.3f ms, %.0f cars; %d frames crashed or off the road" % [
		"on" if raids_on else "off", game.sim.P.vehicle, rows.size(), 100, t.name, _mean(cpu), _mid(cpu), _p95(cpu), _max(cpu),
		_mean(rows.map(func(r): return float(r.rcpu))), _mid(rows.map(func(r): return float(r.gpu))), _mean(rows.map(func(r): return float(r.traffic))),
		_mean(rows.map(func(r): return float(r.cars))), bad])
	return ok


# --- Raids on ----------------------------------------------------------------------------------------------------

func _raid() -> bool:
	if not ResourceLoader.exists(RAIDS_PATH):
		push_error("This build has no raids: --mode=raid is for the head")
		return false
	var TS := _script(TIMED_SEAT)
	var TR := _script(TIMED_RAIDS)
	var TG := _script(TIMED_GUN)
	if TS == null or TR == null or TG == null:
		return false
	_make(true, TS)
	if game.raids == null:
		push_error("No director with Raids pinned on")
		return false
	_swap_raids(TR)
	var R = game.raids
	var sim = game.sim
	var T = game.traffic_net
	R.pack_size = Vector2i(6, 6)      # (a full pack: six)
	R.first_after = 1.0e9             # (not while warming)
	R.arrive_r = 0.0                  # (held off until it is let: the alarm's frames apart from the arrival's)
	R.hit_taken.connect(func(_s): _hits.append(_rows.size()))
	var t := _town(sim)
	sim.respawn_on(int(t.road), maxi(int(t.z.x) - 1000, 10), 1)
	var fast := 3000.0 / MPH
	_last_us = Time.get_ticks_usec()
	for i in 120:
		await _frame("warm", fast)
	# waiting, then the alarm (its own clock, shortened)
	R._clock = 0.0
	R.first_after = 1.5
	var n := 0
	while R.state == "" and n < 900:
		await _frame("waiting", fast)
		n += 1
	var forced: bool = R.state == ""
	if forced:
		R._alarm()
	var alarm_i := _rows.size() if forced else _rows.size() - 1      # (forced: between frames, so the next frame is its first)
	print("RAID COST alarm after %d waiting frames%s: %s (%d km), state %s; the alarm's player %s, played %s" % [n, " (forced: none came)" if forced else "",
		sim.cities[R.city].name if R.city >= 0 else "none", roundi(R.called_m / 1000.0), R.state, R.alarm, R.alarm.plays if R.alarm else 0])
	for i in 30:
		await _frame("called", fast)
	if R.city != int(t.city):
		print("RAID COST it called %s; steered to %s for the rest (its town zone is read on the next frame: 'steer')" % [sim.cities[R.city].name, t.name])
		R.city = int(t.city)
		await _frame("steer", fast)
	# in range: 3.6 km short of the town, traffic settled there, then the director let arrive
	sim.respawn_on(int(t.road), maxi(int(t.z.x) - 150, 10), 1)
	for i in 120:
		await _frame("approach", fast)
	R.arrive_r = 15000.0
	n = 0
	while R.state == "called" and n < 600:
		await _frame("approach", fast)
		n += 1
	var arrive_i := _rows.size() - 1
	if R.state != "on":
		push_error("The pack never arrived (state %s)" % R.state)
		return false
	print("RAID COST arrived %d frames after it was let: %d raiders" % [n, R.pack.size()])
	# hunting: the six moved ahead on the craft's road, the craft at their speed
	_pack_ahead(R, T)
	for i in 120:
		await _frame("settle", _pack_speed(R))
	for i in frames:
		await _frame("hunting", _pack_speed(R))
	# the first arm: the fire control made by the game itself (view/gunnery.gd frame), as in a flight; with --arm=split,
	# frame()'s four steps made here one at a time, timed (the timed subclass in place of view/gunnery.gd)
	var split := {}
	if arm_split:
		var t0 := Time.get_ticks_usec()
		var made = TG.new()
		var t1 := Time.get_ticks_usec()
		game.add_child(made)
		var t2 := Time.get_ticks_usec()
		made.build(game)
		var t3 := Time.get_ticks_usec()
		game.gun_wanted = true
		made.step(DT)
		var t4 := Time.get_ticks_usec()
		game.gunnery = made
		split = {"new": (t1 - t0) / 1000.0, "add_child": (t2 - t1) / 1000.0, "build": (t3 - t2) / 1000.0, "first step": (t4 - t3) / 1000.0}
		print("RAID COST first arm, split (frame()'s steps, here, before the frame): %s ms" % str(split))
	game.gun_wanted = true
	await _frame("first arm", _pack_speed(R))
	var arm_i := _rows.size() - 1
	if game.gunnery == null:
		push_error("No fire control on arming")
		return false
	game.gunnery.hold_fire = true
	n = 0
	while game.gunnery.shots == 0 and n < 400:
		await _frame("deploying", _pack_speed(R))
		n += 1
	var fire_i := _rows.size() - 1
	for i in 30:
		await _frame("first fire", _pack_speed(R))
	# what the first arm's work is: the fire control built again (its sounds, shaders and scripts now loaded), and its
	# five sounds read from disk again (the cache passed by)
	var wav_ms := 0.0
	for s in ["fire", "deploy", "stow", "impact", "burst"]:
		var path := "res://audio/turret/%s.wav" % s
		if ResourceLoader.exists(path):
			var t0 := Time.get_ticks_usec()
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			wav_ms += (Time.get_ticks_usec() - t0) / 1000.0
	# firing, timed; the six put back ahead (0.7 to 1.8 km), where the gun is laid on them
	if not arm_split:
		_swap_gun(TG)
	var g = game.gunnery
	print("RAID COST first arm's work: the fire control built %s %.3f ms; its five sounds read from disk again %.3f ms" % [
		"the first time (split)" if arm_split else "again (loaded: its sounds from the cache)", g.build_us / 1000.0, wav_ms])
	_pack_ahead(R, T, 700.0, 220.0)
	var shots0: int = g.shots
	var hits0: int = g.hits
	var strikes0: int = g.commuter_strikes
	var on_raider := 0
	var bolts := []
	for i in 120 + frames:
		g._damage.clear()                  # (the six kept whole: outside the timing)
		g.hold_fire = (i % 360) != 359     # (a pilot's bursts: let go one frame in 360)
		await _frame("firing" if i >= 120 else "settle fire", _pack_speed(R))
		if i >= 120:
			bolts.append(g._bolts.size())
			if g.aim_car != null and g.aim_car.hostile:
				on_raider += 1
		if R.state != "on":
			push_error("The raid ended while firing (%s)" % R.state)
			return false
	g._damage.clear()
	print("RAID COST firing: %d shots, %d hits, %d commuters struck, %d raiders in the pack throughout, the aim on a raider %d of %d frames, bolts in flight mean %.1f max %d, %d effects at the end" % [
		g.shots - shots0, g.hits - hits0, g.commuter_strikes - strikes0, R.pack.size(), on_raider, frames, _mean(bolts), int(_max(bolts)), g._fx.size()])
	# the first hit (a ram), if none came on its own
	var hit_i := -1
	if _hits.is_empty():
		var t0 := Time.get_ticks_usec()
		R.hit_taken.emit("raider")
		var emit_ms := (Time.get_ticks_usec() - t0) / 1000.0
		hit_i = _rows.size()
		for i in 12:
			g._damage.clear()
			await _frame("first hit" if i == 0 else "after hit", _pack_speed(R))
		print("RAID COST first hit made here (none came on its own): its signal's handlers (the jolt, its thump made, the score) took %.3f ms, in the first hit's frame (there, in the director's update)" % emit_ms)
	else:
		hit_i = int(_hits[0])
		print("RAID COST first hit came on its own at frame %d (%s)" % [hit_i, _rows[hit_i].phase if hit_i < _rows.size() else "?"])
	# the GPU, the world held still mid-fire
	var gpu_ok := await _gpu(R, T, g)
	_last_us = Time.get_ticks_usec()
	# kills: the damage let stand
	var kills0: int = g.kills
	var kill_at: Array = []
	g.killed.connect(func(_c): kill_at.append(_rows.size()))
	g.hold_fire = true
	for i in 360:
		await _frame("kills", _pack_speed(R))
	print("RAID COST kills: %d raiders shot down in 360 frames, the raid %s %s; ram hits taken in all %d (at frames %s)" % [g.kills - kills0, R.state, R.tally, _hits.size(), str(_hits.slice(0, 8))])
	# the report
	for phase in ["waiting", "called", "approach", "hunting", "firing", "kills"]:
		_report(phase, _phase(phase))
	_moment("alarm", alarm_i, 4)
	_moment("arrival", arrive_i, 3)
	_moment("first arm", arm_i, 6)
	_moment("first fire", fire_i, 10)
	if hit_i > 0:
		_moment("first hit", hit_i, 6)
	var kills_rows := _phase("kills")
	var worst := 0.0
	var worst_wall := 0.0
	var worst_i := -1
	for k in _rows.size():
		var r: Dictionary = _rows[k]
		if r.phase != "kills":
			continue
		if float(r.cpu) > worst:
			worst = float(r.cpu)
			worst_i = k
		worst_wall = maxf(worst_wall, float(r.wall))
	print("RAID COST kills: the worst frame's process %.3f ms (median %.3f), the worst frame %.2f ms (median %.2f); shot down at frames %s, the worst at %d" % [worst,
		_mid(kills_rows.map(func(r): return r.cpu)), worst_wall, _mid(kills_rows.map(func(r): return r.wall)), str(kill_at), worst_i])
	if not kill_at.is_empty():
		_moment("first kill", int(kill_at[0]), 3)
	if worst_i >= 0:
		_moment("worst kills", worst_i, 2)
	var firing := _phase("firing")
	var together := _mean(firing.map(func(r): return float(r.raids) + float(r.gun) + float(r.hooks)))
	var core := _mean(firing.map(func(r): return float(r.raids) + float(r.gun)))
	var floor10 := _p10(firing.map(func(r): return float(r.raids) + float(r.gun) + float(r.hooks)))
	print("RAID COST parts, firing, ms a frame (mean): director %.3f = its prey search %.3f + contact %.3f + its town's distance %.3f + the rest %.3f; fire control %.3f = what it is on %.3f (the ground search %.3f, the assist %.3f) + bolts' flight %.3f + drawing %.3f + the rest %.3f" % [
		_col(firing, "raids"), _col(firing, "prey"), _col(firing, "contact"), _col(firing, "gap"),
		_col(firing, "raids") - _col(firing, "prey") - _col(firing, "contact") - _col(firing, "gap"),
		_col(firing, "gun"), _col(firing, "find"), _col(firing, "march"), _col(firing, "assist"), _col(firing, "fly"), _col(firing, "draw"),
		_col(firing, "gun") - _col(firing, "find") - _col(firing, "fly") - _col(firing, "draw")])
	print("RAID COST BUDGET CPU %s, %d frames firing on a pack of six: the director's update and the fire control's step %.3f ms a frame (mean), with the view's raid hooks %.3f ms (the least-loaded tenth of frames %.3f): %s (under %.1f ms)" % [
		game.sim.P.vehicle, firing.size(), core, together, floor10, "PASS" if together < BUDGET_CPU else "FAIL", BUDGET_CPU])
	return gpu_ok


func _col(rows: Array, key: String) -> float:
	return _mean(rows.map(func(r): return float(r[key])))


func _script(code: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = code
	var err := s.reload()
	if err != OK:
		push_error("A timed subclass did not compile (%d)" % err)
		return null
	return s


## The director replaced by its timed subclass, wired as the view wires it (view/craft_view.gd), before its first update.
func _swap_raids(TR: GDScript) -> void:
	var old = game.raids
	game.remove_child(old)
	old.free()
	var r = TR.new()
	game.add_child(r)
	r.traffic = game.traffic_net
	r.build(game)
	game.traffic_net.raids = r
	r.hit_taken.connect(func(_source): game.jolt(1.0))
	r.hit_taken.connect(game._raid_hit)
	game.raids = r


## The fire control (made by the game on arming) replaced by its timed subclass, built as view/gunnery.gd frame builds it.
func _swap_gun(TG: GDScript) -> void:
	var old = game.gunnery
	var hold: bool = old.hold_fire
	for p in [old._servo] + old._gun_audio:      # (its players hang on the arms)
		if is_instance_valid(p):
			p.get_parent().remove_child(p)
			p.free()
	game.remove_child(old)
	old.free()
	var g = TG.new()
	game.add_child(g)
	g.build(game)
	g.hold_fire = hold
	game.gunnery = g


## The six moved `near` to `near` + 5 x `apart` m ahead on the craft's own road, the way it goes, over its lanes: there
## they hunt.
func _pack_ahead(R, T, near := 1100.0, apart := 260.0) -> void:
	var sim = game.sim
	var road: int = sim.pod.path
	var Rd = sim.roads[road]
	var nl: int = T._lanes[road].size()
	var way := int(T.oneway.get(road, 1))
	for k in R.pack.size():
		var c = R.pack[k]
		var m := near + apart * float(k)
		c.road = road
		c.dir = way
		c.f = clampf(float(sim.pod.hint) + way * m / float(Rd.len[clampi(int(sim.pod.hint), 0, Rd.N - 1)]), 2.0, Rd.N - 3.0)
		c.lane = k % nl
		c.lat = T._lane_lat(c, c.lane)
		c.v = 1150.0 / MPH      # (a city's limit: traffic's SF_V)
		T._place(c)


## --mode=whole: the six put 700 m out along the bore and 220 m apart, PIN_DEG off it, on the craft's road beneath (its
## nearest sample, across it where they stand), going its way at its speed.
func _pin_on_bore(R, T, g) -> void:
	var sim = game.sim
	var road: int = sim.pod.path
	var Rd = sim.roads[road]
	var ray: Array = g.mount.aim_ray(game.cam)
	var o: Vector3 = g.to_sim(ray[0])
	var d: Vector3 = g.dir_to_sim(ray[1])
	var ahead := Vector2(d.x, d.y).normalized()
	var left := Vector2(-ahead.y, ahead.x)
	var way := int(T.oneway.get(road, 1))
	var hint := int(sim.pod.hint)
	for k in R.pack.size():
		var c = R.pack[k]
		var a: float = deg_to_rad(float(PIN_DEG[k % PIN_DEG.size()]))
		var at := Vector2(o.x, o.y) + (ahead * cos(a) + left * sin(a)) * (700.0 + 220.0 * float(k))
		var near := hint
		var nd := INF
		for i in range(maxi(0, hint - 10), mini(Rd.N - 1, hint + 110)):
			var dd: float = Vector2(Rd.px[i], Rd.py[i]).distance_squared_to(at)
			if dd < nd:
				nd = dd
				near = i
		c.road = road
		c.dir = way
		c.f = float(near) + ((at.x - Rd.px[near]) * Rd.tx[near] + (at.y - Rd.py[near]) * Rd.ty[near]) / float(Rd.len[near])
		c.lat = (at.x - Rd.px[near]) * Rd.nx[near] + (at.y - Rd.py[near]) * Rd.ny[near]
		c.v = 1150.0 / MPH
		T._place(c)


## The craft is held at the speed of the nearest raider ahead of it on its road (so that one stays where it is, in
## reach; the rest pull away or fall back as they hunt); with none ahead, the pack's.
func _pack_speed(R) -> float:
	if R.pack.is_empty():
		return 1100.0 / MPH
	var sim = game.sim
	var near = null
	var nd := INF
	var v := 0.0
	for c in R.pack:
		v += float(c.v)
		if c.road == sim.pod.path:
			var ahead: float = (float(c.f) - float(sim.pod.hint)) * float(c.dir)
			if ahead > 0.0 and ahead < nd:
				nd = ahead
				near = c
	var speed: float = float(near.v) if near != null else v / R.pack.size()
	return clampf(speed, 200.0 / MPH, 1500.0 / MPH)


## The GPU, the world held still: the raid's drawing shown and hidden turn about, the viewport's GPU time read.
func _gpu(R, T, g) -> bool:
	var sim = game.sim
	var Rd = sim.roads[sim.pod.path]
	var at := clampi(int(sim.pod.hint) + 50, 0, Rd.N - 1)      # (a commuter's burst 1.2 km on, 0.15 s into it)
	R.commuter_lost.emit(Rd.px[at], Rd.py[at])
	R.burst.sync(0.15)
	var pack: Array = R.pack.duplicate()
	var arms = game.craft.weapon.arms if "arms" in game.craft.weapon else null
	var parts := ["gun", "arms", "burst", "jolt", "raiders"]
	var states := ["none", "all"] + parts
	var times := {}
	var rounds := 5
	for s in states:
		times[s] = []
	var diffs := {}
	for p in parts + ["all"]:
		diffs[p] = []
	for round in rounds:
		var this := {}
		for s in states:
			var on := {}
			for p in parts:
				on[p] = s == "all" or s == p
			_show(on, R, T, g, arms, pack)
			for i in 10:
				await process_frame
			var got := []
			for i in 30:
				await process_frame
				got.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
			times[s].append_array(got)
			this[s] = _mid(got)
		for p in parts + ["all"]:
			diffs[p].append(float(this[p]) - float(this.none))
	var all_on := {}
	for p in parts:
		all_on[p] = true
	_show(all_on, R, T, g, arms, pack)
	game._jolt_glow = 0.0
	game._jolt_tick(0.0)
	print("RAID COST GPU %s, %d x %d MSAA 4x, the world held still mid-fire (%d bolts, %d effects, %d bursts, %d raiders), %d rounds of 30 frames a state:" % [
		sim.P.vehicle, size.x, size.y, g._bolts.size(), g._fx.size(), R.burst.shown, pack.size(), rounds])
	for s in states:
		var d := ""
		if diffs.has(s):
			d = "   median difference from none, round by round: %+.3f ms %s" % [_mid(diffs[s]), str((diffs[s] as Array).map(func(x): return snappedf(x, 0.001)))]
		print("RAID COST GPU   %-8s median %.3f ms (p95 %.3f)%s" % [s, _mid(times[s]), _p95(times[s]), d])
	var added := _mid(diffs["all"])
	print("RAID COST BUDGET GPU %s: the raid's drawing adds %.3f ms (all shown, less all hidden; median of %d rounds): %s (under %.1f ms)" % [
		sim.P.vehicle, added, rounds, "PASS" if added < BUDGET_GPU else "FAIL", BUDGET_GPU])
	return true


func _show(on: Dictionary, R, T, g, arms, pack: Array) -> void:
	g.visible = on.gun
	if arms:
		arms.set_deploy(1.0 if on.arms else 0.0)
	R.burst.visible = on.burst and R.burst.shown > 0
	game._jolt_glow = 1.0 if on.jolt else 0.0
	game._jolt_tick(0.0)
	for c in pack:
		T.cars.erase(c)
		if on.raiders:
			T.cars.append(c)
	T._render()


# --- reporting ---------------------------------------------------------------------------------------------------

func _phase(name: String) -> Array:
	return _rows.filter(func(r): return r.phase == name)


func _report(name: String, rows: Array) -> void:
	if rows.is_empty():
		print("RAID COST %s: no frames" % name)
		return
	var cpu := rows.map(func(r): return float(r.cpu))
	var line := "RAID COST %-8s %4d frames: process mean %.3f p50 %.3f p95 %.3f max %.3f ms; render cpu mean %.3f; gpu p50 %.3f; frame p50 %.3f max %.3f; traffic %.3f ms, %.0f cars" % [
		name, rows.size(), _mean(cpu), _mid(cpu), _p95(cpu), _max(cpu), _mean(rows.map(func(r): return float(r.rcpu))), _mid(rows.map(func(r): return float(r.gpu))),
		_mid(rows.map(func(r): return float(r.wall))), _max(rows.map(func(r): return float(r.wall))), _mean(rows.map(func(r): return float(r.traffic))),
		_mean(rows.map(func(r): return float(r.cars)))]
	if name != "off":
		var raids := rows.map(func(r): return float(r.raids))
		var gun := rows.map(func(r): return float(r.gun))
		var hooks := rows.map(func(r): return float(r.hooks))
		line += "; director mean %.3f max %.3f; fire control mean %.3f max %.3f (its ground search %.3f); view's raid hooks mean %.3f max %.3f" % [
			_mean(raids), _max(raids), _mean(gun), _max(gun), _mean(rows.map(func(r): return float(r.march))), _mean(hooks), _max(hooks)]
	print(line)


## One moment (a frame that does something once) beside the frames before it: its process and its frame's time, the
## director's part, and the `after` frames that follow it.
func _moment(name: String, i: int, after: int) -> void:
	if i < 0 or i >= _rows.size():
		print("RAID COST moment %s: none" % name)
		return
	var before := _rows.slice(maxi(0, i - 60), i)
	var said := []
	for k in range(i, mini(_rows.size(), i + 1 + after)):
		var r: Dictionary = _rows[k]
		said.append("+%d: process %.3f (director %.3f, fire control %.3f, hooks %.3f) frame %.2f" % [k - i, r.cpu, r.raids, r.gun, r.hooks, r.wall])
	print("RAID COST moment %-10s (%s) against the 60 frames before it, process p50 %.3f max %.3f, frame p50 %.2f max %.2f: %s" % [name, _rows[i].phase,
		_mid(before.map(func(r): return float(r.cpu))), _max(before.map(func(r): return float(r.cpu))), _mid(before.map(func(r): return float(r.wall))),
		_max(before.map(func(r): return float(r.wall))), "; ".join(said)])


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += float(v)
	return total / values.size()


static func _mid(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func _p95(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])


static func _p10(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[int(sorted.size() * 0.1)])


static func _max(values: Array) -> float:
	var top := 0.0
	for v in values:
		top = maxf(top, float(v))
	return top
