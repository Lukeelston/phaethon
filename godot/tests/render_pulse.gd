## The Vesper's shock pulse (view/weapons/pulse_mount.gd on Codex's view/arms/vesper_arms.gd) in the game's own VR cockpit
## with XR off, on a Network straight: from the seat and from outside with the GUN never armed (seat-stowed, out-stowed)
## and armed, the wheel up out of the forward starboard sill (seat-armed, out-armed); then a ring with the world held still
## (the fire control stepped on its own, as tests/test_pulse.gd does: the craft stands where it is, so the ring spreads
## round it as round a craft at rest): from the seat in its first frames (early-f2, before it is drawn; early-first, the
## first frame it is drawn; early-first-down, the same looking down to the right over the wheel; early-f12), at 150 m and
## at 450 m from the seat (seat-150, seat-450) and from above (above-150, above-450); and a ring on the view's own frames at
## 1,500 mph, the craft chasing its front (moving-first: the first frame it is drawn; moving-450 from the seat;
## moving-above-450). The still world's shots never run the view's own frame: the dash's strip is never told the gun's
## words, and shows none of them.
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_pulse.gd -- --mute --out=ABSOLUTE_DIRECTORY
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
const LOOK := Vector3(0.0, -0.035, -1.0)      # the seat's look: ahead along the rig, a little down
const DOWN_RIGHT := Vector3(0.45, -0.42, -1.0)      # ... and down to the right, over the wheel and the road beside it
const OUT_EYE := Vector3(3.4, 1.9, 1.6)       # outside: behind the forward starboard sill and above it (the cockpit's own frame)
var output := ""
var _way := 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Pulse screenshots need a rendering display.")
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
	var cam := game.cam as Camera3D
	_look_seat(game, cam, LOOK)
	await _snap(game, null, "seat-stowed", 90)
	_look_out(game, cam, null)
	await _snap(game, null, "out-stowed", 50)
	# Armed: the fire control and the arms are made; from here the world is still.
	game.gun_wanted = true
	for i in 2:
		_hold_speed(game)
		game._process(DT)
	var g = game.gunnery
	if g == null or g.mount.get("arms") == null:
		push_error("No fire control or arms were made on arming")
		quit(1)
		return
	var cars: Array = game.traffic_net.cars.duplicate()
	game.traffic_net.cars.clear()
	game.traffic_net._render()      # (traffic held still too, and none of it in the way)
	_hold_speed(game)
	g.want_out = true
	g.power = 1.0
	for i in int(1.1 / DT):
		g.step(DT)
	var m = g.mount
	_look_seat(game, cam, LOOK)
	g.step(DT)
	await _snap(game, g, "seat-armed", 90)
	_look_out(game, cam, m)
	g.step(DT)
	await _snap(game, g, "out-armed", 50)
	# A ring, the world still: its first frames from the seat, then at 150 m and at 450 m.
	_look_seat(game, cam, LOOK)
	_press(g)
	var frame := 0
	var first := -1
	while frame < int(0.6 / DT):
		frame += 1
		_look_seat(game, cam, LOOK)
		g.step(DT)
		if frame == 2:
			await _snap(game, g, "early-f2", 90)
		if first < 0 and m.ring.visible:
			first = frame
			await _snap(game, g, "early-first", 90)
			_look_seat(game, cam, DOWN_RIGHT)
			_redraw(game, g)
			await _snap(game, g, "early-first-down", 90)
		if frame == 12:
			await _snap(game, g, "early-f12", 90)
		if frame == int(round(150.0 / 450.0 * 0.5 / DT)):
			await _snap(game, g, "seat-150", 90)
			_look_above(game, cam, m, 460.0)
			_redraw(game, g)
			await _snap(game, g, "above-150", 50)
		if frame == int(round(0.5 / DT)):
			await _snap(game, g, "seat-450", 90)
			_look_above(game, cam, m, 1150.0)
			_redraw(game, g)
			await _snap(game, g, "above-450", 50)
	print("PULSE RENDER: still, the ring first drawn %d frames after its release" % first)
	# A ring on the view's own frames at 1,500 mph (its charge given back by hand: the recharge is the test's).
	for i in int(0.4 / DT):
		g.step(DT)
	m.charge = 0.0
	for c in cars:
		game.traffic_net.cars.append(c)
	_on_a_straight(game)
	_look_seat(game, cam, LOOK)
	for i in 20:
		_hold_speed(game)
		game._process(DT)
	g.hold_fire = true
	_hold_speed(game)
	game._process(DT)
	g.hold_fire = false
	var moving_first := -1
	for k in range(1, int(0.6 / DT)):
		_hold_speed(game)
		game._process(DT)
		if moving_first < 0 and m.ring.visible:
			moving_first = k
			_look_seat(game, cam, LOOK)
			_redraw(game, g)
			await _snap(game, g, "moving-first", 90)
		if k == int(round(0.5 / DT)):
			_look_seat(game, cam, LOOK)
			_redraw(game, g)
			await _snap(game, g, "moving-450", 90)
			_look_above(game, cam, m, 1150.0)
			_redraw(game, g)
			await _snap(game, g, "moving-above-450", 50)
	print("PULSE RENDER: at 1,500 mph, the ring first drawn %d frames after its release" % moving_first)
	game.free()
	await process_frame
	quit()


func _press(g) -> void:
	g.hold_fire = true
	g.step(DT)
	g.hold_fire = false


## The sights and the ring drawn again for where the camera now is, nothing stepped (the ring itself is not drawn for an
## eye: only the fire control's sight is).
func _redraw(game, g) -> void:
	g._draw(game.cam)


func _look_seat(game, cam: Camera3D, look: Vector3) -> void:
	var rig: Transform3D = game.rig.global_transform
	cam.global_position = rig * Seat.EYE
	cam.look_at(cam.global_position + rig.basis * look.normalized(), rig.basis.y)


## From outside, in the cockpit's own frame (its shell), at the wheel (or where it will rise: the shell's forward
## starboard sill).
func _look_out(game, cam: Camera3D, m) -> void:
	var frame: Transform3D = game.shell.global_transform
	cam.global_position = frame * OUT_EYE
	var at: Vector3 = m.origin() if m != null and m.arms != null else frame * Vector3(1.0, 0.4, -1.0)
	cam.look_at(at, frame.basis.y)


## From `up` m over the ring's release point, looking straight down, the road's way at the top of the picture.
func _look_above(game, cam: Camera3D, m, up: float) -> void:
	var g = game.gunnery
	var c: Vector3 = g.to_render(Vector3(m.centre.x, m.centre.y, m.ring_h))
	cam.global_position = c + Vector3.UP * up
	var way: Vector3 = -game.rig.global_transform.basis.z
	cam.look_at(c, Vector3(way.x, 0.0, way.z).normalized())


func _snap(game, g, shot: String, fov: float) -> void:
	(game.cam as Camera3D).fov = fov
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join("pulse-" + shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	if g == null:
		print("PULSE VIEW %s (unarmed: no fire control %s, no arms %s)" % [path, game.gunnery == null, game.shell.get_node("PodHull").get_node_or_null("Arms") == null])
	else:
		var m = g.mount
		var eye: Vector3 = g.to_sim(game.cam.global_position)
		var front := Vector2(eye.x - m.centre.x, eye.y - m.centre.y).length()      # (the eye's way from the release point, over the ground)
		print("PULSE VIEW %s deploy=%.2f ring_t=%.3f r=%.1f drawn=%s drawn_r=%.1f light=%.2f heat=%.2f charge=%.2f; the eye %.2f m over the ring's plane, %.1f m from its release point" % [
			path, m.deploy_t(), m.ring_t, m.ring_r, m.ring.visible if m.ring != null else false, m.drawn_r, m.ring_light, m.heat(), m.charge,
			eye.z - (m.ring_h + float((m.get_script() as Script).get_script_constant_map().get("RING_LIFT", 0.0))), front])


## As tests/test_pulse.gd: the start of a straight, level stretch of road.
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
				print("PULSE RENDER: on road %s at sample %d" % [R.name, i])
				return


func _hold_speed(game) -> void:
	var sim = game.sim
	var R = sim.roads[sim.pod.path]
	var i := clampi(int(sim.pod.hint), 0, R.N - 1)
	for b in [sim.eL, sim.eR, sim.pod]:
		b.vx = R.tx[i] * _way * SPEED
		b.vy = R.ty[i] * _way * SPEED
		b.vz = 0.0
