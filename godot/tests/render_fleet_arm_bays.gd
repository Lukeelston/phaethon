## Capture the real VR cockpit rig, once from outside and once at its fixed seat eye.
## --resolution 1280x800 -s res://tests/render_fleet_arm_bays.gd -- --out=PATH --vehicle=orrery
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Livery := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const Shrike := preload("res://view/shrike_airframe.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var output := ""
	var id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		if arg.begins_with("--vehicle="):
			id = arg.trim_prefix("--vehicle=")
	if output.is_empty() or not id in ["shrike","orrery","kiln","vesper"] or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Pass --out=directory and --vehicle=shrike, orrery, kiln or vesper")
		quit(1)
		return
	Livery.pinned = true
	Livery.current = Livery.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat.vehicle_override = id
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	root.msaa_3d = Viewport.MSAA_2X
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for i in 12:
		game._process(1.0/120.0)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var cam: Camera3D = game.cam
	var seat_frame := cam.global_transform
	var seat_fov := cam.fov
	var seat_near := cam.near
	var hull: MeshInstance3D = game.shell.get_node("PodHull")
	var craft_frame := hull.global_transform
	var arms = Shrike.ensure_arms(hull) if id == "shrike" else game.craft.fleet.ensure_arms()
	var views := ["exterior", "seat"]
	if id == "vesper":
		views.append("exterior-wide")
	for view: String in views:
		cam.near = seat_near if view == "seat" else .018
		if view == "seat":
			cam.global_transform = seat_frame
			cam.fov = seat_fov
		elif view == "exterior-wide":
			cam.global_position = craft_frame * Vector3(4.8,2.5,-4.8)
			cam.look_at(craft_frame * Vector3.ZERO, craft_frame.basis.y)
			cam.fov = 50
		else:
			var eye: Vector3 = {"shrike":Vector3(3.9,1.8,-3.1),"orrery":Vector3(1.30,1.60,-4.57),"kiln":Vector3(2.7,1.72,-3.7),"vesper":Vector3(2.9,1.7,-2.6)}[id]
			var target: Vector3 = {"shrike":Vector3(0,.16,-.73),"orrery":Vector3(0,.26,-1.40),"kiln":Vector3(.36,.13,-1.32),"vesper":Vector3(.88,.11,-.87)}[id]
			cam.global_position = craft_frame * eye
			cam.look_at(craft_frame * target,craft_frame.basis.y)
			cam.fov = 40 if id == "orrery" else 42
		for state: String in ["stowed","deployed"]:
			if view == "exterior-wide" and state == "stowed":
				continue
			arms.set_deploy(1.0 if state == "deployed" else 0.0)
			arms.heat = .72 if state == "deployed" else 0.0
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var file := output.path_join(id + "-" + view + "-" + state + ".png")
			if root.get_texture().get_image().save_png(file) != OK:
				push_error("Could not write " + file)
				quit(1)
				return
			print("Fleet bay view ",file)
	game.free()
	quit()
