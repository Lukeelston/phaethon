## Eridanus world gate: the dual-purpose course's trackside (view/course_world.gd) and the green
## valley round it (view/verdant_world.gd) hold together.
##   build       the course builds its own world: chunked trackside, the valley, three mountain
##               rings, the green ground and clearer air (no GP dressing); in a few seconds
##   chunks      every sample in a chunk; after a sync only the chunks near the pod are shown
##   zones       a STARFIGHTER zone at each town's mouth and a flashing SPEED AUTHORIZED sign where
##               the loop starts; braking boards 8 / 6 / 4 / 2 / 1 miles out, lit signs over the track,
##               their numbers in front of the face (they once sat inside the board, hidden)
##   bridges     the track crosses the river on short bridges, not along it
##   scenery     thousands of trees and dozens of houses, none within 25 m of a wall (the town
##               poplars stand at 30 m, the rest 120 m and more) or in the water
##   beacons     a fog-free glow on every speed-loop mast (240 m apart, 24 m up) and every other
##               town mast, lit by the speed guide, and a 200 m light column on every other
##               loop mast ("more vertically visible"), shown out to 40 km where the trackside
##               chunks stop at 16 (Luke: "make the walls of speedcraft much more visible from
##               further away")
##   ramps       covered halls over the loop's first and last 4 mi at each town (the sim's ramps):
##               over exactly those samples, their roofs above every board and sign, no light
##               columns through them (Luke: "reach speed inside of a structure before being exposed")
##   mountains   no ridge within 5 km of the track (the rings once cut the course's corners
##               and the track ran under the hills there)
## Prints ERIDANUS WORLD PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_eridanus_world.gd -- --mute
extends SceneTree

const ViewScript := preload("res://view/craft_view.gd")
const CW := preload("res://view/course_world.gd")
const VW := preload("res://view/verdant_world.gd")
const CHECKS := 10
const CELL := 400.0
var fails := 0
var passed := 0
var v
var frames := 0
var build_ms := 0
var t0 := 0


func _initialize() -> void:
	ViewScript.track_override = "eridanus"
	t0 = Time.get_ticks_msec()
	v = ViewScript.new()
	root.add_child(v)   # its _ready (the build) runs at the first frame


func _process(_d: float) -> bool:
	frames += 1
	if frames == 1:
		build_ms = Time.get_ticks_msec() - t0
	if frames < 4:
		return false
	ViewScript.track_override = ""
	var sim = v.sim
	var cw = v.course_world
	var vw = v.verdant_world
	_check("the course builds its own world in %d ms: %s, %d chunks, the valley, %d mountain rings, verdant ground %.0f, fog %.5f, no GP dressing" % [
			build_ms, sim.track_name, cw.chunks.size() if cw else 0, v.horizon.rings.size() if v.horizon else 0,
			v.ground_mat.get_shader_parameter("verdant"), _fog()],
		sim.course and sim.track_name == "eridanus" and cw != null and vw != null and v.gp_world == null
		and v.horizon.rings.size() == 3 and v.ground_mat.get_shader_parameter("verdant") == 1.0 and _fog() < 0.00035
		and build_ms < 20000)
	_chunks(sim, cw)
	_zones(sim, cw)
	_ramps(sim, cw)
	_bridges(sim, vw)
	_scenery(sim, vw)
	_beacons(sim, cw)
	_mountains(sim)
	var good: bool = fails == 0 and passed == CHECKS
	print("ERIDANUS WORLD ", "PASS" if good else "FAIL (%d failed, %d of %d passed)" % [fails, passed, CHECKS])
	quit(0 if good else 1)
	return true


func _fog() -> float:
	for c in v.get_children():
		if c is WorldEnvironment:
			return c.environment.fog_density
	return -1.0


func _chunks(sim, cw) -> void:
	var n_ok: bool = cw.chunks.size() == sim.N / CW.CHUNK or cw.chunks.size() == sim.N / CW.CHUNK + 1
	var shown := 0
	var wrong := 0
	for c in cw.chunks:
		var near: bool = Vector2(c[1] - v.org_x, c[2] - v.org_y).length() < CW.VIS
		shown += 1 if (c[0] as Node3D).visible else 0
		wrong += 0 if (c[0] as Node3D).visible == near else 1
	_check("%d chunks of %d samples hold all %d samples; %d shown round the pod at the start, %d wrongly shown or hidden" % [
			cw.chunks.size(), CW.CHUNK, sim.N, shown, wrong],
		n_ok and wrong == 0 and shown > 0 and shown < cw.chunks.size() / 2 and (cw.chunk_of(0)[0] as Node3D).visible)


func _zones(sim, cw) -> void:
	var sf := 0
	var sp := 0
	var ok := true
	for z in cw.zones:
		var i: int = z[0]
		var here: int = sim.tmode[i]
		var before: int = sim.tmode[posmod(i - 1, sim.N)]
		ok = ok and here != before and ((z[1] == "sf") == (here == 0))
		if z[1] == "sf":
			sf += 1
		else:
			sp += 1
	var signs := 0
	var said := 0
	for node in cw.find_children("*", "MeshInstance3D", true, false):
		if node.is_in_group("authorized"):
			signs += 1
			ok = ok and ((node as MeshInstance3D).material_override as ShaderMaterial).shader.code.contains("TIME")
	for node in cw.find_children("*", "Label3D", true, false):
		if cw.shade and cw.shade.is_ancestor_of(node):
			continue   # the shade line's gate says it too, when the job opens it (test_shade_line.gd)
		said += 1 if (node as Label3D).text == "SPEED AUTHORIZED" else 0
	_check("zones: %d STARFIGHTER (a town's mouth), %d SPEEDCRAFT (the loop's start), each on a mode change; %d flashing SPEED AUTHORIZED signs (%d labelled)" % [sf, sp, signs, said],
		ok and sf == 2 and sp == 2 and signs == sp and said == sp)
	# each board lit, its miles on a label in front of the lit face (they once sat inside the board)
	var faces := 0
	var labels_ok := true
	for node in cw.find_children("*", "MeshInstance3D", true, false):
		faces += 1 if node.is_in_group("board_face") else 0
	for node in cw.find_children("*", "Label3D", true, false):
		var l := node as Label3D
		if l.text.is_valid_int():
			labels_ok = labels_ok and int(l.text) in CW.BOARDS_MI and not l.double_sided and l.billboard == BaseMaterial3D.BILLBOARD_DISABLED
	_check("%d braking boards: %s miles before each town, over the track, %d lit faces, their numbers out in front" % [cw.boards, CW.BOARDS_MI, faces],
		cw.boards == sf * CW.BOARDS_MI.size() and faces == cw.boards and labels_ok)


func _ramps(sim, cw) -> void:
	var want := 0
	for r in sim.covered_ramps:
		want += int(r[1]) - int(r[0]) + 1
	var top := -INF
	for node in cw.find_children("*", "MeshInstance3D", true, false):
		if node.is_in_group("board_face") or node.is_in_group("authorized"):
			var q := (node as MeshInstance3D).mesh as QuadMesh
			top = maxf(top, (node as Node3D).position.y + q.size.y / 2.0 + 6.0)   # the face's top and its beacons
	_check("ramps: %d covered, halls over %d samples (the sim's %d), roofs %.0f m up, the highest board or sign %.0f m; %d ribs inside (one every %d samples), a lit strip down each wall; no stars in the afternoon (%s)" % [
			sim.covered_ramps.size(), cw.hall_samples, want, CW.RAMP_H, top, cw.hall_ribs, CW.HALL_RIB_EVERY, v.stars],
		sim.covered_ramps.size() == 4 and cw.hall_samples == want and top < CW.RAMP_H
		and cw.hall_ribs >= want / CW.HALL_RIB_EVERY - 4 and v.stars == null)


func _bridges(sim, vw) -> void:
	var longest := 0
	for b in vw.bridges:
		longest = maxi(longest, b[1] - b[0] + 1)
	_check("the track crosses the river on %d bridges, the longest %d samples (%.0f m)" % [vw.bridges.size(), longest, longest * 12.0],
		vw.bridges.size() >= 1 and vw.bridges.size() <= 6 and longest <= 30)


## Track samples in CELL-sized buckets, for the nearest-wall distance of each tree and house.
func _grid(sim) -> Dictionary:
	var g := {}
	for i in sim.N:
		var k := Vector2i(floori(sim.tpx[i] / CELL), floori(sim.tpy[i] / CELL))
		if not g.has(k):
			g[k] = []
		g[k].append(i)
	return g


## Metres from (x, y) to the nearer wall (negative: on the track); INF if no sample within CELL.
func _off_wall(sim, g: Dictionary, x: float, y: float) -> float:
	var best := INF
	var cx := floori(x / CELL)
	var cy := floori(y / CELL)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for i in g.get(Vector2i(cx + dx, cy + dy), []):
				var d: float = Vector2(x - sim.tpx[i], y - sim.tpy[i]).length() - sim.tw[i] / 2.0
				best = minf(best, d)
	return best


func _scenery(sim, vw) -> void:
	var g := _grid(sim)
	var closest := INF
	var wet := 0
	for p in vw.spots:
		closest = minf(closest, _off_wall(sim, g, p.x, p.y))
		if vw.water_dist(p.x, p.y) < VW.RIVER_W / 2.0 + 5.0:
			wet += 1
	var placed := 0
	for blk in vw.get_children():
		for mmi in blk.get_children():
			if mmi is MultiMeshInstance3D:
				placed += (mmi as MultiMeshInstance3D).multimesh.instance_count
	_check("scenery: %d trees and %d houses (%d instanced in all)" % [vw.trees, vw.houses, placed],
		vw.trees > 8000 and vw.houses > 40 and placed == vw.trees + vw.houses and vw.spots.size() == placed)
	_check("none of it within 25 m of a wall (closest %.1f m) or in the water (%d)" % [closest, wet],
		closest >= 25.0 and wet == 0)


func _beacons(sim, cw) -> void:
	var want := 0
	var want_cols := 0
	for i in sim.N:
		var sides := 2 - (1 if cw._gap[i] & 1 else 0) - (1 if cw._gap[i] & 2 else 0)   # none where the wall opens for the shade line
		if (sim.tmode[i] == 1 and i % CW.LOOP_MAST_EVERY == 0) or (sim.tmode[i] == 0 and i % 16 == 0):
			want += sides
		if sim.tmode[i] == 1 and i % (2 * CW.LOOP_MAST_EVERY) == 0 and sim.tcover[i] == 0:   # none through a ramp's roof
			want_cols += sides
	var lit := 0
	var wrong := 0
	for c in cw.lights:
		var d := Vector2(c[1] - v.org_x, c[2] - v.org_y).length()
		lit += 1 if (c[0] as Node3D).visible else 0
		wrong += 0 if (c[0] as Node3D).visible == (d < CW.BEACON_VIS) else 1
	var shown := 0
	for c in cw.chunks:
		shown += 1 if (c[0] as Node3D).visible else 0
	var mat: ShaderMaterial = ((cw.lights[0][0] as Node3D).get_node("beacons") as MeshInstance3D).material_override
	var code: String = mat.shader.code
	var re := RegEx.create_from_string("uniform float min_ang = ([0-9.]+);")
	var m := re.search(code)
	var ang := float(m.get_string(1)) if m else 0.0
	_check("beacons: %d (wanted %d: every loop mast and every other town mast) and %d light columns %.0f m tall (wanted %d: every other loop mast), %d chunks' worth lit round the start against %d chunks shown, %d wrongly; unfogged, never under %.4f rad" % [
			cw.beacons, want, cw.pylons, CW.PYLON_H, want_cols, lit, shown, wrong, ang],
		cw.beacons == want and cw.pylons == want_cols and CW.PYLON_H >= 150.0 and wrong == 0 and lit > shown and code.contains("fog_disabled") and code.contains("blend_add") and ang >= 0.004)


func _mountains(sim) -> void:
	# every vertex with any relief, bucketed; then each sample's 5 km neighbourhood
	var big := 5000.0
	var g := {}
	for mi in v.horizon.rings:
		var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in range(0, vs.size(), 3):
			var p: Vector3 = vs[k]
			if p.y < 1.0:
				continue
			var x: float = p.x + v.horizon.centre.x
			var y: float = -p.z + v.horizon.centre.y
			var key := Vector2i(floori(x / big), floori(y / big))
			if not g.has(key):
				g[key] = PackedVector2Array()
			g[key].append(Vector2(x, y))
	var nearest := INF
	for i in range(0, sim.N, 8):
		var q := Vector2(sim.tpx[i], sim.tpy[i])
		var cx := floori(q.x / big)
		var cy := floori(q.y / big)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for p in g.get(Vector2i(cx + dx, cy + dy), PackedVector2Array()):
					nearest = minf(nearest, q.distance_to(p))
	_check("mountains: the nearest ridge is %s from the track (wanted 5 km or more)" % ("over 5 km" if nearest == INF else "%.1f km" % (nearest / 1000.0)),
		nearest >= big)


func _check(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if ok:
		passed += 1
	else:
		fails += 1
