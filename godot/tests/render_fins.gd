## The engine fins in a turn, for looking at (Luke: "The engine fins should rotate left/right as well as
## up/down with turning"): either craft going straight; in a gentle turn each way (a lever split of 0.08:
## three quarters of his flying is gentler than that); in a firm one (a grip a third in, both levers up, as
## the eighth flight's log has an air-brake turn: one in twenty of his is firmer); in a hard one (a lever
## pulled back and that engine's brake thrown: a bench input); and parked with a grip squeezed. From the seat
## and from outside. Run windowed, as render_shrike.gd:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_fins.gd -- --mute --out=DIR [--craft=shrike] [--views=a,b] [--drives=straight,hard-left]
## [--film=DIR --film-view=seat-zoom]   a slalom from the seat, a JPEG every fourth frame (30 a second) into DIR
## It reads nothing an older craft did not have (the fins' own numbers only where they exist), so the same
## pictures can be taken of the craft as it was.
extends "res://tests/render_terminal_art.gd"

# How each picture is flown: seconds at full dry thrust, then seconds of the turn (and which).
const DRIVES := {
	"straight": [3.0, 0.0, ""],
	"gentle-left": [3.0, 1.0, "light-L"],
	"gentle-right": [3.0, 1.0, "light-R"],
	"firm-left": [3.0, 0.8, "squeeze-L"],
	"firm-right": [3.0, 0.8, "squeeze-R"],
	"hard-left": [3.0, 0.55, "hard-L"],      # (a second of it puts her in the wall)
	"hard-right": [3.0, 0.55, "hard-R"],
	"parked-left-grip": [0.0, 1.2, "parked-L"],      # standing on the brakes, the left grip squeezed right in
	"parked-right-grip": [0.0, 1.2, "parked-R"],
}
# The cameras:
#   ["seat", field of view, degrees of head pitch]
#   ["behind", m right of the engines' middle, m up, m behind their nozzles]     looking at the engines
#   ["engine", which, eye, target]                                               in that engine's frame
const CAMS := {
	"seat": ["seat", 96.0, -9.0],
	"seat-zoom": ["seat", 22.0, NAN],      # (the head turned to the engines, wherever the turn has put them)
	"behind": ["behind", 0.0, 3.4, 5.5],
	"above": ["behind", 0.0, 11.0, -1.0],
	"fin-close": ["engine", 1, Vector3(-0.9, 2.3, 6.2), Vector3(0.9, 0.75, 1.0)],
	"fin-port": ["engine", 0, Vector3(0.9, 2.3, 6.2), Vector3(-0.9, 0.75, 1.0)],
	"flank": ["engine", 1, Vector3(4.6, 1.5, 3.6), Vector3(1.3, 0.2, 0.7)],
	"fin-behind": ["engine", 1, Vector3(0.5, 1.9, 4.6), Vector3(0.5, 0.85, 0.9)],
	"fin-above": ["engine", 1, Vector3(0.7, 4.6, 2.2), Vector3(0.7, 0.4, 0.9)],
	"fin-outboard": ["engine", 1, Vector3(3.4, 1.0, 4.0), Vector3(1.5, 0.2, 0.9)],
}


func _input_for(turn: String) -> Dictionary:
	var inp := {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
	match turn:
		"light-L", "light-R":
			var side := turn.right(1)
			inp["thr" + side] = 0.95
			inp["brk" + side] = 0.05
			inp["brk" + ("R" if side == "L" else "L")] = 0.02
		"squeeze-L", "squeeze-R":      # as the eighth flight's log has an air-brake turn
			var side := turn.right(1)
			inp["thr" + side] = 0.74
			inp["brk" + side] = 0.16
			inp["brk" + ("R" if side == "L" else "L")] = 0.10
		"hard-L", "hard-R":
			var side := turn.right(1)
			inp["thr" + side] = 0.25
			inp["brk" + side] = 1.0
		"parked-L":
			inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 0.35, "repair": false, "reignite": true}
		"parked-R":
			inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.35, "brkR": 1.0, "repair": false, "reignite": true}
	return inp


func _fins(craft) -> String:
	var said := ""
	if "fin_swing" in craft:
		said += "  fins swung %.1f deg" % rad_to_deg(craft.fin_swing)
	if "fin_stand" in craft and not craft.fin_parts.is_empty():
		said += "  cant L %.1f R %.1f deg, rods %.3f %.3f m" % [rad_to_deg(craft.fin_stand[0]), rad_to_deg(craft.fin_stand[1]), craft.fin_ram[0], craft.fin_ram[1]]
	elif not craft.fin_parts.is_empty():
		said += "  cant %.1f deg" % rad_to_deg(craft.fin_cant)
	if "fin_pitch" in craft and craft.fin_parts.is_empty():
		said += "  stabilisers pitched %.1f deg" % rad_to_deg(craft.fin_pitch)
	return said


func _aim(cam: Array) -> void:
	var craft = seat.craft
	match str(cam[0]):
		"seat":
			seat.cam.position = Vector3.ZERO
			seat.cam.fov = float(cam[1])
			if not is_nan(float(cam[2])):
				seat.cam.rotation_degrees = Vector3(float(cam[2]), 0.0, 0.0)
			else:
				seat.cam.rotation = Vector3.ZERO
				var mid: Vector3 = ((craft.engines[0] as Node3D).global_position + (craft.engines[1] as Node3D).global_position) * 0.5
				seat.cam.look_at(mid + (craft.engines[0] as Node3D).global_basis.y * 0.6, (seat.cam.get_parent() as Node3D).global_basis.y)
		"behind":
			var mid: Vector3 = ((craft.engines[0] as Node3D).global_position + (craft.engines[1] as Node3D).global_position) * 0.5
			var basis: Basis = (craft.engines[0] as Node3D).global_basis
			var nozzle: Vector3 = mid + basis.z * 4.3
			seat.cam.global_position = nozzle + basis.x * float(cam[1]) + Vector3.UP * float(cam[2]) + basis.z * float(cam[3])
			seat.cam.look_at(mid + basis.z * 1.0 + Vector3.UP * 0.5, Vector3.UP if float(cam[2]) < 8.0 else -basis.z)
			seat.cam.fov = 60.0
		"engine":
			var frame: Transform3D = (craft.engines[int(cam[1])] as Node3D).global_transform
			seat.cam.global_position = frame * (cam[2] as Vector3)
			seat.cam.look_at(frame * (cam[3] as Vector3), Vector3.UP)
			seat.cam.fov = 60.0


func _run() -> void:
	var only := PackedStringArray()
	var drives := PackedStringArray()
	var film := ""
	var film_view := "seat-zoom"
	var vehicle := "phaethon"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			only = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--drives="):
			drives = arg.trim_prefix("--drives=").split(",")
		if arg.begins_with("--craft="):
			vehicle = arg.trim_prefix("--craft=")
		if arg.begins_with("--film="):
			film = arg.trim_prefix("--film=")
		if arg.begins_with("--film-view="):
			film_view = arg.trim_prefix("--film-view=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	Seat._nose_loaded = true       # (the pilot's saved choices stay out of the pictures)
	Seat._slide_loaded = true
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._map_loaded = true
	Seat._school_loaded = true
	preload("res://view/livery.gd").pinned = true
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	var chase_script := preload("res://view/network_chase.gd")
	chase_script.pinned = true
	chase_script.enabled = false
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.vehicle_override = vehicle
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	if seat.cam == null:      # a script under it failed to compile: say so now, not at the timeout
		push_error("The cockpit did not build.")
		quit(1)
		return
	seat.set_process(false)
	seat.cruise = 0.0
	city = {"road": 2, "i": 9000}   # E3, open country
	_set_pose(0)
	for i in 2400:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	var wide: float = seat.cam.fov
	var craft = seat.craft
	print("FIN_SHOT craft %s" % seat.sim.P.vehicle)
	if not film.is_empty():
		await _film(film, CAMS[film_view])
		seat.free()
		quit()
		return
	for drive in DRIVES:
		if not drives.is_empty() and not drives.has(drive):
			continue
		var plan: Array = DRIVES[drive]
		seat.inp = {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}
		_set_pose(0)
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		seat.cam.fov = wide
		for body in [seat.sim.eL, seat.sim.eR, seat.sim.pod]:
			body.heat = 0.3
			body.health = 1.0
		for frame in 360:      # standing: whatever the last drive left runs out
			seat._process(STEP)
			if frame % 8 == 0:
				await process_frame
		var total := int(float(plan[0]) * 120.0)
		var turn := int(float(plan[1]) * 120.0)
		for frame in total + turn:
			seat.inp = _input_for(str(plan[2]) if frame >= total else "")
			seat._process(STEP)
			if frame % 4 == 0:
				await process_frame
		var p = seat.sim.pod
		print("FIN_SHOT %s  %.0f mph  %.0f g  vanes %.1f deg%s" % [drive, sqrt(p.vx * p.vx + p.vy * p.vy) * 2.23694, seat._slide_load, rad_to_deg(craft.vane_angle), _fins(craft)])
		for name in CAMS:
			if not only.is_empty() and not only.has(name):
				continue
			seat.cam.position = Vector3.ZERO
			seat.cam.rotation = Vector3.ZERO
			_aim(CAMS[name])
			for frame in 2:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join("%s-%s.png" % [name, drive])
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			if name == "seat":
				print("FIN_SHOT   from the seat: %d draw calls, %d objects in the frame" % [
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	seat.free()
	quit()


## A slalom as he flies one: up to speed, then gentle turns one way and the other (a lever split of 0.08),
## then a firmer pair (a grip a third in). A JPEG every fourth frame (30 a second).
func _film(dir: String, cam: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	seat.inp = _input_for("")
	for frame in 420:
		seat._process(STEP)
		if frame % 4 == 0:
			await process_frame
	var legs := [["", 0.6], ["light-L", 0.6], ["light-R", 1.2], ["light-L", 1.2], ["light-R", 1.2], ["light-L", 0.6], ["", 0.8], ["squeeze-L", 0.45], ["squeeze-R", 0.9], ["squeeze-L", 0.45], ["", 1.2]]
	var shot := 0
	var n := 0
	for leg in legs:
		for frame in int(float(leg[1]) * 120.0):
			seat.inp = _input_for(str(leg[0]))
			seat._process(STEP)
			_aim(cam)
			n += 1
			if n % 4 == 0:
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(dir.path_join("f%04d.jpg" % shot), 0.92)
				shot += 1
	print("FIN_SHOT film: %d pictures in %s%s" % [shot, dir, _fins(seat.craft)])
