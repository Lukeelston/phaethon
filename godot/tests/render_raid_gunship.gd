## Raids' gunship (view/raid_flyers.gd; the stage 2 plan, task 3), pictured in the game's own VR cockpit with XR off: the
## Phaethon on DUNES's road (the first ground city that is not the start's, as the tests pick it), held still, the world
## running, the gunship the raid's only threat (no raiders, no drones):
##   --set=gunship
##     gunship-station       from the seat, the craft SHORT m short of the gunship's first station facing it, looking
##                           ahead: it holds station 200 m over the road
##     gunship-station-near  ... the head turned to it, a narrow lens
##     gunship-warn          ... its muzzle glowing at the craft (half its warning in), the head turned to it, a narrow lens
##     gunship-shot          ... a shot at the craft a second into its flight, the head turned to between the shot and the
##                           gunship (where each falls on the picture is told)
##     gunship-strafe        the gunship 0.3 s into its run, low over the road; the craft put BEHIND m behind it on the
##                           road's middle facing its way (the gunship held there while the view settles round the craft),
##                           from the seat looking ahead
##     gunship-strafe-near   ... the head turned to it, a narrow lens
##   --set=off       Raids off (before): the same seat at the same place (--at=, --way=: the sample and way the gunship's
##                   pictures told), looking ahead and at its station's place (--station=): gunship-off, gunship-off-near
## Needs a window: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
##   -s res://tests/render_raid_gunship.gd -- --mute --out=ABSOLUTE_DIRECTORY --set=gunship|off [--at=N --way=N --station=N]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const Raids := preload("res://view/network_raids.gd")
const Tactical := preload("res://view/tactical_display.gd")
const DT := 1.0 / 120.0
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
const SHORT := 1000.0                         # m short of its station the craft is held
const BEHIND := 600.0                         # m behind it on its run the craft is put
var output := ""
var at_arg := -1
var way_arg := 1
var station_arg := -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gunship pictures need a rendering display.")
		quit(1)
		return
	var which := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
		elif arg.begins_with("--at="):
			at_arg = int(arg.trim_prefix("--at="))
		elif arg.begins_with("--way="):
			way_arg = int(arg.trim_prefix("--way="))
		elif arg.begins_with("--station="):
			station_arg = int(arg.trim_prefix("--station="))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	var ok := false
	if which == "gunship" or which == "off":
		ok = await _pictures(which == "gunship")
	else:
		push_error("--set=gunship|off")
	print("GUNSHIP RENDER DONE" if ok else "GUNSHIP RENDER FAILED")
	quit(0 if ok else 1)


func _pin(raids_on: bool) -> void:
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Chase.pinned = true
	Chase.enabled = false
	Raids.pinned = true
	Raids.enabled = raids_on
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.spot_override = "E3@9000"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat.map_whole = false
	Seat._school_loaded = true
	Seat._rush_loaded = true
	Seat.vehicle_override = "phaethon"
	Tactical.wanted = false


func _hold(game) -> void:
	for b in [game.sim.eL, game.sim.eR, game.sim.pod]:
		b.vx = 0.0
		b.vy = 0.0
		b.vz = 0.0


func _step(game, n := 1) -> void:
	for i in n:
		_hold(game)
		game._process(DT)


func _look_seat(game, cam: Camera3D) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * LOOK.normalized(), rig.basis.y)


func _look_at(game, cam: Camera3D, at: Vector3) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(at, rig.basis.y)


func _snap(game, shot: String, fov: float) -> void:
	(game.cam as Camera3D).fov = fov
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	print("GUNSHIP VIEW %s" % path)


static func _render(game, x: float, y: float, z: float) -> Vector3:
	return Vector3(x - game.org_x, z, -(y - game.org_y))


## The first ground city that is not the start's (the raid's, as the tests pick it).
static func _city(sim) -> int:
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


## The gunship's flight fields, to hold it where it is (_put_back) while the view settles round a craft just moved.
static func _keep(g) -> Array:
	return [g.state, g.dive_t, g.f, g.x, g.y, g.z, g.vx, g.vy, g.vz, g.v, g.hx, g.hy, g.face, g.yaw, g.pitch]


static func _put_back(F, g, kept: Array) -> void:
	g.state = kept[0]
	g.dive_t = kept[1]
	g.f = kept[2]
	g.x = kept[3]
	g.y = kept[4]
	g.z = kept[5]
	g.vx = kept[6]
	g.vy = kept[7]
	g.vz = kept[8]
	g.v = kept[9]
	g.hx = kept[10]
	g.hy = kept[11]
	g.face = kept[12]
	g.yaw = kept[13]
	g.pitch = kept[14]
	F._pose_ship(g)


func _pictures(raids_on: bool) -> bool:
	_pin(raids_on)
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	var sim = game.sim
	var k := _city(sim)
	# the zone found as the director finds it (a director of the picture's own with Raids off: never updated)
	var R = game.raids if raids_on else Raids.new()
	if not raids_on:
		R.traffic = game.traffic_net
		R.sim = sim
	var zone: Dictionary = R._zone(k)
	var road: int = zone.road
	var z: Vector2i = zone.z
	var Rd = sim.roads[road]
	sim.respawn_on(road, (int(z.x) + int(z.y)) / 2, 1)
	_step(game, 240)
	var i0 := at_arg
	var way := way_arg
	var F = null
	var g = null
	if raids_on:
		R.time_limit = 1.0e9
		R.away_t = 1.0e9
		R.tick_every = 1.0e9
		R.pack_size = Vector2i(0, 0)
		R.drones = Vector2i(0, 0)
		R.gunship_from = 1
		R.gunship_every = 1
		R._alarm()
		R.city = k
		_step(game)
		F = R.flyers
		g = F.gunship() if F != null else null
		if R.state != "on" or g == null:
			push_error("The raid never arrived with the gunship (state %s)" % R.state)
			return false
		way = g.way
		i0 = clampi(roundi(g.f0 - way * SHORT / float(Rd.len[int(g.f0)])), int(z.x) + 2, int(z.y) - 2)
		g.dive_t = 0.0      # (its station afresh: 14 s of it for the pictures)
	sim.respawn_on(road, i0, way)
	_step(game, 150)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	if not raids_on:
		_look_seat(game, cam)
		await _snap(game, "gunship-off", 90)
		var s := station_arg if station_arg >= 0 else clampi(i0 + way * roundi(SHORT / float(Rd.len[i0])), 0, Rd.N - 1)
		_look_at(game, cam, _render(game, Rd.px[s], Rd.py[s], sim.net_height(road, float(s)) + 200.0))
		await _snap(game, "gunship-off-near", 20)
		print("GUNSHIP RENDER off: the craft on %s at sample %d way %d, looking at sample %d; no director %s, no flyers node %s" % [Rd.name, i0, way, s, game.raids,
			game.find_child("raid_flyers", true, false)])
		R.free()
		game.free()
		await process_frame
		return true
	var gap := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	print("GUNSHIP RENDER station: the craft on %s at sample %d (--at=%d --way=%d), the gunship's station sample %.0f (--station=%d), %.0f m up, %.0f m from the craft, %s" % [
		Rd.name, i0, i0, way, g.f0, roundi(g.f0), g.z - sim.net_height(road, g.f0), gap, g.state])
	_look_seat(game, cam)
	await _snap(game, "gunship-station", 90)
	_look_at(game, cam, _render(game, g.x, g.y, g.z))
	await _snap(game, "gunship-station-near", 20)
	# its muzzle glowing at the craft: half its warning in
	var n := 0
	while n < 1200 and not (g.warn >= F.SHOT_WARN * 0.5 and g.at_pod):
		_step(game)
		n += 1
	if not (g.warn >= 0.0 and g.at_pod):
		push_error("No warning at the craft in 10 s")
		return false
	_look_at(game, cam, _render(game, g.x, g.y, g.z))
	print("GUNSHIP RENDER warn: %.2f s into its glow at the craft, the turret's yaw %.2f and pitch %.2f rad" % [g.warn, g.yaw, g.pitch])
	await _snap(game, "gunship-warn", 12)
	# a shot at the craft a second into its flight
	var shot = null
	n = 0
	while n < 1200 and shot == null:
		_step(game)
		n += 1
		for s in F.shots:
			if s.pilot and float(s.t) >= 1.0:
				shot = s
	if shot == null:
		push_error("No shot at the craft in 10 s")
		return false
	var p: Vector3 = shot.p
	var s_at := _render(game, p.x, p.y, p.z)
	var g_at := _render(game, g.x, g.y, g.z)
	_look_at(game, cam, s_at.lerp(g_at, 0.5))
	cam.fov = 40.0
	print("GUNSHIP RENDER shot: %.2f s into its flight, %.0f m from the craft (%.0f m/s), %.0f m from the gunship; on the 40 degree picture the shot at %s, the gunship at %s" % [
		float(shot.t), p.distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z)), (shot.v as Vector3).length(), p.distance_to(Vector3(g.x, g.y, g.z)),
		cam.unproject_position(s_at), cam.unproject_position(g_at)])
	await _snap(game, "gunship-shot", 40)
	# its run: 0.3 s in, held there; the craft put BEHIND m behind it on the road's middle, facing its way
	n = 0
	while n < 4800 and not (g.state == "strafe" and g.dive_t >= 0.3):
		_step(game)
		n += 1
	if g.state != "strafe":
		push_error("No run in 40 s (%s)" % g.state)
		return false
	g.cool = 1.0e9      # (no more shots: none lands on the craft while the view settles)
	F.shots.clear()
	var kept := _keep(g)
	var back := clampi(roundi(g.f - g.way * BEHIND / float(Rd.len[int(g.f)])), 2, Rd.N - 3)
	sim.respawn_on(road, back, g.way)
	for i in 90:
		_step(game)
		_put_back(F, g, kept)
	var low: float = g.z - sim.net_height(road, g.f)
	var behind := Vector3(g.x, g.y, g.z).distance_to(Vector3(sim.pod.x, sim.pod.y, sim.pod.z))
	_look_seat(game, cam)
	print("GUNSHIP RENDER strafe: the gunship %.2f s into its run at sample %.1f, %.0f m over the road, %.0f m from the craft (at sample %d), %.0f m/s" % [
		g.dive_t, g.f, low, behind, back, Vector3(g.vx, g.vy, g.vz).length()])
	await _snap(game, "gunship-strafe", 90)
	_look_at(game, cam, _render(game, g.x, g.y, g.z))
	await _snap(game, "gunship-strafe-near", 20)
	R.reset()
	game.free()
	await process_frame
	return true
