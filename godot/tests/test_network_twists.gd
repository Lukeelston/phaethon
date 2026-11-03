## Full rotations on recovery decks must carry the real road, craft and headset
## together, with upright joins, lateral clearance and continuous eye movement.
extends SceneTree
const View := preload("res://vr/vr_cockpit.gd")
const FlatView := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
var v
var failed := 0
var checks := 0
var prefs := {}

func _initialize() -> void:
	for path in [Settings.PREFS, View.PREFS]:
		prefs[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	FlatView.track_override = "network"
	FlatView.job_override = "none"
	FlatView.best_dir = OS.get_user_data_dir().path_join("test_twist_%d_" % Time.get_ticks_usec())
	v = View.new()
	root.add_child(v)
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	var mapper = v.network_world.shaft
	if not mapper.has_method("_build_twist"):
		check("twisted recovery decks exist", false)
		_finish()
		return
	var sim = v.sim
	var specs: Array = sim.twists
	check("at least four actual twisted routes", specs.size() >= 4)
	for spec in specs:
		var r := int(spec[0])
		var lo := int(spec[1])
		var hi := int(spec[2])
		var road = sim.roads[r]
		var worst_eye_step := 0.0
		var last_eye := Vector3.INF
		for k in 65:
			var f := lerpf(lo + 0.01, hi - 0.01, float(k) / 64.0)
			var i := int(f)
			for direction in [-1, 1]:
				sim.respawn_on(r, i, direction)
				for b in sim.bodies:
					b.x += road.tx[i] * (f - i) * road.len[i]
					b.y += road.ty[i] * (f - i) * road.len[i]
					sim._nearest_on(r, b.x, b.y, i, 12)
					b.hint = sim._n_i
					b.z = sim.net_height(r, sim._n_i + sim._n_t) + sim.P.rideH
				v._follow_origin()
				v.craft.sync(sim, v.inp, 1.0 / 60.0)
				v._ride.clear()
				v._place_camera(1.0)
				var frame: Basis = mapper.frame(r, f)
				var point: Vector3 = mapper.point(r, f, 0.0, 0.0, v.org_x, v.org_y)
				var eye: Vector3 = v.rig.transform * (v.origin.position + v.cam.position)
				var clearance := (eye - point).dot(frame.y)
				check("eyes stay above rolled road", clearance > 0.4 and clearance < 5.0)
				check("cockpit follows full roll", v.rig.basis.y.dot(frame.y) > 0.99)
				check("pod stays above rolled road", (v.craft.pod.position - point).dot(frame.y) > 0.5)
				if direction == 1:
					var eye_world := eye + Vector3(v.org_x, 0, -v.org_y)
					if last_eye != Vector3.INF:
						worst_eye_step = maxf(worst_eye_step, eye_world.distance_to(last_eye))
					last_eye = eye_world
			# Committed real road row agrees with the carried mapping, at all roll phases.
			var chunk: int = i / v.network_world.CH
			if not v.network_world.chunks.has(Vector2i(r, chunk)):
				v.network_world._build_chunk(r, chunk)
			var entry: Array = v.network_world.chunks[Vector2i(r, chunk)]
			var mesh: ArrayMesh = entry[0].get_node("road").mesh
			var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var section: Dictionary = v.network_world._section(road.w[i])
			for col in section.o.size():
				var expected: Vector3 = mapper.point(r, i, section.o[col], section.h[col] + 0.02, entry[1], entry[2])
				var actual := verts[(i % v.network_world.CH) * section.o.size() + col]
				check("real road mesh follows roll", actual.distance_to(expected) < 0.02)
		check("continuous sweep", worst_eye_step < (hi - lo) * 24.0 / 64.0 * 1.15)
		check("upright endpoints", mapper.frame(r, lo).y.y > 0.99 and mapper.frame(r, hi).y.y > 0.99)
		check("inverted midpoint", mapper.frame(r, (lo + hi) / 2.0).y.y < -0.99)
		for direction in [-1, 1]:
			_drive(spec, direction, 45.0 * direction)
	_finish()

func _drive(spec: Array, direction: int, offset: float) -> void:
	var sim = v.sim
	var r := int(spec[0])
	var lo := int(spec[1])
	var hi := int(spec[2])
	var R = sim.roads[r]
	var start := lo - 30 if direction > 0 else hi + 30
	sim.respawn_on(r, start, direction)
	v._ride.clear()
	v.craft.bank = [0.0, 0.0, 0.0]
	v.craft._lat = [0.0, 0.0, 0.0]
	for b in sim.bodies:
		b.x += R.nx[start] * offset
		b.y += R.ny[start] * offset
		b.vx = direction * 8000.0 / 2.236936 * R.tx[start]
		b.vy = direction * 8000.0 / 2.236936 * R.ty[start]
	var input := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "gearOverdrive": true}
	var minimum := INF
	var max_step_ratio := 0.0
	var previous := Vector3.INF
	var reached := false
	var samples := 0
	for frame in 1800:
		for sub in 8:
			sim.step(input, 1.0 / 480.0)
		v._follow_origin()
		v.craft.sync(sim, input, 1.0 / 60.0)
		v._place_camera(1.0)
		sim.events.clear()
		sim._nearest_on(r, sim.pod.x, sim.pod.y, sim.pod.hint, 12)
		var f: float = sim._n_i + sim._n_t
		var eye: Vector3 = v.cam.global_position
		var eye_world := eye + Vector3(v.org_x, 0, -v.org_y)
		if previous != Vector3.INF:
			var speed := Vector2(sim.pod.vx, sim.pod.vy).length()
			max_step_ratio = maxf(max_step_ratio, eye_world.distance_to(previous) / maxf(1.0, speed / 60.0))
		previous = eye_world
		if v.network_world.shaft.on(r, f):
			var road_point: Vector3 = v.network_world.shaft.point(r, f, sim._n_lat, 0.0, v.org_x, v.org_y)
			var normal: Vector3 = v.network_world.shaft.frame(r, f).y
			minimum = minf(minimum, (eye - road_point).dot(normal))
			samples += 1
		if (direction > 0 and f > hi + 20) or (direction < 0 and f < lo - 20):
			reached = true
			break
	check("actual 8000mph traversal exits twist", reached and samples > 50 and sim.pod.path == r)
	check("off-center moving eyes clear the rolled road", minimum > 0.5)
	check("no twist entry or exit teleport", max_step_ratio < 1.15)
	print("TWIST RIDE %s direction%d: %d samples, eye %.3fm, step ratio %.3f" % [R.name, direction, samples, minimum, max_step_ratio])

func _finish() -> void:
	for path in prefs:
		if prefs[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(prefs[path])
			file.close()
	DirAccess.remove_absolute(FlatView.best_dir + "network.json")
	print("NETWORK TWISTS %s (%d checks, %d failures)" % ["PASS" if failed == 0 else "FAIL", checks, failed])
	quit(int(failed > 0))
