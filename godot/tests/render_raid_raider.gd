## Reproduce the ground-raider review directly on a Network deck.
## --resolution 1280x720 --xr-mode off --audio-driver Dummy --fixed-fps 120
## -s res://tests/render_raid_raider.gd -- --mute --out=DIR
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
const Outlook := preload("res://view/outlook.gd")

func _initialize() -> void:
	review.call_deferred()


func review() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(1)
		return
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = output.path_join("review_")
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	var view := View.new()
	root.add_child(view)
	view.set_process(false)
	for child in view.get_children():
		if child is CanvasLayer:
			child.hide()
	var road := 2 # E3, with open approaches in both directions.
	var station := 9000
	view.sim.respawn_on(road, station - 16, 1)
	view._process(1.0 / 120.0)
	for i in 1600:
		view.network_world.sync(view.sim.pod.x, view.sim.pod.y)
		view.landscape.sync(view.sim.pod.x, view.sim.pod.y)
		if i % 40 == 0:
			await process_frame
	var traffic: Traffic = view.traffic_net
	traffic.cars.clear()
	traffic._warm = 0
	var raider := Traffic.Car.new()
	raider.kind = Traffic.DEMON
	raider.road = road
	raider.dir = 1
	raider.f = float(station)
	raider.lat = 22.5
	traffic._place(raider)
	traffic.set_raider_visual(raider)
	traffic.cars.append(raider)
	var target := Vector3(raider.x - view.org_x, view.sim.net_height(road, raider.f) + 3.7,
			view.org_y - raider.y)
	var fwd := Vector3(raider.hx, 0.0, -raider.hy)
	var across := fwd.cross(Vector3.UP)
	for shot in [["front", 36.0, 24.0, 4.6, 26.0], ["rear", -35.0, -24.0, 5.8, 26.0],
			["approach", 175.0, 12.0, 4.5, 30.0]]:
		view.cam.fov = shot[4]
		view.cam.global_position = target + fwd * float(shot[1]) + across * float(shot[2]) + Vector3.UP * float(shot[3])
		view.cam.look_at(target, Vector3.UP)
		traffic._render()
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := output.path_join("raider-%s.png" % shot[0])
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("Could not save " + path)
			quit(1)
			return
		print("RAIDER ROAD SHOT ", path)
	view.free()
	quit()
