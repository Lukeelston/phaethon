## Real Network terrain, origin, clearance and stream regression gate.
extends SceneTree
const View := preload("res://view/craft_view.gd")
var checks := 0
var failures := 0
func check(label: String, ok: bool) -> void:
	checks += 1
	failures += int(not ok)
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("landscape_test_")
	var v = View.new()
	root.add_child(v)
	v.set_process(false)
	var land = v.get("landscape")
	check("Network replaces sprint strips and player-pinned mountain ring", land != null and v.horizon == null)
	if land == null:
		v.free()
		quit(1)
		return
	var families := {}
	for region in land.REGIONS:
		families[land.region_at(region[1])] = true
	check("all requested landscapes exist geographically", families.size() == land.REGIONS.size())
	v.network_world.sync(v.org_x,v.org_y)
	var foundation_error := 0.0
	for lm in v.network_world.scenery.landmarks:
		foundation_error = maxf(foundation_error,absf(lm.node.position.y-land.surface_at(Vector2(lm.x,lm.y))))
	check("authored landmarks rest on terrain foundations", foundation_error < 0.01)
	var seam := 0.0
	var bad := 0
	var samples := 0
	var road_index := {}
	for r in v.sim.roads.size():
		var road = v.sim.roads[r]
		for i in range(0, road.N, 8):
			var p: Vector2 = v.network_world._wxy(r, i)
			var rc := Vector2i(floori(p.x/1000),floori(p.y/1000))
			if not road_index.has(rc): road_index[rc] = []
			road_index[rc].append([p,road.w[i]*0.5])
			for side in [-1.0, 0.0, 1.0]:
				var q: Vector2 = p + Vector2(road.nx[i], road.ny[i]) * (road.w[i] * 0.5 + 80.0) * side
				bad += int(land.surface_at(q) > -0.49)
				samples += 1
	check("terrain triangles remain below real road decks and shoulders (%d samples)" % samples, bad == 0)
	var pos := Vector2(300000, 300000)
	for k in 1400:
		land.sync(pos.x, pos.y)
	check("terrain streaming settles and stays bounded", land.pending.is_empty() and land.tiles.size() <= land.MAX_TILES)
	var key: Vector2i = land.tiles.keys()[0]
	var tile = land.tiles[key]
	var original: Vector3 = tile.node.position + Vector3(pos.x, 0, -pos.y)
	land.sync(pos.x + 1200, pos.y + 900)
	check("terrain has real parallax instead of following player", (tile.node.position + Vector3(pos.x + 1200, 0, -pos.y - 900)).distance_to(original) < 0.01)
	var first: ArrayMesh = tile.node.get_child(0).mesh
	var rebuilt: ArrayMesh = land.make_mesh(key)
	check("recreated tiles reproduce exact vertices and colors", first.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == rebuilt.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] and first.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == rebuilt.surface_get_arrays(0)[Mesh.ARRAY_COLOR])
	for n in 17:
		var a: Vector3 = land.vertex_at(key, 16, n)
		var b: Vector3 = land.vertex_at(key + Vector2i.RIGHT, 0, n)
		seam = maxf(seam, (a + Vector3(key.x * land.TILE, 0, -key.y * land.TILE)).distance_to(b + Vector3((key.x + 1) * land.TILE, 0, -key.y * land.TILE)))
	check("neighboring terrain tiles meet exactly", seam < 0.01)
	check("regional vegetation and habitation are present", land.get("prop_library") != null)
	if land.get("prop_library") != null:
		var count := 0
		var unsupported := 0
		var obstructing := 0
		var real_clearance := INF
		for region in land.REGIONS:
			var rk := Vector2i(floori(region[1].x / land.TILE), floori(region[1].y / land.TILE))
			var records: Array = land.prop_records(rk)
			# A region's central tile may be entirely occupied by the highway interchange.
			# Include its neighboring landscape, while retaining every placement check.
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				records.append_array(land.prop_records(rk+offset))
			check("region has characteristic plants or settlements: " + region[0], not records.is_empty())
			for prop in records:
				count += 1
				unsupported += int(absf(prop.height - land.surface_at(prop.p)) > 0.01)
				obstructing += int(not land.clear_at(prop.p, prop.radius))
				var pc := Vector2i(floori(prop.p.x/1000),floori(prop.p.y/1000))
				for dx in range(-1,2):
					for dy in range(-1,2):
						for sample in road_index.get(pc+Vector2i(dx,dy),[]):
							real_clearance = minf(real_clearance,prop.p.distance_to(sample[0])-sample[1]-prop.radius)
		check("props sit on the actual rendered triangles", unsupported == 0 and count > 300)
		check("whole prop footprints clear the road protection field", obstructing == 0)
		check("props independently clear actual road samples with gap allowance (%.1f m)" % real_clearance, real_clearance>100.0)
	check("terrain and vegetation work is bounded per slice",land.max_slice_ms<6.0)
	var arr := first.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var downward := 0
	for i in range(0, idx.size(), 3):
		downward += int((verts[idx[i + 1]] - verts[idx[i]]).cross(verts[idx[i + 2]] - verts[idx[i]]).y >= 0)
	check("terrain triangles face upward", downward == 0)
	land.sync(520000, 500000)
	check("teleport evicts distant terrain immediately", not land.tiles.has(key) and land.tiles.size() <= land.MAX_TILES)
	print("LANDSCAPE metrics: %d road probes, %d protected vertices, %.2f ms worst slice" % [samples, land.clearance.size(), land.max_slice_ms])
	v.free()
	print("NETWORK LANDSCAPE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

