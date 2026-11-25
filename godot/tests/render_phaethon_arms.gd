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
	var arms = game.craft.arms      # (built with the craft, view/craft_model.gd: hidden until first brought out)
	if arms == null:
		push_error("The production cockpit has no Phaethon engine mounts")
		quit(1)
		return
	var cam := game.cam as Camera3D
	var port: Transform3D = game.craft.engines[0].global_transform
	var starboard: Transform3D = game.craft.engines[1].global_transform
	var middle := Transform3D(port.basis, (port.origin + starboard.origin) * 0.5)
	var seat := cam.global_transform
	var flight_fov := cam.fov
	var previous: Image
	var previous_state := ""
	var seat_frames := {}
	for shot in ["outside", "seat", "intake"]:
		var states := {"stowed": 0.0, "quarter": 0.25, "half": 0.5, "three-quarter": 0.75, "deployed": 1.0} if shot == "seat" else {"stowed": 0.0, "deployed": 1.0}
		if shot == "seat":
			states.merge({"return-three-quarter": 0.75, "return-half": 0.5, "return-quarter": 0.25, "restowed": 0.0})
		for state: String in states:
			arms.set_deploy(states[state])
			arms.heat = 0.0
			if shot == "outside":
				cam.global_position = middle * Vector3(3.7, 3.45, -12)
				cam.look_at(middle * Vector3(0.0, 0.1, -2.5), middle.basis.y)
				cam.fov = 43.0
			elif shot == "intake":
				cam.global_position = port * Vector3(-2.15, 2.17, -7.15)
				cam.look_at(port * Vector3(0, 1.00, -3.24), port.basis.y)
				cam.fov = 48.0
			else:
				cam.global_transform = seat
				cam.fov = flight_fov
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := output.path_join("phaethon-%s-%s.png" % [shot, state])
			var picture := root.get_texture().get_image()
			if shot == "seat":
				var reversing := state.begins_with("return-") or state == "restowed"
				var area_scale := picture.get_height() / 810.0
				for engine: Node3D in game.craft.engines:
					var viewport_scale := Vector2(picture.get_size()) / cam.get_viewport().get_visible_rect().size
					var center := Vector2i(cam.unproject_position(engine.to_global(Vector3(0.0, 1.1, -2.5))) * viewport_scale)
					var half_size := Vector2i(Vector2(32, 36) * area_scale)
					var region := Rect2i(center - half_size, 2 * half_size).intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
					var minimum := maxi(2, roundi(24 * area_scale * area_scale))
					var changed := _changed_pixels(previous, picture, region) if previous else minimum
					if changed < minimum:
						push_error("Only %d visibly changed pixels in %s: %s to %s" % [changed, region, previous_state, state])
						quit(1)
						return
					if reversing and _changed_pixels(seat_frames[states[state]], picture, region) >= minimum:
						push_error("Retracting gun diverged from the matching arming pose: " + state)
						quit(1)
						return
				if not reversing:
					seat_frames[states[state]] = picture
				previous = picture
				previous_state = state
			if picture.save_png(path) != OK:
				push_error("Could not save " + path)
				quit(1)
				return
	game.free()
	await process_frame
	quit()


## Count distinctly changed RGB pixels in a single nacelle's projection. Heat, eye, FOV
## and scenery stay fixed, so a mechanism hidden behind either intake fails this check.
func _changed_pixels(first: Image, second: Image, region: Rect2i) -> int:
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var delta := first.get_pixel(x, y) - second.get_pixel(x, y)
			if maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) > 0.07:
				changed += 1
	return changed
