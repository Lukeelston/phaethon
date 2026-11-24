## A film of the headset menu's turntable (release/title_stage.gd, release/vr_menu.gd), from the pilot's
## standing eye looking ahead: the board in front; the pilot craft row highlighted, the board swinging
## aside and the turntable coming up with the chosen craft; two craft chosen in turn; the highlight moved
## on, the board back and the turntable put away. The menu is driven as the controller would drive it.
## Frames as JPEGs to stitch: run windowed, a frame a step:
## --xr-mode off --resolution 1280x720 --fixed-fps 30 --audio-driver Dummy -s res://tests/film_title_turntable.gd -- --mute --out=DIR
## Nothing here is a headset's picture: no stereo, no lens. It chooses craft as the row does, so it saves
## the pilot craft in the profile it runs under: run it under a scratch profile, not a pilot's.
extends SceneTree

const UI := preload("res://release/release_config.gd")
const FPS := 30.0

var out_dir := ""
var frame := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	change_scene_to_file(UI.VR_MENU_SCENE)
	await scene_changed
	var menu = current_scene
	menu.set_process(false)      # (no headset: this script is its controller)
	var stage = menu.stage
	var deadline := Time.get_ticks_msec() + 15000
	while not stage.art_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	var cam: Camera3D = menu.camera
	cam.rotation_degrees = Vector3(-7.0, 0.0, 0.0)
	cam.fov = 96.0
	for i in 20:
		await process_frame
	var craft_row: int = menu.buttons.find(menu.craft_selector.button)
	# [seconds, what happens then]
	var beats := [[1.2, "craft row"], [4.6, "next"], [8.2, "next"], [11.8, "leave"], [13.6, "end"]]
	var t := 0.0
	var beat := 0
	var done := false
	while not done:
		if beat < beats.size() and t >= float(beats[beat][0]):
			match String(beats[beat][1]):
				"craft row":
					menu.focus_row(craft_row)
				"next":
					menu.activate()      # (A or the trigger on the pilot craft row: the next craft, saved in the profile this runs under)
				"leave":
					menu.focus_row(menu.start_index)
				"end":
					done = true
			beat += 1
		menu.update_swing(1.0 / FPS)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_jpg(out_dir.path_join("f%04d.jpg" % frame), 0.92)
		frame += 1
		t += 1.0 / FPS
	print("TURNTABLE FILM %d frames in %s" % [frame, out_dir])
	quit(0)
