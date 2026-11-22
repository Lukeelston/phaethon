## The title (release/title_stage.gd): pictures of it as the menus show it. Run windowed:
## --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_title.gd -- --mute --out=DIR [--views=a,b] [--settle=1.2]
## Views:
##   flat             the desktop menu itself, as a player sees it
##   flat-art         ... with the menu's panels hidden: the camera's picture alone
##   vr-ahead         the headset's menu from the pilot's standing eye, looking straight ahead (XR off: one
##                    flat camera at the eye, 96 degrees top to bottom, which is about a Quest 3's)
##   vr-left, vr-right, vr-up, vr-down, vr-behind      ... turned 50 degrees either way, 25 up, 30 down, right round
##   vr-left-near, vr-right-near                       ... 50 degrees either way through a 50 degree field: a craft as it is looked at
##   vr-word          ... 18 degrees up through a 60 degree field: the word as it is read
##   stage-vr-*       the same views of the stage alone, no menu board in front of it
## Nothing here is a headset's picture: no stereo, no lens.
extends SceneTree

const Stage := preload("res://release/title_stage.gd")
const TURNS := {"ahead": [0.0, 0.0, 96.0], "left": [50.0, 0.0, 96.0], "right": [-50.0, 0.0, 96.0], "up": [0.0, 25.0, 96.0], "down": [0.0, -30.0, 96.0],
	"behind": [180.0, 0.0, 96.0], "left-near": [54.0, -9.0, 50.0], "right-near": [-54.0, -9.0, 50.0], "word": [0.0, 18.0, 60.0]}
const ALL := ["flat", "flat-art", "vr-ahead", "vr-left", "vr-right", "vr-up", "vr-down", "vr-behind", "vr-left-near", "vr-right-near", "vr-word"]

var out_dir := ""
var settle := 1.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var views := PackedStringArray(ALL)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--views="):
			views = arg.trim_prefix("--views=").split(",")
		if arg.begins_with("--settle="):
			settle = float(arg.trim_prefix("--settle="))
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	root.msaa_3d = Viewport.MSAA_4X
	var scene := ""
	for view in views:
		var want := "stage" if view.begins_with("stage-") else ("flat" if view.begins_with("flat") else "vr")
		if want != scene:
			scene = want
			if want == "stage":
				if current_scene != null:
					current_scene.queue_free()
					await process_frame
				var holder := Node3D.new()
				holder.name = "StageOnly"
				root.add_child(holder)
				current_scene = holder
				var stage := Stage.make("vr")
				holder.add_child(stage)
				var cam := Camera3D.new()
				cam.name = "eye"
				cam.far = 200000.0
				cam.near = 0.05
				holder.add_child(cam)
				cam.make_current()
				stage.place(Vector3.ZERO, Vector3.FORWARD)
				print("TITLE STAGE built in %d ms" % stage.build_ms)
			else:
				change_scene_to_file("res://release/menu.tscn" if want == "flat" else "res://release/vr_menu.tscn")
				await scene_changed
				if want == "vr":
					current_scene.set_process(false)      # (no headset: its own frame would only look for one)
			await _wait(settle)
		var cam: Camera3D = null
		if want == "stage":
			cam = current_scene.get_node("eye")
		elif want == "vr":
			cam = current_scene.camera
		if want == "flat":
			for child in current_scene.get_children():
				if child is Control:
					(child as Control).visible = view != "flat-art"
		else:
			var turn: Array = TURNS[view.trim_prefix("stage-").trim_prefix("vr-")]
			cam.rotation_degrees = Vector3(float(turn[1]), float(turn[0]), 0.0)
			cam.fov = float(turn[2])
		await _wait(0.25)
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("title-%s.png" % view)
		print("TITLE SHOT %s %s" % [view, "saved" if root.get_texture().get_image().save_png(path) == OK else "FAILED"])
	print("TITLE RENDER DONE")
	quit(0)


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await process_frame
