## Regression for shaft contact at speed: use the real simulation, craft, cockpit and road-grid
## builder; measure signed clearance from the actual triangles under each body and the VR eye.
## No live XR session is required. Exact preference bytes are restored before exiting.
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const VrScript := preload("res://vr/vr_cockpit.gd")
const CM := preload("res://view/craft_model.gd")
const Settings := preload("res://release/game_settings.gd")
const DT := 1.0 / 480.0
const FD := 1.0 / 60.0
const MPH := 2.236936
var v
var frames := 0
var fails := 0
var saved := {}
var r := -1
var sh: Array
var distances := PackedFloat64Array()
var inp := {"thrL": 0.87, "thrR": 0.87, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true, "gearOverdrive": true}


func _initialize() -> void:
	for path in [Settings.PREFS, VrScript.PREFS]:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	ViewScript.track_override = "network"
	ViewScript.job_override = "none"
	ViewScript.best_dir = OS.get_user_data_dir().path_join("test_shaft_high_speed_%d_" % Time.get_ticks_usec())
	v = VrScript.new()
	root.add_child(v)


func _process(_delta: float) -> bool:
	frames += 1
	if frames != 3:
		return false
	v.set_process(false)
	v.set_partner(false)
	v.sim.P.obstacleCollisions = false
	for k in v.sim.roads.size():
		if v.sim.roads[k].name == "TE2+":
			r = k
	for item in v.sim.shafts:
		if int(item[0]) == r:
			sh = item
	distances.resize(v.sim.roads[r].N)
	for k in range(1, distances.size()):
		distances[k] = distances[k - 1] + v.sim.roads[r].len[k - 1]
	for mph in [4000.0, 8000.0, 12000.0, 20000.0]:
		for direction in [1, -1]:
			_ride(mph, direction)
	for path in saved:
		if saved[path] == null:
			DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(saved[path])
			f.close()
		_check("restore %s" % path, (not FileAccess.file_exists(path)) if saved[path] == null else FileAccess.get_file_as_bytes(path) == saved[path])
	DirAccess.remove_absolute(ViewScript.best_dir + "network.json")
	print("SHAFT HIGH SPEED ", "PASS" if fails == 0 else "FAIL (%d failed)" % fails)
	v.queue_free()
	quit(0 if fails == 0 else 1)
	return false


func _phase(f: float) -> String:
	if f <= float(sh[1]):
		return "entry"
	if f >= float(sh[2]):
		return "exit"
	var i := int(f)
	var d: float = distances[i] + (f - i) * v.sim.roads[r].len[i] - distances[int(sh[1])]
	var q: float = PI * float(sh[3]) / 2.0
	var h: float = sh[4]
	if d < q:
		return "pullup"
	if d < q + h:
		return "climb"
	if d < 3.0 * q + h:
		return "top"
	if d < 3.0 * q + 2.0 * h:
		return "roll"
	return "pullout"


## Ray against exactly the same vertices/triangles _road_row emits for the streamed mesh.
## The ray follows the local road normal, so inverted and sideways sections keep the same sign.
func _mesh_clearance(point: Vector3, f: float) -> float:
	var world = v.network_world
	var R = v.sim.roads[r]
	var i := clampi(int(f), 1, R.N - 3)
	var J := {"r": r, "ox": v.org_x, "oy": v.org_y, "u0": 0.0, "rv": PackedVector3Array(), "rn": PackedVector3Array(), "ru": PackedVector2Array(), "rows": 0, "cols": 0, "joins": false}
	var sec: Dictionary = world._section(R.w[i])
	for row in range(i - 1, i + 3):
		world._road_row(J, R, sec, row, v.sim.net_height(r, row))
	var normal := Vector3.UP
	if world.shaft.on(r, f):
		normal = world.shaft.at(r, f)[5]
	var indices: PackedInt32Array = world._grid_index(J.rows, J.cols)
	var best := INF
	for k in range(0, indices.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(point + normal * 100.0, -normal, J.rv[indices[k]], J.rv[indices[k + 1]], J.rv[indices[k + 2]])
		if hit != null:
			var distance: float = normal.dot(point - hit)
			if absf(distance) < absf(best):
				best = distance
	return best


func _ride(mph: float, direction: int) -> void:
	var sim = v.sim
	var R = sim.roads[r]
	var start: int = int(sh[1]) - 40 if direction > 0 else int(sh[2]) + 40
	sim.respawn_on(r, start, direction)
	v._ride.clear()
	v.craft._prev_v.clear()
	v.craft.bank = [0.0, 0.0, 0.0]
	v.craft._lat = [0.0, 0.0, 0.0]
	for b in sim.bodies:
		b.vx = direction * mph / MPH * R.tx[start]
		b.vy = direction * mph / MPH * R.ty[start]
	var phases := {}
	var reached_exit := false
	var worst_step_ratio := 0.0
	var worst_angle := 0.0
	var prev := Vector3.INF
	var prev_basis := Basis.IDENTITY
	var prev_org := Vector3.ZERO
	for frame in 60 * 50:
		for sub in 8:
			sim.step(inp, DT)
		v._follow_origin()
		v.craft.sync(sim, inp, FD)
		v._place_camera(1.0)
		sim.events.clear()
		if sim.pod.path != r:
			reached_exit = true
			break
		sim._nearest_on(r, sim.pod.x, sim.pod.y, sim.pod.hint, 12)
		var f: float = sim._n_i + sim._n_t
		var phase := _phase(f)
		if not phases.has(phase):
			phases[phase] = {"body": INF, "engine": INF, "floor": INF, "eye": INF, "max_body": -INF, "height_error": 0.0, "max_bank": 0.0, "mph": 0.0, "f": 0.0, "misses": 0}
		var stat: Dictionary = phases[phase]
		var speed: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
		var org := Vector3(v.org_x, 0.0, -v.org_y)
		if prev != Vector3.INF:
			var step: float = (v.craft.pod.position - prev + org - prev_org).length()
			worst_step_ratio = maxf(worst_step_ratio, step / maxf(speed * FD, 0.01))
			worst_angle = maxf(worst_angle, prev_basis.get_rotation_quaternion().angle_to(v.craft.pod.basis.get_rotation_quaternion()))
		prev = v.craft.pod.position
		prev_org = org
		prev_basis = v.craft.pod.basis
		# Sample every other render frame; still 30 Hz at every tested speed.
		if frame % 2 == 0:
			var body := _mesh_clearance(v.craft.pod.position, f)
			var floor := _mesh_clearance(v.rig.position, f)
			var eye := _mesh_clearance(v.cam.global_position, f)
			if not is_finite(body) or not is_finite(floor) or not is_finite(eye):
				stat.misses += 1
			stat.body = minf(stat.body, body)
			stat.max_body = maxf(stat.max_body, body)
			stat.floor = minf(stat.floor, floor)
			stat.eye = minf(stat.eye, eye)
			for k in 2:
				var b = sim.bodies[k]
				sim._nearest_on(r, b.x, b.y, b.hint, 12)
				var engine := _mesh_clearance(v.craft.engines[k].position, sim._n_i + sim._n_t)
				if not is_finite(engine):
					stat.misses += 1
				stat.engine = minf(stat.engine, engine)
			sim._nearest_on(r, sim.pod.x, sim.pod.y, sim.pod.hint, 12)
			var err: float = sim.pod.z - sim.net_height(r, f) - sim.net_edge(R.w[sim._n_i], sim._n_lat).x - sim.P.rideH
			if absf(err) > absf(stat.height_error):
				stat.height_error = err
				stat.mph = speed * MPH
				stat.f = f
		stat.max_bank = maxf(stat.max_bank, absf(v.craft.bank[2]))
		if (direction > 0 and f > float(sh[2]) + 20.0) or (direction < 0 and f < float(sh[1]) - 20.0):
			reached_exit = true
			break
	for phase in phases:
		var s: Dictionary = phases[phase]
		print("SHAFT %5.0f mph dir %+d %-7s body %.3f..%.3f engine %.3f floor %.3f eye %.3f height_error %.3f at %.1f mph f %.3f bank %.2f deg mesh misses %d" % [mph, direction, phase, s.body, s.max_body, s.engine, s.floor, s.eye, s.height_error, s.mph, s.f, rad_to_deg(s.max_bank), s.misses])
		_check("%.0f mph dir %d %s clear of mesh" % [mph, direction, phase], s.misses == 0 and s.body > 0.5 and s.engine > 0.5 and s.floor > 0.5 and s.eye > 1.0)
		_check("%.0f mph dir %d %s keeps ride height" % [mph, direction, phase], absf(s.height_error) < 0.05)
	print("SHAFT %5.0f mph dir %+d worst move / speed %.4f; largest attitude step %.3f deg; reached exit %s" % [mph, direction, worst_step_ratio, rad_to_deg(worst_angle), reached_exit])
	_check("%.0f mph dir %d reaches exit continuously" % [mph, direction], reached_exit and phases.size() == 7 and worst_step_ratio < 1.1 and worst_angle < deg_to_rad(20.0))


func _check(label: String, ok: bool) -> void:
	print(("  ok " if ok else "  FAIL ") + label)
	if not ok:
		fails += 1
