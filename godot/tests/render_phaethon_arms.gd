## Fixed-camera captures of the flight meshes. Run with an XR-off rendering window,
## --resolution 1440x900 -s res://tests/render_phaethon_arms.gd -- --mute --out=DIR.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless" or output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a rendering display and writable --out directory")
		quit(1)
		return
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.vehicle_override = Pilot.STANDARD
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	Livery.pinned = true
	Livery.current = "ember"
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for frame in 12:
		game._process(1.0 / 120.0)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var arms = game.craft.phaethon_arms()
	if arms == null:
		push_error("The production cockpit has no Phaethon engine mounts")
		quit(1)
		return
	var cam := game.cam as Camera3D
	var port: Transform3D = game.craft.engines[0].global_transform
	var starboard: Transform3D = game.craft.engines[1].global_transform
	var middle := Transform3D(port.basis, (port.origin + starboard.origin) * 0.5)
	var seat: Transform3D = game.rig.global_transform
	for shot in ["outside", "seat", "intake"]:
		for state: String in ["stowed", "deployed"]:
			arms.set_deploy(1.0 if state == "deployed" else 0.0)
			arms.heat = 0.65 if state == "deployed" else 0.0
			if shot == "outside":
				cam.global_position = middle * Vector3(3.7, 3.45, -12)
				cam.look_at(middle * Vector3(0.0, 0.1, -2.5), middle.basis.y)
				cam.fov = 43.0
			elif shot == "intake":
				cam.global_position = port * Vector3(-1.18, 0.85, -6.32)
				cam.look_at(port * Vector3(0, 0.17, -3.88), port.basis.y)
				cam.fov = 39.0
			else:
				cam.global_position = seat * Seat.EYE
				cam.look_at(cam.global_position + seat.basis * Vector3(0.0, -0.07, -1.0), seat.basis.y)
				cam.fov = 85.0
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join("phaethon-%s-%s.png" % [shot, state])
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Could not save " + path)
				quit(1)
				return
	game.free()
	await process_frame
	quit()
