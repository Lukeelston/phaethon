## The Phaethon's bay with either body standing in it (the Talon is a Phaethon in another body: sim/pilot_craft.gd
## bay_of), seen from both sides at the stands' height, so the shoes under the pod and the engine stands can be read
## against each body; and the headset's sign at that bay (garage_prompts.gd's placard, built as in the headset):
##   bay-talon-port, bay-talon-starboard           the Talon on the Phaethon's stands, from either side, low
##   bay-talon-port-high, bay-talon-starboard-high ... from higher, the whole craft
##   bay-phaethon-port, bay-phaethon-starboard     the same two low views with the Phaethon (swapped back)
##   bay-sign                                      the sign at the Phaethon's bay: board, menu, paint and body lines
## Prints each body's pod bounds and the bay's gate (BODIES ...). Its own settings file; the pilot's is left alone.
## Needs a window: --xr-mode off --resolution 1600x900 --audio-driver Dummy
##   -s res://tests/render_garage_bodies.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const Prompts := preload("res://garage/garage_prompts.gd")
const GARAGE := "res://garage/garage.tscn"
var output := ""
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Garage pictures need a rendering display.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if output.is_empty() or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("--out=ABSOLUTE_DIRECTORY")
		quit(1)
		return
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://render-garage-bodies-%d.cfg" % OS.get_process_id()
	Settings.set_phaethon_body("talon")
	Route.enter(self, false, "network")
	var until := Time.get_ticks_msec() + 20000
	while (current_scene == null or current_scene.scene_file_path != GARAGE) and Time.get_ticks_msec() < until:
		await process_frame
	var ok := current_scene != null and current_scene.scene_file_path == GARAGE
	if ok:
		await _pictures(current_scene)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("BODIES RENDER %s" % ("done" if ok else "FAILED: no garage"))
	quit(0 if ok else 1)


func _pictures(garage) -> void:
	var walker = garage.walker
	var hall = garage.environment
	walker.set_physics_process(false)
	walker.set_process(false)
	walker.set_seated(false, hall.spawn_transform())
	_camera = Camera3D.new()
	_camera.fov = 55.0
	root.add_child(_camera)
	_camera.make_current()
	await _wait(1.5)
	var bay: Node3D = hall.bay_node("phaethon")
	print("BODIES the Talon in the Phaethon's bay at the hall's build: pod %s, gate %s" % [_pod(bay), hall.boarding_transform("phaethon").origin])
	for side in [["port", -1.0], ["starboard", 1.0]]:
		await _look(bay, Vector3(side[1] * 2.1, -0.42, 0.05), Vector3(0.0, -0.10, 0.05), "bay-talon-" + side[0])
		await _look(bay, Vector3(side[1] * 4.6, 1.30, 2.6), Vector3(0.0, 0.0, -1.0), "bay-talon-" + side[0] + "-high")
	await _sign(garage, hall)
	# from the bay's gate, at a standing pilot's eye: toward the seat, and aft along the near wing
	var gate: Vector3 = bay.to_local(hall.boarding_transform("phaethon").origin)
	await _look(bay, gate + Vector3.UP * 1.62, Vector3(0.0, 0.0, 0.54), "bay-talon-gate")
	await _look(bay, gate + Vector3.UP * 1.62, Vector3(signf(gate.x) * 2.2, -0.2, 1.6), "bay-talon-gate-wing")
	walker.set_seated(false, hall.boarding_transform("phaethon"))
	garage._work_bay("body")
	await _wait(0.5)
	print("BODIES the Phaethon swapped in: pod %s, gate %s (stands in %s)" % [_pod(bay), hall.boarding_transform("phaethon").origin, hall.bay_craft("phaethon")])
	walker.set_seated(false, hall.spawn_transform())
	for side in [["port", -1.0], ["starboard", 1.0]]:
		await _look(bay, Vector3(side[1] * 2.1, -0.42, 0.05), Vector3(0.0, -0.10, 0.05), "bay-phaethon-" + side[0])


func _pod(bay: Node3D) -> String:
	var bounds: AABB = bay.model.pod.transform * bay.model.pod.mesh.get_aabb()
	# its reach out to the side, a metre-long band at a time along it (the seat's band holds the gate's line)
	var reach := {}
	var mesh: Mesh = bay.model.pod.mesh
	for s in mesh.get_surface_count():
		var points: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in points:
			var at: Vector3 = bay.model.pod.transform * p
			var band := floori(at.z)
			reach[band] = maxf(float(reach.get(band, 0.0)), absf(at.x))
	var bands := reach.keys()
	bands.sort()
	var said := []
	for band in bands:
		said.append("z %d..%d: %.2f" % [band, band + 1, reach[band]])
	var surfaces := []
	for s in mesh.get_surface_count():
		var widest := 0.0
		for p in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			widest = maxf(widest, absf(p.x))
		surfaces.append("%d %s %.2f" % [s, mesh.surface_get_name(s), widest])
	return "%s (%.2f m across; out to the side by band: %s; by surface: %s)" % [bounds, bounds.size.x, ", ".join(said), ", ".join(surfaces)]


## The camera at `from`, looking at `at`, both in the bay's own frame.
func _look(bay: Node3D, from: Vector3, at: Vector3, shot: String) -> void:
	_camera.global_position = bay.global_transform * from
	_camera.look_at(bay.global_transform * at, Vector3.UP)
	await _wait(0.6)
	await _save(shot)


## The headset's sign, built as the headset builds it, hung where it hangs at the Phaethon's bay, read face on.
func _sign(garage, hall) -> void:
	var card = Prompts.new()
	garage.add_child(card)
	card.setup(true)
	var eye: Vector3 = hall.boarding_transform("phaethon").origin + Vector3.UP * 1.6
	var mount: Transform3D = hall.marker_guide("phaethon", eye)
	card.show_controls("Phaethon Talon", false, "The Network", false, mount, "Factory", "", "Phaethon Talon")
	_camera.global_position = mount * Vector3(0.0, -0.05, 0.75)
	_camera.look_at(mount * Vector3(0.0, -0.05, 0.0), Vector3.UP)
	await _wait(0.6)
	await _save("bay-sign")
	card.queue_free()


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	print("BODIES VIEW %s" % path)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
