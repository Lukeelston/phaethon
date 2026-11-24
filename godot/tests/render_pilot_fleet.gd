## In-game exterior, engine, cab and pilot-eye views. Run with --xr-mode off
## -s res://tests/render_pilot_fleet.gd -- --mute --out=ABSOLUTE_DIRECTORY.
## Add --interiors for each custom cockpit at eye height and a closer view of its instruments.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fleet screenshots need a rendering display.")
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
	Livery.current = Livery.FACTORY      # (each craft as designed: "ember" is the Ember paint on these)
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
	var interiors := "--interiors" in OS.get_cmdline_user_args()
	var vehicles := [Pilot.SHRIKE, Pilot.ORRERY, Pilot.KILN, Pilot.VESPER, Pilot.BASILISK] if interiors else [Pilot.ORRERY, Pilot.KILN, Pilot.VESPER, Pilot.BASILISK]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vehicle="):
			var chosen := arg.trim_prefix("--vehicle=")
			if not vehicles.has(chosen):
				push_error("Unknown vehicle for this review: " + chosen)
				quit(1)
				return
			vehicles = [chosen]
	for id in vehicles:
		Seat.vehicle_override = id
		var game := Seat.new()
		root.add_child(game)
		game.set_process(false)
		for i in 12:
			game._process(1.0 / 120.0)
		for child in game.get_children():
			if child is CanvasLayer:
				child.hide()
		var cab: Transform3D = game.canopy.global_transform
		var engine: Transform3D = game.craft.engines[1].global_transform
		var middle: Vector3 = (cab.origin + engine.origin - cab.basis.x * game.sim.P.engineGap * 0.5) * 0.5
		var cam := game.cam as Camera3D
		var shots := ["flight-deck", "instruments"] if interiors else ["exterior", "engine", "cab", "seat"]
		for shot: String in shots:
			match shot:
				"exterior":
					cam.global_position = middle + cab.basis * Vector3(26, 14, -19)
					cam.look_at(middle + cab.basis * Vector3(0, 0, -1.75), cab.basis.y)
					cam.fov = 33
				"engine":
					cam.global_position = engine * Vector3(7.2, 3.6, -6.7)
					cam.look_at(engine.origin, engine.basis.y)
					cam.fov = 38
				"cab":
					cam.global_position = cab * Vector3(3.9, 2.5, 4.1)
					cam.look_at(cab * Vector3(0, -0.02, -0.07), cab.basis.y)
					cam.fov = 38
				"flight-deck", "instruments":
					var xf: Transform3D = game.shell.global_transform
					var close := shot == "instruments"
					var eye := Seat.EYE + (Vector3(.028,-.014,-.055) if close else Vector3.ZERO)
					cam.global_position = xf * eye
					cam.look_at(xf * (Vector3(.055,.365,-.32) if close else Vector3(0,.51,-.41)),xf.basis.y)
					cam.fov = 57 if close else 69
				"seat":
					cam.global_position = game.shell.global_transform * Seat.EYE
					cam.look_at(cam.global_position + cab.basis * Vector3(0, -0.18, -1), cab.basis.y)
					cam.fov = 79
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join(id + "-" + shot + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Could not write " + path)
				quit(1)
				return
			print("FLEET VIEW ", path)
		game.free()
		await process_frame
	quit()
