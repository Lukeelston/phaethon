## The scenic roads (Luke, 2026-11-19: "a track that drives along the side of a mountain, with the
## beach on one side. Then maybe another with a massive vertical drop into the valley below ...
## Maybe they could run on either edge of the map"): tools/design_network.py's SCoast and SDrop,
## their land (view/network_scenic.gd), their edges and flanks (view/network_world.gd), their menu
## entries (release/release_config.gd).
##   roads     both on the Network, joined to their highways at both ends, on the map's two edges
##   coast     rolls between beach level and the headlands; the sea on its left the whole way, that
##             edge open (see-through); a mountain on its right, that edge walled
##   drop      climbs to a rim over 2,300 m up, then falls 1,900 m or more down a grade of 20-30%
##   land      the terrain's grid stays under both decks, and under the roads' own land beside them
##             (it stood out through the sea cliffs as a slab once)
##   piers     none where a road lies on its land; piers under the dive's viaduct
##   mesh      a coast chunk carries its open edge's ramp as its own surface, and its land
##   menu      Coast Road and The Drop start the Network on those roads, and a crash goes back there
##   flight    off the rim at 2,000 mph the craft stays on the deck all the way down
## Prints SCENIC ROADS PASS.
## Run: Godot_v4.7.1-stable_win64_console.exe --headless --path godot -s res://tests/test_scenic_roads.gd -- --mute
extends SceneTree

const View := preload("res://view/craft_view.gd")
const UI := preload("res://release/release_config.gd")
const CraftSimScript := preload("res://sim/craft_sim.gd")
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


func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.spot_override = ""
	View.best_dir = OS.get_user_data_dir().path_join("scenic_test_")
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var sim = v.sim
	var world = v.network_world
	var land = v.get("landscape")
	var scenic = world.scenic
	var coast := -1
	var drop := -1
	for r in sim.roads.size():
		if sim.roads[r].name == "SCoast":
			coast = r
		elif sim.roads[r].name == "SDrop":
			drop = r
	if coast < 0 or drop < 0 or land == null:
		check("the scenic roads and the land are there", false)
		quit(1)
		return
	var C = sim.roads[coast]
	var D = sim.roads[drop]
	var x_c := [INF, -INF]
	var x_d := [INF, -INF]
	for i in C.N:
		x_c = [minf(x_c[0], C.px[i]), maxf(x_c[1], C.px[i])]
	for i in D.N:
		x_d = [minf(x_d[0], D.px[i]), maxf(x_d[1], D.px[i])]
	check("both roads are on the Network, joined to their highways at both ends: the coast road %.0f km long by the west edge (x from %.0f km), the drop %.0f km by the east (x to %.0f km)" % [
		C.length / 1000.0, x_c[0] / 1000.0, D.length / 1000.0, x_d[1] / 1000.0],
		world._joined_at(coast, 0) and world._joined_at(coast, C.N - 1) and world._joined_at(drop, 0) and world._joined_at(drop, D.N - 1)
		and x_c[0] > 2000.0 and x_c[0] < 20000.0 and x_d[1] > 580000.0 and x_d[1] < 598000.0)
	# the coast: its heights, the sea on its left, the mountain on its right
	var lo := INF
	var hi := -INF
	var sea_n := 0
	var sea_ok := 0
	var wall_ok := 0
	for i in range(0, C.N, 16):
		if not scenic.sea_side(coast, i, true):
			continue
		var h: float = sim.net_height(coast, float(i))
		var left: PackedFloat32Array = scenic.row(coast, i, true)
		if left[6] - left[0] < 1.0:   # (no shelf: the road is on the shore itself)
			lo = minf(lo, h)
			hi = maxf(hi, h)
		sea_n += 1
		var far: float = left[left.size() - 2] + 400.0
		var q := Vector2(C.px[i] + C.nx[i] * far, C.py[i] + C.ny[i] * far)
		sea_ok += int(scenic.is_sea(q) and land.surface_at(q) <= scenic.SEA - 1.0 and scenic.open(coast, i, true) and left[left.size() - 1] < scenic.SEA)
		var right: PackedFloat32Array = scenic.row(coast, i, false)
		wall_ok += int(_flank_h(right, 1000.0) > h + 120.0 and not scenic.open(coast, i, false))
	check("the coast road rolls between the beach and the headlands: %.0f to %.0f m up along the shore" % [lo, hi], lo > 10.0 and lo < 35.0 and hi > 200.0 and hi < 260.0)
	check("the sea is on its left the whole way (%d of %d stations: water beyond the beach, that edge open)" % [sea_ok, sea_n], sea_n > 300 and sea_ok >= sea_n - 2)
	check("a mountain stands on its right (%d of %d stations: 120 m or more over the road a kilometre in, that edge walled)" % [wall_ok, sea_n], wall_ok >= sea_n * 9 / 10)
	# the drop: the rim and the dive
	var top := 0.0
	var top_i := 0
	var steepest := 0.0
	for i in D.N - 1:
		var h: float = sim.net_height(drop, float(i))
		if h > top:
			top = h
			top_i = i
		steepest = maxf(steepest, absf(sim.net_height(drop, float(i + 1)) - h) / D.len[i])
	var fall: float = top - sim.net_height(drop, float(mini(top_i + 584, D.N - 1)))   # 14 km on
	check("the drop: a rim %.0f m up, then %.0f m down in 14 km, %.0f%% at its steepest" % [top, fall, steepest * 100.0], top > 2300.0 and fall > 1900.0 and steepest > 0.2 and steepest < 0.3)
	var rim_i := top_i - 500
	var rim_left: PackedFloat32Array = scenic.row(drop, rim_i, true)
	var rim_right: PackedFloat32Array = scenic.row(drop, rim_i, false)
	var rim_h: float = sim.net_height(drop, float(rim_i))
	check("on the rim the land falls %.0f m away on the left and stands %.0f m over the road on the right" % [rim_h - _flank_h(rim_left, 1700.0), _flank_h(rim_right, 1700.0) - rim_h],
		rim_h - _flank_h(rim_left, 1700.0) > 1800.0 and _flank_h(rim_right, 1700.0) - rim_h > 400.0 and scenic.open(drop, rim_i, true) and not scenic.open(drop, rim_i, false))
	# the terrain under the decks, and under the roads' own land
	var under := 0
	var through := 0
	var samples := 0
	var where := {}
	for r in [coast, drop]:
		var R = sim.roads[r]
		for i in range(0, R.N, 6):
			if not scenic.on(r, i):
				continue
			var h: float = sim.net_height(r, float(i))
			var hw: float = R.w[i] / 2.0
			for f in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				under += int(land.surface_at(Vector2(R.px[i] + R.nx[i] * hw * f, R.py[i] + R.ny[i] * hw * f)) > h - 2.0)
				samples += 1
			for left in [false, true]:
				var pairs: PackedFloat32Array = scenic.row(r, i, left)
				var sgn := 1.0 if left else -1.0
				var data: Dictionary = scenic.roads[r]
				var run: float = (data.rl if left else data.rr)[i - int(data.first)]
				for off in [150.0, 400.0, 800.0, 1200.0]:   # (not the last few hundred metres, where the two are meant to meet)
					if hw + off > pairs[pairs.size() - 4] or (not scenic.sea_side(r, i, left) and off > run - 100.0):
						continue   # (past the waterline, the road's land is under the seabed; past its run, the country's own land takes over)
					var over: float = land.surface_at(Vector2(R.px[i] + R.nx[i] * sgn * (hw + off), R.py[i] + R.ny[i] * sgn * (hw + off))) - _flank_h(pairs, hw + off)
					if over > 0.5:
						through += 1
						var tag := "%s %s %d" % [R.name, "left" if left else "right", int(off)]
						where[tag] = [int(where.get(tag, [0, 0.0])[0]) + 1, maxf(float(where.get(tag, [0, 0.0])[1]), over)]
					samples += 1
	var coast_through := 0
	for tag in where:
		print("    through: %s: %d, by %.0f m at most" % [tag, where[tag][0], where[tag][1]])
		coast_through += int(where[tag][0]) if str(tag).begins_with("SCoast") else 0
	# (where the drop's plateau ends the land falls 2 km in 3: the grid cuts that corner here and there, rock through rock)
	check("the terrain's grid stays under both decks (%d places over them) and under the roads' own land (%d through it, none of them on the coast: %d), of %d read" % [under, through, coast_through, samples],
		under == 0 and coast_through == 0 and through < samples / 100)
	# piers
	var bench_piers := 0
	var bridge_piers := 0
	for i in range(0, C.N, 40):
		if scenic.on(coast, i):
			bench_piers += world.pillar_specs(coast, i).size()
	for i in range(0, D.N, 40):
		if scenic.bridged(drop, i):
			bridge_piers += world.pillar_specs(drop, i).size()
		elif scenic.on(drop, i):
			bench_piers += world.pillar_specs(drop, i).size()
	check("no piers where a road lies on its land (%d), piers under the dive's viaduct (%d)" % [bench_piers, bridge_piers], bench_piers == 0 and bridge_piers >= 6)
	# a coast chunk: its open ramp and its land
	var spot: Vector2i = View.scenic_spot("SCoast")
	var k: int = (int(scenic.roads[coast].first) + 1500) / world.CH
	var key := Vector2i(coast, k)
	if not world.chunks.has(key):
		world._build_chunk(coast, k)
	world._bank_work(Time.get_ticks_usec() + 5000000)
	var mesh: Mesh = ((world.chunks[key][0] as Node3D).get_node("road") as MeshInstance3D).mesh
	var has_glass := false
	var land_vertices := 0
	for s in mesh.get_surface_count():
		has_glass = has_glass or mesh.surface_get_material(s) == world._glass
		if mesh.surface_get_material(s) == land.material:
			land_vertices = mesh.surface_get_array_len(s)
	check("a coast chunk carries its open edge's ramp as a see-through surface and its own land (%d vertices of cliff, beach, mountainside and trees)" % land_vertices, has_glass and land_vertices > 400)
	# the menu
	var over: Array = UI.course_overrides("coast")
	var drop_spot: Vector2i = View.scenic_spot("SDrop")
	var s2 = CraftSimScript.new({"track": "network", "handling": "speed", "startRoad": spot.x, "startSample": spot.y})
	var started: bool = int(s2.pod.path) == coast and Vector2(s2.pod.x - C.px[spot.y], s2.pod.y - C.py[spot.y]).length() < 60.0
	for b in s2.bodies:
		b.x += 4000.0
	s2.respawn()
	var back: bool = int(s2.pod.path) == coast and Vector2(s2.pod.x - C.px[spot.y], s2.pod.y - C.py[spot.y]).length() < 60.0
	check("Coast Road and The Drop are on the menu and start the Network on their roads (%s, sample %d; SDrop sample %d); a restart goes back there" % [over, spot.y, drop_spot.y],
		UI.course_index("coast") >= 0 and UI.course_index("drop") >= 0 and over == ["network", "none", "SCoast"] and UI.course_overrides("network") == ["network", "none", ""]
		and spot.x == coast and drop_spot.x == drop and started and back and UI.course_for("network", "SDrop") == "drop")
	# off the rim at 2,000 mph
	var s3 = CraftSimScript.new({"track": "network", "handling": "speed", "startRoad": drop, "startSample": top_i - 60})   # (on the dive's own straight)
	for b in s3.bodies:
		b.vx = D.tx[top_i - 60] * 894.0
		b.vy = D.ty[top_i - 60] * 894.0
	var z0: float = s3.pod.z
	var worst_gap := 0.0
	var off := false
	var crashed := false
	for n in 9600:   # 20 s
		s3.step({"thrL": 0.6, "thrR": 0.6, "brkL": 0.0, "brkR": 0.0, "repair": false, "reignite": true}, 1.0 / 480.0)
		off = off or s3.pod.off_road or int(s3.pod.path) != drop
		for e in s3.events:
			crashed = crashed or str(e.get("type", "")) in ["crash", "wreck", "airborne"]
		s3.events.clear()
		if not off:
			s3._nearest_on(drop, s3.pod.x, s3.pod.y, s3.pod.hint, 4)
			# (the deck: its height, its edge's ramp, and round the banked bends after the dive the bank's lift where the craft is)
			worst_gap = maxf(worst_gap, absf(s3.pod.z - s3.P.rideH - s3.road_h(drop, float(s3._n_i) + s3._n_t) - s3.net_edge(D.w[s3._n_i], s3._n_lat).x
				- CraftSimScript.net_bank_lift(s3.roads[drop], int(s3._n_i), float(s3._n_t), float(s3._n_lat))))
	check("off the rim at 2,000 mph the craft rides the deck all the way down: %.0f m lower after 20 s, never more than %.2f m off it" % [z0 - s3.pod.z, worst_gap],
		not off and not crashed and z0 - s3.pod.z > 1500.0 and worst_gap < 1.0)
	print("SCENIC ROADS ", "PASS" if failures == 0 and checks == 11 else "FAIL (%d failed of %d)" % [failures, checks])
	v.free()
	quit(0 if failures == 0 and checks == 11 else 1)
