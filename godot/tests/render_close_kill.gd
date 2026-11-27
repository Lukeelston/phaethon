## A raider killed 30 m ahead of the seat's eye, from the VR seat (XR off), the Vesper on a Network straight, the world held
## still (the fire control stepped on its own, as tests/test_pulse.gd does): the raider before (closekill-TAG-raider), and
## its burst two and eight frames after the kill (closekill-TAG-plus2, -plus8). It is killed by the fire control's own
## damage() (bare, as the pulse's and the lance's hits are: no spark of its own), so the burst is the only thing drawn.
## Each shot's line tells every disc drawn (across, distance from the eye, degrees of view) and how much of the picture
## is washed out (every channel over 0.92) and the picture's mean light. The whole-branch review's finding 1.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_close_kill.gd -- --mute --out=ABSOLUTE_DIRECTORY --tag=TAG
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Raids := preload("res://view/network_raids.gd")
const Chase := preload("res://view/network_chase.gd")
const DT := 1.0 / 120.0
const SPEED := 1500.0 * 0.44704
const STRAIGHT := 1600.0
const AHEAD := 30.0                            # m over the ground from the eye, straight ahead along the rig
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
const FOV := 90.0
var output := ""
var tag := "now"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Close-kill screenshots need a rendering display.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--tag="):
			tag = arg.trim_prefix("--tag=")
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
	Raids.enabled = false
	Chase.pinned = true
	Chase.enabled = false
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
	Seat.vehicle_override = "vesper"
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	_on_a_straight(game)
	for i in 30:
		_hold_speed(game)
		game._process(DT)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	game.gun_wanted = true
	for i in 2:
		_hold_speed(game)
		game._process(DT)
	var g = game.gunnery
	if g == null:
		push_error("No fire control was made on arming")
		quit(1)
		return
	var T = game.traffic_net
	T.cars.clear()
	g.want_out = true
	g.power = 1.0
	var cam := game.cam as Camera3D
	for i in int(1.1 / DT):
		_look_seat(game, cam)
		g.step(DT)
	# The raider, 30 m ahead of the eye over the ground, on the craft's road.
	var eye: Vector3 = g.to_sim(cam.global_position)
	var fw: Vector3 = g.dir_to_sim(-game.rig.global_transform.basis.z)
	var way := Vector2(fw.x, fw.y).normalized()
	var at := Vector2(eye.x, eye.y) + way * AHEAD
	var c = _raider(game, at)
	T._render()
	_look_seat(game, cam)
	g.step(DT)
	await _snap(game, g, "raider")
	var hit := Vector3(c.x, c.y, T.body_height(c))
	var killed: bool = g.damage(c, g.HOSTILE_HP, hit, false, true)
	T._render()
	print("CLOSE KILL: raider %.1f m ahead of the eye over the ground, killed %s" % [Vector2(eye.x, eye.y).distance_to(at), killed])
	for k in range(1, 9):
		_look_seat(game, cam)
		g.step(DT)
		if k == 2:
			await _snap(game, g, "plus2")
		elif k == 8:
			await _snap(game, g, "plus8")
	game.free()
	await process_frame
	quit()


## A raider (a hostile traffic Car) standing still at `at` (the sims' plane), on the craft's road's nearest sample.
func _raider(game, at: Vector2):
	var T = game.traffic_net
	var sim = game.sim
	var road: int = sim.pod.path
	var R = sim.roads[road]
	var h := int(sim.pod.hint)
	var near := h
	for i in range(maxi(0, h - 200), mini(R.N - 1, h + 200)):
		if Vector2(R.px[i], R.py[i]).distance_squared_to(at) < Vector2(R.px[near], R.py[near]).distance_squared_to(at):
			near = i
	var c = T.Car.new()
	c.id = 997001
	c.kind = T.CAR
	c.road = road
	c.dir = 1
	c.f = float(near)
	c.lane = 0
	c.lat = T._lane_lat(c, 0)
	c.hostile = true
	T._place(c)
	c.x = at.x
	c.y = at.y
	c.v = 0.0
	T.cars.append(c)
	return c


func _look_seat(game, cam: Camera3D) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * LOOK.normalized(), rig.basis.y)


func _snap(game, g, shot: String) -> void:
	var cam := game.cam as Camera3D
	cam.fov = FOV
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := output.path_join("closekill-%s-%s.png" % [tag, shot])
	if img.save_png(path) != OK:
		push_error("Could not write " + path)
	var washed := 0
	var seen := 0
	var light := 0.0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p := img.get_pixel(x, y)
			seen += 1
			light += (p.r + p.g + p.b) / 3.0
			washed += int(p.r > 0.92 and p.g > 0.92 and p.b > 0.92)
	var discs := []
	var e := cam.global_position
	for pair: Array in [["flash", g._flash_mm], ["smoke", g._smoke_mm]]:
		var mm: MultiMesh = pair[1]
		for i in mm.visible_instance_count:
			var t := mm.get_instance_transform(i)
			var side := t.basis.x.length()
			var d := e.distance_to(t.origin)
			discs.append("%s %.1f m across at %.1f m (%.0f deg)" % [pair[0], side, d, rad_to_deg(2.0 * atan(0.5 * side / maxf(d, 0.01)))])
	print("CLOSE KILL VIEW %s: %.1f%% washed out, mean light %.3f; discs: %s" % [path, 100.0 * washed / maxf(1, seen), light / maxf(1, seen),
		"; ".join(discs) if not discs.is_empty() else "none"])


## As tests/render_pulse.gd: the start of a straight, level stretch of road.
func _on_a_straight(game) -> void:
	var sim = game.sim
	var span := int(ceil(STRAIGHT / float(Sim.NET_STEP)))
	var roads := [int(sim.pod.path)]
	for r in sim.roads.size():
		if r != roads[0]:
			roads.append(r)
	for r: int in roads:
		var R = sim.roads[r]
		if R.deck or R.shaft or R.banked or R.role != "" or R.N < span + 400:
			continue
		var from := clampi(int(sim.pod.hint), 300, R.N - span - 100) if r == roads[0] else 300
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
				print("CLOSE KILL: on road %s at sample %d" % [R.name, i])
				return


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * SPEED
		b.vy = R.ty[i] * SPEED
		b.vz = 0.0
