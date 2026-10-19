## Shade line gate (view/shade_line.gd): the private covered line off Eridanus' loop, as the
## course builds it (the sim's branch 0, tools/design_eridanus.py).
##   ribbon   the road's up turns 0 -> 180 -> 0 deg through the corkscrews (the sim's roll_at), never
##            faster than 90 deg/s at 1,200 mph
##   ground   no vertex of it below the ground, however the road is rolled (a 120 m road stood on
##            edge is 120 m tall: its centre climbs as it turns)
##   canopy   over exactly the sim's covered samples
##   gate     where it leaves the loop: shut (PRIVATE LINE) without the job, open with it, and shut
##            again for a pass the sim's gate shut (too fast); the loop's wall opens there for it
##   clear    no vertex within 250 m of the main road outside the junction zones; the gate's legs
##            and boom off the loop's road (nothing solid-looking where you can fly)
##   sign     on the job, a sign over the loop where the gate decides (its zone's start): under
##            1,250 mph there or it stays shut; none without the job
##   trees    none of the valley's trees or houses on it
##   shaders  every pow( in its shaders takes a clamped argument (MSAA extrapolates edge pixels)
## Prints SHADE LINE PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_shade_line.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const MPH := 2.236936
const CHECKS := 10
var fails := 0
var passed := 0
var views := []
var frames := 0


func _initialize() -> void:
	_view("")


## A view of Eridanus, flying `job` (its _ready, the build, runs at the next frame).
func _view(job: String) -> void:
	ViewScript.track_override = "eridanus"
	ViewScript.job_override = job
	var v = ViewScript.new()
	root.add_child(v)
	views.append(v)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_view("emergency")   # one at a time: the overrides are read at the build
	if frames < 6:
		return false
	ViewScript.track_override = ""
	ViewScript.job_override = ""
	var v = views[0]
	var sim = v.sim
	var sl = v.course_world.shade if v.course_world else null
	if sl == null:
		_check("the course builds the shade line", false)
		return _finish()
	var B = sim.branches[0]
	# ribbon: the road's up, as built, is the sim's roll
	var worst := 0.0
	var peak := 0.0
	for i in B.N:
		var ang: float = sl.normals[i].angle_to(Vector3.UP)
		worst = maxf(worst, absf(ang - sim.roll_at(1, i)))
		if i > 0:
			peak = maxf(peak, absf(sl.normals[i].angle_to(sl.normals[i - 1])) / B.len[i - 1] * 1200.0 / MPH)
	var mid: int = (B.covered.x + B.covered.y) / 2
	_check("ribbon: up %.1f deg at the split, %.1f under the canopy, %.1f at the join; the sim's roll to %.5f rad; turning at most %.1f deg/s at 1,200 mph" % [
			rad_to_deg(sl.normals[0].angle_to(Vector3.UP)), rad_to_deg(sl.normals[mid].angle_to(Vector3.UP)), rad_to_deg(sl.normals[B.N - 1].angle_to(Vector3.UP)), worst, rad_to_deg(peak)],
		sl.normals.size() == B.N and worst < 1e-4 and rad_to_deg(sl.normals[mid].angle_to(Vector3.UP)) > 179.9
		and rad_to_deg(sl.normals[0].angle_to(Vector3.UP)) < 0.1 and rad_to_deg(sl.normals[B.N - 1].angle_to(Vector3.UP)) < 0.1 and rad_to_deg(peak) <= 90.0)
	# every vertex, in sim (x, y) and height
	var lowest := INF
	var near := INF
	var top := -INF
	var grid := _main_grid(sim)
	for c in sl.chunks:
		var inner: bool = c[3] >= B.jz and c[4] <= B.N - 1 - B.jz
		for vert in _verts(c[0]):
			var p: Vector3 = vert
			lowest = minf(lowest, p.y)
			top = maxf(top, p.y)
			if inner:
				near = minf(near, _to_main(sim, grid, c[1] + p.x, c[2] - p.z))
	_check("ground: the lowest vertex %.2f m, the highest %.0f m (the canopy at %.0f m)" % [lowest, top, B.height], lowest > -0.1 and top < 2.0 * B.height + 20.0)
	_check("canopy: over samples %s (the sim's covered %s)" % [sl.canopy_range, B.covered], sl.canopy_range == B.covered)
	_check("clear: outside the junction zones the nearest vertex is %.0f m from the main road" % near, near >= 250.0)
	# the gate
	var vj = views[1]
	var slj = vj.course_world.shade
	slj.sync(vj.org_x, vj.org_y)
	var open_job: bool = slj.gate_open and slj.open_sign.visible and not slj.shut_sign.visible and not slj.barrier.visible
	vj.sim.gate[0] = false   # a pass too fast: the sim shut it
	slj.sync(vj.org_x, vj.org_y)
	var shut_fast: bool = not slj.gate_open and slj.shut_sign.visible and slj.barrier.visible
	vj.sim.gate[0] = null
	sl.sync(v.org_x, v.org_y)
	_check("gate at branch sample %d: shut without the job (%s), open on it (%s), shut for a pass taken too fast (%s); the loop's wall opens for it over %d samples" % [
			sl.gate_i, not sl.gate_open and sl.shut_sign.visible, open_job, shut_fast, v.course_world.wall_gaps],
		not sl.gate_open and sl.shut_sign.visible and not sl.open_sign.visible and sl.barrier.visible and open_job and shut_fast and v.course_world.wall_gaps > 10)
	# the gate stands off the loop's road: its legs and its boom's ends
	var worst_in := -INF
	var gi: int = sl.gate_i
	for lat in [-(B.w[gi] / 2.0 + 3.0), B.w[gi] / 2.0 + 3.0]:
		var x: float = B.px[gi] + B.nx[gi] * lat
		var y: float = B.py[gi] + B.ny[gi] * lat
		sim._nearest(x, y, B.from_i + gi, 60)
		worst_in = maxf(worst_in, sim._n_w / 2.0 - absf(sim._n_lat))   # > 0: on the loop's road
	_check("the gate at branch sample %d stands off the loop's road (its legs %.1f m outside it at the nearest)" % [gi, -worst_in], worst_in < -2.0)
	# the decision sign, on the job only
	var sj = vj.course_world.shade_sign
	var zone: int = posmod(B.from_i - B.jz, sim.N)
	var at_ok := false
	if sj:
		var p: Vector3 = (sj as Node3D).global_position
		var ox: float = p.x + vj.org_x
		var oy: float = -p.z + vj.org_y
		at_ok = Vector2(ox - sim.tpx[zone], oy - sim.tpy[zone]).length() < 300.0
	_check("on the job a sign over the loop where the gate decides (main sample %d: %s), none without the job (%s)" % [zone, at_ok, v.course_world.shade_sign],
		sj != null and at_ok and v.course_world.shade_sign == null)
	# the valley keeps off it
	var on_it := 0
	var bgrid := {}
	for i in range(0, B.N, 2):
		var k := Vector2i(floori(B.px[i] / 200.0), floori(B.py[i] / 200.0))
		if not bgrid.has(k):
			bgrid[k] = []
		bgrid[k].append(i)
	for s in v.verdant_world.spots:
		var k := Vector2i(floori(s.x / 200.0), floori(s.y / 200.0))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for i in bgrid.get(Vector2i(k.x + dx, k.y + dy), []):
					if Vector2(s.x - B.px[i], s.y - B.py[i]).length() < B.w[i] / 2.0 + 25.0:
						on_it += 1
	_check("trees: %d of the valley's %d trees and houses on the shade line" % [on_it, v.verdant_world.spots.size()], on_it == 0 and v.verdant_world.spots.size() > 1000)
	# shaders
	var src := FileAccess.get_file_as_string("res://view/shade_line.gd")
	var bad := []
	var n_pow := 0
	var rx := RegEx.new()
	rx.compile("res://[a-z_/]+\\.gdshader")
	var shaders := {}
	for m in rx.search_all(src):
		shaders[m.get_string()] = true
	for path in shaders:
		var s2 := FileAccess.get_file_as_string(path)
		var at := s2.find("pow(")
		while at >= 0:
			n_pow += 1
			var arg := s2.substr(at + 4, 6)
			if not (arg.begins_with("clamp(") or arg.begins_with("max(")):
				bad.append("%s: %s" % [path.get_file(), s2.substr(at, 30)])
			at = s2.find("pow(", at + 4)
	_check("shaders: %d of its own (%s), %d pow( calls, unclamped: %s" % [shaders.size(), shaders.keys(), n_pow, bad], shaders.size() > 0 and bad.is_empty())
	_check("built in %d chunks, %d of them clear of the junctions" % [sl.chunks.size(), sl.chunks.filter(func(c): return c[3] >= B.jz and c[4] <= B.N - 1 - B.jz).size()], sl.chunks.size() >= 8)
	return _finish()


func _finish() -> bool:
	var good: bool = fails == 0 and passed == CHECKS
	print("SHADE LINE ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return true


## Every vertex of a chunk's meshes, chunk-local (x, height, -y).
func _verts(node: Node) -> Array:
	var out := []
	for ch in node.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is ArrayMesh:
			var m: ArrayMesh = (ch as MeshInstance3D).mesh
			for s in m.get_surface_count():
				for p in m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					out.append((ch as MeshInstance3D).transform * p)
		out.append_array(_verts(ch))
	return out


func _main_grid(sim) -> Dictionary:
	var g := {}
	for i in sim.N:
		var k := Vector2i(floori(sim.tpx[i] / 1000.0), floori(sim.tpy[i] / 1000.0))
		if not g.has(k):
			g[k] = []
		g[k].append(i)
	return g


## Distance (m) from (x, y) to the main road's edge, near enough (samples 12 m apart).
func _to_main(sim, g: Dictionary, x: float, y: float) -> float:
	var k := Vector2i(floori(x / 1000.0), floori(y / 1000.0))
	var best := INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for i in g.get(Vector2i(k.x + dx, k.y + dy), []):
				best = minf(best, Vector2(x - sim.tpx[i], y - sim.tpy[i]).length() - sim.tw[i] / 2.0 - 6.0)
	return best


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
