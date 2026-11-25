## Codex's pilot garage as a pilot sees it, from the walker's own eye (garage/garage_walker.gd's camera), after its merge
## onto Raids stage 1 and push 45 (each bay in its own saved paint; six bays, none for the Talon):
##   garage-entrance       on foot at the public entrance, looking down the hall
##   garage-aisle          on foot in the aisle at the first row, looking along the bays
##   garage-vesper         at the Vesper's boarding gate (its paint pinned to Star Command)
##   garage-kiln           at the Kiln's boarding gate (its paint pinned to cobalt)
##   garage-basilisk       at the Basilisk's boarding gate (Factory; its hull rebuilt in the merge from both sides' tool)
##   garage-seat-<craft>   boarded, from the seat, looking ahead: phaethon, vesper, basilisk, kiln
##   garage-seat-basilisk-gun   boarded in the Basilisk, the head turned to its GUN switch on the starboard sill
## The paints are set in a profile of this run's own (game_settings.gd prefs_path), and nothing is written to the pilot's.
## Needs a window: --xr-mode off --resolution 1600x900 --audio-driver Dummy
##   -s res://tests/render_garage.gd -- --mute --out=ABSOLUTE_DIRECTORY
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Settings := preload("res://release/game_settings.gd")
const Livery := preload("res://view/livery.gd")
const Route := preload("res://release/garage_route.gd")
const GARAGE := "res://garage/garage.tscn"
const PAINTS := {"vesper": "star_command", "kiln": "cobalt"}
var output := ""


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
	Settings.prefs_path = "user://render-garage-%d.cfg" % OS.get_process_id()
	for id: String in PAINTS:
		Settings.set_choice(Livery.key_for(id), PAINTS[id])
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
	print("GARAGE RENDER %s" % ("done" if ok else "FAILED: no garage"))
	quit(0 if ok else 1)


func _pictures(garage) -> void:
	var walker = garage.walker
	var hall = garage.environment
	walker.set_physics_process(false)
	walker.set_process(false)
	await _wait(1.5)
	walker.set_seated(false, hall.spawn_transform())
	await _settle()
	await _save("garage-entrance")
	var first: Transform3D = hall.boarding_transform("phaethon")
	walker.set_seated(false, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, first.origin.z + 3.0)))
	walker.camera.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
	await _settle()
	await _save("garage-aisle")
	for id: String in ["vesper", "kiln", "basilisk"]:
		walker.set_seated(false, hall.boarding_transform(id))
		walker.camera.rotation = Vector3(deg_to_rad(-12.0), 0.0, 0.0)
		await _settle()
		await _save("garage-" + id)
	for id: String in ["phaethon", "vesper", "basilisk", "kiln"]:
		walker.set_seated(false, hall.boarding_transform(id))
		garage.interact()
		var until := Time.get_ticks_msec() + 10000
		while garage.seated_craft != id and Time.get_ticks_msec() < until:
			await process_frame
		walker.camera.rotation = Vector3(deg_to_rad(-10.0), 0.0, 0.0)
		await _settle()
		await _save("garage-seat-" + id)
		if id == "basilisk":
			var gun: Node3D = garage.environment.bay_node(id).find_child("GunSwitch", true, false)
			if gun:
				walker.camera.look_at(gun.global_position, Vector3.UP)
				await _settle()
				await _save("garage-seat-basilisk-gun")
		garage.leave_seat()
		await _settle()


func _settle() -> void:
	await _wait(0.6)


func _save(shot: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(shot + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not write " + path)
	print("GARAGE VIEW %s" % path)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
