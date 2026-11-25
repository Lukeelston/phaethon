## Raids stage 1's pictures (the stage 1 plan, task 13), in the game's own VR cockpit with XR off (and its menus):
##   --set=raid    (the head) a full pack of six put down in DUNES's town zone and moved 0.6-1.5 km ahead of the craft on
##                 its road, the world running, the craft at the nearest raider's speed:
##                   raid-pack        from the seat: the pack ahead in the city, the GUN safe
##                   raid-pack-near   ... the pack close (the head turned to it, a narrow lens)
##                 --vehicle=phaethon|talon (fixed guns):
##                   raid-out         the GUN armed, the guns out (the boresight ring, the lead pip on a raider)
##                   raid-fire        firing on the pack (the raiders kept whole: their damage cleared each frame)
##                   raid-fire-near   ... close, at the raider the assist lays the bolts on
##                   raid-fire-out    ... from outside, behind and above the starboard engine
##                   raid-gun-close   the starboard gun itself, firing (behind its muzzle)
##                 --vehicle=basilisk (the gaze turret): the head turned to the nearest raider and kept on it
##                   basilisk-out, basilisk-fire, basilisk-fire-near, basilisk-fire-out
##   --set=struck  (the head) the Phaethon on DUNES's approach, the world held still once armed, a commuter (no raider) at rest
##                 550 m out on the bore: struck-aim (the guns out, on it), struck (its first strikes: sparks),
##                 struck-near (close), struck-after and struck-after-near (a second of fire on: it is still there, no burst)
##   --set=off     Raids off, the same seat at the same moments as tests/render_raid_display.gd's --raids=off: 3.6 km
##                 short of DUNES's town at 3,000 mph. off-seat, off-map, then the tactical display up: off-tac-seat,
##                 off-tac-map, off-dash. It reads nothing the base (8e601ab) lacks: run on the base by absolute path
##                 for the pictures before.
##   --set=menus   the menus as a player sees them (run at 1280x720, the window the desktop menu is laid out for):
##                 menu-desktop (over the title), menu-desktop-plain (the title off), menu-vr (the headset's menu from
##                 the pilot's standing eye, 96 degrees), menu-vr-board (its board close). Runs on the base too. Each
##                 menu's buttons are measured against every label they can show (_measure): the courses (marked and
##                 not), the option rows, Fly for every course, Pilot garage and Quit; and the room left in its column;
##                 and the headset board's two hint lines (under its option rows, and at its foot) against the board.
## Needs a window: --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
##   -s res://tests/render_raids.gd -- --mute --out=ABSOLUTE_DIRECTORY --set=raid|struck|off|menus [--vehicle=phaethon]
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Chase := preload("res://view/network_chase.gd")
const Tactical := preload("res://view/tactical_display.gd")
const Title := preload("res://release/title_stage.gd")
const UI := preload("res://release/release_config.gd")
const DT := 1.0 / 120.0
const MPH := 2.236936
const RAIDS_PATH := "res://view/network_raids.gd"
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
var output := ""
var vehicle := "phaethon"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Raid pictures need a rendering display.")
		quit(1)
		return
	var which := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--set="):
			which = arg.trim_prefix("--set=")
		elif arg.begins_with("--vehicle="):
			vehicle = arg.trim_prefix("--vehicle=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	var ok := true
	match which:
		"raid":
			ok = await _raid_set()
		"struck":
			ok = await _struck_set()
		"off":
			ok = await _off_set()
		"menus":
			ok = await _menus_set()
		_:
			push_error("--set=raid|struck|off|menus")
			ok = false
	print("RAIDS RENDER DONE" if ok else "RAIDS RENDER FAILED")
	quit(0 if ok else 1)


# --- the seat -----------------------------------------------------------------------------------------------------

func _pin(raids_on: bool) -> void:
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Chase.pinned = true
	Chase.enabled = false
	if ResourceLoader.exists(RAIDS_PATH):
		var R: GDScript = load(RAIDS_PATH)
		R.set("pinned", true)
		R.set("enabled", raids_on)
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
	Seat.vehicle_override = vehicle
	Tactical.wanted = false


func _seat():
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	return game


func _hide_layers(game) -> void:
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()


func _hold(game, speed: float) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * speed
		b.vy = R.ty[i] * speed
		b.vz = 0.0


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
	print("RAIDS VIEW %s" % path)


## The first raid city's town zone (as view/network_raids.gd _zone finds it; copied, so the base can run --set=off).
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


# --- a raid -------------------------------------------------------------------------------------------------------

func _raid_set() -> bool:
	if not ResourceLoader.exists(RAIDS_PATH):
		push_error("This build has no raids")
		return false
	_pin(true)
	var game = _seat()
	var sim = game.sim
	var R = game.raids
	var T = game.traffic_net
	if R == null:
		push_error("No raid director (raids pinned on)")
		return false
	R.pack_size = Vector2i(6, 6)
	R.arrive_r = 0.0
	R.tick_every = 1.0e9
	var t := _town(sim)
	sim.respawn_on(int(t.road), int(t.z.x) - 150, 1)
	for i in 90:
		_hold(game, 1500.0 / MPH)
		game._process(DT)
	_hide_layers(game)
	var cam := game.cam as Camera3D
	R._alarm()
	R.city = int(t.city)
	for i in 12:
		_hold(game, 1500.0 / MPH)
		game._process(DT)
	R.arrive_r = 15000.0
	var n := 0
	while R.state != "on" and n < 240:
		_hold(game, 1500.0 / MPH)
		game._process(DT)
		n += 1
	if R.state != "on":
		push_error("The pack never arrived")
		return false
	_pack_ahead(game, 600.0, 180.0)
	_look_seat(game, cam)
	for i in 30:
		_step(game, null)
	print("RAIDS RENDER raid: %s, %d raiders on %s's road; dash \"%s\"; nearest %.0f m" % [sim.P.vehicle, R.pack.size(), t.name, game._net_text(), _nearest_m(game)])
	await _snap(game, "raid-pack", 90)
	_look_at(game, cam, _pack_middle(game))
	await _snap(game, "raid-pack-near", 35)
	_look_seat(game, cam)
	game.gun_wanted = true
	if vehicle == "basilisk":
		return await _basilisk_fire(game, cam)
	for i in 140:      # (the fire control made on the first arm, the guns out over a second)
		_step(game, null)
	var g = game.gunnery
	if g == null:
		push_error("No fire control on arming")
		return false
	print("RAIDS RENDER out: deploy %.2f, aim %s %.0f m, on a raider %s" % [g.mount.deploy_t(), g.aim_kind, g.aim_dist, g.aim_car != null and g.aim_car.hostile])
	await _snap(game, "raid-out", 90)
	g.hold_fire = true
	for i in 45:
		_step(game, g)
	print("RAIDS RENDER fire: %d shots, %d hits, %d bolts in flight, aim %s %.0f m on a raider %s" % [g.shots, g.hits, g._bolts.size(), g.aim_kind, g.aim_dist,
		g.aim_car != null and g.aim_car.hostile])
	await _snap(game, "raid-fire", 90)
	if g.aim_car != null:
		_look_at(game, cam, g.to_render(Vector3(g.aim_car.x, g.aim_car.y, g.aim_sim.z)))
		g.step(0.0)      # (its sights drawn for this eye)
		await _snap(game, "raid-fire-near", 22)
	var engine: Transform3D = game.craft.engines[1].global_transform
	var lead: Vector3 = g.to_render(g.aim_lead)
	cam.global_position = engine * Vector3(14.0, 7.0, 34.0)
	cam.look_at(engine.origin.lerp(lead, 0.04), Vector3.UP)
	g.step(0.0)
	await _snap(game, "raid-fire-out", 45)
	cam.global_position = engine * Vector3(2.0, 1.1, -8.5)
	cam.look_at(engine * Vector3(0.0, 0.0, -4.0), engine.basis.y)
	g.step(0.0)
	await _snap(game, "raid-gun-close", 40)
	game.free()
	await process_frame
	return true


## One frame of the world, the craft at the nearest raider's speed; with a fire control, the raiders kept whole.
func _step(game, g) -> void:
	if g != null:
		g._damage.clear()
	_hold(game, _pack_speed(game))
	game._process(DT)


## The six moved `near` to `near` + 5 x `apart` m ahead on the craft's own road, the way it goes, over its lanes.
func _pack_ahead(game, near: float, apart: float) -> void:
	var sim = game.sim
	var R = game.raids
	var T = game.traffic_net
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
		c.v = 1150.0 / MPH
		T._place(c)


func _pack_speed(game) -> float:
	var R = game.raids
	var sim = game.sim
	if R == null or R.pack.is_empty():
		return 1100.0 / MPH
	var near = null
	var nd := INF
	for c in R.pack:
		if c.road == sim.pod.path:
			var ahead: float = (float(c.f) - float(sim.pod.hint)) * float(c.dir)
			if ahead > 0.0 and ahead < nd:
				nd = ahead
				near = c
	return clampf(float(near.v) if near != null else 1100.0 / MPH, 200.0 / MPH, 1500.0 / MPH)


func _nearest(game):
	var sim = game.sim
	var best = null
	for c in game.raids.pack:
		if best == null or Vector2(c.x - sim.pod.x, c.y - sim.pod.y).length() < Vector2(best.x - sim.pod.x, best.y - sim.pod.y).length():
			best = c
	return best


func _nearest_m(game) -> float:
	var c = _nearest(game)
	return Vector2(c.x - game.sim.pod.x, c.y - game.sim.pod.y).length() if c != null else -1.0


func _pack_middle(game) -> Vector3:
	var at := Vector3.ZERO
	for c in game.raids.pack:
		at += c.lamp_position
	return at / maxf(1.0, game.raids.pack.size())


## The Basilisk: the head turned to the nearest raider and kept on it (the cockpit's camera turned within the rig: the
## turret follows the gaze), the turret out, then firing.
func _basilisk_fire(game, cam: Camera3D) -> bool:
	var target = _nearest(game)
	for i in 200:
		_aim_head(game, cam, target)
		_step(game, game.gunnery)
	var g = game.gunnery
	if g == null:
		push_error("No fire control for the Basilisk")
		return false
	print("RAIDS RENDER basilisk out: deploy %.2f, aim %s %.0f m, on a raider %s" % [g.mount.deploy_t(), g.aim_kind, g.aim_dist, g.aim_car != null and g.aim_car.hostile])
	await _snap(game, "basilisk-out", 90)
	g.hold_fire = true
	for i in 50:
		_aim_head(game, cam, target)
		_step(game, g)
	print("RAIDS RENDER basilisk fire: %d shots, %d hits, %d bolts in flight, aim %s %.0f m on a raider %s, lock %.2f" % [g.shots, g.hits, g._bolts.size(), g.aim_kind,
		g.aim_dist, g.aim_car != null and g.aim_car.hostile, g.lock])
	await _snap(game, "basilisk-fire", 90)
	(game.cam as Camera3D).fov = 30.0
	g.step(0.0)
	await _snap(game, "basilisk-fire-near", 30)
	var pod: Transform3D = game.rig.global_transform
	var lead: Vector3 = g.to_render(g.aim_lead)
	cam.global_position = pod * Vector3(9.0, 6.0, 22.0)
	cam.look_at(pod.origin.lerp(lead, 0.03), Vector3.UP)
	g.step(0.0)
	await _snap(game, "basilisk-fire-out", 50)
	game.free()
	await process_frame
	return true


func _aim_head(game, cam: Camera3D, target) -> void:
	if target == null or not game.traffic_net.cars.has(target):
		return
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(target.lamp_position, rig.basis.y)


# --- a commuter struck --------------------------------------------------------------------------------------------

func _struck_set() -> bool:
	if not ResourceLoader.exists(RAIDS_PATH):
		push_error("This build has no raids")
		return false
	_pin(true)
	var game = _seat()
	var sim = game.sim
	var T = game.traffic_net
	var R = game.raids
	var t := _town(sim)      # (DUNES's approach, as the raid's pictures: the land streamed in, the road straight there)
	sim.respawn_on(int(t.road), int(t.z.x) - 150, 1)
	for i in 120:
		_hold(game, 1500.0 / MPH)
		game._process(DT)
	_hide_layers(game)
	var cam := game.cam as Camera3D
	game.gun_wanted = true
	_hold(game, 1500.0 / MPH)
	game._process(DT)
	var g = game.gunnery
	if g == null:
		push_error("No fire control on arming")
		return false
	T.cars.clear()      # (from here the world is still: the fire control stepped on its own)
	_hold(game, 1500.0 / MPH)
	g.want_out = true
	for i in int(1.1 / DT):
		g.step(DT)
	var car = _put(game, g, 0.0, 550.0)
	_look_seat(game, cam)
	T._render()
	g.step(DT)
	await _snap(game, "struck-aim", 90)
	g.hold_fire = true
	var frames := 0
	while g.commuter_strikes == 0 and frames < int(3.0 / DT):
		_look_seat(game, cam)
		g.step(DT)
		frames += 1
	g.step(DT)
	var sparks := 0
	for f in g._fx:
		sparks += int(f.kind == "spark")
	print("RAIDS RENDER struck after %.2f s of fire: %d strikes, %d hits, %d out, the commuter %s, %d sparks, bursts %d shown (%d waiting), the raid '%s'" % [frames * DT,
		g.commuter_strikes, g.hits, g.kills, "still there" if T.cars.has(car) else "GONE", sparks, R.burst.shown if R.burst else 0, R.burst.bursts.size() if R.burst else 0, R.state])
	await _snap(game, "struck", 90)
	_look_at(game, cam, car.lamp_position)
	g.step(0.0)
	await _snap(game, "struck-near", 6)
	for i in 120:
		_look_seat(game, cam)
		g.step(DT)
	T._render()
	print("RAIDS RENDER a second on: %d strikes, %d out, the commuter %s, bursts %d shown (%d waiting)" % [g.commuter_strikes, g.kills,
		"still there" if T.cars.has(car) else "GONE", R.burst.shown if R.burst else 0, R.burst.bursts.size() if R.burst else 0])
	await _snap(game, "struck-after", 90)
	_look_at(game, cam, car.lamp_position)
	g.step(0.0)
	await _snap(game, "struck-after-near", 6)
	game.free()
	await process_frame
	return true


## A commuter `dist` m out along the bore, `deg` degrees to its left, at a standstill (no raider: hostile false).
func _put(game, g, deg: float, dist: float):
	var T = game.traffic_net
	var sim = game.sim
	var ray: Array = g.mount.aim_ray(game.cam)
	var o: Vector3 = g.to_sim(ray[0])
	var d: Vector3 = g.dir_to_sim(ray[1])
	var ahead := Vector2(d.x, d.y).normalized()
	var left := Vector2(-ahead.y, ahead.x)
	var at := Vector2(o.x, o.y) + (ahead * cos(deg_to_rad(deg)) + left * sin(deg_to_rad(deg))) * dist
	var R = sim.roads[sim.pod.path]
	var near := int(sim.pod.hint)
	for i in range(maxi(0, int(sim.pod.hint) - 10), mini(R.N - 1, int(sim.pod.hint) + int(3000.0 / 24.0))):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	c.id = 990201
	c.kind = T.CAR
	c.road = sim.pod.path
	c.dir = 1
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = false
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	return c


# --- Raids off (the head, or the base) ----------------------------------------------------------------------------

func _off_set() -> bool:
	_pin(false)
	var game = _seat()
	var sim = game.sim
	var t := _town(sim)
	sim.respawn_on(int(t.road), int(t.z.x) - 150, 1)
	for i in 90:
		_hold(game, 3000.0 / MPH)
		game._process(DT)
	_hide_layers(game)
	var cam := game.cam as Camera3D
	for i in 12:
		_hold(game, 3000.0 / MPH)
		game._process(DT)
	print("RAIDS RENDER off: dash \"%s\", map target %d, director %s, fire control %s" % [game._net_text(), game.minimap.target, game.get("raids"), game.get("gunnery")])
	_look_seat(game, cam)
	await _snap(game, "off-seat", 90)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "off-map", 24)
	Tactical.wanted = true
	for i in 151:
		_hold(game, 3000.0 / MPH)
		game._process(DT)
	print("RAIDS RENDER off: dash \"%s\", tactical %d lines, the score %d" % [game._net_text(), game.tactical.line_count if game.tactical else -1,
		game.skill_score.total if game.skill_score else -1])
	_look_seat(game, cam)
	await _snap(game, "off-tac-seat", 90)
	_look_at(game, cam, (game.minimap_panel as Node3D).global_position)
	await _snap(game, "off-tac-map", 24)
	_look_at(game, cam, (game.dashboard as Node3D).global_position)
	await _snap(game, "off-dash", 34)
	Tactical.wanted = false
	game.free()
	await process_frame
	return true


# --- the menus ----------------------------------------------------------------------------------------------------

func _menus_set() -> bool:
	for view in ["menu-desktop", "menu-desktop-plain", "menu-vr"]:
		Title.enabled = view != "menu-desktop-plain"
		change_scene_to_file("res://release/vr_menu.tscn" if view == "menu-vr" else "res://release/menu.tscn")
		await scene_changed
		var menu = current_scene
		if view == "menu-vr":
			menu.set_process(false)      # (no headset: its own frame would only look for one)
		var stage = menu.get("stage")
		var deadline := Time.get_ticks_msec() + 15000
		while stage != null and not stage.art_ready and Time.get_ticks_msec() < deadline:
			await process_frame
		await _wait(1.0)
		_measure(view, menu)
		if view == "menu-vr":
			var cam: Camera3D = menu.camera
			if menu.has_method("_place_board"):
				menu.set("swing", 0.0)
				menu._place_board()
			if stage != null and stage.has_method("attend"):
				stage.attend(false)
				stage.set("reveal", 0.0)
				if stage.has_method("_pose_turntable"):
					stage._pose_turntable()
			cam.rotation_degrees = Vector3.ZERO
			cam.fov = 96.0
			await _wait(0.25)
			await _save("menu-vr")
			var board: Node3D = menu.get("board")
			if board != null:
				cam.look_at(board.global_position, Vector3.UP)
				cam.fov = 44.0
				await _wait(0.25)
				await _save("menu-vr-board")
		else:
			await _save(view)
	Title.enabled = true
	return true


## Does each button's label fit it? Every button the menus have, against every label it can show (each course marked
## and not, each start point, hour and weather, each craft's name, Fly for each course) and the room inside it (its
## width less its style's margins), with its height; where the menu's last control (Quit, or the headset's Start and
## Quit) stands against the window; and the room left in the column Fly or Start stands in (a column with none
## pushes its foot down). Prints "fits" or "CUT" with the widths in pixels of the window. (The saved choices differ
## between checkouts' profiles: this measures every choice, so the head and the base are compared like for like.)
func _measure(view: String, menu: Node) -> void:
	var crafts: Dictionary = (load("res://sim/pilot_craft.gd") as GDScript).get_script_constant_map().get("NAMES", {})
	var named := func(title: String, choices: Array) -> Array: return choices.map(func(c): return "%s:  %s" % [title, c[1]])
	var asks := {
		"Start": named.call("Start", UI.INSERTIONS),
		"Time": named.call("Time", Outlook.TIMES),
		"Weather": named.call("Weather", Outlook.WEATHERS),
		"Chase": named.call("Chase", Chase.MODES),
		"Role": named.call("Role", Chase.CRAFTS),
		"Raids": ["Raids:  Off", "Raids:  On"],
		"Pilot craft": crafts.values().map(func(n): return "Pilot craft   ·   %s   ›" % n),
		"Pilot garage": ["Pilot garage"],      # (Codex's garage, beside Quit)
		"Quit to desktop": ["Quit to desktop"],
	}
	for title in asks:
		var b := _find_button(menu, title)
		if b == null:
			print("RAIDS RENDER %s: no %s button" % [view, title])
			continue
		_fit(view, title, b, asks[title])
	var rows = menu.get("buttons")
	for i in UI.COURSES.size():
		var course: Dictionary = UI.COURSES[i]
		var b := menu.find_child("Course_" + course.id, true, false) as Button
		if b == null and rows is Array and (rows as Array).size() > i:
			b = rows[i]
		if b != null:
			_fit(view, "course " + course.id, b, ["●  " + course.name, "    " + course.name])
	var fly := menu.find_child("Fly", true, false) as Button
	if fly == null:
		fly = menu.get("start_button") as Button
	if fly != null:
		_fit(view, "Fly", fly, UI.COURSES.map(func(c): return "%s — %s" % [fly.text.get_slice(" —", 0), c.name]))
		var column := fly.get_parent() as Control
		print("RAIDS RENDER %s: the column Fly stands in is %d px tall and needs %d: %d px to spare" % [view, roundi(column.size.y), roundi(column.get_combined_minimum_size().y),
			roundi(column.size.y - column.get_combined_minimum_size().y)])
	for last in ["Quit to desktop", "Start flight", "Fly"]:
		var q := _find_text(menu, last)
		if q != null:
			var r := q.get_global_rect()
			var seen := q.get_viewport().get_visible_rect().size
			print("RAIDS RENDER %s: \"%s\" at y %d..%d of the %d px it is drawn in: %s" % [view, q.text.get_slice(" —", 0), roundi(r.position.y), roundi(r.end.y), roundi(seen.y),
				"on screen" if r.end.y <= seen.y + 0.5 else "OFF SCREEN"])
	if rows is Array:
		print("RAIDS RENDER %s: the stick's order: %s" % [view, " | ".join((rows as Array).map(func(b): return (b as Button).text.get_slice("  ", 0).get_slice(":", 0).strip_edges()))])
	var panel = menu.get("panel_view")
	if panel is SubViewport:
		var board := Rect2(Vector2.ZERO, Vector2((panel as SubViewport).size))
		for hint in ["Release controls", "Stick up/down"]:
			for l: Label in menu.find_children("*", "Label", true, false):
				if not l.text.begins_with(hint):
					continue
				var r := l.get_global_rect()
				var widest := 0.0
				for line in l.text.split("\n"):
					widest = maxf(widest, l.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
				print("RAIDS RENDER %s: the hint \"%s\" at x %d..%d, y %d..%d of the %d x %d board, its longest line %d px in %d: %s" % [view, hint, roundi(r.position.x), roundi(r.end.x),
					roundi(r.position.y), roundi(r.end.y), roundi(board.size.x), roundi(board.size.y), roundi(widest), roundi(r.size.x), "fits" if board.encloses(r) and widest <= r.size.x + 0.5 else "CUT"])


## One button against the labels it can show: "fits" or "CUT", each with its width; the button's own size.
func _fit(view: String, title: String, b: Button, texts: Array) -> void:
	var style := b.get_theme_stylebox("normal")
	var room := b.size.x - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT)
	var font := b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var said := []
	var cut := 0
	for text: String in texts:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		cut += int(w > room)
		said.append("%s %s (%d)" % ["fits" if w <= room else "CUT", text.strip_edges().replace("   ", " ").replace("  ", " "), roundi(w)])
	print("RAIDS RENDER %s: %s button %d x %d px, %d inside%s; showing \"%s\": %s" % [view, title, roundi(b.size.x), roundi(b.size.y), roundi(room),
		", %d CUT" % cut if cut > 0 else "", b.text.strip_edges(), "; ".join(said)])


func _find_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text.begins_with(text):
		return node
	for child in node.get_children():
		var b := _find_text(child, text)
		if b != null:
			return b
	return null


func _find_button(node: Node, title: String) -> Button:
	if node is Button and ((node as Button).text == title or (node as Button).text.begins_with(title + ":") or (node as Button).text.begins_with(title + "   ·")):
		return node
	for child in node.get_children():
		var b := _find_button(child, title)
		if b != null:
			return b
	return null


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	print("RAIDS VIEW %s" % path)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
