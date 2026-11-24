## The Basilisk's gun (view/turret.gd, view/gunnery.gd): the mount's geometry, the GUN switch, the deploy
## and the stow, the gaze's search (a vehicle, the ground), the lock, the interlock against the craft's own
## engines, the bolts, a vehicle knocked out, the battery's say, and the ground search's cost.
## Headless: --xr-mode off -s res://tests/test_turret.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Switch := preload("res://vr/mode_switch.gd")
const T := preload("res://view/turret.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Raids := preload("res://view/network_raids.gd")
const DT := 1.0 / 90.0
var failures := 0
var sections := 0      # (a section that dies on a script error never counts itself: the verdict then fails)


func _initialize() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_turret_")
	Cockpit.camera = "cockpit"
	Cockpit._camera_loaded = true
	Cockpit._nose_loaded = true
	Cockpit._slide_loaded = true
	Cockpit._startup_loaded = true
	Cockpit.cold_start = false
	Cockpit._map_loaded = true
	Cockpit._school_loaded = true
	_run.call_deferred()


func _check(label: String, passed: bool) -> void:
	print(("PASS " if passed else "FAIL ") + label)
	failures += int(not passed)


func _near(a: float, b: float, tol := 0.01) -> bool:
	return absf(a - b) <= tol


func _run() -> void:
	_geometry()
	await _without_gun()
	await _in_the_cockpit()
	_check("every section ran to its end (%d of 3)" % sections, sections == 3)
	print("TURRET %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)


# --- the mount on its own ---------------------------------------------------------------------------

func _geometry() -> void:
	var ahead := T.lay_for(Vector3(0, 0, -1))
	var right := T.lay_for(Vector3(1, 0, 0))
	var up := T.lay_for(Vector3(0, 1, -1))
	_check("a lay dead ahead is (0, 0), to starboard 90 degrees, up the diagonal 45: %s %s %s" % [ahead, right, up],
		_near(ahead.x, 0.0) and _near(ahead.y, 0.0) and _near(right.x, PI / 2.0) and _near(up.y, PI / 4.0) and _near(up.x, 0.0))
	_check("it reaches ahead and to starboard, not over the canopy to port nor straight up",
		T.reachable(ahead) and T.reachable(right) and not T.reachable(T.lay_for(Vector3(-1, 0, -0.2))) and not T.reachable(T.lay_for(Vector3(0, 1, -0.3))))
	var ph0 := T.phases(0.0)
	var ph1 := T.phases(T.T_FREE)
	var mid := T.phases(0.45)
	_check("the deploy: hatch, then lift, then free (%s, %s, %s)" % [ph0, mid, ph1],
		ph0 == Vector3.ZERO and mid.x > 0.7 and mid.y > 0.0 and mid.y < 0.3 and mid.z == 0.0 and ph1 == Vector3.ONE)
	# A capsule across the ray 10 m out, a metre thick: met at 9 m. Beside it: missed.
	var t := Traffic.ray_capsule(Vector3.ZERO, Vector3(1, 0, 0), Vector3(10, -5, 0), Vector3(10, 5, 0), 1.0)
	var miss := Traffic.ray_capsule(Vector3.ZERO, Vector3(1, 0, 0), Vector3(10, -5, 3), Vector3(10, 5, 3), 1.0)
	var behind := Traffic.ray_capsule(Vector3.ZERO, Vector3(1, 0, 0), Vector3(-10, -5, 0), Vector3(-10, 5, 0), 1.0)
	var end_on := Traffic.ray_capsule(Vector3.ZERO, Vector3(1, 0, 0), Vector3(20, 0, 0), Vector3(40, 0, 0), 2.0)
	sections += 1
	_check("the ray meets a capsule where it should (%.2f), misses one beside it (%.0f) and one behind (%.0f), and meets one end on (%.2f)" % [t, miss, behind, end_on],
		_near(t, 9.0) and miss < 0.0 and behind < 0.0 and _near(end_on, 18.0))


# --- a craft without one ----------------------------------------------------------------------------

func _without_gun() -> void:
	View.vehicle_override = Pilot.KILN
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	for i in 4:
		v._process(DT)
	_check("another craft carries no gun, no GUN switch and no fire control", v.craft.turret == null and v.gun_switch == null and v.gunnery == null)
	sections += 1
	_check("... and X still repairs there (no gun to take it)", not Pilot.armed(Pilot.KILN) and Pilot.armed(Pilot.BASILISK))
	v.queue_free()
	await process_frame


# --- the Basilisk ------------------------------------------------------------------------------------

func _push(sw: Node3D, hand: Node3D, from_y: float, to_y: float) -> String:
	var answer := ""
	for y: float in [from_y, to_y]:
		hand.global_position = sw.global_transform * Vector3(0.0, y, 0.05) - hand.global_basis * Switch.TIP
		answer = sw.poke(hand, 1.0 / 60.0)
	return answer


func _step(v, frames: int, look = null) -> void:
	for i in frames:
		if look != null:
			_look(v, look)
		v._process(DT)


## The seat's eye looking at a point (render frame), or along a direction in the rig's frame.
func _look(v, at) -> void:
	var cam: Camera3D = v.cam
	var rig: Transform3D = v.rig.global_transform
	cam.global_position = rig * Cockpit.EYE
	if at is Vector3:
		cam.look_at(at, rig.basis.y)
	else:
		cam.look_at(cam.global_position + rig.basis * (at as Array)[0], rig.basis.y)


func check_commuter_spared(traffic, car, g, shots: int, hits: int, kill_log: Array, struck_log: Array) -> void:
	_check("held on a commuter for 3 s it is spared: %d shots, %d hits, %d struck, %d out, %d killed signals" % [g.shots - shots, g.hits - hits, g.commuter_strikes, g.kills, kill_log.size()],
		traffic.cars.has(car) and g.kills == 0 and g.commuter_strikes > 0 and kill_log.is_empty() and g.shots > shots)
	_check("... and every strike was told by struck_commuter (%d of %d, all this car)" % [struck_log.size(), g.commuter_strikes], struck_log.size() == g.commuter_strikes and struck_log.all(func(c) -> bool: return c == car))


func check_hostile_killed(traffic, car, g, shots: int, hits: int, kill_log: Array, frames: int) -> void:
	_check("a raider held on is knocked out in %.2f s: %d shots, %d hits, %d out, %d killed signals" % [frames * DT, g.shots - shots, g.hits - hits, g.kills, kill_log.size()],
		not traffic.cars.has(car) and g.kills == 1 and g.hits - hits >= g.HOSTILE_HP and frames * DT < 2.0 and kill_log == [car])


func check_kill_reaches_raid(v, traffic, car) -> void:
	var R = v.raids
	_check("the gun's kill reaches the raid: raids %s, kills %d (want 1), fled %d (want 0), the raider out of traffic (%s)" % [R != null, R.kills if R else -1, R.fled if R else -1, not traffic.cars.has(car)],
		R != null and R.kills == 1 and R.fled == 0 and not traffic.cars.has(car))


func _in_the_cockpit() -> void:
	View.vehicle_override = Pilot.BASILISK
	var was_pinned: bool = Raids.pinned      # (put back at the end)
	var was_enabled: bool = Raids.enabled
	Raids.pinned = true      # (raids on, so the cockpit has a director for the gun's kills to reach)
	Raids.enabled = true
	var v = Cockpit.new()
	root.add_child(v)
	await process_frame
	v.set_process(false)
	_step(v, 6, [Vector3(0, -0.05, -1)])
	var turret = v.craft.turret
	var g = v.gunnery
	_check("the Basilisk has its gun, on the hull the seat sees, and its fire control",
		turret != null and g != null and turret.get_parent() == v.shell.get_node("PodHull"))
	if turret == null or g == null:
		v.queue_free()
		return
	var parts := []
	for key in ["GunHatch", "GunRing", "GunCradle", "GunCoils", "SightBall", "SightLens"]:
		var mi := turret.find_child(key, true, false) as MeshInstance3D
		if mi and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0 and mi.mesh.get_aabb().size.length() > 0.05:
			parts.append(key)
	_check("its parts are the authored ones (%s)" % [parts], parts.size() == 6)
	_check("it starts stowed, its hatch shut, and no sight is shown", turret.t == 0.0 and turret.hatch.rotation.z == 0.0 and not g.sight.visible)
	# The switch.
	var sw: Node3D = v.gun_switch
	var words := []
	for label: Label3D in sw.find_children("*", "Label3D", true, false):
		words.append(label.text)
	_check("the GUN switch is the guarded toggle, GUN over SAFE: %s" % [words], sw.get_script() == Switch and words == ["GUN", "SAFE"])
	var eye: Vector3 = v.shell.global_transform * Cockpit.EYE
	var reach: float = sw.global_position.distance_to(v.lever_pivots[1].global_transform * Vector3(0, 0.36, 0))
	_check("it is in reach of the right hand on its lever (%.2f m) and turned to the seat" % reach,
		reach < 0.6 and (eye - sw.global_position).normalized().dot(sw.global_basis.z) > 0.6)
	var hand := Node3D.new()
	root.add_child(hand)
	sw.poke(hand, 1.1)
	var thrown := _push(sw, hand, 0.0, 0.03)
	_check("a push up throws it to GUN: \"%s\"" % thrown, thrown == "gun")
	v.set_gun(thrown == "gun")
	# The battery's say: with no power the switch is thrown but the gun stays in.
	g.want_out = true
	g.power = 0.0
	for i in 30:
		g.step(DT)
	_check("with the battery off it stays stowed", turret.t == 0.0)
	# Out.
	_step(v, int(0.5 / DT), [Vector3(0.3, -0.02, -1)])
	_check("half a second on: the hatch is open (%.0f deg) and it is still coming up (%.2f s)" % [rad_to_deg(-turret.hatch.rotation.z), turret.t],
		-turret.hatch.rotation.z > deg_to_rad(120.0) and not turret.is_out() and g.sight.visible)
	_step(v, int(0.8 / DT), [Vector3(0.3, -0.02, -1)])
	_check("by 1.3 s it is out, risen %.2f m on its post" % (turret.ring.position.y - T.GUN_PIVOT.y), turret.is_out() and _near(turret.ring.position.y - T.GUN_PIVOT.y, T.LIFT, 0.005))
	# It lays itself where the gaze is (the ground there).
	_step(v, 40, [Vector3(0.45, -0.02, -1)])
	var bore_cab: Vector3 = turret.global_transform.basis.inverse() * turret.bore()
	var want: Vector2 = T.lay_for(turret.global_transform.affine_inverse() * g.to_render(g.aim_sim) - turret.trunnion())
	_check("the sight is on the ground (%s, %.0f m) and the gun is laid on it: %.1f/%.1f against %.1f/%.1f deg" % [g.aim_kind, g.aim_dist,
		rad_to_deg(turret.yaw), rad_to_deg(turret.pitch), rad_to_deg(want.x), rad_to_deg(want.y)],
		g.aim_kind == "ground" and g.aim_dist > 20.0 and g.on_aim and absf(turret.yaw - want.x) < deg_to_rad(1.0) and bore_cab.length() > 0.9)
	# The ground search's cost, looking down the road.
	var cost := 0.0
	var n := 0
	for i in 60:
		_step(v, 1, [Vector3(0.1 * sin(i * 0.2), -0.01 - 0.01 * cos(i * 0.3), -1)])
		cost += g.march_ms
		n += 1
	print("  ground search: %.3f ms a frame on average (%d frames)" % [cost / n, n])
	_check("the ground search costs under a millisecond a frame on average (%.3f ms)" % (cost / n), cost / n < 1.0)
	# The interlock: a line through the starboard engine is held.
	var shots0: int = g.shots
	var engine: Vector3 = v.craft.engines[1].global_position
	g.hold_fire = true
	_step(v, 40, engine + (engine - eye).normalized() * 30.0)
	_check("a line of fire through its own engine is held (fouled %s, %d shots)" % [g.fouled, g.shots - shots0], g.fouled and g.shots == shots0)
	g.hold_fire = false
	# A vehicle: brought up the road ahead in a right-hand lane, held under the sight, fired on.
	var traffic = v.traffic_net
	var sim = v.sim
	var car = null
	for c in traffic.cars:
		if c.road == sim.pod.path and not c.craft and c != traffic.racer:
			car = c
			break
	_check("there is a vehicle on the craft's road to bring up", car != null)
	if car != null:
		var R = sim.roads[car.road]
		var i := clampi(int(sim.pod.hint), 0, R.N - 1)
		var way := 1.0 if R.tx[i] * (sim.eL.x - sim.pod.x) + R.ty[i] * (sim.eL.y - sim.pod.y) >= 0.0 else -1.0
		car.f = clampf(float(sim.pod.hint) + way * 19.0, 0.0, R.N - 2.0)
		car.dir = int(way)
		car.lane = traffic._lanes[car.road].size() - 2 if car.dir > 0 else 1
		for k in ["v", "vdes", "cruise", "cruise_goal", "vcap"]:
			car.set(k, 45.0)
		traffic._place(car)
		_step(v, 3)
		var at := func() -> Vector3: return g.to_render(Vector3(car.x, car.y, traffic._drawing.height(car.road, car.f) + 3.0))
		var trace := []
		for k in int(0.25 / DT):
			_look(v, at.call())
			v._process(DT)
			trace.append("%s%s%.2f" % [g.aim_kind[0], "*" if g.aim_car == car else "", g.lock])
		print("  lock trace: ", " ".join(trace))
		_check("the sight finds the vehicle (%s at %.0f m) and the lock builds (%.2f)" % [g.aim_kind, g.aim_dist, g.lock],
			g.aim_kind == "vehicle" and g.aim_car == car and g.lock > 0.5 and g.lock < 1.0)
		var shots: int = g.shots
		var hits: int = g.hits
		var kill_log := []
		var struck_log := []
		g.struck_commuter.connect(func(c) -> void: struck_log.append(c))
		g.killed.connect(func(c) -> void: kill_log.append(c))
		# Raids' score: a raid "on" (its director held still: no traffic of its own to drive), the run's total high.
		# The strike reaches the score through the view's own connection made in _process, and costs 150, once.
		var rd = v.raids
		var rd_traffic = null
		var drops := 0
		if rd:
			rd_traffic = rd.traffic
			rd.traffic = null
			rd.state = "on"
			v.skill_score.total = 5000
		g.hold_fire = true
		var frames := 0
		while frames < int(3.0 / DT):
			_look(v, at.call())
			var was: int = v.skill_score.total
			v._process(DT)
			drops += int(v.skill_score.total == was - 150)
			frames += 1
		g.hold_fire = false
		if rd:
			var connected: bool = g.struck_commuter.is_connected(v._raid_struck)
			_check("a gun strike on a commuter in a raid costs 150, once (%d strikes, %d charge(s) of 150, total %d, charged car %s, connected %s)" % [g.commuter_strikes, drops, v.skill_score.total, v._raid_struck_ids.has(car.get_instance_id()), connected],
				connected and g.commuter_strikes > 1 and drops == 1 and v._raid_struck_ids.size() == 1 and v._raid_struck_ids.has(car.get_instance_id()))
			rd.state = ""
			rd.traffic = rd_traffic
		check_commuter_spared(traffic, car, g, shots, hits, kill_log, struck_log)
		# The same car, now a raider (Raids): it takes HOSTILE_HP hits and is knocked out.
		car.hostile = true
		var raid = v.raids
		if raid:         # (the car is this raid's raider: on, with it the only one in its pack)
			raid.pack = [car]
			raid.state = "on"
			raid.city = 0
		g._damage.clear()
		shots = g.shots
		hits = g.hits
		g.hold_fire = true
		frames = 0
		while traffic.cars.has(car) and frames < int(3.0 / DT):
			_look(v, at.call())
			v._process(DT)
			frames += 1
		g.hold_fire = false
		check_hostile_killed(traffic, car, g, shots, hits, kill_log, frames)
		v._process(DT)
		check_kill_reaches_raid(v, traffic, car)
		# A director made after the gun (the gun came first): the next view frame joins it, and a kill still reaches it.
		var late = Raids.new()
		v.add_child(late)
		late.traffic = traffic
		late.build(v)
		v.raids = late
		traffic.raids = late
		v._process(DT)
		traffic.cars.append(car)
		late.pack = [car]
		late.state = "on"
		late.city = 0
		g._damage.clear()
		for k in g.HOSTILE_HP:
			g._land({"a": Vector3.ZERO, "b": Vector3(car.x, car.y, 0.0), "t": 0.0, "dur": 0.0, "car": car, "id": 0, "kind": "vehicle"})
		_check("a director made after the gun is joined and a kill reaches it: kills %d (want 1), fled %d, out of traffic %s" % [late.kills, late.fled, not traffic.cars.has(car)],
			late.kills == 1 and late.fled == 0 and not traffic.cars.has(car) and g.killed.is_connected(late.on_kill))
		var fx := []
		for f in g._fx:
			fx.append(f.kind)
		_check("... in a burst of fire and smoke (%s)" % [fx], fx.has("fireball") and fx.has("smoke"))
	# Safe: it comes home, then goes down and in, and the hatch shuts.
	v.set_gun(false)
	_step(v, int(0.25 / DT), [Vector3(0.6, 0.1, -1)])
	_check("thrown to SAFE it lays itself home before it goes down (%.1f deg, %.2f s)" % [rad_to_deg(turret.yaw), turret.t], turret.t > T.T_FREE - 0.3)
	_step(v, int(2.0 / DT), [Vector3(0.6, 0.1, -1)])
	_check("then it is stowed: in its bed, the hatch shut, the sight gone", turret.is_stowed() and _near(turret.hatch.rotation.z, 0.0, 0.001) and turret.yaw == 0.0 and not g.sight.visible)
	# The keyboard's K does the same as the switch.
	var key := InputEventKey.new()
	key.keycode = KEY_K
	key.pressed = true
	v._unhandled_key_input(key)
	_check("K brings it out too", v.gun_wanted)
	v._unhandled_key_input(key)
	_check("... and puts it away", not v.gun_wanted)
	Raids.pinned = was_pinned
	Raids.enabled = was_enabled
	sections += 1
	hand.queue_free()
	v.queue_free()
	await process_frame
