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
##   vr-show          the board swung aside (a row that changes the craft has the highlight): straight ahead at the turntable
##   vr-show-near     ... through a 70 degree field, as the craft on it is looked at
##   flat-show        the desktop menu with its camera turned to the turntable (the pilot craft button has the keyboard)
## --craft=ID puts that pilot craft on the turntable, --paint=ID in that paint; --spin=DEG turns the deck to that angle.
## Nothing here is a headset's picture: no stereo, no lens.
extends SceneTree

const Stage := preload("res://release/title_stage.gd")
const TURNS := {"ahead": [0.0, 0.0, 96.0], "left": [50.0, 0.0, 96.0], "right": [-50.0, 0.0, 96.0], "up": [0.0, 25.0, 96.0], "down": [0.0, -30.0, 96.0],
	"behind": [180.0, 0.0, 96.0], "left-near": [54.0, -9.0, 50.0], "right-near": [-54.0, -9.0, 50.0], "word": [0.0, 18.0, 60.0],
	"show": [0.0, -8.0, 96.0], "show-near": [0.0, -11.0, 70.0]}
const ALL := ["flat", "flat-art", "flat-show", "vr-ahead", "vr-show", "vr-show-near", "vr-left", "vr-right", "vr-up", "vr-down", "vr-behind", "vr-left-near", "vr-right-near", "vr-word"]

var out_dir := ""
var settle := 1.2
var craft := ""
var paint := ""
var spin := NAN


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
		if arg.begins_with("--craft="):
			craft = arg.trim_prefix("--craft=")
		if arg.begins_with("--paint="):
			paint = arg.trim_prefix("--paint=")
		if arg.begins_with("--spin="):
			spin = float(arg.trim_prefix("--spin="))
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
			var stage: Stage
			if want == "stage":
				if current_scene != null:
					current_scene.queue_free()
					await process_frame
				var holder := Node3D.new()
				holder.name = "StageOnly"
				root.add_child(holder)
				current_scene = holder
				stage = Stage.make("vr") as Stage
				holder.add_child(stage)
				var cam := Camera3D.new()
				cam.name = "eye"
				cam.far = 200000.0
				cam.near = 0.05
				holder.add_child(cam)
				cam.make_current()
				stage.place(Vector3.ZERO, Vector3.FORWARD)
			else:
				change_scene_to_file("res://release/menu.tscn" if want == "flat" else "res://release/vr_menu.tscn")
				await scene_changed
				if want == "vr":
					current_scene.set_process(false)      # (no headset: its own frame would only look for one)
				stage = current_scene.stage
			var deadline := Time.get_ticks_msec() + 15000
			while stage != null and not stage.art_ready and Time.get_ticks_msec() < deadline:
				await process_frame
			if stage == null or not stage.art_ready:
				push_error("Title assembly did not finish for " + want)
				quit(1)
				return
			print("TITLE STAGE built in %d ms" % stage.build_ms)
			if not craft.is_empty() or not paint.is_empty():      # (straight to the stage: the menus' saved choices are not touched)
				stage.show_craft(craft if not craft.is_empty() else stage.show_vehicle, paint)
				var until := Time.get_ticks_msec() + 15000
				while stage.showcase.get("key", "") != stage._show_key() and Time.get_ticks_msec() < until:
					await process_frame
				print("TITLE TURNTABLE ", stage.showcase.get("key", "none"))
			await _wait(settle)
		var cam: Camera3D = null
		var stage_now = current_scene.stage if want != "stage" else current_scene.get_child(0)
		if want == "stage":
			cam = current_scene.get_node("eye")
		elif want == "vr":
			cam = current_scene.camera
			current_scene.swing = 1.0 if view.begins_with("vr-show") else 0.0
			current_scene._place_board()
			stage_now.attend(view.begins_with("vr-show"))
			stage_now.reveal = 1.0 if view.begins_with("vr-show") else 0.0
			stage_now._pose_turntable()
		if want == "flat":
			for child in current_scene.get_children():
				if child is Control:
					(child as Control).visible = view != "flat-art"
			current_scene.set_process(view != "flat-show")      # (its own frame would turn the camera back)
			stage_now.attend(view == "flat-show")
			stage_now.attention = 1.0 if view == "flat-show" else 0.0
			stage_now.reveal = stage_now.attention
			stage_now._aim_camera()
			stage_now._pose_turntable()
		else:
			var turn: Array = TURNS[view.trim_prefix("stage-").trim_prefix("vr-")]
			cam.rotation_degrees = Vector3(float(turn[1]), float(turn[0]), 0.0)
			cam.fov = float(turn[2])
		if not is_nan(spin) and stage_now.turntable != null:
			stage_now.turntable.rotation.y = deg_to_rad(spin)
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
