## Raids on the dash, the maps and the tactical display, and a lost commuter's burst (the stage 1 plan, task 12), in the
## game's own VR cockpit with XR off: the Phaethon on a raid city's road, 3.6 km short of its town, at 3,000 mph.
##   raid-called       from the seat: the raid called, the dash's line and the map pointing at the city
##   raid-called-map   ... the map's screen close (the eye's own place, a narrow lens); raid-called-map-least and
##                     raid-called-map-most: the raid's city pulsing, at the least and the most of its swell
##   raid-on           from the seat: the raid on, the tactical display up; the raiders red on the map and the display
##   raid-on-map, raid-on-dash, raid-on-tactical   ... the map, the instrument strip and the display close
##   raid-on-map-<SCHEME>   the map close in each of its colour schemes (NETWORK, AMBER, PHOSPHOR, ICE, PAPER)
##   raid-tactical-pair     a raider and a commuter in the next lane, at rest 1.34 km on (each a second off at 3,000 mph,
##                          both red): the raider's brackets beside the commuter's line, the world held still
##   raid-burst        a commuter lost 1.2 km ahead, 0.15 s on; raid-burst-ring the same at 0.45 s; raid-burst-far one
##                     5 km ahead at 0.2 s
##   raid-alarm.wav    the alarm's tone, as made
## Once the raid is on, the world is held still for the bursts (the director's burst stepped on its own).
## With --raids=off, the same seat at the same moments with raids off, the pictures before this work: off-called,
## off-called-map, off-on, off-on-map, off-on-dash (the tactical display up as in raid-on).
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_raid_display.gd -- --mute --out=ABSOLUTE_DIRECTORY [--raids=off]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Tactical := preload("res://view/tactical_display.gd")
const Traffic := preload("res://view/network_traffic.gd")
const MiniMap := preload("res://view/minimap.gd")
const DT := 1.0 / 120.0
const MPH := 2.236936
const SPEED := 3000.0 / MPH
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Raid display screenshots need a rendering display.")
		quit(1)
		return
	var raids_on := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg == "--raids=off":
			raids_on = false
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	var wav_path := output.path_join("raid-alarm.wav")      # (the alarm itself, to be heard off the headset)
	if Raids.alarm_tone().save_to_wav(wav_path) != OK:
		push_error("Could not write " + wav_path)
	print("RAID VIEW %s (%.2f s)" % [wav_path, Raids.alarm_tone().get_length()])
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Raids.pinned = true
	Raids.enabled = raids_on
	Chase.pinned = true
	Chase.enabled = false
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
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	var sim = game.sim
	var R = game.raids
	if raids_on and R == null:
		push_error("No raid director (raids pinned on)")
		quit(1)
		return
	var Z = R if R != null else Raids.new()      # (raids off: a director of its own, only to find the town's zone)
	Z.sim = sim
	var k := -1      # the raid's city: a ground city that is not the start's
	for c in sim.cities.size():
		if String(sim.cities[c].get("kind", "")) != "orbit" and c != int(sim.net.from):
			k = c
			break
	var zone: Dictionary = Z._zone(k)
	if R == null:
		Z.free()
	sim.respawn_on(int(zone.road), int(zone.z.x) - 150, 1)
	for i in 90:
		_hold_speed(game)
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	if not raids_on:      # the same frames as below, nothing called
		for i in 12:
			_hold_speed(game)
			game._process(DT)
		print("RAID RENDER: off: dash \"%s\", map target %d, director %s" % [game._net_text(), game.minimap.target, game.raids])
		_look_seat(game, cam)
		await _snap(game, "off-called", 90)
		_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
		await _snap(game, "off-called-map", 24)
		Tactical.wanted = true
		for i in 151:
			_hold_speed(game)
			game._process(DT)
		print("RAID RENDER: off: dash \"%s\", tactical %d lines" % [game._net_text(), game.tactical.line_count if game.tactical else -1])
		_look_seat(game, cam)
		await _snap(game, "off-on", 90)
		_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
		await _snap(game, "off-on-map", 24)
		_look_at(game, cam, (game.dashboard as Node3D).global_position)
		await _snap(game, "off-on-dash", 34)
		Tactical.wanted = false
		game.free()
		await process_frame
		quit()
		return
	# called
	R.arrive_r = 0.0
	R.tick_every = 1.0e9
	R._alarm()
	if R.city != k:
		print("RAID RENDER: picked %s; held to %s for the pictures" % [sim.cities[R.city].name, sim.cities[k].name])
		R.city = k
	R.lost = 3      # (as though three had been lost on the way)
	for i in 12:
		_hold_speed(game)
		game._process(DT)
	print("RAID RENDER: called: dash \"%s\", map target %d (%s)" % [game._net_text(), game.minimap.target, sim.cities[game.minimap.target].name])
	_look_seat(game, cam)
	await _snap(game, "raid-called", 90)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "raid-called-map", 24)
	for phase in [["least", 0.0], ["most", 0.5 / MiniMap.RAID_HZ]]:      # (the world held still: the pulse's clock set)
		game.minimap._raid_t = float(phase[1])
		var pf: Dictionary = game.minimap.update(sim.pod.th, 0.0)
		game.minimap_panel.show_frame(pf)
		print("RAID RENDER: the city's pulse %s: %.2f, diamond %s" % [phase[0], float(pf.target.get("raid", -1.0)), MiniMap.target_swell(0.011, pf)])
		await _snap(game, "raid-called-map-%s" % phase[0], 24)
	# on, with the tactical display up
	R.arrive_r = 15000.0
	Tactical.wanted = true
	var frames := 0
	while R.state != "on" and frames < 240:
		_hold_speed(game)
		game._process(DT)
		frames += 1
	for i in 150:
		_hold_speed(game)
		game._process(DT)
	var t = game.tactical
	var reds := 0
	if t:
		for j in t.line_count:
			reds += int(t.line_tints[j].is_equal_approx(Color(Traffic.HOSTILE_COL, 1.0)))
	print("RAID RENDER: on after %d frames: dash \"%s\", %d raiders, map target %s, tactical %d lines (%d red), %d lost, bursts %s" % [frames, game._net_text(), R.pack.size(),
		sim.cities[game.minimap.target].name, t.line_count if t else -1, reds, R.lost, R.burst.shown if R.burst else 0])
	_look_seat(game, cam)
	await _snap(game, "raid-on", 90)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "raid-on-map", 24)
	var P = game.minimap_panel
	for s in P.SCHEMES.size():      # the map in each of its schemes (the world held still)
		P.set_scheme(s, false)
		P.show_frame(game.minimap.update(sim.pod.th, 0.0))
		_look_at(game, cam, (P as Node3D).global_position)
		await _snap(game, "raid-on-map-%s" % String(P.SCHEMES[s].name), 24)
	P.set_scheme(0, false)
	P.show_frame(game.minimap.update(sim.pod.th, 0.0))
	_look_at(game, cam, (game.dashboard as Node3D).global_position)
	await _snap(game, "raid-on-dash", 34)
	var nearest = null
	for c in R.pack:
		if nearest == null or Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length() < Vector2(nearest.x - sim.pod.x, nearest.y - sim.pod.y).length():
			nearest = c
	if nearest:
		_look_at(game, cam, nearest.lamp_position)
		await _snap(game, "raid-on-tactical", 30)
	# a raider and a commuter in the next lane, each a second off: both red, told apart by the raider's brackets
	var T = game.traffic_net
	var pc = T._pod_as_car()
	var nl: int = T._lanes[pc.road].size()
	var pair := []
	for n in 2:
		var c = T.Car.new()
		c.id = 990100 + n
		c.kind = T.DEMON if n == 0 else T.CAR
		c.visual = c.kind
		c.hostile = n == 0
		if c.hostile:
			c.col = Traffic.HOSTILE_COL
		c.road = pc.road
		c.dir = pc.dir
		c.f = pc.f + pc.dir * SPEED * 1.0 / 24.0      # (at rest, a second off at her speed)
		c.lane = 0
		var best := INF
		for l in nl:      # her own lane, and the one beside it
			var off: float = absf(T._lane_lat(c, l) - pc.lat)
			if off < best:
				best = off
				c.lane = l
		if n == 1:
			c.lane = c.lane + 1 if c.lane + 1 < nl else c.lane - 1
		c.lat = T._lane_lat(c, c.lane)
		c.v = 0.0
		c.vdes = 0.0
		c.turn_p = 0.0
		c.nsp_road = -1
		T._place(c)
		T.cars.append(c)
		pair.append(c)
	T._render()
	for i in 80:
		game.tactical.sync(DT, game._rush_flow, true)
	var shapes := []
	var kk := 0
	for m in game.tactical.marks.values():
		if m.car in pair:
			shapes.append("%s shape %d %s %.2f s" % ["raider" if m.car.hostile else "commuter", game.tactical.line_shape[kk], game.tactical.line_tints[kk].to_html(false), m.seconds])
		kk += 1
	print("RAID RENDER: the pair: %s" % [shapes])
	_look_at(game, cam, (pair[0].lamp_position + pair[1].lamp_position) * 0.5)
	await _snap(game, "raid-tactical-pair", 14)
	# a commuter lost ahead: the world held still, the burst stepped on its own
	var road: int = sim.pod.path
	var Rd = sim.roads[road]
	var near_i := clampi(int(sim.pod.hint) + 50, 0, Rd.N - 1)      # 1.2 km on
	var far_i := clampi(int(sim.pod.hint) + 208, 0, Rd.N - 1)      # 5 km on
	R.commuter_lost.emit(Rd.px[near_i], Rd.py[near_i])
	R.burst.sync(0.15)
	_look_seat(game, cam)
	await _snap(game, "raid-burst", 90)
	R.burst.sync(0.3)
	await _snap(game, "raid-burst-ring", 90)
	R.burst.sync(1.0)
	R.commuter_lost.emit(Rd.px[far_i], Rd.py[far_i])
	R.burst.sync(0.2)
	await _snap(game, "raid-burst-far", 90)
	print("RAID RENDER: bursts at %.1f and %.1f km on: %s" % [Vector2(Rd.px[near_i] - sim.pod.x, Rd.py[near_i] - sim.pod.y).length() / 1000.0,
		Vector2(Rd.px[far_i] - sim.pod.x, Rd.py[far_i] - sim.pod.y).length() / 1000.0, R.burst.laid])
	Tactical.wanted = false
	game.free()
	await process_frame
	quit()


func _look_seat(game, cam: Camera3D) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * LOOK.normalized(), rig.basis.y)


## From the seated eye, at a point (a close look: the caller narrows the lens).
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
	print("RAID VIEW %s" % path)


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * SPEED
		b.vy = R.ty[i] * SPEED
		b.vz = 0.0
