## Over Mount Hyperion's lip from the pilot's seat, slowly (Luke, 2026-11-22, flying it: "going over the edge
## slowly goes in chunks rather than just smoothly rolling over"): what the pilot is shown a 90 Hz frame at a
## time, and pictures of it. Run windowed, as render_hyperion.gd, but at the headset's rate:
## --xr-mode off --resolution 1280x720 --fixed-fps 90 --audio-driver Dummy
## -s res://tests/render_brink.gd -- --mute --out=DIR [--mph=20,80,250] [--film=20] [--every=3] [--gaze=0,-6]
## The craft is put three samples short of the lip and held to each speed along the deck (the sim's own
## thrust and drag left out, as tests/test_hyperion.gd holds it) until it is three samples down the wall.
## DIR/seat-<mph>.csv has a line a frame: the time, the deck covered, the pod's sample; the sim's pitch for
## the views (deck_pitch); the cockpit's place (m along the road's line from the lip, m up) and pitch; the
## camera's; where the left engine is drawn from the cockpit (m ahead, m up: degrees over the nose); and the
## pod's model's pitch. --film= saves a picture every --every frames at that speed, DIR/film-<mph>/f00000.jpg.
extends "res://tests/render_terminal_art.gd"

const Hyperion := preload("res://view/hyperion.gd")
const MPH := 2.236936
const HZ := 90.0


## The production cockpit, its craft held to a speed along its road after every step of the sim.
class Creeper extends "res://vr/vr_cockpit.gd":
	var hold_mps := -1.0
	var hold_at := 0

	func _sim_step() -> void:
		super()
		hold()

	func hold() -> void:
		if hold_mps < 0.0:
			return
		var R = sim.roads[sim.pod.path]
		for b in sim.bodies:
			b.vx = hold_mps * R.tx[hold_at]
			b.vy = hold_mps * R.ty[hold_at]
			b.w = 0.0
			b.th = atan2(R.ty[hold_at], R.tx[hold_at])


func _run() -> void:
	var speeds := [20.0, 80.0, 250.0]
	var film := -1.0
	var every := 3
	var gaze := Vector2(0.0, -6.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--mph="):
			speeds = []
			for part in arg.trim_prefix("--mph=").split(","):
				speeds.append(float(part))
		if arg.begins_with("--film="):
			film = float(arg.trim_prefix("--film="))
		if arg.begins_with("--every="):
			every = maxi(1, int(arg.trim_prefix("--every=")))
		if arg.begins_with("--gaze="):
			var parts := arg.trim_prefix("--gaze=").split(",")
			gaze = Vector2(float(parts[0]), float(parts[1]))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Creeper.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	var sim = seat.sim
	var world = seat.network_world
	if not Hyperion.ready:
		push_error("No Mount Hyperion in this world.")
		quit(1)
		return
	var road: int = Hyperion.road
	var R = sim.roads[road]
	var lip: int = int(Hyperion.at.lip)
	var drop: int = int(Hyperion.at.drop)
	var from := lip - 3
	sim.respawn_on(road, from, 1)
	seat._ride.clear()
	for i in 6000:
		world.sync(sim.pod.x, sim.pod.y)
		seat.landscape.sync(sim.pod.x, sim.pod.y)
		if i % 40 == 0:
			await process_frame
		var roads_done: bool = world.wanted == 0 and world._job.is_empty() and world._bank_queue.is_empty() and world._bank_job.is_empty()
		if i > 600 and roads_done and seat.landscape.pending.is_empty() and seat.landscape._job.is_empty():
			break
	seat.cam.position = Vector3.ZERO
	seat.cam.rotation_degrees = Vector3(gaze.y, gaze.x, 0.0)
	for mph in speeds:
		var filming: bool = film == mph
		var film_dir := out_dir.path_join("film-%d" % int(mph))
		if filming:
			DirAccess.make_dir_recursive_absolute(film_dir)
		sim.respawn_on(road, from, 1)
		seat._ride.clear()
		seat.acc = 0.0
		seat.hold_at = from
		seat.hold_mps = mph / MPH
		seat.hold()
		for warm in 30:      # (the cockpit's own easing settled on the level summit, the craft not yet moving on)
			seat.hold_mps = 0.0
			seat.hold()
			seat._process(1.0 / HZ)
			await process_frame
		seat.hold_mps = mph / MPH
		seat.hold()
		var rows := FileAccess.open(out_dir.path_join("seat-%d.csv" % int(mph)), FileAccess.WRITE)
		rows.store_line("frame,t,deck_m,f,sim_pitch,rig_plan,rig_z,rig_pitch,cam_plan,cam_z,cam_pitch,eng_ahead,eng_up,eng_deg,pod_pitch")
		var frame := 0
		var t := 0.0
		var shots := 0
		while t < 400.0 and sim._road_f(sim.pod) < float(drop + 3) and not sim.pod.off_road:
			seat._process(1.0 / HZ)
			seat.cam.rotation_degrees = Vector3(gaze.y, gaze.x, 0.0)
			await process_frame
			t += 1.0 / HZ
			var rig: Transform3D = seat.rig.transform
			var cam: Transform3D = seat.transform.affine_inverse() * (seat.cam.global_transform as Transform3D)
			var eng: Vector3 = rig.affine_inverse() * ((seat.craft.engines[0] as Node3D).position)
			rows.store_line("%d,%.5f,%.4f,%.5f,%.5f,%.4f,%.4f,%.5f,%.4f,%.4f,%.5f,%.4f,%.4f,%.5f,%.5f" % [frame, t, mph / MPH * t, sim._road_f(sim.pod),
				rad_to_deg(sim.deck_pitch(sim.pod)), _plan(R, lip, rig.origin), rig.origin.y, _nose(rig.basis, R, lip), _plan(R, lip, cam.origin), cam.origin.y,
				_nose(cam.basis, R, lip) - gaze.y, -eng.z, eng.y, rad_to_deg(atan2(eng.y - Seat.EYE.y, -(eng.z - Seat.EYE.z))), rad_to_deg((seat.craft.pod as Node3D).rotation.x)])
			if filming and frame % every == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(film_dir.path_join("f%05d.jpg" % shots), 0.92)
				shots += 1
			frame += 1
		print("BRINK_SEAT %d mph: %d frames (%.1f s) from sample %d to %.2f; %d pictures" % [int(mph), frame, t, from, sim._road_f(sim.pod), shots])
	seat.free()
	quit()


## How far along the road's line over the map a place in the view is from the lip's sample, m.
func _plan(R, lip: int, at: Vector3) -> float:
	var x: float = seat.org_x + at.x
	var y: float = seat.org_y - at.z
	return (x - R.px[lip]) * R.tx[lip] + (y - R.py[lip]) * R.ty[lip]


## A frame's nose (its -Z) against the level, degrees (+ up), in the upright plane the road runs in (so a
## gaze that passes straight down reads on past 90).
func _nose(b: Basis, R, lip: int) -> float:
	var ahead := -b.z.normalized()
	return rad_to_deg(atan2(ahead.y, ahead.dot(Vector3(R.tx[lip], 0.0, -R.ty[lip]))))
