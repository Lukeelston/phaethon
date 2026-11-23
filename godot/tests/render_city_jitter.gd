## Is a Network city still when nothing but a hair's breadth moves? (Luke, from the headset, 2026-11-22:
## "The buildings around cities jitter when i look at them.") One eye's view of a city from the seated
## eye, at about the headset's pixels a degree, drawn again and again with one small thing changed, for
## tools/city_jitter_diff.py to compare pixel for pixel:
##   base, again            the same pose twice: what changes by itself (the floor every other number sits on)
##   origin+D               the craft D metres further along its road and the eye held where it was in the
##                          world (D = 1 mm, 1 cm, 10 cm, 1 m, 10 m): only the floating origin has moved, so
##                          nothing in the picture should change at all
##   head+D                 the eye D to its right (1 mm, 1 cm): at these distances, a hundredth of a pixel
##   turn-NN                the head turning 0.008 degrees a frame (a still head's drift: a fifth of a pixel)
##   creep-NN               the craft creeping along its road at 1 m/s, the eye riding with it
##   speed-NN               ... and at 150 m/s (335 mph)
##   off-towers, off-landmarks, off-props    the base pose with that layer undrawn: where each one is in the picture
## Run with --xr-mode off --resolution 1600x900 --fixed-fps 120 --audio-driver Dummy
## -s res://tests/render_city_jitter.gd -- --mute --out=DIR
## [--city=0..4] the city looked at (0 Eridanus, 1 Dunes, 2 Glacier, 3 Basalt, 4 Mesa)
## [--off=150] samples along the city's own road from its terminal (25 m each), or [--at=ROAD,SAMPLE] any road's
## [--time=night] [--weather=fog] [--fov=35] degrees top to bottom (35 at 900 rows is 26 pixels a degree)
## [--up=250] m over the city's ground the eye aims at; [--bearing=DEG] aim that far right of the city's middle
## [--landmark=K] aim at a landmark instead (view/network_scenery.gd): the K-th nearest to the craft, 0 the nearest
## [--seat] the cockpit and the craft left in the picture and the view's own 70 degrees (pictures, not measures)
## [--only-base] the base pose's picture alone; [--no-sweeps] the stills without the three sweeps
## [--fine] every pixel drawn as four (the 3D picture at twice the size each way, averaged down): what a sweep's
## flicker would be with the facades' fine pattern properly averaged. What is left then is the picture's own
## detail moving; what goes was sampling
## [--time-against=FILE] no pictures, a timing: the base pose's view with the towers drawn by the shader as it is
## ("now"), by the shader in FILE ("other": the one before a change, say) and not drawn at all ("none"), turn
## about in this one run, three rounds after one to warm up, so other work on the machine falls on all three
## alike. Each turn is 110 frames, the last 60 timed: the rounds' medians of the viewport's GPU time, and the
## median of those. (--fine draws four pixels for one: at 1600x900 about two thirds of the headset's two eyes.)
extends SceneTree

const Seat := preload("res://vr/vr_cockpit.gd")
const STEP := 1.0 / 120.0
const ORIGIN_MOVES := [0.001, 0.01, 0.1, 1.0, 10.0]
const HEAD_MOVES := [0.001, 0.01]
const SWEEP := 12
const UNSEEN := 1 << 19      # a layer the eye's camera leaves out (not no layer at all: see _undraw)

var seat
var out_dir := ""
var city_i := 0
var road := -1
var sample := 0
var dir := 1
var fov := 35.0
var aim_up := 250.0
var bearing := 0.0
var landmark := -1
var bare := true
var _eye_at := Vector3.ZERO
var _look := Basis.IDENTITY
var _aimed := false
var _bare := []      # the cockpit's and the craft's parts taken out of the picture, and the layers they had


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var off := 150
	var at := ""
	for arg in args:
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		if arg.begins_with("--city="):
			city_i = int(arg.trim_prefix("--city="))
		if arg.begins_with("--off="):
			off = int(arg.trim_prefix("--off="))
		if arg.begins_with("--at="):
			at = arg.trim_prefix("--at=")
		if arg.begins_with("--fov="):
			fov = float(arg.trim_prefix("--fov="))
		if arg.begins_with("--up="):
			aim_up = float(arg.trim_prefix("--up="))
		if arg.begins_with("--bearing="):
			bearing = float(arg.trim_prefix("--bearing="))
		if arg.begins_with("--landmark="):
			landmark = int(arg.trim_prefix("--landmark="))
	bare = "--seat" not in args
	if out_dir.is_empty() or DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		push_error("Pass --out= and a writable directory.")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("A picture needs a window: run without --headless.")
		quit(1)
		return
	# The pilot's saved hour, weather, paint, camera and chase stay out of the pictures.
	var outlook := preload("res://view/outlook.gd")
	outlook.pinned = true
	outlook.time = "afternoon"
	outlook.weather = "fair"
	for arg in args:
		if arg.begins_with("--time="):
			outlook.time = arg.trim_prefix("--time=")
		if arg.begins_with("--weather="):
			outlook.weather = arg.trim_prefix("--weather=")
	preload("res://view/livery.gd").pinned = true
	preload("res://view/network_chase.gd").pinned = true
	Seat._nose_loaded = true
	Seat._rush_loaded = true
	Seat.speed_rush = false
	Seat.camera = "cockpit"
	Seat._camera_loaded = true
	root.msaa_3d = Viewport.MSAA_4X
	if "--fine" in args:
		root.scaling_3d_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if bare:
		# (the windscreen's reflection takes its picture of the cockpit every so often, and puts every part of
		# the cockpit back on a layer for it: after this script's turn in the frame, so the cockpit would be
		# in that one frame's picture)
		preload("res://view/screen_reflection.gd").enabled = false
	Seat.track_override = "network"
	Seat.job_override = "none"
	Seat.best_dir = out_dir.path_join("review_")
	seat = Seat.new()
	root.add_child(seat)
	seat.set_process(false)
	seat.cruise = 0.0
	if root.use_xr or city_i < 0 or city_i >= seat.sim.cities.size():
		push_error("This needs a flat viewport and a city 0 to %d." % (seat.sim.cities.size() - 1))
		quit(1)
		return
	var city: Dictionary = seat.sim.cities[city_i]
	road = int(city.road)
	sample = int(city.i) + off
	if at != "":
		road = int(at.split(",")[0])
		sample = int(at.split(",")[1])
	var R = seat.sim.roads[road]
	sample = clampi(sample, 2, R.N - 3)
	# face the way along the road that has the city ahead rather than behind
	var to_city := Vector2(city.cx - R.px[sample], city.cy - R.py[sample])
	dir = 1 if to_city.dot(Vector2(R.tx[sample], R.ty[sample])) >= 0.0 else -1
	print("CITY_JITTER %s from road %d (%s) sample %d, %.1f km from its middle; the Network's own numbers here: (%.1f, %.1f) km; %s, %s; fov %.0f, %s" % [
		city.name, road, R.name, sample, to_city.length() / 1000.0, R.px[sample] / 1000.0, R.py[sample] / 1000.0,
		outlook.time, outlook.weather, fov if bare else 70.0, "the world alone" if bare else "from the seat"])
	_pose(0.0)
	# Both streamers resolved before a picture is taken, and their props' fade in (1.8 s by the clock) over.
	for i in 5000:
		seat.network_world.sync(seat.sim.pod.x, seat.sim.pod.y)
		seat.landscape.sync(seat.sim.pod.x, seat.sim.pod.y)
		if i % 40 == 0:
			await process_frame
		if seat.landscape.pending.is_empty() and seat.landscape._job.is_empty() and seat.landscape._decor_job.is_empty() and i > 1200:
			break
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 2600 or not seat.landscape._deco_revealing.is_empty():
		_pose(0.0)
		seat._process(STEP)
		await process_frame
		if Time.get_ticks_msec() - began > 20000:
			break
	seat.cam.cull_mask &= ~UNSEEN
	if bare:
		# the world alone: the cockpit, the craft and the traffic are not what is being looked at, and a head's
		# millimetre moves a canopy rib three pixels
		for part in [seat.craft, seat.rig, seat.traffic_net, seat.dust, seat.cues]:
			if part != null:
				_bare.append_array(_undraw(part))
		seat.cam.fov = fov
	for frame in 60:
		_pose(0.0)
		seat._process(STEP)
		_aim(0.0, false, 0.0, 0.0)
		await process_frame
	for arg in args:
		if arg.begins_with("--time-against="):
			await _time_against(arg.trim_prefix("--time-against="))
			await _finish()
			return
	await _shot("base", 0.0, false, 0.0, 0.0, 3)
	if "--only-base" in args:
		await _finish()
		return
	await _shot("again", 0.0, false, 0.0, 0.0, 3)
	for d: float in ORIGIN_MOVES:
		await _shot("origin+%s" % _mm(d), d, true, 0.0, 0.0, 3)
	for d: float in HEAD_MOVES:
		await _shot("head+%s" % _mm(d), 0.0, false, d, 0.0, 3)
	# where each layer is in the picture: the base pose with it left undrawn
	var layers := {"towers": [], "landmarks": [seat.network_world.scenery], "props": []}
	for sk in seat.network_world.skylines:
		(layers.towers as Array).append(sk[0])
	for tile in seat.landscape.tiles.values():
		if tile.has("deco") and is_instance_valid(tile.deco):
			(layers.props as Array).append(tile.deco)
	for layer in layers:
		var undo := []
		for node in layers[layer]:
			if node != null:
				undo.append_array(_undraw(node))
		await _shot("off-" + layer, 0.0, false, 0.0, 0.0, 3)
		_redraw(undo)
	if "--no-sweeps" not in args:
		for k in SWEEP:
			await _shot("turn-%02d" % k, 0.0, false, 0.0, 0.008 * k, 2)
		for k in SWEEP:
			await _shot("creep-%02d" % k, k / 120.0, false, 0.0, 0.0, 2)
		for k in SWEEP:
			await _shot("speed-%02d" % k, 150.0 * k / 120.0, false, 0.0, 0.0, 2)
	await _shot("again-after", 0.0, false, 0.0, 0.0, 3)   # (the base pose once more: has anything drifted meanwhile?)
	await _finish()


func _time_against(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("--time-against: no shader at " + path)
		return
	var other := Shader.new()
	other.code = text
	var looks := []
	for sk in seat.network_world.skylines:
		for child in (sk[0] as Node).get_children():
			if child is GeometryInstance3D and (child as GeometryInstance3D).material_override is ShaderMaterial:
				looks.append((child as GeometryInstance3D).material_override)
	# (the shader as it is, read from its file as the other is: one made the same way, so that how the engine
	# came by a shader is not part of the difference)
	var mine: Shader = (looks[0] as ShaderMaterial).shader
	var now := Shader.new()
	now.code = FileAccess.get_file_as_string(mine.resource_path)
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var kept := {"now": [], "other": [], "none": []}
	for turn in 4:
		for variant in ["now", "other", "none"]:
			for look: ShaderMaterial in looks:
				look.shader = other if variant == "other" else now
			var undo := []
			if variant == "none":
				for sk in seat.network_world.skylines:
					undo.append_array(_undraw(sk[0]))
			var got := []
			for frame in 110:
				_pose(0.0)
				seat._process(STEP)
				if bare:
					for part in [seat.craft, seat.rig, seat.traffic_net, seat.dust, seat.cues]:
						if part != null:
							_bare.append_array(_undraw(part))
				_aim(0.0, false, 0.0, 0.0)
				await process_frame
				if frame >= 50:
					got.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			_redraw(undo)
			if turn > 0:
				got.sort()
				(kept[variant] as Array).append(got[got.size() / 2])
	for look: ShaderMaterial in looks:
		look.shader = mine
	var line := "CITY_JITTER timing, viewport GPU ms (%s, %s):" % [str(root.size), "four pixels for one" if root.scaling_3d_scale > 1.0 else "as the window"]
	for variant in kept:
		var rounds: Array = (kept[variant] as Array).duplicate()
		var told := ""
		for ms in rounds:
			told += " %.3f" % ms
		rounds.sort()
		line += "  %s [%s ] median %.3f" % [variant, told, rounds[rounds.size() / 2]]
	print(line)


func _finish() -> void:
	_redraw(_bare)
	await process_frame
	seat.free()
	quit()


func _redraw(undo: Array) -> void:
	for u in undo:
		if is_instance_valid(u[0]):
			(u[0] as VisualInstance3D).layers = u[1]


func _mm(d: float) -> String:
	return ("%dmm" % roundi(d * 1000.0)) if d < 1.0 else ("%dm" % roundi(d))


## The craft parked at the place, `along` m further on down its road.
func _pose(along: float) -> void:
	var R = seat.sim.roads[road]
	seat.sim.respawn_on(road, sample, dir, 0.0)
	for body in seat.sim.bodies:
		body.x += R.tx[sample] * dir * along
		body.y += R.ty[sample] * dir * along
	seat._ride.clear()


## The eye: at the seated eye's place, looking at the city. `hold`: kept where it was in the world while the
## craft (and so the floating origin) is `along` m further on; `right` m to its own right; turned `yaw` degrees.
func _aim(along: float, hold: bool, right: float, yaw: float) -> void:
	if not _aimed:
		_aimed = true
		seat.cam.position = Vector3.ZERO
		seat.cam.rotation = Vector3.ZERO
		_eye_at = seat.cam.global_position
		var city: Dictionary = seat.sim.cities[city_i]
		var target := Vector3(city.cx - seat.org_x, seat.network_world.scenery_ground_height + aim_up, -(city.cy - seat.org_y))
		if landmark >= 0 and seat.network_world.scenery != null:
			var marks: Array = (seat.network_world.scenery.landmarks as Array).duplicate()
			marks.sort_custom(func(a, b): return Vector2(a.x - seat.org_x, a.y - seat.org_y).length() < Vector2(b.x - seat.org_x, b.y - seat.org_y).length())
			var mark: Dictionary = marks[mini(landmark, marks.size() - 1)]
			target = Vector3(mark.x - seat.org_x, seat.network_world.scenery_ground_height + aim_up, -(mark.y - seat.org_y))
			print("CITY_JITTER aimed at the landmark %s, %.1f km off" % [(mark.node as Node).name, Vector2(mark.x - seat.org_x, mark.y - seat.org_y).length() / 1000.0])
		var flat := Vector3(target.x - _eye_at.x, 0.0, target.z - _eye_at.z).rotated(Vector3.UP, -deg_to_rad(bearing))
		_look = Basis.looking_at(Vector3(flat.x, target.y - _eye_at.y, flat.z), Vector3.UP)
	var R = seat.sim.roads[road]
	var at := _eye_at
	if hold:   # the world is drawn this much the other way when the origin moves on: go with it
		at += Vector3(-R.tx[sample] * dir * along, 0.0, R.ty[sample] * dir * along)
	seat.cam.global_transform = Transform3D(Basis(Vector3.UP, -deg_to_rad(yaw)) * _look, at + _look.x * right)


func _shot(name: String, along: float, hold: bool, right: float, yaw: float, frames: int) -> void:
	for frame in frames:
		_pose(along)
		seat._process(STEP)
		if bare:   # (again every frame: the terminal's lighting puts the cockpit back on its layers as the craft crosses its bounds)
			for part in [seat.craft, seat.rig, seat.traffic_net, seat.dust, seat.cues]:
				if part != null:
					_bare.append_array(_undraw(part))
		_aim(along, hold, right, yaw)
		if frame < frames - 1:
			await process_frame
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(name + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Couldn't save " + path)
	print("CITY_JITTER shot ", name)
	await process_frame


## Take a node and everything under it out of the eye's picture (some are shown again by their own sync each
## frame, so hiding is not enough): onto a layer its camera leaves out. (Not onto no layer: with lights about,
## by night, the renderer loses track of which light a part on no layer was paired with, and the run ends in
## a crash as the scene is freed.) -> [[part, the layers it had], ...]
func _undraw(node: Node) -> Array:
	var undo := []
	var parts: Array = node.find_children("*", "GeometryInstance3D", true, false)
	parts.append(node)
	for part in parts:
		if part is GeometryInstance3D and (part as VisualInstance3D).layers != UNSEEN:
			if (part as VisualInstance3D).layers & ~UNSEEN:
				undo.append([part, (part as VisualInstance3D).layers & ~UNSEEN])
			(part as VisualInstance3D).layers = UNSEEN
	return undo
