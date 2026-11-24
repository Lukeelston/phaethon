## Physical weapon motion at the production cockpit camera, with the hull and dash
## occluding the rig as they do in flight. Each progress interval is tested in both directions.
## Run windowed. Use -- --proof=DIR to save pilot stills and --movie to capture a full cycle.
## --eye-offset and --seat-height shift the stock eye horizontally or vertically in metres.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const Paint := preload("res://view/livery.gd")
const Outlook := preload("res://view/outlook.gd")
const PILOTS := ["phaethon", "talon", "shrike", "orrery", "kiln", "vesper"]
const TRAVEL := 24
var failures := 0
var checks := 0
var out := ""
var movie := false
var eye_offset := Vector3.ZERO
var selected := ""
var magenta := StandardMaterial3D.new()
var green := StandardMaterial3D.new()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Pilot occlusion needs a rendering device")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proof="): out = arg.trim_prefix("--proof=")
		if arg.begins_with("--vehicle="): selected = arg.trim_prefix("--vehicle=")
		if arg.begins_with("--eye-offset="): eye_offset.x = float(arg.trim_prefix("--eye-offset="))
		if arg.begins_with("--seat-height="): eye_offset.y = float(arg.trim_prefix("--seat-height="))
		if arg == "--movie": movie = true
	for material in [magenta, green]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	magenta.albedo_color = Color.MAGENTA
	green.albedo_color = Color.GREEN
	Paint.pinned = true
	Paint.current = Paint.FACTORY
	Outlook.pinned = true
	Outlook.time = "afternoon"
	Outlook.weather = "fair"
	Seat.track_override = "range"
	Seat.job_override = "none"
	Seat._camera_loaded = true
	Seat.camera = "cockpit"
	Seat._startup_loaded = true
	Seat.cold_start = false
	Seat._nose_loaded = true
	Seat._slide_loaded = true
	Seat._map_loaded = true
	Seat._school_loaded = true
	root.msaa_3d = Viewport.MSAA_2X
	for id: String in PILOTS:
		if not selected.is_empty() and id != selected:
			continue
		# Each development branch may ship a subset. The combined build exercises all six.
		if not ResourceLoader.exists("res://view/arms/" + id + "_arms.gd"):
			continue
		await inspect_vehicle(id)
	if checks == 0:
		failures += 1
		push_error("No pilot rig was exercised")
	print("PILOT ARMING VISIBILITY %s (%d intervals, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

func inspect_vehicle(id: String) -> void:
	var dir := out.path_join(id)
	if not out.is_empty() and DirAccess.make_dir_recursive_absolute(dir) != OK:
		push_error("Cannot create " + dir)
		failures += 1
		return
	Seat.vehicle_override = id
	var game := Seat.new()
	root.add_child(game)
	game.set_process(false)
	for frame in 12:
		game._process(1.0 / 120.0)
	for child in game.get_children():
		if child is CanvasLayer:
			child.hide()
	var camera: Camera3D = game.cam
	camera.make_current()
	camera.position += eye_offset
	var hull: MeshInstance3D = game.shell.get_node("PodHull")
	var rig
	match id:
		"phaethon": rig = game.craft.call("phaethon_arms")
		"talon": rig = load("res://view/talon_airframe.gd").call("wing_arms", hull)
		"shrike": rig = load("res://view/shrike_airframe.gd").call("ensure_arms", hull)
		_: rig = game.craft.fleet.call("ensure_arms", hull)
	if rig == null:
		push_error("Cannot fit " + id)
		failures += 1
		game.free()
		return
	var roots: Array[Node] = []
	if id == "phaethon":
		for engine in game.craft.engines:
			roots.append(engine.get_node("PhaethonNoseBay"))
	else:
		roots.append(rig)
	var parts: Array[MeshInstance3D] = []
	for mount in roots:
		if mount is MeshInstance3D:
			parts.append(mount)
		for child: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
			parts.append(child)
	var materials: Array[Material] = []
	for part in parts:
		materials.append(part.material_override)
	# Heat is intentionally held at zero: an emission change alone cannot pass the test.
	rig.heat = 0.0
	var prev_image := PackedByteArray()
	var prev_mask := PackedByteArray()
	var initial_xf := camera.global_transform
	var steps := PackedInt32Array()
	var stride := 1 if movie else 3
	for i in range(0, 2 * TRAVEL + 1, stride):
		steps.append(mini(i, 2 * TRAVEL - i))
	for tick in steps.size():
		var step := steps[tick]
		rig.set_deploy(float(step) / TRAVEL)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var photo := root.get_texture().get_image()
		photo.convert(Image.FORMAT_RGB8)
		if not out.is_empty():
			if photo.save_jpg(dir.path_join("%02d.jpg" % tick), 0.94) != OK:
				push_error("Could not save pilot image for " + id)
				failures += 1
		if step % 3 != 0:
			continue
		var target_width := 640
		var target_height := roundi(float(target_width) * photo.get_height() / photo.get_width())
		photo.resize(target_width, target_height, Image.INTERPOLATE_BILINEAR)
		var actual := photo.get_data()
		var pink_pixels := await render_marker(parts, magenta, target_width, target_height)
		var green_pixels := await render_marker(parts, green, target_width, target_height)
		for i in parts.size():
			parts[i].material_override = materials[i]
		var mask := PackedByteArray()
		mask.resize(target_width * target_height)
		# Ignore instruments and clipped slivers at the edge of the pilot's forward view.
		for y in range(roundi(target_height * 0.15), roundi(target_height * 0.76)):
			for x in range(roundi(target_width * 0.05), roundi(target_width * 0.95)):
				var index := y * target_width + x
				var at := index * 3
				# Complementary ID renders isolate the hardware visible through the cabin depth buffer.
				mask[index] = int(pink_pixels[at] - green_pixels[at] > 60
					and green_pixels[at+1] - pink_pixels[at+1] > 60
					and pink_pixels[at+2] - green_pixels[at+2] > 60)
		# The narrow strip immediately over the road ahead should remain usable for aiming.
		var reticle := Rect2i(roundi(target_width * 0.48), roundi(target_height * 0.48),
			roundi(target_width * 0.04), roundi(target_height * 0.10))
		var covered := 0
		for y in range(reticle.position.y, reticle.end.y):
			for x in range(reticle.position.x, reticle.end.x):
				covered += int(mask[y * target_width + x])
		if covered > reticle.get_area() * 0.10:
			failures += 1
			print("  FAIL ", id, " covers the forward aiming corridor at ", float(step) / TRAVEL,
				" (", covered, " pixels)")
		if not prev_mask.is_empty():
			var changed := 0
			for index in mask.size():
				if mask[index] == 0 and prev_mask[index] == 0:
					continue
				var at := index * 3
				if maxi(absi(actual[at] - prev_image[at]),
					maxi(absi(actual[at+1] - prev_image[at+1]), absi(actual[at+2] - prev_image[at+2]))) >= 18:
					changed += 1
			checks += 1
			print("PILOT MOTION ", id, " tick ", tick, " step ", step, " visible change ", changed, " pixels at ", target_width, "x", target_height)
			# Reject a handful of subpixel highlights. Visibility is also reviewed in real-time footage.
			if changed < maxi(16, roundi(mask.size() * 0.00020)) or not initial_xf.is_equal_approx(camera.global_transform):
				failures += 1
				print("  FAIL ", id, " interval ending at ", float(step) / TRAVEL)
		prev_mask = mask
		prev_image = actual
	game.free()
	await process_frame


func render_marker(parts: Array[MeshInstance3D], material: Material, width: int, height: int) -> PackedByteArray:
	for part in parts:
		part.material_override = material
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var marked := root.get_texture().get_image()
	marked.convert(Image.FORMAT_RGB8)
	marked.resize(width, height, Image.INTERPOLATE_BILINEAR)
	return marked.get_data()
