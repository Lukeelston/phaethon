## Raids' drones (view/raid_flyers.gd; the stage 2 plan, task 2), pictured in the game's own VR cockpit with XR off: the
## Phaethon in DUNES's town zone, held still on its road about 400 m short of the drones' nearest group (the pilot's
## share of dives set to none, so the pictures are of the commuters' dives), the world running:
##   --set=drones
##     drones-group        from the seat, looking ahead: a group circling over the city's road
##     drones-group-near   ... the group, the head turned to it, a narrow lens
##     drones-dive         from the seat, the drone nearest the craft a second into a dive on a commuter, the head
##                         turned to between the two (where each falls on the picture is told)
##     drones-dive-near    ... the head turned to the drone itself, a narrow lens
##   --set=off      Raids off (before), the same seat at the same place (--at=, the sample the drones' run told) and the
##                  same looks (the near one at --group=, the group's point it told): drones-off, drones-off-near
## Needs a window: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
##   -s res://tests/render_raid_drones.gd -- --mute --out=ABSOLUTE_DIRECTORY --set=drones|off [--at=N --group=N]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const Raids := preload("res://view/network_raids.gd")
const Tactical := preload("res://view/tactical_display.gd")
const DT := 1.0 / 120.0
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
const SHORT := 400.0                          # m short of the group's point the craft is held
var output := ""
var at_arg := -1
var group_arg := -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Drone pictures need a rendering display.")
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
		elif arg.begins_with("--group="):
			group_arg = int(arg.trim_prefix("--group="))
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	var ok := false
	if which == "drones" or which == "off":
		ok = await _pictures(which == "drones")
	else:
		push_error("--set=drones|off")
	print("DRONES RENDER DONE" if ok else "DRONES RENDER FAILED")
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
	print("DRONES VIEW %s" % path)


static func _render(game, x: float, y: float, z: float) -> Vector3:
	return Vector3(x - game.org_x, z, -(y - game.org_y))


## The first ground city that is not the start's (the raid's, as the tests pick it).
static func _city(sim) -> int:
	for k in sim.cities.size():
		if String(sim.cities[k].get("kind", "")) != "orbit" and k != int(sim.net.from):
			return k
	return -1


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
	# the raid put down with the craft in the zone's middle (Raids on), then the craft moved SHORT m short of the group
	# nearest the zone's start, facing it; the same place with Raids off
	var mid := (int(z.x) + int(z.y)) / 2
	sim.respawn_on(road, mid, 1)
	_step(game, 240)
	var at_f := float(mid)
	if raids_on:
		R.time_limit = 1.0e9
		R.away_t = 1.0e9
		R.tick_every = 1.0e9
		R.pack_size = Vector2i(4, 4)
		R._alarm()
		R.city = k
		_step(game)
		if R.state != "on" or R.flyers == null or R.flyers.all().is_empty():
			push_error("The raid never arrived with drones (state %s)" % R.state)
			return false
		var F = R.flyers
		F.pilot_share = 0.0
		for f in F.all():
			f.at_pod = false
		var G = F._groups[0]
		for g in F._groups:
			if absf(float(g.f) - float(z.x)) < absf(float(G.f) - float(z.x)):
				G = g
		at_f = float(G.f)
	var i0 := clampi(roundi(at_f - SHORT / float(Rd.len[clampi(int(at_f), 0, Rd.N - 1)])), int(z.x) + 2, int(z.y) - 2)
	if not raids_on and at_arg >= 0:
		i0 = at_arg
	sim.respawn_on(road, i0, 1)
	_step(game, 150)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	var here := Vector3(Rd.px[i0], Rd.py[i0], sim.net_height(road, float(i0)))
	if not raids_on:
		# (Raids off: the same look as the drones' pictures, at the same group's place: read from the --set=drones run)
		_look_seat(game, cam)
		await _snap(game, "drones-off", 90)
		var ahead := group_arg if group_arg >= 0 else clampi(i0 + roundi(SHORT / float(Rd.len[i0])), 0, Rd.N - 1)
		_look_at(game, cam, _render(game, Rd.px[ahead], Rd.py[ahead], sim.net_height(road, float(ahead)) + 90.0))
		await _snap(game, "drones-off-near", 30)
		print("DRONES RENDER off: the craft on %s at sample %d (%s), looking at sample %d; no director %s, no flyers node %s" % [Rd.name, i0, here, ahead, game.raids,
			game.find_child("raid_flyers", true, false)])
		R.free()
		game.free()
		await process_frame
		return true
	var F = R.flyers
	var G = F._groups[0]
	var gk := 0
	for j in F._groups.size():
		var g = F._groups[j]
		if Vector2(g.x - sim.pod.x, g.y - sim.pod.y).length() < Vector2(G.x - sim.pod.x, G.y - sim.pod.y).length():
			G = g
			gk = j
	var group := []
	for f in F.all():
		if f.group == gk:
			group.append(f)
	# the group circling: every one of it circling (no dive), wait for it
	var n := 0
	while n < 1200 and group.any(func(f): return f.state != "circle"):
		_step(game)
		n += 1
	_look_seat(game, cam)
	var gap := Vector2(G.x - sim.pod.x, G.y - sim.pod.y).length()
	print("DRONES RENDER group: the craft on %s at sample %d (--at=%d), the group's point sample %d (--group=%d); %d drones circling %.0f m round it %.0f m from the craft, %.0f to %.0f m up; %d drones in all, %d commuters lost so far" % [
		Rd.name, i0, i0, int(G.f), int(G.f), group.size(), G.radius, gap, group.map(func(f): return f.alt).min(), group.map(func(f): return f.alt).max(), F.count("drone"), R.lost])
	await _snap(game, "drones-group", 90)
	_look_at(game, cam, _render(game, G.x, G.y, G.deck + 90.0))
	await _snap(game, "drones-group-near", 30)
	# a dive: the first drone within 1.5 km of the craft to dive on a commuter, a second into it
	var diver = null
	n = 0
	while n < 2400 and diver == null:
		_step(game)
		n += 1
		for f in F.all():
			if f.state == "dive" and f.prey != null and f.dive_t < 0.05 and Vector2(f.x - sim.pod.x, f.y - sim.pod.y).length() < 1500.0:
				diver = f
	if diver == null:
		push_error("No drone of the group dived in 20 s")
		return false
	_step(game, 120)
	var prey = diver.prey
	var p_gap: float = Vector3(diver.x, diver.y, diver.z).distance_to(Vector3(prey.x, prey.y, game.traffic_net.body_height(prey))) if prey != null else -1.0
	print("DRONES RENDER dive: drone %d %.2f s into its dive (%s), %.0f m up, %.0f m from its commuter, %.0f m/s, %.0f m from the craft" % [diver.id, diver.dive_t, diver.state,
		diver.z - sim.net_height(road, float(G.f)), p_gap, Vector3(diver.vx, diver.vy, diver.vz).length(), Vector2(diver.x - sim.pod.x, diver.y - sim.pod.y).length()])
	var d_at := _render(game, diver.x, diver.y, diver.z)
	var p_at := _render(game, prey.x, prey.y, game.traffic_net.body_height(prey)) if prey != null else d_at
	_look_at(game, cam, d_at.lerp(p_at, 0.5))
	cam.fov = 50.0
	print("DRONES RENDER dive (50 deg): the drone at %s on the picture, its commuter at %s" % [cam.unproject_position(d_at), cam.unproject_position(p_at)])
	await _snap(game, "drones-dive", 50)
	_look_at(game, cam, d_at)
	cam.fov = 16.0
	print("DRONES RENDER dive near (16 deg): the drone at %s on the picture, its commuter at %s (in front: %s)" % [cam.unproject_position(d_at), cam.unproject_position(p_at),
		not cam.is_position_behind(p_at)])
	await _snap(game, "drones-dive-near", 16)
	R.reset()
	game.free()
	await process_frame
	return true
