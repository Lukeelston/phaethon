## The bay doors (garage/bay_doors.gd) as a pilot sees them, from the walker's own eye: seated in the Phaethon's bay
## (the west wall, the low sun's side) and the Shrike's opposite (the east wall, in the hall's shadow), the door shut,
## half up and open, after the one-touch start; then on foot at the gate, the door open, and looking back up the aisle.
##   door-<craft>-shut  door-<craft>-half  door-<craft>-open  door-<craft>-gate  door-aisle-open
## Needs a window: --xr-mode off --resolution 1600x900 --audio-driver Dummy
##   -s res://tests/render_bay_door.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const GARAGE := "res://garage/garage.tscn"
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Door pictures need a rendering display.")
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
	Settings.prefs_path = "user://render-bay-door-%d.cfg" % OS.get_process_id()
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
	print("BAY DOOR RENDER %s" % ("done" if ok else "FAILED: no garage"))
	quit(0 if ok else 1)


func _pictures(garage) -> void:
	var walker = garage.walker
	var hall = garage.environment
	var doors = hall.doors
	walker.set_physics_process(false)
	await _wait(1.5)
	for id: String in ["phaethon", "shrike"]:
		walker.set_seated(false, hall.boarding_transform(id))
		garage.interact()
		var until := Time.get_ticks_msec() + 10000
		while garage.seated_craft != id and Time.get_ticks_msec() < until:
			await process_frame
		walker.camera.rotation = Vector3(deg_to_rad(-2.0), 0.0, 0.0)
		await _settle()
		await _save("door-%s-shut" % id)
		walker.cockpit_control_requested.emit("power")
		until = Time.get_ticks_msec() + 12000
		while doors.fraction(id) < .5 and Time.get_ticks_msec() < until:
			await process_frame
		await _save("door-%s-half" % id)
		while not doors.is_open(id) and Time.get_ticks_msec() < until:
			await process_frame
		await _settle()
		await _save("door-%s-open" % id)
		# On foot at the gate, the engines left running: the door is open until the pilot is out, then comes down.
		var gate: Transform3D = hall.boarding_transform(id)
		var door: Vector3 = hall.door_transform(id).origin
		walker.set_physics_process(false)
		garage.leave_seat()
		walker.set_seated(false, gate)
		walker.look_at(Vector3(door.x, walker.global_position.y, door.z))
		walker.camera.rotation = Vector3(deg_to_rad(4.0), 0.0, 0.0)
		await _wait(.2)
		await _save("door-%s-gate" % id)
		while doors.phase(id) != "shut" and Time.get_ticks_msec() < until + 8000:
			await process_frame
	# Up the aisle from the entrance end, the Phaethon's door up again.
	walker.set_seated(false, hall.boarding_transform("phaethon"))
	garage.interact()
	var until := Time.get_ticks_msec() + 10000
	while not doors.is_open("phaethon") and Time.get_ticks_msec() < until:
		await process_frame
	walker.camera.rotation = Vector3(deg_to_rad(-2.0), 0.0, 0.0)
	await _settle()
	await _save("door-phaethon-reboarded")
	garage.leave_seat()
	walker.set_seated(false, Transform3D(Basis(Vector3.UP, deg_to_rad(62.0)), Vector3(4.0, 0.0, 19.0)))
	walker.camera.rotation = Vector3(deg_to_rad(2.0), 0.0, 0.0)
	await _wait(.1)
	await _save("door-aisle-open")


func _settle() -> void:
	await _wait(0.6)


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	print("BAY DOOR VIEW %s" % path)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
