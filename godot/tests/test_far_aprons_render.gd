## Windowed readback of the same road samples at 1 km and 32 km, in metres per pixel.
## Run windowed: it reads the roads' pixels back (tools/run_suite.ps1 finds this line).
## --xr-mode off --resolution 1280x720 -s res://tests/test_far_aprons_render.gd -- [--out=DIR]
extends SceneTree

const World := preload("res://view/network_world.gd")
# Left-only, both sides, right-only. Choose the middle of each 40-sample near chunk.
const STRETCHES := [["SCoast", 3220], ["SDrop", 4620], ["SCaucasus", 6060]]
var failures := 0
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Far apron comparison needs a windowed renderer.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if not output.is_empty() and DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(1)
		return
	# Build both flight meshes with the Network pinned, without opening a cockpit or its preferences.
	var sim := CraftSim.new({"track": "network"})
	var world := World.new()
	root.add_child(world)
	world.hide()
	world.build(sim, null)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#29443d")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	root.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 530.0
	cam.far = 50000.0
	root.add_child(cam)
	cam.make_current()
	for stretch in STRETCHES:
		var road_id := -1
		for r in sim.roads.size():
			if sim.roads[r].name == stretch[0]:
				road_id = r
				break
		if road_id == -1:
			push_error("Missing road " + str(stretch[0]))
			failures += 1
			continue
		var road: CraftSim.TrackPath = sim.roads[road_id]
		var sample_id: int = stretch[1]
		var at := world._wxy(road_id, sample_id)
		var height := world._h(road_id, sample_id)
		var forward := Vector3(road.tx[sample_id], 0, -road.ty[sample_id])
		var left := Vector3(road.nx[sample_id], 0, -road.ny[sample_id])
		var chunk := Vector2i(road_id, sample_id / world.CH)
		if not world.chunks.has(chunk):
			world._build_chunk(road_id, chunk.y)
		var near_record: Array = world.chunks[chunk]
		var near_mesh: MeshInstance3D = near_record[0].get_node("road")
		var far_record := []
		for piece in world.far_roads.pieces:
			if piece[2] == road_id and sample_id >= piece[3] and sample_id < piece[4]:
				far_record = piece
				break
		if far_record.is_empty():
			push_error("Missing far ribbon on " + road.name)
			failures += 1
			continue
		for far: bool in [false, true]:
			var source: MeshInstance3D = far_record[0] if far else near_mesh
			var origin: Vector2 = far_record[1] if far else Vector2(near_record[1], near_record[2])
			var instance := MeshInstance3D.new()
			instance.mesh = source.mesh
			instance.material_override = source.material_override
			instance.position = Vector3(origin.x - at.x, -height, at.y - origin.y)
			root.add_child(instance)
			cam.position = Vector3.UP * (32000.0 if far else 1000.0)
			cam.look_at(Vector3.ZERO, forward)
			for frame in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var label := "%s-%s" % [road.name, "far" if far else "near"]
			if not output.is_empty() and image.save_png(output.path_join(label + ".png")) != OK:
				failures += 1
			var bg := image.get_pixel(0, image.get_height() / 2)
			var core := _coverage(image, cam.unproject_position(Vector3.ZERO), bg)
			for side: float in [-1.0, 1.0]:
				var extra := road.apl[sample_id] if side > 0.0 else road.apr[sample_id]
				var edge := road.w[sample_id] * 0.5 + extra
				var inside := _coverage(image, cam.unproject_position(left * side * (edge - 12.0)), bg)
				var outside := _coverage(image, cam.unproject_position(left * side * (edge + 15.0)), bg)
				var ok := core > 0.9 and inside > 0.02 and outside < 0.02
				if far:
					ok = ok and (inside < 0.40 if extra > 0.0 else inside > 0.9)
				print("%s %s sample %d, %+.0f m edge: centre %.0f%% / 12 m inside %.0f%% / 15 m outside %.0f%%" % [
					"PASS" if ok else "FAIL", label, sample_id, side * edge, core * 100.0, inside * 100.0, outside * 100.0])
				failures += int(not ok)
			instance.free()
	world.free()
	cam.free()
	env.free()
	print("FAR APRONS RENDER %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(int(failures > 0))


## Fraction of an 11-pixel square that contains road or glass against the clear background.
func _coverage(image: Image, centre: Vector2, bg: Color) -> float:
	var occupied := 0
	for y in range(-5, 6):
		for x in range(-5, 6):
			var p := image.get_pixel(roundi(centre.x) + x, roundi(centre.y) + y)
			if maxf(absf(p.r - bg.r), maxf(absf(p.g - bg.g), absf(p.b - bg.b))) > 1.5 / 255.0:
				occupied += 1
	return float(occupied) / 121.0
