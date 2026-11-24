## Game's actual Talon hull and cockpit. --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Talon := preload("res://view/talon_airframe.gd")
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if DisplayServer.get_name() == "headless" or output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Use a rendering display and pass --out=ABSOLUTE_DIRECTORY")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.vehicle_override = "talon"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for i in 12:
		game._process(1.0 / 120)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var hull := game.shell.get_node("PodHull") as MeshInstance3D
	var guns := Talon.wing_arms(hull)
	var cam := game.cam as Camera3D
	var cab := hull.global_transform
	for state in ["stowed", "deployed"]:
		guns.set_deploy(0.0 if state == "stowed" else 1.0)
		guns.heat = 0.0 if state == "stowed" else 0.65
		for view in ["exterior", "seat"]:
			if view == "exterior":
				cam.global_position = cab * Vector3(3.25, 2.75, -6.20)
				cam.look_at(cab * Vector3(0.0, -0.15, -0.05), cab.basis.y)
				cam.fov = 36
			else:
				var rig: Transform3D = game.rig.global_transform
				cam.global_position = rig * Seat.EYE
				cam.look_at(cam.global_position + rig.basis * Vector3(0, -0.12, -1), rig.basis.y)
				cam.fov = 85
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join("talon-%s-%s.png" % [view, state])
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Unable to write " + path)
				quit(1)
				return
			print("TALON VIEW ", path)
	game.free()
	quit()
