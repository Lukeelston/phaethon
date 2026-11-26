## Each bay's cockpit from outside, close: its roof and glass bounds (pod-local), the hull's reach and top at the seat,
## the gate. Prints CANOPY lines; with --out= also saves a three-quarter and a side picture of each cockpit.
## Needs a window for pictures: --xr-mode off --resolution 1280x800 --audio-driver Dummy
##   -s res://tests/probe_canopy_geometry.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const Fleet := preload("res://sim/pilot_craft.gd")
const GARAGE := "res://garage/garage.tscn"
var output := ""
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://probe-canopy-%d.cfg" % OS.get_process_id()
	var talon := OS.get_cmdline_user_args().has("--talon")
	Settings.set_phaethon_body("talon" if talon else "phaethon")
	Route.enter(self, false, "network")
	var until := Time.get_ticks_msec() + 20000
	while (current_scene == null or current_scene.scene_file_path != GARAGE) and Time.get_ticks_msec() < until:
		await process_frame
	var garage = current_scene
	garage.walker.set_physics_process(false)
	garage.walker.set_process(false)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	root.add_child(_camera)
	_camera.make_current()
	await _wait(1.0)
	for id: String in Fleet.GARAGE_BAYS:
		var hall = garage.environment
		var bay: Node3D = hall.bay_node(id)
		var pod: MeshInstance3D = bay.model.pod
		var canopy: Node3D = bay.model.canopy
		var craft: String = hall.bay_craft(id)
		var parts := []
		for node: Node in canopy.get_children():
			if node is MeshInstance3D and node.visible and node.mesh:
				var box: AABB = canopy.transform * node.transform * node.mesh.get_aabb()
				parts.append("%s %s..%s" % [node.name, _v(box.position), _v(box.end)])
		var hull: AABB = pod.mesh.get_aabb()
		var gate: Vector3 = bay.to_local(hall.boarding_transform(id).origin)
		var seat: Vector3 = bay.to_local(hall.seat_transform(id).origin)
		print("CANOPY %s (%s) pod.transform %s hull %s..%s | %s | gate(bay) %s seat-eye(bay) %s top@seat %.3f" % [id, craft,
				_v(pod.transform.origin), _v(hull.position), _v(hull.end), "; ".join(parts), _v(gate), _v(seat), _top_at(pod, 0.54 - pod.transform.origin.z)])
		# the hull's section at the seat, gate side: the top of the skin in each 10 cm band out from the centreline
		var section := []
		var side_sign := signf(gate.x)
		for band in 32:
			var top := -INF
			for s in pod.mesh.get_surface_count():
				for p: Vector3 in pod.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var at: Vector3 = pod.transform * p
					if absf(at.z - 0.54) < 0.18 and at.x * side_sign >= band * 0.1 and at.x * side_sign < band * 0.1 + 0.1:
						top = maxf(top, at.y)
			if top > -INF:
				section.append("%.1f:%.2f" % [band * 0.1, top])
		print("SECTION %s %s" % [craft, " ".join(section)])
		# the same, lengthwise along the gate-side sill (x 0.5..0.9 out): its top every 20 cm from nose to tail
		var length := []
		for band in range(-14, 14):
			var top := -INF
			for s in pod.mesh.get_surface_count():
				for p: Vector3 in pod.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					var at: Vector3 = pod.transform * p
					if at.x * side_sign > 0.45 and at.x * side_sign < 1.0 and at.z >= band * 0.2 and at.z < band * 0.2 + 0.2:
						top = maxf(top, at.y)
			if top > -INF:
				length.append("%.1f:%.2f" % [band * 0.2, top])
		print("SILL %s %s" % [craft, " ".join(length)])
		if not output.is_empty() and DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(output)
			var side := signf(gate.x)
			await _look(bay, Vector3(side * 3.2, 1.9, 2.4), Vector3(0, 0.4, 0.1), "%s-%s-34" % [id, craft])
			await _look(bay, Vector3(side * 4.2, 0.55, 0.3), Vector3(0, 0.45, 0.3), "%s-%s-side" % [id, craft])
			await _look(bay, Vector3(side * 0.6, 3.6, 2.6), Vector3(0, 0.35, 0.0), "%s-%s-top" % [id, craft])
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("CANOPY PROBE done")
	quit(0)


## The hull's highest vertex within 12 cm of a pod-local z, its height in the bay's frame.
func _top_at(pod: MeshInstance3D, z: float) -> float:
	var best := -INF
	for s in pod.mesh.get_surface_count():
		for p: Vector3 in pod.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if absf(p.z - z) < 0.12 and absf(p.x) > 0.45:
				best = maxf(best, (pod.transform * p).y)
	return best


func _v(p: Vector3) -> String:
	return "(%.2f %.2f %.2f)" % [p.x, p.y, p.z]


func _look(bay: Node3D, from: Vector3, at: Vector3, label: String) -> void:
	_camera.global_position = bay.to_global(from)
	_camera.look_at(bay.to_global(at), Vector3.UP)
	await _wait(0.4)
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(label + ".png"))


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
