## The Network traffic's lamps and its far bodies (Luke: "Make distant traffic readable - right now
## it just looks like a blur of taillights from far away"; view/traffic_lamps.gdshader,
## art/traffic/fleet.gdshader, view/network_traffic.gd).
##   which end   the lamps a vehicle shows are the ones toward the eye: tail lamps (red; a racer's
##               magenta) on one going away, head lamps (white) on one coming, whatever the pod is doing
##   the pair    each vehicle's lamps stand across its own width, by kind: a freighter's wide, a
##               racer's close
##   drawn       with a window (a headless renderer draws nothing): on a 20-pixel-a-degree picture a
##               vehicle a kilometre off shows as two lamps, one at the horizon as a point a pixel or
##               two across; the light a lamp puts on the picture falls with distance, and forty
##               vehicles strung from 6 to 18 km do not add up to a saturated smear, as the glows they
##               replace do; a far body is never under two pixels wide
## --headless --xr-mode off --audio-driver Dummy -s res://tests/test_traffic_lamps.gd -- --mute
## (windowed: --xr-mode off --resolution 1280x720 --audio-driver Dummy -s ... for the drawn checks too)
## Prints TRAFFIC LAMPS PASS.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
const PPD := 20.0
const SIZE := Vector2i(640, 360)
var failures := 0
var checks := 0
var v


func _initialize() -> void:
	View.track_override = "network"      # (its own track, whatever the command line says)
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("test_traffic_lamps_")
	preload("res://view/outlook.gd").pinned = true      # (the pilot's saved hour, paint and chase stay out of it)
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	failures += int(not ok)


func _car(net, road: int, f: float, dir: int, kind: int, lat: float):
	var c = Traffic.Car.new()
	c.id = 900 + net.cars.size()
	c.kind = kind
	c.road = road
	c.dir = dir
	c.f = f
	c.lat = lat
	c.v = 0.0
	c.owed = 0.0
	if kind == Traffic.RACER:
		c.name = "VEGA"
	net._place(c)
	net.cars.append(c)
	return c


func _which_end() -> void:
	v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var net = v.traffic_net
	var road := 2      # E3, open country: long, straight and level
	var at := 9000
	sim.respawn_on(road, at, 1)
	v._follow_origin()
	v._place_camera(1.0)
	net.cars.clear()
	var ahead = _car(net, road, at + 1000.0 / 24.0, 1, Traffic.CAR, -22.5)
	var train = _car(net, road, at + 2000.0 / 24.0, 1, Traffic.TRANSPORT, -157.5)
	var coming = _car(net, road, at + 1500.0 / 24.0, -1, Traffic.DEMON, 67.5)
	var behind = _car(net, road, at - 1500.0 / 24.0, 1, Traffic.CAR, 22.5)
	var racer = _car(net, road, at + 800.0 / 24.0, 1, Traffic.RACER, 112.5)
	var pod_ = _car(net, road, at + 3000.0 / 24.0, 1, Traffic.SLOW, -112.5)
	net._render()
	var eye: Vector3 = root.get_camera_3d().global_position
	var ex: float = eye.x + v.org_x
	var ey: float = v.org_y - eye.z
	var seen := {}
	for row in [["ahead", ahead], ["train", train], ["coming", coming], ["behind", behind], ["racer", racer], ["pod", pod_]]:
		var c = row[1]
		var nose_to_eye: bool = c.hx * (ex - c.x) + c.hy * (ey - c.y) > 0.0
		var lamp_x: float = c.lamp_position.x + v.org_x
		var lamp_y: float = v.org_y - c.lamp_position.z
		seen[row[0]] = {"toward": nose_to_eye, "col": c.lamp_color, "fore": (lamp_x - c.x) * c.hx + (lamp_y - c.y) * c.hy, "c": c}
	_check("the pod stands on E3 with the eye behind the cars ahead and ahead of the one behind (toward the eye: ahead %s, behind %s, coming %s)" % [
		seen.ahead.toward, seen.behind.toward, seen.coming.toward], not seen.ahead.toward and seen.behind.toward and seen.coming.toward and not seen.train.toward)
	var red := func(col: Color) -> bool: return col.r > 0.9 and col.g < 0.3 and col.b < 0.3
	var white := func(col: Color) -> bool: return col.r > 0.9 and col.g > 0.85 and col.b > 0.7
	_check("one going away ahead shows tail lamps, red, behind its middle (%s, %.1f m)" % [seen.ahead.col, seen.ahead.fore], red.call(seen.ahead.col) and seen.ahead.fore < -8.0)
	_check("one coming shows head lamps, white, ahead of its middle (%s, %.1f m)" % [seen.coming.col, seen.coming.fore], white.call(seen.coming.col) and seen.coming.fore > 8.0)
	_check("one coming up behind, going the pod's own way, shows its head lamps too: it is the eye that decides, not the pod's speed (%s, %.1f m)" % [seen.behind.col, seen.behind.fore],
		white.call(seen.behind.col) and seen.behind.fore > 8.0)
	_check("a racer's tail lamps are its own magenta (%s)" % [seen.racer.col], seen.racer.col.r > 0.9 and seen.racer.col.b > 0.7 and seen.racer.col.g < 0.5)
	var amber := func(col: Color) -> bool: return col.r > 0.9 and col.g > 0.35 and col.g < 0.7 and col.b < 0.25
	_check("the slow ones' are amber, a slow pod's and a transport's: at a distance the colour says what is slow (%s, %s)" % [seen.pod.col, seen.train.col],
		amber.call(seen.pod.col) and amber.call(seen.train.col) and not amber.call(seen.ahead.col))
	_check("a transport's tail lamps are behind the last of its train (%.0f m behind its tractor's middle; the train is %.0f m)" % [-seen.train.fore, (Traffic.TRAIN - 1) * Traffic.TRAIN_GAP],
		-seen.train.fore > (Traffic.TRAIN - 1) * Traffic.TRAIN_GAP + 8.0)
	# the pod's own speed changes nothing
	var before := [ahead.lamp_color, behind.lamp_color, coming.lamp_color]
	var R = sim.roads[road]
	for body in sim.bodies:
		body.vx = -R.tx[at] * 900.0
		body.vy = -R.ty[at] * 900.0
	net._render()
	_check("with the pod made to go backwards at 900 m/s every lamp is the same", before == [ahead.lamp_color, behind.lamp_color, coming.lamp_color])
	# the pair across the vehicle's own width
	var ok := true
	var widths := []
	for name in ["ahead", "pod", "coming", "train", "racer"]:
		var c = seen[name].c
		var lamps: Vector3 = Traffic.LAMPS[c.kind]
		var x: Vector3 = c.lamp_basis.x
		var heading := Vector3(c.hx, 0.0, -c.hy)
		ok = ok and absf(x.length() - lamps.x) < 1e-3 and absf(x.dot(heading)) < 1e-3 and absf(x.y) < 1e-3 and absf(c.lamp_basis.y.length() - lamps.y) < 1e-3 and absf(c.lamp_basis.z.length() - lamps.z) < 1e-3
		widths.append("%s %.1f" % [name, 2.0 * x.length()])
	_check("each pair stands across its vehicle's own width, level, as far apart as its kind's (m: %s)" % ", ".join(widths), ok)
	_check("a freighter's lamps are the widest and the biggest, a racer's and a demon's the closest (%s)" % [Traffic.LAMPS],
		Traffic.LAMPS[Traffic.TRANSPORT].x > Traffic.LAMPS[Traffic.SLOW].x and Traffic.LAMPS[Traffic.SLOW].x > Traffic.LAMPS[Traffic.CAR].x
		and Traffic.LAMPS[Traffic.CAR].x > Traffic.LAMPS[Traffic.DEMON].x and Traffic.LAMPS[Traffic.TRANSPORT].y > Traffic.LAMPS[Traffic.RACER].y)
	var mat: ShaderMaterial = net._beams.material_override
	_check("the lamps are drawn by their own shader, not the wall beacons' (%s), never under %.2f px in radius" % [mat.shader.resource_path.get_file(), Traffic.LAMP_MIN_PX],
		mat.shader.resource_path.ends_with("traffic_lamps.gdshader") and is_equal_approx(float(mat.get_shader_parameter("min_px")), Traffic.LAMP_MIN_PX)
		and Traffic.LAMP_MIN_PX >= 1.0 and Traffic.LAMP_MIN_PX <= 2.0)
	v.queue_free()


# ---- drawn: a small picture at a headset's pixel density, black behind, nothing but the lamps or the bodies ----

var port: SubViewport
var cam: Camera3D


func _stage() -> void:
	port = SubViewport.new()
	port.size = SIZE
	port.own_world_3d = true
	port.msaa_3d = Viewport.MSAA_4X
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	port.add_child(world_env)
	cam = Camera3D.new()
	cam.fov = rad_to_deg(2.0 * atan(SIZE.y * 0.5 * PI / 180.0 / PPD))
	cam.far = 40000.0
	cam.near = 0.5
	port.add_child(cam)
	cam.current = true


func _picture() -> Image:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	return port.get_texture().get_image()


## The lit part of a picture: [light summed (linear, the red channel), the brightest pixel (0..1 as shown), its box in pixels].
static func _lit(img: Image, from := Vector2i.ZERO, to := Vector2i(-1, -1)) -> Array:
	if to.x < 0:
		to = img.get_size()
	var total := 0.0
	var peak := 0.0
	var box := Rect2i()
	var any := false
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			var px := img.get_pixel(x, y)
			var r := maxf(px.r, maxf(px.g, px.b))
			if r > 0.03:
				total += pow(px.r, 2.2)
				peak = maxf(peak, r)
				if not any:
					box = Rect2i(x, y, 1, 1)
					any = true
				else:
					box = box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
	return [total, peak, box]


## How many of a picture's pixels are lit to `level` or more.
static func _over(img: Image, level: float) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			n += int(maxf(px.r, maxf(px.g, px.b)) >= level)
	return n


## The columns of a picture's row band that hold a peak of light: how many separate lamps show.
static func _peaks(img: Image, box: Rect2i) -> int:
	var prof := []
	for x in range(box.position.x, box.end.x):
		var s := 0.0
		for y in range(box.position.y, box.end.y):
			s += img.get_pixel(x, y).r
		prof.append(s)
	var peaks := 0
	var top := 0.0
	for s in prof:
		top = maxf(top, s)
	for i in prof.size():
		var left: float = prof[i - 1] if i > 0 else 0.0
		var right: float = prof[i + 1] if i < prof.size() - 1 else 0.0
		if prof[i] > 0.5 * top and prof[i] >= left and prof[i] > right:
			peaks += 1
	return peaks


func _lamp_batch(shader_new: bool, places: Array, kind: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Traffic.lamp_mesh()
	mm.instance_count = places.size()
	var lamps: Vector3 = Traffic.LAMPS[kind]
	for i in places.size():
		var basis := Basis.from_scale(lamps) if shader_new else Basis.IDENTITY
		mm.set_instance_transform(i, Transform3D(basis, places[i]))
		mm.set_instance_color(i, Color(1.0, 0.15, 0.08))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	if shader_new:
		mat.shader = preload("res://view/traffic_lamps.gdshader")
		mat.set_shader_parameter("min_px", Traffic.LAMP_MIN_PX)
		mat.set_shader_parameter("energy", Traffic.LAMP_ENERGY.y)      # as at night
	else:      # what they were: one glow a vehicle, the wall beacons' shader with the traffic's old numbers
		mat.shader = preload("res://view/beacon.gdshader")
		mat.set_shader_parameter("size", 0.9)
		mat.set_shader_parameter("min_ang", 0.0022)
		mat.set_shader_parameter("far_dim", 0.25)
		mat.set_shader_parameter("energy", 2.0)
	node.material_override = mat
	node.custom_aabb = AABB(Vector3(-40000, -1000, -40000), Vector3(80000, 2000, 80000))
	port.add_child(node)
	return node


func _drawn() -> void:
	_stage()
	var px := 1.0 / PPD      # degrees a pixel
	# one car's lamps, straight ahead, at a ladder of distances
	var rows := []
	for d in [250.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]:
		var node := _lamp_batch(true, [Vector3(0.0, 0.0, -d)], Traffic.CAR)
		var img: Image = await _picture()
		var lit := _lit(img)
		rows.append({"m": d, "light": lit[0], "peak": lit[1], "box": lit[2], "peaks": _peaks(img, lit[2]) if lit[2].size.x > 0 else 0})
		node.free()
	var told := []
	for r in rows:
		told.append("%d m: %d lamp%s, %d x %d px, peak %.2f, light %.2f" % [int(r.m), r.peaks, "" if r.peaks == 1 else "s", r.box.size.x, r.box.size.y, r.peak, r.light])
	print("     " + "; ".join(told))
	var spacing: float = 2.0 * Traffic.LAMPS[Traffic.CAR].x
	_check("a car 250 m, 1 km and 2 km off shows as a pair of lamps (the pair is %.1f, %.1f and %.1f px apart)" % [
		rad_to_deg(spacing / 250.0) / px, rad_to_deg(spacing / 1000.0) / px, rad_to_deg(spacing / 2000.0) / px],
		rows[0].peaks == 2 and rows[1].peaks == 2 and rows[2].peaks == 2)
	_check("at 8 and 16 km it is one point, a pixel or two across, still there (%d x %d and %d x %d px)" % [rows[4].box.size.x, rows[4].box.size.y, rows[5].box.size.x, rows[5].box.size.y],
		rows[4].peaks == 1 and rows[5].peaks == 1 and rows[4].box.size.x >= 1 and rows[4].box.size.x <= 4 and rows[5].box.size.x >= 1 and rows[5].box.size.x <= 4 and rows[5].box.size.y <= 4)
	_check("the light it puts on the picture falls with distance: at 4 km under a third of what it is at 1 km, at 16 km under a third of what it is at 4 km (%.2f, %.2f, %.3f)" % [rows[1].light, rows[3].light, rows[5].light],
		rows[3].light < 0.34 * rows[1].light and rows[5].light < 0.34 * rows[3].light and rows[5].light > 0.0)
	# the same far lamp a quarter of a pixel further across each time: it must not come and go with the pixels it falls on
	var px_m := 8000.0 * deg_to_rad(px)
	var sums := []
	for step in 8:
		var node := _lamp_batch(true, [Vector3(step * 0.25 * px_m, 0.0, -8000.0)], Traffic.CAR)
		var img: Image = await _picture()
		sums.append(snappedf(float(_lit(img)[0]), 0.001))
		node.free()
	var least: float = sums.min()
	var most: float = sums.max()
	_check("a lamp 8 km off moved across the picture a quarter of a pixel at a time keeps its light: %s (the most is %.2f times the least)" % [sums, most / maxf(least, 1e-6)],
		least > 0.0 and most / least < 1.45)
	# forty vehicles strung along four lanes from 6 to 18 km, seen from a seat 2 m up: the far end of a busy road
	var column := []
	for i in 40:
		column.append(Vector3([-67.5, -22.5, 22.5, 67.5][i % 4], -2.0, -(6000.0 + 300.0 * i)))
	var now_node := _lamp_batch(true, column, Traffic.CAR)
	var now_img: Image = await _picture()
	var now := _lit(now_img)
	now_node.free()
	var was_node := _lamp_batch(false, column, Traffic.CAR)
	var was_img: Image = await _picture()
	var was := _lit(was_img)
	was_node.free()
	var area_now: int = (now[2] as Rect2i).get_area()
	var area_was: int = (was[2] as Rect2i).get_area()
	var glare_now := _over(now_img, 0.8)
	var glare_was := _over(was_img, 0.8)
	_check("forty vehicles strung from 6 to 18 km: the lamps light %d pixels to 80%% or more and put %.1f of light on the picture; the glows they replace lit %d and put %.1f, over a patch %d x %d px against %d x %d" % [
		glare_now, now[0], glare_was, was[0], (now[2] as Rect2i).size.x, (now[2] as Rect2i).size.y, (was[2] as Rect2i).size.x, (was[2] as Rect2i).size.y],
		glare_now * 4 <= glare_was and glare_was >= 40 and now[0] < 0.25 * was[0] and area_now > 0 and area_now <= area_was)
	# a far body: never under two pixels wide
	var body := MultiMeshInstance3D.new()
	var model: Node = Traffic.FLEET[Traffic.CAR].instantiate()
	var bm := MultiMesh.new()
	bm.transform_format = MultiMesh.TRANSFORM_3D
	bm.use_colors = true
	bm.mesh = model.get_node("Distance").mesh
	model.free()
	bm.instance_count = 1
	body.multimesh = bm
	body.material_override = preload("res://art/traffic/fleet.tres")
	body.custom_aabb = AABB(Vector3(-40000, -1000, -40000), Vector3(80000, 2000, 80000))
	body.set_instance_shader_parameter("grow_per_m", Traffic.BODY_MIN_ANG / Traffic.BODY_HALF_WIDTH)
	port.add_child(body)
	var wide := []
	for d in [1000.0, 4000.0, 8000.0, 16000.0]:
		bm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * Traffic.SCALE), Vector3(0.0, -2.0, -d)))
		bm.set_instance_color(0, Color(0.85, 0.86, 0.9))
		var img: Image = await _picture()
		wide.append((_lit(img)[2] as Rect2i).size.x)
	body.free()
	_check("a car's body seen from behind is %d px wide at 1 km (its own size), and %d, %d and %d px at 4, 8 and 16 km: never under two" % wide,
		wide[0] >= 6 and wide[0] <= 12 and wide[1] >= 2 and wide[2] >= 2 and wide[3] >= 2 and wide[3] <= 5)
	port.queue_free()


func _run() -> void:
	_which_end()
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("     (headless: nothing is drawn, so the drawn checks are left to a run with a window)")
	else:
		await _drawn()
	print("TRAFFIC LAMPS %s (%d checks, %d failures%s)" % ["PASS" if failures == 0 else "FAIL", checks, failures, "" if DisplayServer.get_name() != "headless" else "; drawn checks not run"])
	quit(0 if failures == 0 else 1)
