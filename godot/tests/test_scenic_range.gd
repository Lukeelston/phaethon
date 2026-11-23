## The Caucasus and the open edges' aprons (Luke, 2026-11-22: "Add a mountain road like the coastal
## road and the drop - One that winds through and over a mountain system. Extend the transparent edges
## on the coastal road and the drop so you can drive farther over the beach and ocean").
## tools/design_network.py's SCaucasus and apron_table, sim/craft_sim.gd's NET_APRONS and net_lat,
## view/network_world.gd's apron surface, release/release_config.gd's entries, view/pad_stations.gd's two.
##   road      on the Network between E2 and E1 by the south-east edge, joined at both ends
##   heights   the Col, the Cauldron, the Crest, the Span and the Shoulder, at their heights and in that order
##   land      a peak either side at the Col; a level floor in the Cauldron; nothing either side on the
##             Crest; a peak on the left and air on the right at the Shoulder; walls either side in the Chute
##   span      a viaduct over the gorge with piers under it, and none anywhere else on the road
##   grid      the terrain's grid stays under the deck and under the road's own land
##   aprons    150 m where a side is open on all three roads, none within 400 samples of an end, and
##             only where the views draw that edge open; net_lat takes the apron out of that side
##   parity    tools/record_aprons.js's runs replayed: the same pod to a millimetre, the same wall
##             contacts on the same steps; 80 m past the old wall the craft rides level, the new wall
##             turns it back 150 m further out, the closed side's wall is where it was
##   under     no land and no terrain stands up through an apron
##   mesh      a coast chunk draws its apron see-through from the old ramp's foot to 250 m out, and no
##             longer draws the ramp where it was
##   menu      The Caucasus is two start points on the Network, each with a pad station; a flight starts there
##   crest     set down 200 m out on the Crest's left apron the craft hovers at the deck's height, over nothing
## Prints SCENIC RANGE PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_scenic_range.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")
const CraftSimScript := preload("res://sim/craft_sim.gd")
const Stations := preload("res://view/pad_stations.gd")
const DT := 1.0 / 480.0
const WANT := 11
var checks := 0
var failures := 0


func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("  ok   " if ok else "  FAIL ") + label)


func _initialize() -> void:
	_run.call_deferred()


## The height of a flank row (scenic.row: pairs of m out from the centreline, height) `off` m out.
func _flank_h(pairs: PackedFloat32Array, off: float) -> float:
	for m in range(0, pairs.size() - 2, 2):
		if off <= pairs[m + 2]:
			return lerpf(pairs[m + 1], pairs[m + 3], clampf((off - pairs[m]) / maxf(0.01, pairs[m + 2] - pairs[m]), 0.0, 1.0))
	return pairs[pairs.size() - 1]


func _road(sim, road_name: String) -> int:
	for r in sim.roads.size():
		if sim.roads[r].name == road_name:
			return r
	return -1


## One of the recorder's runs flown here: [worst difference from its samples (m, m/s), the same roads and
## samples, the events the same, how far out it reached, the most it stood over the level deck].
func _replay(X: Dictionary, side: float) -> Array:
	var sim = CraftSimScript.new({"track": "network", "handling": "speed"})
	var r := int(X.start[0])
	var i := int(X.start[1])
	var R = sim.roads[r]
	sim.respawn_on(r, i, 1)
	var speed: float = X.speed
	for b in sim.bodies:
		b.x += R.nx[i] * side * float(X.off)
		b.y += R.ny[i] * side * float(X.off)
		b.vx = speed * R.tx[i] + float(X.drift) * side * R.nx[i]
		b.vy = speed * R.ty[i] + float(X.drift) * side * R.ny[i]
	var lev: float = X.lev
	var worst := 0.0
	var same := true
	var events := []
	var reach := -INF
	var high := 0.0
	var n := 0
	for k in int(float(X.secs) * 480.0):
		sim.step({"thrL": lev, "thrR": lev, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, DT)
		for e in sim.events:
			if str(e.type) in ["hit", "scrape", "crash", "binder", "airborne"]:
				events.append([k, str(e.type)])
		sim.events.clear()
		var p = sim.pod
		var q: int = p.hint
		var lat: float = ((p.x - R.px[q]) * R.nx[q] + (p.y - R.py[q]) * R.ny[q]) * side
		reach = maxf(reach, lat)
		sim._nearest_on(r, p.x, p.y, q, 4)      # (where it is along the road, as the view finds it: the sample its hover used may be the one behind)
		var f: float = float(sim._n_i) + float(sim._n_t)
		var apron: float = 0.0 if R.apl.is_empty() else float(R.apl[q] if side > 0.0 else R.apr[q])
		if lat < float(R.w[q]) / 2.0 + apron - CraftSimScript.net_edge_span(R.w[q]) - 1.0:      # (short of the ramp's foot: the level deck)
			high = maxf(high, absf(p.z - sim.P.rideH - sim.road_h(r, f)))
		if k % 240 == 239:
			var s: Array = X.samples[n]
			n += 1
			same = same and int(s[0]) == int(p.path) and int(s[1]) == int(p.hint)
			for pair in [[p.x, s[2]], [p.y, s[3]], [p.z, s[4]], [p.vx, s[5]], [p.vy, s[6]]]:
				worst = maxf(worst, absf(float(pair[0]) - float(pair[1])))
	var ev_same: bool = not X.has("events") or events.size() == (X.events as Array).size()
	if ev_same and X.has("events"):
		for k in events.size():
			ev_same = ev_same and int(events[k][0]) == int(X.events[k][0]) and events[k][1] == str(X.events[k][1])
	var kinds := {}
	for e in events:
		kinds[e[1]] = true
	return [worst, same, ev_same, reach, high, events.size(), ",".join(kinds.keys())]


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = ""
	View.best_dir = OS.get_user_data_dir().path_join("scenic_range_test_")
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var world = v.network_world
	var land = v.get("landscape")
	var scenic = world.scenic
	var range_r := _road(sim, "SCaucasus")
	var coast := _road(sim, "SCoast")
	var drop := _road(sim, "SDrop")
	if range_r < 0 or coast < 0 or drop < 0 or land == null or not scenic.roads.has(range_r):
		check("the Caucasus, the scenic roads and the land are there", false)
		print("SCENIC RANGE FAIL (no road)")
		quit(1)
		return
	var R = sim.roads[range_r]
	var D: Dictionary = scenic.roads[range_r]
	var first: int = D.first
	var last: int = D.last
	# the road
	var x := [INF, -INF]
	var y := [INF, -INF]
	for i in R.N:
		x = [minf(x[0], R.px[i]), maxf(x[1], R.px[i])]
		y = [minf(y[0], R.py[i]), maxf(y[1], R.py[i])]
	var e2 := _road(sim, "E2")
	var e1 := _road(sim, "E1")
	var joined := 0
	for J in sim.junctions:
		joined += int((int(J[0]) == e2 or int(J[0]) == e1) and int(J[3]) == range_r)
	check("the Caucasus is on the Network: %.0f km of road by the south-east edge (x %.0f to %.0f km), from E2 down to E1 (y %.0f to %.0f km), joined to each (%d junctions) and the last road made but Mount Hyperion's leaps' (%d of %d: a lane and a field for each leap come after it)" % [
		R.length / 1000.0, x[0] / 1000.0, x[1] / 1000.0, y[1] / 1000.0, y[0] / 1000.0, joined, range_r, sim.roads.size()],
		R.length > 240000.0 and R.length < 265000.0 and x[0] > 545000.0 and x[1] < 598000.0 and y[1] < 300000.0 and y[0] > 100000.0
		and world._joined_at(range_r, 0) and world._joined_at(range_r, R.N - 1) and joined == 2 and range_r == sim.roads.size() - 1 - 2 * sim.leaps.size())      # (push 36: the leaps' four roads are made after it, so it and every road before it keep their numbers)
	# its heights: the extremes, in order (a rise or fall of 150 m and more makes one)
	var marks := []          # [sample, height, 1 a top / -1 a bottom]
	var steepest := 0.0
	var run_hi := 0.0
	var run_hi_i := 0
	var run_lo := 0.0
	var run_lo_i := 0
	var way := 1
	var bends := 0.0
	for i in R.N - 1:
		var h: float = sim.net_height(range_r, float(i))
		steepest = maxf(steepest, absf(sim.net_height(range_r, float(i + 1)) - h) / R.len[i])
		bends += absf(atan2(R.tx[i] * R.ty[i + 1] - R.ty[i] * R.tx[i + 1], R.tx[i] * R.tx[i + 1] + R.ty[i] * R.ty[i + 1]))
		if way > 0:
			if h > run_hi:
				run_hi = h
				run_hi_i = i
			elif h < run_hi - 150.0:
				marks.append([run_hi_i, run_hi, 1])
				way = -1
				run_lo = h
				run_lo_i = i
		else:
			if h < run_lo:
				run_lo = h
				run_lo_i = i
			elif h > run_lo + 150.0:
				marks.append([run_lo_i, run_lo, -1])
				way = 1
				run_hi = h
				run_hi_i = i
	var want_marks := [[1720.0, 1], [1040.0, -1], [3260.0, 1], [2330.0, -1], [2560.0, 1]]
	var marks_ok: bool = marks.size() == want_marks.size()
	var told := []
	for k in marks.size():
		told.append("%s %.0f m at sample %d" % ["top" if int(marks[k][2]) > 0 else "bottom", marks[k][1], marks[k][0]])
		marks_ok = marks_ok and int(marks[k][2]) == int(want_marks[k][1]) and absf(float(marks[k][1]) - float(want_marks[k][0])) < 15.0
	check("it winds (%.0f degrees of bend in all) through and over the range: %s; %.1f%% at its steepest" % [rad_to_deg(bends), ", ".join(told), steepest * 100.0],
		marks_ok and steepest > 0.08 and steepest < 0.14 and rad_to_deg(bends) > 900.0)
	if not marks_ok:
		print("SCENIC RANGE FAIL (its heights are not the design's: the rest reads them)")
		v.free()
		quit(1)
		return
	var col: int = marks[0][0]
	var cauldron: int = marks[1][0]
	var crest: int = marks[2][0]
	var span: int = marks[3][0]
	var shoulder: int = marks[4][0]
	# its land
	var seen := []
	var land_ok := true
	for place in [["the Col", col, 300.0, 300.0, false, false], ["the Crest", crest, -900.0, -1300.0, true, true], ["the Shoulder", shoulder, 400.0, -900.0, false, true]]:
		var i: int = place[1]
		var h: float = sim.net_height(range_r, float(i))
		var left: float = _flank_h(scenic.row(range_r, i, true), 1600.0) - h
		var right: float = _flank_h(scenic.row(range_r, i, false), 1600.0) - h
		seen.append("%s (%.0f m up) %+.0f m on the left and %+.0f on the right, 1.5 km out" % [place[0], h, left, right])
		for side in [[left, float(place[2]), bool(place[4]), true], [right, float(place[3]), bool(place[5]), false]]:
			land_ok = land_ok and (float(side[0]) > float(side[1]) if float(side[1]) > 0.0 else float(side[0]) < float(side[1])) and scenic.open(range_r, i, bool(side[3])) == bool(side[2])
	var floor_left: float = _flank_h(scenic.row(range_r, cauldron, true), 700.0) - sim.net_height(range_r, float(cauldron))
	var floor_right: float = _flank_h(scenic.row(range_r, cauldron, false), 700.0) - sim.net_height(range_r, float(cauldron))
	var chute := shoulder + 1200
	var chute_h: float = sim.net_height(range_r, float(chute))
	var chute_left: float = _flank_h(scenic.row(range_r, chute, true), 1600.0) - chute_h
	var chute_right: float = _flank_h(scenic.row(range_r, chute, false), 1600.0) - chute_h
	check("its land: %s; the Cauldron's floor level with it (%+.0f, %+.0f m at 600 m); the Chute's walls %.0f and %.0f m over it" % ["; ".join(seen), floor_left, floor_right, chute_left, chute_right],
		land_ok and absf(floor_left) < 15.0 and absf(floor_right) < 15.0 and not scenic.open(range_r, cauldron, true) and not scenic.open(range_r, cauldron, false)
		and chute_left > 300.0 and chute_right > 300.0 and not scenic.open(range_r, chute, true) and not scenic.open(range_r, chute, false))
	# the Span and its piers
	var bridged := 0
	var bench_piers := 0
	var bridge_piers := 0
	for i in range(first, last + 1):
		bridged += int(scenic.bridged(range_r, i))
		if i % 40 == 0:
			if scenic.bridged(range_r, i):
				bridge_piers += world.pillar_specs(range_r, i).size()
			else:
				bench_piers += world.pillar_specs(range_r, i).size()
	var gorge: float = sim.net_height(range_r, float(span)) - _flank_h(scenic.row(range_r, span, true), 1500.0)
	check("the Span: %.1f km of viaduct %.0f m over the gorge's floor, on %d piers; none anywhere else on the road (%d)" % [bridged * 0.024, gorge, bridge_piers, bench_piers],
		bridged > 80 and bridged < 220 and gorge > 700.0 and bridge_piers >= 4 and bench_piers == 0 and scenic.bridged(range_r, span))
	# the terrain's grid under the deck and under the road's own land
	var under := 0
	var through := 0
	var samples := 0
	for i in range(first, last + 1, 6):
		var h: float = sim.net_height(range_r, float(i))
		var hw: float = R.w[i] / 2.0
		for f in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			under += int(land.surface_at(Vector2(R.px[i] + R.nx[i] * hw * f, R.py[i] + R.ny[i] * hw * f)) > h - 2.0)
			samples += 1
		for left in [false, true]:
			var pairs: PackedFloat32Array = scenic.row(range_r, i, left)
			var sgn := 1.0 if left else -1.0
			var run: float = (D.rl if left else D.rr)[i - first]
			for off in [150.0, 400.0, 800.0, 1200.0]:
				if hw + off > pairs[pairs.size() - 4] or off > run - 100.0:
					continue
				through += int(land.surface_at(Vector2(R.px[i] + R.nx[i] * sgn * (hw + off), R.py[i] + R.ny[i] * sgn * (hw + off))) - _flank_h(pairs, hw + off) > 0.5)
				samples += 1
	check("the terrain's grid stays under its deck (%d places over it) and under its own land (%d through it), of %d read" % [under, through, samples], under == 0 and through < samples / 100)
	# the aprons
	var told_aprons := []
	var aprons_ok := true
	var shut := 0
	var near_end := 0
	for r in [coast, drop, range_r]:
		var A = sim.roads[r]
		var widest := [0.0, 0.0]
		var length := [0, 0]
		aprons_ok = aprons_ok and A.apl.size() == A.N and A.apr.size() == A.N
		for i in A.N:
			for side in 2:
				var wide: float = (A.apr if side == 0 else A.apl)[i]
				if wide <= 0.0:
					continue
				widest[side] = maxf(widest[side], wide)
				length[side] += 1
				shut += int(not scenic.open(r, i, side == 1))
				near_end += int(i < 400 or i > A.N - 400)
		told_aprons.append("%s %.0f km on its left and %.0f km on its right (%.0f and %.0f m at most)" % [A.name, length[1] * 0.024, length[0] * 0.024, widest[1], widest[0]])
		aprons_ok = aprons_ok and widest[1] <= 150.0 and widest[0] <= 150.0
	var C = sim.roads[coast]
	var mid_c: int = (int(scenic.roads[coast].first) + int(scenic.roads[coast].last)) / 2
	var lat_ok: bool = (absf(CraftSimScript.net_lat(C, mid_c, 180.0) - 30.0) < 1e-9 and CraftSimScript.net_lat(C, mid_c, 100.0) == 0.0 and CraftSimScript.net_lat(C, mid_c, -50.0) == -50.0
		and CraftSimScript.net_edge(C.w[mid_c], CraftSimScript.net_lat(C, mid_c, 215.0)).x == 0.0
		and absf(CraftSimScript.net_edge(C.w[mid_c], CraftSimScript.net_lat(C, mid_c, 235.0)).x - CraftSimScript.net_edge(C.w[mid_c], 85.0).x) < 1e-9
		and CraftSimScript.net_lat(sim.roads[e2], 500, 180.0) == 180.0)
	check("the aprons: %s; %d of their samples are where the views draw the edge shut, %d within 400 samples of an end; the coast's sea side has one and its mountain side none; net_lat takes it out of that side only" % [
		"; ".join(told_aprons), shut, near_end],
		aprons_ok and shut == 0 and near_end == 0 and C.apl[mid_c] == 150.0 and C.apr[mid_c] == 0.0 and sim.roads[drop].apr.size() > 0 and sim.roads[e2].apl.is_empty() and lat_ok)
	# the recorder's runs
	var X: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/aprons_expected.json"))
	var worst := 0.0
	var same := true
	var by_tag := {}
	for run_x: Dictionary in X.runs:
		var got := _replay(run_x, float(run_x.side))
		worst = maxf(worst, float(got[0]))
		same = same and bool(got[1]) and bool(got[2])
		by_tag[str(run_x.tag)] = got
	var shut_x: Dictionary = X.closed
	var closed := _replay({"start": shut_x.start, "off": shut_x.off, "drift": shut_x.drift, "speed": shut_x.speed, "lev": shut_x.lev, "secs": shut_x.secs, "samples": shut_x.samples}, -1.0)
	worst = maxf(worst, float(closed[0]))
	same = same and bool(closed[1])
	check("flown as tools/record_aprons.js flew them (%d runs: the pod within %.9f of the JS sim's, the same samples and wall contacts %s): 180 m out on the coast's apron the craft rides level (%.3f m off the deck) and touches nothing (%d); drifting on it meets the wall %.1f m out (%d contacts) where it met it at %.1f m on the closed side; off the level deck at most %.3f m on the dive's apron and %.3f on the Caucasus'; where an apron opens the craft drifts out to %.0f m untouched (%d), where one closes it is turned back in (%d contacts: %s)" % [
		(X.runs as Array).size() + 1, worst, same, by_tag.cruise[4], by_tag.cruise[5], by_tag.wall[3], by_tag.wall[5], closed[3], by_tag["dive-right"][4], by_tag.caucasus[4],
		by_tag["ease-in"][3], by_tag["ease-in"][5], by_tag["ease-out"][5], by_tag["ease-out"][6]],
		worst < 1e-3 and same and float(by_tag.cruise[4]) < 0.1 and int(by_tag.cruise[5]) == 0 and absf(float(by_tag.cruise[3]) - 180.0) < 0.5
		and float(by_tag.wall[3]) > 240.0 and float(by_tag.wall[3]) < 250.0 and int(by_tag.wall[5]) > 0 and float(closed[3]) > 90.0 and float(closed[3]) < 100.0
		and float(by_tag["dive-right"][4]) < 1.0 and float(by_tag.caucasus[4]) < 0.3 and int(by_tag["ease-in"][5]) == 0
		and float(by_tag["ease-in"][3]) > 100.0 and int(by_tag["ease-out"][5]) > 0 and by_tag["ease-out"][6] == "scrape")
	# nothing stands up through an apron
	var poke := 0
	var read := 0
	for r in [coast, drop, range_r]:
		var A = sim.roads[r]
		for i in range(0, A.N, 6):
			var h: float = sim.net_height(r, float(i))
			var hw: float = A.w[i] / 2.0
			for left in [false, true]:
				var wide: float = (A.apl if left else A.apr)[i]
				if wide <= 0.0:
					continue
				var sgn := 1.0 if left else -1.0
				var pairs: PackedFloat32Array = scenic.row(r, i, left)
				for off in [hw - 20.0, hw + 10.0, hw + wide * 0.5, hw + wide - 2.0]:
					var q := Vector2(A.px[i] + A.nx[i] * sgn * off, A.py[i] + A.ny[i] * sgn * off)
					poke += int(land.surface_at(q) > h - 0.5) + int(off >= pairs[0] and _flank_h(pairs, off) > h - 0.5)
					read += 2
	check("no terrain and none of the roads' own land stands up through an apron (%d of %d places read)" % [poke, read], poke == 0 and read > 4000)
	# a coast chunk: its apron
	var k: int = mid_c / world.CH
	var key := Vector2i(coast, k)
	if not world.chunks.has(key):
		world._build_chunk(coast, k)
	world._bank_work(Time.get_ticks_usec() + 5000000)
	var mesh: Mesh = ((world.chunks[key][0] as Node3D).get_node("road") as MeshInstance3D).mesh
	var glass_out := [INF, -INF]
	var glass_tris := 0
	var paved_out := 0.0
	var high_at_edge := 0.0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if mesh.surface_get_material(s) == world._glass:
			glass_tris += idx.size() / 3
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for q in idx:
				glass_out = [minf(glass_out[0], uv[q].y), maxf(glass_out[1], uv[q].y)]
			if verts.size() % (world.EDGE_SEGS + 2) == 0:      # (the apron's own surface: each row its foot, then the ramp's points)
				high_at_edge = verts[world.EDGE_SEGS + 1].y - verts[0].y
		elif s == 0:
			for q in idx:
				paved_out = maxf(paved_out, uv[q].y)
	check("a coast chunk draws its sea side see-through from the old ramp's foot (%.1f m left of the centreline) to the wall %.1f m out, %d triangles; its pavement stops at %.1f m; the ramp's top is %.1f m up" % [
		glass_out[0], glass_out[1], glass_tris, paved_out, high_at_edge],
		absf(float(glass_out[0]) - 70.0) < 0.01 and absf(float(glass_out[1]) - 250.0) < 0.01 and glass_tris >= (world.CH - 1) * 14 and absf(paved_out - 70.0) < 0.01 and absf(high_at_edge - 3.9) < 0.05)
	# the menu, the start points, the pads
	var spot: Vector2i = View.scenic_spot("SCaucasus")
	var ids := []
	for entry in UI.INSERTIONS:
		ids.append(String(entry[0]))
	var crest_spot: Array = View.start_spot("SCaucasus@4534")
	var crest_listed := false
	for entry in UI.INSERTIONS:
		crest_listed = crest_listed or (String(entry[0]) == "crest" and String(entry[2]) == "SCaucasus@4534")
	var s2 = CraftSimScript.new({"track": "network", "handling": "speed", "startRoad": spot.x, "startSample": spot.y})
	var started: bool = int(s2.pod.path) == range_r and Vector2(s2.pod.x - R.px[spot.y], s2.pod.y - R.py[spot.y]).length() < 60.0
	var crest_h: float = sim.net_height(range_r, 4534.0)
	var crest_grade: float = absf(sim.net_height(range_r, 4535.0) - sim.net_height(range_r, 4533.0)) / 48.0
	var stations := 0
	for id in ["caucasus", "crest"]:
		if Stations.LEGENDS.has(id):
			var made: ArrayMesh = Stations.new().make(id, Transform3D.IDENTITY, Vector3(0.0, 0.0, 6.0), 30.0)
			stations += int(made != null and made.get_surface_count() == 2 and made.surface_get_array_len(0) > 100)
	check("The Caucasus is two start points on the Network (the foot, sample %d on level ground %.0f m up; the crest, sample 4534, %.0f m up and level to %.2f%%), each with its pad station (%d); a flight starts there; the road is named %s, %s" % [
		spot.y, sim.net_height(range_r, float(spot.y)), crest_h, crest_grade * 100.0, stations, world.SCENIC_NAMES.get("SCaucasus", "?"), world.SCENIC_ROUTES.get("SCaucasus", "?")],
		ids.has("caucasus") and ids.has("crest")
		and spot.x == range_r and sim.net_height(range_r, float(spot.y)) < 5.0 and crest_spot == [range_r, 4534, 1] and crest_listed and crest_h > 3250.0 and crest_grade < 0.005
		and stations == 2 and started and world.SCENIC_NAMES.has("SCaucasus") and world.SCENIC_ROUTES.get("SCaucasus", "") == "S23")
	# on the Crest, out over nothing
	var s3 = CraftSimScript.new({"track": "network", "handling": "speed"})
	s3.respawn_on(range_r, 4600, 1)
	for b in s3.bodies:
		b.x += R.nx[4600] * 200.0
		b.y += R.ny[4600] * 200.0
	var held := true
	var sag := 0.0
	for n in 960:
		s3.step({"thrL": 0.0, "thrR": 0.0, "brkL": 1.0, "brkR": 1.0, "repair": false, "reignite": true}, DT)
		held = held and not s3.pod.off_road and int(s3.pod.path) == range_r
		sag = maxf(sag, absf(s3.pod.z - s3.P.rideH - s3.road_h(range_r, s3._road_f(s3.pod))))
		s3.events.clear()
	var out_now: float = (s3.pod.x - R.px[4600]) * R.nx[4600] + (s3.pod.y - R.py[4600]) * R.ny[4600]
	var below: float = sim.net_height(range_r, 4600.0) - _flank_h(scenic.row(range_r, 4600, true), 300.0)
	check("set down %.0f m to the left on the Crest, at sample 4600 (the old wall stood at 100) the craft hovers at the deck's height for 2 s (%.3f m off it at most), still on the road, the land %.0f m below it; the apron there is %.0f m on the left and %.0f on the right" % [
		out_now, sag, below, R.apl[4600], R.apr[4600]],
		held and sag < 0.05 and out_now > 190.0 and out_now < 210.0 and below > 150.0 and R.apl[4600] == 150.0 and R.apr[4600] == 150.0)
	print("SCENIC RANGE ", "PASS" if failures == 0 and checks == WANT else "FAIL (%d failed of %d)" % [failures, checks])
	v.free()
	quit(0 if failures == 0 and checks == WANT else 1)
