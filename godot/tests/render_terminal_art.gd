## Render the production pilot seat on the default Network departure with XR disabled.
## Run with --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_terminal_art.gd -- --track=network --handling=speed --mute --out=DIR
## Optional: --captures-only, --benchmark-only, --flat-panel (the flat instrument panel and
## heads-up map instead of the gauge cluster and map pod). Timings are for one desktop eye.
## Timings with the head tipped back (--look-up=60) and the cockpit rolled over (--inverted) weigh what
## is seen through the top of the canopy: the sky, or with both the road as a corkscrew's top shows it.
## A place, not a stretch: --bench-span=N sweeps N samples of road in the timed pass, not 240 (0: parked);
## --bench-dir=-1 faces and sweeps down the road's samples (Mount Hyperion taken from E3: up the cliff, down the ramp).
## What a layer of the world costs: --off=clouds,ground,... leaves it undrawn (_switch_off has the names);
## --msaa=0|2|4 and --fov=DEG change the view's own. --bench-shot=NAME keeps a picture of the first pose.
## --weigh=a,b,... times the parked place with each of those left out in turn, all in this one run and turn
## about (--weigh-rounds=3), so that other work on the machine falls on all of them alike: weigh.json.
## With the engine's own --gpu-profile (before -s) the timing also says what each of the renderer's passes
## took, a viewport at a time (the depth pass, the opaque, the sky, the see-through): "passes" in timing.json.
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const STEP := 1.0 / 120.0
const SHOTS := {
	"01-terminal": 0, "02-under-ribs": 60, "03-portal": 80,
	"04-daylight": 98, "05-landmark": 124, "06-downrange": 180, "07-controls": 98
}

var seat
var city: Dictionary
var out_dir := ""
var gpu := PackedFloat64Array()
var cpu := PackedFloat64Array()
var elapsed := PackedFloat64Array()
var draws := PackedFloat64Array()
var prims := PackedFloat64Array()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable review directory.")
		quit(1)
		return
	if "--flat-panel" in OS.get_cmdline_user_args():   # v0.3.2's flat instrument panel and heads-up map
		preload("res://vr/gauge_cluster.gd").enabled = false
		preload("res://vr/minimap_panel.gd").enclosure = false
	if "--open" in OS.get_cmdline_user_args():   # the open cockpit, before the roof
		preload("res://view/canopy.gd").roofed = false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--edge-probe="):   # timings: the scenic roads' open edges undrawn
			preload("res://view/network_world.gd").open_edge_probe = arg.trim_prefix("--edge-probe=")
		if arg.begins_with("--roof-probe="):   # timings: the roof without its glass, or without its dome light
			preload("res://view/canopy.gd").probe = arg.trim_prefix("--roof-probe=")
	if "--no-beam" in OS.get_cmdline_user_args():   # timings: the approach guidance without its projector beam
		preload("res://view/approach_projector.gd").beams = false
	if "--no-streaks" in OS.get_cmdline_user_args():   # timings: the speed rush's streaks undrawn
		preload("res://vr/speed_rush.gd").streaks_drawn = false
	if "--no-rush" in OS.get_cmdline_user_args():   # the speed rush switched off (the cockpit where it was, no streaks)
		Seat.speed_rush = false
		Seat._rush_loaded = true
	if "--no-plume" in OS.get_cmdline_user_args():   # timings: the jets' gas undrawn
		preload("res://view/craft_model.gd").plumes = false
	Seat._nose_loaded = true                              # (the pilot's saved choice stays out of the pictures and the timings)
	if "--closed-nose" in OS.get_cmdline_user_args():   # the nose skinned over (the quick menu's NOSE line)
		preload("res://view/craft_model.gd").nose_closed = true
	if "--guidance-every-frame" in OS.get_cmdline_user_args():   # timings: the approach readout's picture drawn every frame, to weigh one
		preload("res://view/approach_projector.gd").picture_every_frame = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="):   # timings: the quick menu's chase views
			Seat.camera = arg.trim_prefix("--camera=")
			Seat._camera_loaded = true
	if "--no-start-panel" in OS.get_cmdline_user_args():   # timings: the cockpit without its start panel
		preload("res://vr/overhead_panel.gd").fitted = false
	if "--no-reflection" in OS.get_cmdline_user_args():   # timings: the windscreen without its reflection of the cockpit
		preload("res://view/screen_reflection.gd").enabled = false
	if "--reflection-every-frame" in OS.get_cmdline_user_args():   # timings: a picture every frame, to weigh one
		preload("res://view/screen_reflection.gd").every = 0.0
	if "--reflection-whole" in OS.get_cmdline_user_args():   # timings: the sheet over the whole pane, not cut to what shows
		preload("res://view/screen_reflection.gd").whole = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reflection="):   # (looking at it: the reflection this many times its strength)
			preload("res://view/screen_reflection.gd").strength = float(arg.trim_prefix("--reflection="))
	if "--whole-trees" in OS.get_cmdline_user_args():   # timings: every tree drawn whole at any distance, as before push 26
		preload("res://view/network_biome_props.gd").far_shapes = false
	if "--no-scenic" in OS.get_cmdline_user_args():   # the scenic roads' land and edges left out
		preload("res://view/network_world.gd").scenic_on = false
	# The pilot's saved hour, weather, paint and chase stay out of pictures and timings: a fair afternoon
	# in Ember, no chase, unless --time= or --weather= says otherwise.
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	root.msaa_3d = Viewport.MSAA_4X
	if "--headset" in OS.get_cmdline_user_args():   # twice the window each way: with --resolution 2064x1104, a Quest 3's two eyes' worth of pixels in one flat view
		root.scaling_3d_scale = 2.0
	if "--two-eyes" in OS.get_cmdline_user_args():   # both eyes' worth of pixels in one flat view, whatever the window: 4868x2604, two of 3440x1840 (the headset's work a pixel against its work a triangle)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size = Vector2i(2434, 1302)
		root.scaling_3d_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	for c in seat.sim.cities:
		if c.name == "ERIDANUS":
			city = c
	if city.is_empty() or root.use_xr:
		push_error("This review requires the Eridanus Network road and a monoscopic viewport.")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-at="):   # road,sample: time the seat along another stretch (open country, a sky bridge)
			var at := arg.trim_prefix("--bench-at=").split(",")
			city = {"road": int(at[0]), "i": int(at[1])}
		if arg.begins_with("--bench-right="):   # m right of the centre line (negative: left), for timing the seat out on a scenic road's open apron
			_bench_right = float(arg.trim_prefix("--bench-right="))
		if arg.begins_with("--bench-dir="):   # -1: facing down the road's samples, and sweeping that way
			_bench_dir = -1 if int(arg.trim_prefix("--bench-dir=")) < 0 else 1
		if arg.begins_with("--bench-span="):   # samples of road the timed pass sweeps (240 as it was; 0: parked)
			_bench_span = int(arg.trim_prefix("--bench-span="))
		if arg.begins_with("--msaa="):   # timings: the view's multisampling (4 as the headset's; 2; 0 none)
			root.msaa_3d = {"0": Viewport.MSAA_DISABLED, "2": Viewport.MSAA_2X, "4": Viewport.MSAA_4X, "8": Viewport.MSAA_8X}[arg.trim_prefix("--msaa=")]
	if "--as-flown" in OS.get_cmdline_user_args():   # the first spike flight's world: no banks, no fins, level traffic
		seat.network_world.banks = false
		seat.network_world.fins = false
		seat.traffic_net.grade = false
	_set_pose(0)
	# Resolve both streamers before capture; their regular sync budgets stay in force while travelling.
	for i in 5000:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
		if seat.landscape.pending.is_empty() and seat.landscape._job.is_empty() and seat.landscape._decor_job.is_empty() and i > 1200:
			break
	if "--benchmark-only" not in OS.get_cmdline_user_args():
		for name in SHOTS:
			_set_pose(SHOTS[name])
			seat.cam.position = Vector3.ZERO
			seat.cam.rotation = Vector3.ZERO
			if name == "07-controls":
				# A plausible seated lean and glance down at the starboard control.
				seat.cam.position = Vector3(0.12, 0.04, -0.04)
				seat.cam.rotation_degrees = Vector3(-27, -32, 0)
			for frame in 84:
				seat._process(STEP)
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out_dir.path_join(name + ".png")
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("Couldn't save " + path)
				quit(1)
				return
			print("TERMINAL_SHOT ", name, " sample=", int(city.i) + int(SHOTS[name]))
	if "--captures-only" not in OS.get_cmdline_user_args():
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--look-up="):   # timings: the head tipped back this many degrees (90: straight up through the canopy)
				seat.cam.rotation_degrees.x = float(arg.trim_prefix("--look-up="))
			if arg.begins_with("--fov="):   # timings: the flat view's field, degrees top to bottom (70 as it is; a headset's eye sees about 96)
				seat.cam.fov = float(arg.trim_prefix("--fov="))
			if arg.begins_with("--look-right="):   # ... and the head turned this many degrees to the right
				seat.cam.rotation_degrees.y = -float(arg.trim_prefix("--look-right="))
			if arg.begins_with("--off="):   # timings: these layers of the world undrawn
				for layer in arg.trim_prefix("--off=").split(","):
					_switch_off(layer)
			if arg.begins_with("--hide="):   # timings: the nodes of these names undrawn (what a part costs: the same run with and without it)
				for part in arg.trim_prefix("--hide=").split(","):
					for node in root.find_children(part, "", true, false):
						if node is Node3D:
							node.visible = false
							print("TERMINAL_HIDE ", node.get_path())
		var weighing := false
		var weigh_rounds := 3
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--weigh-rounds="):
				weigh_rounds = int(arg.trim_prefix("--weigh-rounds="))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--weigh="):   # timings: each of these left out in turn, in this one run
				weighing = true
				await _weigh(arg.trim_prefix("--weigh=").split(","), weigh_rounds)
		if not weighing:
			await _benchmark()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--bench-shot="):   # a picture of the timed place's first pose, as it was timed
				_set_pose(0)
				for body in seat.sim.bodies:
					body.vx = 0.0
					body.vy = 0.0
				for frame in 6:
					seat._process(STEP)
					await process_frame
				await RenderingServer.frame_post_draw
				var shot := out_dir.path_join(arg.trim_prefix("--bench-shot=") + ".png")
				if root.get_texture().get_image().save_png(shot) != OK:
					push_error("Couldn't save " + shot)
				print("TERMINAL_SHOT ", shot)
	seat.free()
	quit()


var _bench_right := 0.0   # (--bench-right=)
var _bench_span := 240    # (--bench-span=)
var _bench_dir := 1       # (--bench-dir=)


## Leave one layer of the world undrawn (--off=), to weigh it: the same run with and without. Besides the
## layers: "msaa0" and "msaa2" (the view's multisampling), "flat-ground", "flat-terrain", "flat-hyperion"
## and "flat-asphalt" (that material painted one flat colour: its shape still drawn, its shader's work not),
## "world" (every layer); "swap:MATERIAL:FILE" (ground, terrain, hyperion, asphalt or clouds painted by the
## shader in --swap-dir=DIR's FILE: another version of it, the same run). -> what puts it back (_switch_on).
func _switch_off(layer: String) -> Array:
	var land = seat.landscape
	var world = seat.network_world
	var nodes := []
	var undo := []
	match layer:
		"now": return undo
		"clouds": nodes = [land.clouds]
		"ground": nodes = [seat.ground]
		"hyperion": nodes = [land.hyperion]
		"summit": nodes = [land.hyperion_summit]
		"tiles": nodes = [land._tile_root]
		"helios": nodes = [land.far_helios, land.sun_gate]
		"far_roads": nodes = [world.far_roads]
		"roads": nodes = [world._chunk_root]
		"scenery": nodes = [world.scenery]
		"skylines":
			for sk in world.skylines:
				nodes.append(sk[0])
		"traffic": nodes = [seat.traffic_net]
		"craft": nodes = [seat.craft]
		"horizon": nodes = [seat.horizon]
		"sky":      # the sky's own shader: a flat colour in its place
			for child in seat.get_children():
				if child is WorldEnvironment:
					var env: Environment = (child as WorldEnvironment).environment
					undo.append(["background", env, env.background_mode])
					env.background_mode = Environment.BG_COLOR
					env.background_color = Color(0.02, 0.03, 0.06)
			return undo
		"msaa0", "msaa2":
			undo.append(["msaa", root.msaa_3d])
			root.msaa_3d = Viewport.MSAA_DISABLED if layer == "msaa0" else Viewport.MSAA_2X
			return undo
		"flat-ground", "flat-terrain", "flat-hyperion", "flat-asphalt":
			var mat: ShaderMaterial = {"flat-ground": seat.ground_mat, "flat-terrain": land.material,
				"flat-hyperion": land.hyperion.material_override if land.hyperion != null else null, "flat-asphalt": world._asph}[layer]
			if mat != null:
				if not _flat.has(layer):
					var plain := Shader.new()
					plain.code = FLAT[layer]
					_flat[layer] = plain
				undo.append(["shader", mat, mat.shader])
				mat.shader = _flat[layer]
			return undo
		_ when layer.begins_with("swap:"):
			var bits := layer.split(":")
			var mats := {"ground": seat.ground_mat, "terrain": land.material, "asphalt": world._asph, "clouds": land.clouds.material_override,
				"hyperion": land.hyperion.material_override if land.hyperion != null else null}
			var other: ShaderMaterial = mats.get(bits[1])
			if other == null or bits.size() < 3:
				push_error("--weigh: nothing to swap for " + layer)
				return undo
			if not _flat.has(layer):
				var path := ""
				for arg in OS.get_cmdline_user_args():
					if arg.begins_with("--swap-dir="):
						path = arg.trim_prefix("--swap-dir=").path_join(bits[2])
				var text := FileAccess.get_file_as_string(path)
				if text.is_empty():
					push_error("--weigh: no shader at " + path)
					return undo
				var made := Shader.new()
				made.code = text
				_flat[layer] = made
				# (a picture beside it called FILE.<parameter>.png is that parameter's: one the base shader does not take)
				var folder := DirAccess.open(path.get_base_dir())
				if folder != null:
					for file in folder.get_files():
						if file.begins_with(bits[2] + ".") and file.ends_with(".png"):
							var picture := Image.load_from_file(path.get_base_dir().path_join(file))
							if picture != null:
								other.set_shader_parameter(file.trim_prefix(bits[2] + ".").trim_suffix(".png"), ImageTexture.create_from_image(picture))
			undo.append(["shader", other, other.shader])
			other.shader = _flat[layer]
			return undo
		"far-tiles":      # the terrain's tiles no part of which is within the 64 km they have faded right out by
			var hidden := 0
			for tile in land.tiles.values():
				for surface in (tile.node as Node).get_children():
					if surface is MeshInstance3D and (surface as MeshInstance3D).material_override == land.material:
						var box: AABB = (surface as MeshInstance3D).get_aabb()
						var middle: Vector3 = (surface as MeshInstance3D).global_transform * box.get_center()
						if seat.cam.global_position.distance_to(middle) - box.size.length() / 2.0 > 64000.0:
							undo.append(["visible", surface, (surface as Node3D).visible])
							(surface as Node3D).visible = false
							hidden += 1
			if not _told.has(layer):
				_told[layer] = true
				print("TERMINAL_OFF far-tiles: ", hidden, " of ", land.tiles.size(), " tiles")
			return undo
		"world":
			for each in ["clouds", "ground", "hyperion", "summit", "tiles", "helios", "far_roads", "roads", "scenery", "skylines", "traffic"]:
				undo.append_array(_switch_off(each))
			return undo
		_:
			push_error("--off=: no layer called " + layer)
			return undo
	for node in nodes:
		if node == null:
			continue
		# (some are shown again by their own sync each frame: taken off every camera's layers too)
		undo.append(["visible", node, (node as Node3D).visible])
		(node as Node3D).visible = false
		var parts: Array = (node as Node).find_children("*", "VisualInstance3D", true, false)
		parts.append(node)
		for part in parts:
			if part is VisualInstance3D:
				undo.append(["layers", part, (part as VisualInstance3D).layers])
				(part as VisualInstance3D).layers = 0
	return undo


## Put back what _switch_off left out.
func _switch_on(undo: Array) -> void:
	for k in range(undo.size() - 1, -1, -1):
		var u: Array = undo[k]
		match String(u[0]):
			"visible":
				if is_instance_valid(u[1]):
					(u[1] as Node3D).visible = u[2]
			"layers":
				if is_instance_valid(u[1]):
					(u[1] as VisualInstance3D).layers = u[2]
			"background": (u[1] as Environment).background_mode = u[2]
			"msaa": root.msaa_3d = u[1]
			"shader": (u[1] as ShaderMaterial).shader = u[2]


var _flat := {}      # (_switch_off's flat shaders, made once)
var _told := {}      # (... and what it has said once)
const FLAT := {
	"flat-ground": "shader_type spatial;\nrender_mode cull_back;\nvoid fragment() { ALBEDO = vec3(0.2); ROUGHNESS = 0.95; SPECULAR = 0.25; }\n",
	"flat-asphalt": "shader_type spatial;\nrender_mode cull_disabled;\nvoid fragment() { ALBEDO = vec3(0.08); ROUGHNESS = 0.86; SPECULAR = 0.4; }\n",
	# (the terrain's own fade with distance kept: without it tiles the eye never sees would cover the ground)
	"flat-terrain": "shader_type spatial;\nrender_mode fog_disabled;\ninstance uniform float stream_reveal = 1.0;\nvoid fragment() {\n\tfloat reveal = stream_reveal * (1.0 - smoothstep(54000.0, 64000.0, length(VERTEX)));\n\tif (reveal <= fract(dot(floor(FRAGCOORD.xy), vec2(0.75487766, 0.56984029)))) discard;\n\tALBEDO = vec3(0.2); ROUGHNESS = 0.9; SPECULAR = 0.2;\n}\n",
	# (the mountain's own pull toward the eye kept)
	"flat-hyperion": "shader_type spatial;\nrender_mode fog_disabled;\nvoid vertex() {\n\tvec3 seen = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;\n\tfloat d = length(seen);\n\tfloat pulled = d > 88000.0 ? 88000.0 + 26000.0 * (1.0 - exp(-(d - 88000.0) / 160000.0)) : d;\n\tPOSITION = PROJECTION_MATRIX * vec4(seen * (pulled / max(d, 0.001)), 1.0);\n}\nvoid fragment() { ALBEDO = vec3(0.2); ROUGHNESS = 0.9; SPECULAR = 0.2; }\n",
}


## --weigh=: the parked place's view timed with nothing left out ("now") and with each of `names` left out
## in turn (_switch_off's names), `rounds` times turn about; one more round first is thrown away (a shader new
## to the view is compiled in it). Each turn is 110 frames, the last 60 timed. With --gpu-profile, the
## renderer's passes too.
func _weigh(names: PackedStringArray, rounds: int) -> void:
	var vp := root.get_viewport_rid()
	var device := RenderingServer.get_rendering_device()
	var main_id := "vp_begin_" + str(vp.get_id())
	var order := ["now"]
	for nm in names:
		order.append(nm)
	var kept := {}      # variant -> {measure -> [a median a round]}
	for turn in rounds + 1:
		for variant in order:
			var undo := []
			for each in String(variant).split("+"):
				undo.append_array(_switch_off(each))
			var got := {"gpu": []}
			for frame in 110:
				_set_pose(0)
				seat._process(STEP)
				await process_frame
				if frame < 50:
					continue
				(got.gpu as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				if device != null and device.get_captured_timestamps_count() > 4:
					var frame_ms := {}
					var mine := false
					for k in device.get_captured_timestamps_count() - 1:
						var stamp := device.get_captured_timestamp_name(k)
						if stamp.begins_with("vp_begin_"):
							mine = stamp == main_id
						elif stamp.begins_with("vp_end_"):
							mine = false
						elif mine:
							frame_ms[stamp] = float(frame_ms.get(stamp, 0.0)) + float(device.get_captured_timestamp_gpu_time(k + 1) - device.get_captured_timestamp_gpu_time(k)) / 1e6
					for key in frame_ms:
						if not got.has(key):
							got[key] = []
						(got[key] as Array).append(frame_ms[key])
			_switch_on(undo)
			if turn == 0:
				continue
			if not kept.has(variant):
				kept[variant] = {}
			for key in got:
				var values: Array = got[key]
				values.sort()
				if not (kept[variant] as Dictionary).has(key):
					kept[variant][key] = []
				(kept[variant][key] as Array).append(values[values.size() / 2])
	var result := {}
	for variant in order:
		var line := {}
		for key in kept[variant]:
			var values: Array = kept[variant][key]
			values.sort()
			line[key] = snappedf(values[values.size() / 2], 0.001)
		result[variant] = line
		var base: Dictionary = result["now"]
		print("TERMINAL_WEIGH %-28s gpu %.2f (%+.2f) | opaque %.2f (%+.2f) | see-through %.2f (%+.2f) | depth %.2f (%+.2f) | resolve %.2f" % [
			variant, line.gpu, float(line.gpu) - float(base.gpu),
			line.get("Render Opaque Pass", 0.0), float(line.get("Render Opaque Pass", 0.0)) - float(base.get("Render Opaque Pass", 0.0)),
			line.get("Render 3D Transparent Pass", 0.0), float(line.get("Render 3D Transparent Pass", 0.0)) - float(base.get("Render 3D Transparent Pass", 0.0)),
			line.get("Render Depth Pre-Pass", 0.0), float(line.get("Render Depth Pre-Pass", 0.0)) - float(base.get("Render Depth Pre-Pass", 0.0)),
			line.get("Resolve", 0.0)])
	var output := FileAccess.open(out_dir.path_join("weigh.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))


func _set_pose(offset: int) -> void:
	seat.sim.respawn_on(int(city.road), int(city.i) + offset * _bench_dir, _bench_dir, _bench_right)
	seat._ride.clear()


func _benchmark() -> void:
	var road = seat.sim.roads[int(city.road)]
	var vp := root.get_viewport_rid()
	var burner := "--burner" in OS.get_cmdline_user_args()
	var guidance := "--guidance" in OS.get_cmdline_user_args()
	var inverted := "--inverted" in OS.get_cmdline_user_args()   # timings: the cockpit rolled right over about the pilot's head, the road over the canopy (the top of a corkscrew, near enough)
	var device := RenderingServer.get_rendering_device()
	var passes := {}      # "viewport: pass" -> ms a frame (the renderer's own timestamps: there are none but the viewports' without --gpu-profile)
	var main_id := "vp_begin_" + str(vp.get_id())
	# Two warm passes give the runtime a chance to compile newly visible materials.
	# Every pass follows identical transforms even if the host display rate changes.
	for lap in 3:
		var last := Time.get_ticks_usec()
		for frame in 480:
			var offset := (frame * _bench_span) / 480
			var moving := float(_bench_span) / 240.0
			var idx := int(city.i) + offset * _bench_dir
			_set_pose(offset)
			var dx: float = road.px[idx + _bench_dir] - road.px[idx]
			var dy: float = road.py[idx + _bench_dir] - road.py[idx]
			for body in seat.sim.bodies:
				if _bench_span == 240:
					body.x += dx * 0.5 * (frame % 2)
					body.y += dy * 0.5 * (frame % 2)
				body.vx = dx * 60.0 * moving
				body.vy = dy * 60.0 * moving
			if burner:      # both levers through the gate: the long plumes
				seat.inp = {"thrL": 1.0, "thrR": 1.0, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "burner": true}
			var begin := Time.get_ticks_usec()
			seat._process(STEP)
			var update_ms := (Time.get_ticks_usec() - begin) / 1000.0
			if inverted:
				var head: Vector3 = seat.cam.global_position
				var over := Transform3D(Basis((seat.rig as Node3D).global_basis.z.normalized(), PI), Vector3.ZERO)
				(seat.rig as Node3D).global_transform = Transform3D(Basis.IDENTITY, head) * over * Transform3D(Basis.IDENTITY, -head) * (seat.rig as Node3D).global_transform
			if guidance and seat.approach_display:      # the approach readout held up (the frame's own update has just stowed it)
				seat.approach_display.set_message("JUMP LIP  2 MI / 4.0 S\nASCENT J0 > N2 UPPER\nMIN 3,000 MPH AT LIP | READY")
				seat.approach_display._process(1.0)
			await process_frame
			var now := Time.get_ticks_usec()
			if lap == 2:
				cpu.append(update_ms)
				elapsed.append((now - last) / 1000.0)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				if device != null and device.get_captured_timestamps_count() > 4:
					var frame_ms := {}
					var where := "before"
					for k in device.get_captured_timestamps_count() - 1:
						var stamp := device.get_captured_timestamp_name(k)
						if stamp.begins_with("vp_begin_"):
							where = "main" if stamp == main_id else "other"
						elif stamp.begins_with("vp_end_"):
							where = "between"
						var key := where + ": " + stamp.trim_prefix("vp_begin_").trim_prefix("vp_end_") if not stamp.begins_with("vp_") else where + ": (start)"
						frame_ms[key] = float(frame_ms.get(key, 0.0)) + float(device.get_captured_timestamp_gpu_time(k + 1) - device.get_captured_timestamp_gpu_time(k)) / 1e6
					for key in frame_ms:
						if not passes.has(key):
							passes[key] = []
						(passes[key] as Array).append(frame_ms[key])
			last = now
	if burner:
		print("TERMINAL_BENCH engines: mode %s, thrust %.2f %.2f, plume %.1f m, camera %s" % [seat.sim.mode, seat.sim.eL.thrust, seat.sim.eR.thrust, seat.craft.plume_len[0], Seat.camera])
	var result := {"viewport": str(root.size), "frames": cpu.size(), "road": road.name,
		"view_update_ms": _stats(cpu), "viewport_gpu_ms": _stats(gpu),
		"wall_frame_ms": _stats(elapsed), "draw_calls": _stats(draws), "primitives": _stats(prims),
		"near_tiles": seat.landscape.near_tiles}
	if not passes.is_empty():
		var split := {}
		for key in passes:
			var ms: Array = passes[key]
			ms.sort()
			if ms[ms.size() / 2] >= 0.005:
				split[key] = snappedf(ms[ms.size() / 2], 0.001)
		result["passes"] = split
	print("TERMINAL_BENCH ", JSON.stringify(result))
	var output := FileAccess.open(out_dir.path_join("timing.json"), FileAccess.WRITE)
	if output:
		output.store_line(JSON.stringify(result, "\t"))


func _stats(values: PackedFloat64Array) -> Dictionary:
	values.sort()
	return {"p50": values[int(values.size() * 0.50)], "p95": values[int(values.size() * 0.95)],
		"p99": values[int(values.size() * 0.99)], "max": values[-1]}
