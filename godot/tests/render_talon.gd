## The Phaethon Talon (sim/pilot_craft.gd "talon": the Phaethon with Codex's swept twin-tail starfighter body,
## view/talon_airframe.gd) and the Phaethon, in the game's own VR cockpit with XR off: outside, the starboard
## engine, the cab, the seat (Seat.EYE, ahead and a little down), the chase camera (Seat.CAMERA_OFFSETS.chase),
## the pod from the side and from above. Then how far below the horizon the view from the eye is first cut off
## by the craft itself, straight ahead and either side (the road nearer than that is hidden).
## Needs a window: --xr-mode off --fixed-fps 120 -s res://tests/render_talon.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   [--vehicles=phaethon,talon] [--paint=factory|<a view/livery.gd id>] [--views=exterior,seat,...] [--arms=out]
## --arms=out brings the craft's arms out (view/arms/<craft>_arms.gd set_deploy(1)) where it has them; the "gun" view
## (not in the default list) looks at the starboard gun from ahead: the Phaethon's engine's nose, the Talon's wing root.
## (It names no craft or script that the Phaethon's own line lacks, so the same file renders a base checkout's.)
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const VIEWS := ["exterior", "engine", "cab", "seat", "chase", "side", "above"]
const AZIMUTHS := [-50.0, -30.0, -15.0, 0.0, 15.0, 30.0, 50.0]   # degrees right of straight ahead
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Talon screenshots need a rendering display.")
		quit(1)
		return
	var vehicles := ["phaethon", "talon"]
	var views := VIEWS.duplicate()
	var arms_out := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--vehicles="):
			vehicles = Array(arg.trim_prefix("--vehicles=").split(","))
		elif arg.begins_with("--views="):
			views = Array(arg.trim_prefix("--views=").split(","))
		elif arg == "--arms=out":
			arms_out = true
		elif arg.begins_with("--paint="):
			load("res://view/talon_airframe.gd").paint = arg.trim_prefix("--paint=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = "ember"
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	for id: String in vehicles:
		Seat.vehicle_override = id
		var game := Seat.new()
		root.add_child(game)
		game.set_process(false)
		for i in 12:
			game._process(1.0 / 120.0)
		var arms = game.craft.get("arms")      # (a base checkout's craft has none: get, not .arms)
		if arms_out and arms != null:
			arms.set_deploy(1.0)
			print("TALON ARMS out: ", id)
		for child in game.get_children():
			if child is CanvasLayer:
				child.hide()
		var cab: Transform3D = game.canopy.global_transform
		var shell: Transform3D = game.shell.global_transform
		var engine: Transform3D = game.craft.engines[1].global_transform
		var middle: Vector3 = (cab.origin + engine.origin - cab.basis.x * game.sim.P.engineGap * 0.5) * 0.5
		var ahead := Vector3(-cab.basis.z.x, 0.0, -cab.basis.z.z).normalized()      # the heading, level
		var cam := game.cam as Camera3D
		for view: String in views:
			cam.fov = 38
			match view:
				"exterior":
					cam.global_position = middle + cab.basis * Vector3(26, 14, -19)
					cam.look_at(middle + cab.basis * Vector3(0, 0, -1.75), cab.basis.y)
					cam.fov = 33
				"engine":
					cam.global_position = engine * Vector3(7.2, 3.6, -6.7)
					cam.look_at(engine.origin, engine.basis.y)
				"cab":
					cam.global_position = cab * Vector3(3.9, 2.5, 4.1)
					cam.look_at(cab * Vector3(0, -0.02, -0.07), cab.basis.y)
				"seat":
					cam.global_position = shell * Seat.EYE
					cam.look_at(cam.global_position + cab.basis * Vector3(0, -0.18, -1), cab.basis.y)
					cam.fov = 79
				"chase":
					cam.global_position = shell * (Seat.EYE + Seat.CAMERA_OFFSETS.chase)
					cam.look_at(cam.global_position + ahead * 10.0 + Vector3.DOWN * 1.2, Vector3.UP)
					cam.fov = 79
				"side":
					cam.global_position = cab * Vector3(9.0, 1.4, 0.2)
					cam.look_at(cab * Vector3(0, -0.1, 0.2), cab.basis.y)
				"above":
					cam.global_position = cab * Vector3(0.0, 11.0, 0.4)
					cam.look_at(cab * Vector3(0, 0, 0.4), -cab.basis.z)
				"gun":      # the starboard gun, from ahead and outboard: the Talon's wing root, the Phaethon's engine's nose
					if id == "talon":
						cam.global_position = cab * Vector3(3.0, 0.9, -3.6)
						cam.look_at(cab * Vector3(1.18, -0.14, -1.2), cab.basis.y)
					else:
						cam.global_position = engine * Vector3(1.5, 0.9, -7.2)
						cam.look_at(engine * Vector3(0.0, 0.0, -4.1), engine.basis.y)
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join(id + "-" + view + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Could not write " + path)
				quit(1)
				return
			print("TALON VIEW ", path)
		_sight_line(game, id, ahead)
		game.free()
		await process_frame
	quit()


## Scanning down from the horizon at each azimuth: the first angle at which a ray from the eye meets the craft's
## own cockpit or hull (the shell's meshes, the canopy's glass and forcefield left out), and where on the road that
## ray would have landed. The road nearer than that is hidden.
func _sight_line(game, id: String, ahead: Vector3) -> void:
	var eye: Vector3 = game.shell.global_transform * Seat.EYE
	var ground: float = game.wz(game.sim.pod.x, game.sim.pod.y, 0.0).y      # (the range's road is the sims' height 0: a pod rides 1.5 m over it)
	var meshes: Array = []
	for part: MeshInstance3D in game.shell.find_children("*", "MeshInstance3D", true, false):
		if not part.is_visible_in_tree() or part.mesh == null or game.canopy.is_ancestor_of(part):
			continue
		meshes.append([part, part.mesh.generate_triangle_mesh()])
	var line := "%s sight line (eye %.2f m over the road):" % [id, eye.y - ground]
	for az: float in AZIMUTHS:
		var across := Basis(Vector3.UP, -deg_to_rad(az)) * ahead
		var cut := -1.0
		var by := ""
		var d := 0.0
		while d <= 60.0 and cut < 0.0:
			var dir := (across * cos(deg_to_rad(d)) + Vector3.DOWN * sin(deg_to_rad(d))).normalized()
			for entry: Array in meshes:
				var part: MeshInstance3D = entry[0]
				var into := part.global_transform.affine_inverse()
				var hit: Dictionary = (entry[1] as TriangleMesh).intersect_ray(into * eye, (into.basis * dir).normalized())
				if not hit.is_empty() and (part.global_transform * Vector3(hit.position)).distance_to(eye) < 40.0:
					cut = d
					by = part.name
					break
			d += 0.1
		var reach := (eye.y - ground) / tan(deg_to_rad(cut)) if cut > 0.0 else INF
		line += "  %+.0f deg: %.1f deg down (%s), road hidden nearer than %.1f m;" % [az, cut, by, reach]
	print(line)
