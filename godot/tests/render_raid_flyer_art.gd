## Road-level portraits on the actual Network just outside Eridanus.
## Godot --path godot --xr-mode off --resolution 1440x900 --audio-driver Dummy
## -s res://tests/render_raid_flyer_art.gd -- --mute --out=DIR
extends SceneTree

const Art := preload("res://view/raid_flyer_art.gd")
const View := preload("res://view/craft_view.gd")
var out_dir := ""
var camera: Camera3D
var frame: Transform3D

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("A writable --out= directory is required.")
		quit(1)
		return
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = out_dir.path_join("review_")
	preload("res://view/outlook.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var view := View.new()
	root.add_child(view)
	view.set_process(false)
	view.cruise = 0.0
	var city: Dictionary = view.sim.cities[0]
	var road: int = city.road
	var sample_index: int = city.i + 153
	view.sim.respawn_on(road, sample_index, 1)
	for i in 1350:
		view.network_world.sync(view.sim.pod.x, view.sim.pod.y)
		view.landscape.sync(view.sim.pod.x, view.sim.pod.y)
		if i % 100 == 0:
			await process_frame
	for i in 24:
		view._process(1.0 / 120.0)
		await process_frame
	view.craft.hide()
	view.hud.get_parent().hide()
	# Use the road tangent the game uses, facing the nearby towers.
	var path = view.sim.roads[road]
	var tangent := Vector2(path.tx[sample_index], path.ty[sample_index])
	var toward_city := Vector2(city.cx - path.px[sample_index], city.cy - path.py[sample_index])
	if toward_city.dot(tangent) < 0.0:
		tangent = -tangent
	frame = Transform3D(Basis.looking_at(Vector3(tangent.x, 0, -tangent.y), Vector3.UP),
			view.wz(path.px[sample_index], path.py[sample_index], view.sim.net_height(road, sample_index)))
	camera = Camera3D.new()
	root.add_child(camera)
	camera.far = view.cam.far
	camera.current = true

	var swarm := Art.drone_batch(3)
	root.add_child(swarm)
	swarm.transform = frame
	swarm.multimesh.set_instance_transform(0, Transform3D(Basis.from_euler(Vector3(-0.22, 2.71, -0.19)), Vector3(0, 3.45, -10.8)))
	swarm.multimesh.set_instance_transform(1, Transform3D(Basis.from_euler(Vector3(0.23, 2.38, 0.45)), Vector3(11.5, 9.5, -40)))
	swarm.multimesh.set_instance_transform(2, Transform3D(Basis.from_euler(Vector3(-0.08, -2.65, -0.33)), Vector3(-9.8, 13, -38)))
	swarm.multimesh.visible_instance_count = 3
	await shot("drone-road", Vector3(-0.4, 1.85, 0), Vector3(0, 2.74, -10.8), 32.0)
	swarm.hide()

	var ship := Art.gunship()
	root.add_child(ship)
	ship.transform = frame * Transform3D(Basis.from_euler(Vector3(-0.06, 2.48, -0.05)), Vector3(0, 7.85, -30))
	ship.get_node("TurretPivot").rotation.y = deg_to_rad(25)
	ship.get_node("TurretPivot/Cradle").rotation.x = deg_to_rad(-12)
	await shot("gunship-turret", Vector3(-0.5, 1.85, 0), Vector3(0, 6.7, -30), 32.0)
	ship.transform = frame * Transform3D(Basis.from_euler(Vector3(-0.15, 2.36, 0.35)), Vector3(0, 5.9, -31))
	await shot("gunship-road", Vector3(-0.5, 1.85, 0), Vector3(0, 4.9, -31), 30.0)
	ship.transform = frame * Transform3D(Basis.from_euler(Vector3(0.03, 0.65, 0.05)), Vector3(0, 8.20, -30))
	await shot("gunship-stern", Vector3(-0.5, 1.85, 0), Vector3(0, 7.0, -30), 32.0)
	quit()

func shot(label: String, eye: Vector3, target: Vector3, fov: float) -> void:
	camera.position = frame * eye
	camera.look_at(frame * target)
	camera.fov = fov
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(label + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)
	print("RAID ART SHOT ", path)
