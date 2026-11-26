## Film the climbs in and out of parked craft (garage/boarding.gd), stepped at 30 frames a second, from outside on the
## gate's side (and with --eye, through the pilot's own helmet as the desktop plays it). Frames are saved as
## <craft>-in-out/0001.png ... under --out; tools join them into clips.
## Needs a window: --xr-mode off --resolution 1280x720 --audio-driver Dummy
##   -s res://tests/render_climbs.gd -- --mute --out=ABSOLUTE_DIRECTORY [--craft=kiln] [--talon] [--eye] [--fps=30]
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const GARAGE := "res://garage/garage.tscn"
var output := ""
var only := ""
var eye_view := false
var fps := 30.0
var _camera: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var talon := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--craft="):
			only = arg.trim_prefix("--craft=")
		elif arg.begins_with("--fps="):
			fps = float(arg.trim_prefix("--fps="))
		elif arg == "--eye":
			eye_view = true
		elif arg == "--talon":
			talon = true
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://render-climbs-%d.cfg" % OS.get_process_id()
	Settings.set_phaethon_body("talon" if talon else "phaethon")
	Route.enter(self, false, "network")
	var until := Time.get_ticks_msec() + 30000
	while (current_scene == null or current_scene.scene_file_path != GARAGE) and Time.get_ticks_msec() < until:
		await process_frame
	var garage = current_scene
	for tick in 20:
		await process_frame
	_camera = Camera3D.new()
	_camera.fov = 52.0
	_camera.near = 0.05
	root.add_child(_camera)
	for id: String in Pilot.GARAGE_BAYS:
		var craft: String = garage.environment.bay_craft(id)
		if not only.is_empty() and craft != only:
			continue
		await _film(garage, id, craft)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("CLIMB FILM done")
	quit(0)


func _film(garage, id: String, craft: String) -> void:
	var hall = garage.environment
	var bay: Node3D = hall.bay_node(id)
	var gate: Transform3D = hall.boarding_transform(id)
	var side := signf((bay.global_transform.affine_inverse() * gate.origin).x)
	garage.walker.set_seated(false, Transform3D(gate.basis, gate.origin + gate.basis.z * 0.9))
	for tick in 4:
		await process_frame
	for leg in ["in", "out"]:
		var folder := output.path_join("%s-%s%s" % [craft, leg, "-eye" if eye_view else ""])
		DirAccess.make_dir_recursive_absolute(folder)
		garage._board_button()
		var climb = garage._climb
		climb.set_process(false)      # (stepped here, frame by frame, not by the clock)
		var frame := 0
		var t := 0.0
		while is_instance_valid(climb) and garage._climb == climb and t < 20.0:
			if not eye_view:
				var watch: Vector3 = bay.global_transform * Vector3(4.1 * side, 1.75, 3.5)
				var look: Vector3 = bay.global_transform * Vector3(0.85 * side, 0.30, 0.55)
				_camera.global_transform = Transform3D(Basis.looking_at(look - watch, Vector3.UP), watch)
				_camera.make_current()
			await process_frame
			await process_frame
			frame += 1
			root.get_texture().get_image().save_png(folder.path_join("%04d.png" % frame))
			climb.advance(1.0 / fps)
			t += 1.0 / fps
		# a beat of stillness at the end
		for hold in int(fps * 0.4):
			await process_frame
			frame += 1
			root.get_texture().get_image().save_png(folder.path_join("%04d.png" % frame))
		print("CLIMB FILM %s %s: %d frames" % [craft, leg, frame])
