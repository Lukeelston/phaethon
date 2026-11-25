## Close-up review pictures of the four pilot craft (Shrike RS, Orrery IX, Kiln Six, Vesper): the
## parts a geometry and finish pass works on, each from where it is seen. Grown from Codex's review
## capture (C:\Users\Luke\tmp\phaethon-geometry-review\capture.gd), 2026-11-23.
## Run windowed:  --xr-mode off -s res://tests/render_fleet_detail.gd -- --mute --out=ABSOLUTE_DIRECTORY
##   --crafts=orrery,kiln      only those craft (the game's --vehicle selects one craft)
##   --only=engine,seat        only those shots
##   --wire                    wireframe over the shaded picture's geometry (faceting, density)
##   --size=1600x1000          picture size
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Pilot := preload("res://sim/pilot_craft.gd")
const SHOTS := ["exterior", "engine", "nozzle", "cab", "eye", "dash", "welt", "gauge", "control", "grip",
	"seat", "sill", "floor", "roof"]
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="):
			return arg.trim_prefix(key + "=")
	return fallback


func _centre(node: Node) -> Vector3:
	var box := AABB()
	var first := true
	var meshes: Array = [node] if node is MeshInstance3D else []
	meshes.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Fleet detail pictures need a rendering display.")
		quit(1)
		return
	output = _arg("--out", "")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass a writable --out directory")
		quit(1)
		return
	var wire := "--wire" in OS.get_cmdline_user_args()
	if wire:
		RenderingServer.set_debug_generate_wireframes(true)
	var size := _arg("--size", "1600x1000").split("x")
	root.size = Vector2i(int(size[0]), int(size[1]))
	DisplayServer.window_set_size(root.size)
	Livery.pinned = true
	Livery.current = Livery.FACTORY      # (each craft as designed: "ember" is the Ember paint on these)
	Outlook.pinned = true
	Outlook.time = _arg("--review-time", "afternoon")
	Outlook.weather = _arg("--review-weather", "fair")
	Seat.track_override = _arg("--review-track", "range")
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
	var vehicles := Array(_arg("--crafts", "shrike,orrery,kiln,vesper").split(","))
	var shots := Array(_arg("--only", ",".join(SHOTS)).split(","))
	for id: String in vehicles:
		if not Pilot.ORDER.has(id):
			push_error("Unknown review craft: " + id)
			quit(1)
			return
		Seat.vehicle_override = id
		var game := Seat.new()
		root.add_child(game)
		if game.sim._overrides.vehicle != id:
			push_error("Review selected " + str(game.sim._overrides.vehicle) + " instead of " + id)
			game.free()
			quit(1)
			return
		game.set_process(false)
		for i in 12:
			game._process(1.0 / 120.0)
		for child in game.get_children():
			if child is CanvasLayer:
				child.hide()
		var cam := game.cam as Camera3D
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		cam.near = 0.01
		var shell: Transform3D = game.shell.global_transform
		var cab: Transform3D = game.canopy.global_transform
		var engine: Transform3D = game.craft.engines[1].global_transform
		var eye_at: Vector3 = shell * Seat.EYE
		for shot: String in shots:
			var target: Vector3
			var eye: Vector3
			cam.fov = 40
			match shot:
				"whole":
					target = (cab.origin + engine.origin - cab.basis.x * game.sim.P.engineGap * 0.5) * 0.5
					eye = target + cab.basis * Vector3(26, 14, -19)
					cam.fov = 33
				"rear":
					target = engine * Vector3(0, 0.1, 0.5)
					eye = engine * Vector3(6.8, 3.2, 8.7)
					cam.fov = 40
				"exterior":
					target = engine * Vector3.ZERO
					eye = engine * Vector3(8.4, 3.5, -6.5)
					cam.fov = 38
				"engine":
					target = engine * Vector3(0, 0.1, -1.6)
					eye = engine * Vector3(3.6, 1.7, -4.6)
					cam.fov = 42
				"nozzle":
					target = engine * Vector3(0, 0, 3.0)
					eye = engine * Vector3(2.9, 1.5, 6.2)
					cam.fov = 42
				"cab":
					target = cab * Vector3(0, -0.1, 0.2)
					eye = cab * Vector3(2.6, 1.1, -2.4)
					cam.fov = 44
				"cab-rear":
					target = cab * Vector3(0, -0.15, 1.2)
					eye = cab * Vector3(2.1, 0.5, 4.2)
					cam.fov = 44
				"cab-belly":
					target = cab * Vector3(0, -0.30, 1.5)
					eye = cab * Vector3(1.5, -1.1, 3.0)
					cam.fov = 50
				"eye":
					target = shell * (Seat.EYE + Vector3(0, -0.22, -1.0))
					eye = eye_at
					cam.fov = 80
				"dash":
					var binnacle := game.find_child("binnacle", true, false)
					target = _centre(binnacle) if binnacle else shell * Vector3(0, .45, -.4)
					eye = eye_at.lerp(target, 0.35) + shell.basis * Vector3(0.12, 0.02, 0)
					cam.fov = 50
				"welt":
					var rim: MeshInstance3D = game.interior.get_node("SegmentedCoaming")
					var hit := rim.mesh.generate_triangle_mesh().intersect_ray(Vector3(-.313, .595, 0), Vector3.FORWARD)
					var at: Vector3 = hit.get("position", Vector3(-.313, .595, -.5))
					target = shell * at
					eye = shell * (at + Vector3(.021, .095, .145))
					cam.fov = 38
				"gauge":
					target = game.aux_meter.to_global(Vector3(0, .001, .001))
					eye = game.aux_meter.to_global(Vector3(.054, .045, .245))
					cam.fov = 36
				"control":
					target = shell * Vector3(-.46, .18, .20)
					eye = shell * Vector3(-.18, .43, .52)
					cam.fov = 38
				"grip":
					target = shell * Vector3(-.46, .47, .20)
					eye = shell * Vector3(-.30, .58, .40)
					cam.fov = 34
				"seat":
					var seat := game.find_child("FleetSeat", true, false)
					if seat == null:
						seat = game.find_child("SeatBack", true, false)
					target = _centre(seat) if seat else shell * Vector3(0, .4, 1.0)
					eye = target + shell.basis * Vector3(0.30, 0.30, -0.75)
					cam.fov = 46
				"sill":
					target = shell * Vector3(-.72, .45, .30)
					eye = shell * Vector3(-.30, .60, .55)
					cam.fov = 44
				"floor":
					target = shell * Vector3(-.20, .15, -.10)
					eye = shell * Vector3(-.02, .52, .42)
					cam.fov = 44
				"roof":
					target = cab * Vector3(0.12, 0.47, 0.30)
					eye = eye_at + shell.basis * Vector3(0.08, -0.06, 0.20)
					cam.fov = 60
				_:
					push_error("Unknown shot " + shot)
					continue
			cam.global_position = eye
			cam.look_at(target, shell.basis.y)
			root.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if wire else Viewport.DEBUG_DRAW_DISABLED
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			var path := output.path_join(id + "-" + shot + ("-wire" if wire else "") + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Could not write " + path)
				quit(1)
				return
			print("FLEET DETAIL ", path)
			if "--measure" in OS.get_cmdline_user_args():
				var gpu: Array[float] = []
				for frame in 180:
					await RenderingServer.frame_post_draw
					if frame >= 60:
						gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				gpu.sort()
				print("CRAFT STATIC GPU ", JSON.stringify({"craft":id,"shot":shot,"width":root.size.x,"height":root.size.y,"samples":gpu.size(),"median_ms":gpu[gpu.size()/2],"p95_ms":gpu[int(gpu.size()*.95)],"draws":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)}))
		game.free()
		await process_frame
	quit()
