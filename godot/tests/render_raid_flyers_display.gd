## Raids' flyers on the dash, the map and the tactical display (the stage 2 plan, task 4), in the game's own VR cockpit
## with XR off: the Phaethon on a raid city's road, 3.6 km short of its town, at 3,000 mph; a full raid arrived (6
## raiders, 10 drones, the gunship: the director's own arrival, its counts set so), and 3.5 s on, in the town.
##   flyers-seat        from the seat, the tactical display up: the dash's longest line, "RAID  6 RAIDERS  10 DRONES
##                      GUNSHIP  m:ss"
##   flyers-dash        ... the instrument strip close (the eye's own place, a narrow lens): does the whole line fit?
##   flyers-map         ... the map's screen close: the raiders', the drones' and the gunship's marks, all the hostile red
##   flyers-tactical    ... toward the nearest drone: its brackets standing on the road under it
##   drones-dash, drones-map   every raider shot down (the world on two frames): "RAID  10 DRONES  GUNSHIP  m:ss", and
##                      the map's red marks the flyers' alone
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_raid_flyers_display.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const Tactical := preload("res://view/tactical_display.gd")
const DT := 1.0 / 120.0
const MPH := 2.236936
const SPEED := 3000.0 / MPH
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Raid flyer display screenshots need a rendering display.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Raids.pinned = true
	Raids.enabled = true
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
	Tactical.wanted = true
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	Tactical.wanted = true      # (after the seat's own load of the saved choice)
	game.set_power_ups(false)   # (no gate's flash over the dash's line)
	var sim = game.sim
	var R = game.raids
	if R == null:
		push_error("No raid director (raids pinned on)")
		quit(1)
		return
	var k := -1      # the raid's city: a ground city that is not the start's
	for c in sim.cities.size():
		if String(sim.cities[c].get("kind", "")) != "orbit" and c != int(sim.net.from):
			k = c
			break
	var zone: Dictionary = R._zone(k)
	sim.respawn_on(int(zone.road), int(zone.z.x) - 150, 1)
	for i in 90:
		_hold_speed(game)
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam := game.cam as Camera3D
	# a full raid: the director's own call and arrival, its counts set to the most
	R.tick_every = 1.0e9
	R.pack_size = Vector2i(6, 6)
	R.drones = Vector2i(10, 10)
	R.gunship_from = 1
	R._alarm()
	if R.city != k:
		print("FLYERS RENDER: picked %s; held to %s for the pictures" % [sim.cities[R.city].name, sim.cities[k].name])
		R.city = k
	var frames := 0
	while R.state != "on" and frames < 240:
		_hold_speed(game)
		game._process(DT)
		frames += 1
	for i in 420:      # (3.5 s on, into the town: flyers on the map and the tactical display, ahead and about)
		_hold_speed(game)
		game._process(DT)
	var F = R.flyers
	var t = game.tactical
	print("FLYERS RENDER: on after %d frames: %d raiders, %d drones, gunship %s; dash \"%s\" (%d characters); tactical %d lines" % [frames, R.pack.size(), F.count("drone"),
		F.gunship() != null, game._net_text(), game._net_text().length(), t.line_count if t else -1])
	_look_seat(game, cam)
	await _snap(game, "flyers-seat", 90)
	game.flash_until = 0.0      # (the dash's own line, not a flash over it)
	_look_at(game, cam, (game.dashboard as Node3D).global_position)
	await _snap(game, "flyers-dash", 34)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "flyers-map", 24)
	_marks(game, "flyers-map")
	var nearest = null
	for f in F.all():
		if f.kind == "drone" and t and t.marks.has(f.id) and (nearest == null or Vector2(f.x - sim.pod.x, f.y - sim.pod.y).length() < Vector2(nearest.x - sim.pod.x, nearest.y - sim.pod.y).length()):
			nearest = f
	if nearest:
		var m = t.marks[nearest.id]
		print("FLYERS RENDER: the nearest marked drone %.0f m off, %.0f m up; its mark stands at %.0f m (the road there), %.2f s off, its strength %.2f" % [
			Vector2(nearest.x - sim.pod.x, nearest.y - sim.pod.y).length(), nearest.z, m.deck, m.seconds, m.a])
		_look_at(game, cam, Vector3(nearest.x - game.org_x, m.deck + 40.0, -(nearest.y - game.org_y)))
		await _snap(game, "flyers-tactical", 30)
	else:
		print("FLYERS RENDER: no drone marked on the tactical display")
	# every raider shot down: the dash and the map the flyers' alone
	var T = game.traffic_net
	for c in R.pack.duplicate():
		R.on_kill(c)
		T.knock_out(c)
	for i in 2:
		_hold_speed(game)
		game._process(DT)
	print("FLYERS RENDER: raiders shot: %d raiders, %d drones, gunship %s; dash \"%s\"" % [R.pack.size(), F.count("drone"), F.gunship() != null, game._net_text()])
	game.flash_until = 0.0      # (the dash's own line, not a flash over it)
	_look_at(game, cam, (game.dashboard as Node3D).global_position)
	await _snap(game, "drones-dash", 34)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "drones-map", 24)
	_marks(game, "drones-map")
	Tactical.wanted = false
	game.free()
	await process_frame
	quit()


## What the map's frame marks: its hostile dots (the raiders', the drones', the gunship's) and the rest.
func _marks(game, shot: String) -> void:
	var hostile := 0
	var flyers := 0
	var F = game.raids.flyers
	for m in game.minimap.marks:
		if int(m[2]) == game.traffic_net.HOSTILE_MARK:
			hostile += 1
			for f in F.all():
				flyers += int(is_equal_approx(float(m[0]), f.x) and is_equal_approx(float(m[1]), f.y))
	print("FLYERS RENDER %s: %d marks, %d hostile (%d of them flyers' of %d up)" % [shot, game.minimap.marks.size(), hostile, flyers, F.all().size()])


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
	print("FLYERS VIEW %s" % path)


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * SPEED
		b.vy = R.ty[i] * SPEED
		b.vz = 0.0
