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
				# (a scenic road lies on its own land, high over the open ground: under its deck there, not under -0.49)
				var scenic_here: bool = v.network_world.scenic.on(r, i)
				var limit: float = v.sim.net_height(r, float(i)) - 2.0 if scenic_here else -0.49
				if land.surface_at(q) > limit:
					bad += 1
					if bad <= 6:
						print("  over a deck: %s sample %d side %.0f: land %.1f m, limit %.1f" % [road.name, i, side, land.surface_at(q), limit])
				samples += 1
	check("terrain triangles remain below real road decks and shoulders (%d samples)" % samples, bad == 0)
	var jump_clearance := INF
	for jump in v.sim.jumps:
		var launch: int = jump[0]
		var catch_road: int = jump[1]
		var end: int = v.sim.roads[launch].N-1
		var a: Vector2 = v.network_world._wxy(launch,end)
		var b: Vector2 = v.network_world._wxy(catch_road,0)
		var min_deck: float = minf(v.sim.net_height(launch,float(end)),v.sim.net_height(catch_road,0.0))
		var lateral := (b-a).normalized().orthogonal()
		for k in 41:
			for offset in [-400.0,0.0,400.0]:
				jump_clearance=minf(jump_clearance,min_deck-land.surface_at(a.lerp(b,float(k)/40.0)+lateral*offset))
	check("terrain stays below all20 launch-to-catch flight corridors (%.1f m)" % jump_clearance,jump_clearance>100.0)
	var pos := Vector2(300000, 300000)
	for k in 3000:
		land.sync(pos.x, pos.y)
	check("terrain streaming settles and stays bounded", land.pending.is_empty() and land.tiles.size() <= land.MAX_TILES)
	check("terrain extends at least 65km before eviction",land.RANGE*land.TILE>=65000)
	check("detailed roads stream beyond 25km",v.network_world.VIS>=25000)
	var far = v.network_world.far_roads
	# (110,000, from 100,000: the Helios road added about 370 km of far ribbon)
	check("distant roads cover every road without unbounded vertices",far!=null and far.vertex_count<110000 and far.pieces.size()>v.sim.roads.size())
	far.sync(pos.x,pos.y)
	var endpoint_error := 0.0
	var chord_intrusion := -INF
	for piece in far.pieces:
		var r: int = piece[2]
		var road = v.sim.roads[r]
		var vertices: PackedVector3Array = piece[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for end in 2:
			var i: int = piece[3+end]
			for side in 2:
				var index: int = side if end==0 else vertices.size()-2+side
				var actual: Vector3 = vertices[index]+piece[0].global_position+Vector3(pos.x,0,-pos.y)
				var expected: Vector3 = v.network_world._p(road,0,0,i,(side*2-1)*road.w[i]*0.5,v.sim.net_height(r,i)-far.UNDER_DECK)
				endpoint_error=maxf(endpoint_error,actual.distance_to(expected))
		var rows := vertices.size()/2
		for row in rows-1:
			var stride: int = piece[5]      # (its own: finer where a climb steepens fast, _stride)
			var start: int = piece[3]+row*stride
			var finish: int = mini(start+stride,piece[4])
			var mid: int = (start+finish)/2
			var u := float(mid-start)/maxi(1,finish-start)
			var normal := Vector3.UP
			if v.network_world.shaft.on(r,float(mid)): normal=v.network_world.shaft.at(r,float(mid))[5]
			for side in 2:
				var actual: Vector3=vertices[row*2+side].lerp(vertices[(row+1)*2+side],u)+piece[0].global_position+Vector3(pos.x,0,-pos.y)
				var expected: Vector3=v.network_world._p(road,0,0,mid,(side*2-1)*road.w[mid]*0.5,v.sim.net_height(r,mid))
				chord_intrusion=maxf(chord_intrusion,(actual-expected).dot(normal))
	check("distant road endpoints follow real carried geometry and floating origin",endpoint_error<0.15)
	check("coarse road chords stay below detailed decks (%.3f m)"%chord_intrusion,chord_intrusion<0.1)
	var wet_key := Vector2i(floori(300000/land.TILE),floori(100000/land.TILE))
	var water_a := Node3D.new()
	var water_b := Node3D.new()
	root.add_child(water_a)
	root.add_child(water_b)
	land._water(wet_key,water_a)
	land._water(wet_key+Vector2i.RIGHT,water_b)
	var phase_a = water_a.get_child(0).get_instance_shader_parameter("world_offset")
	var phase_b = water_b.get_child(0).get_instance_shader_parameter("world_offset")
	if phase_a == null: phase_a = Vector2.ZERO
	if phase_b == null: phase_b = Vector2.ZERO
	check("water has continuous world-space phase at tile boundary",(phase_a+Vector2(land.TILE/2,0)).distance_to(phase_b-Vector2(land.TILE/2,0))<0.01)
	water_a.free()
	water_b.free()
	var key: Vector2i = land.tiles.keys()[0]
	var tile = land.tiles[key]
	# (a tile's place is its own under the tiles' node, plus that node's: the node is what follows the craft)
	var original: Vector3 = land._tile_root.position + tile.node.position + Vector3(pos.x, 0, -pos.y)
	land.sync(pos.x + 1200, pos.y + 900)
	check("terrain has real parallax instead of following player", (land._tile_root.position + tile.node.position + Vector3(pos.x + 1200, 0, -pos.y - 900)).distance_to(original) < 0.01)
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
		# the growing things' three shapes (view/network_biome_props.gd): whole near the craft, far and distant beyond
		var lib = land.prop_library
		var shapes := []
		var fewer := true
		var outline := 0.0
		for kind in lib.far:
			var counts := [lib.triangles(lib.cache[kind]), lib.triangles(lib.far[kind]), lib.triangles(lib.distant[kind])]
			shapes.append("%s %d / %d / %d" % [kind, counts[0], counts[1], counts[2]])
			fewer = fewer and counts[1] * 2 < counts[0] and counts[2] < counts[1]
			if kind in lib.TREES:
				fewer = fewer and counts[2] * 2 <= counts[1] and counts[1] < lib.triangles(lib.proxy[kind])
			var whole: AABB = (lib.cache[kind] as Mesh).get_aabb()
			for other: Mesh in [lib.far[kind], lib.distant[kind]]:
				var box := other.get_aabb()
				outline = maxf(outline, absf(box.end.y - whole.end.y) / whole.end.y)
				outline = maxf(outline, absf(maxf(box.size.x, box.size.z) - maxf(whole.size.x, whole.size.z)) / maxf(whole.size.x, whole.size.z))
		check("all roadside kinds have a cheaper shape at each tier (whole / far / distant: %s)" % ", ".join(shapes), fewer and shapes.size() == 18)
		check("... that stand as tall and spread as wide as the whole one (off by %.0f%% at most)" % (outline * 100.0), outline < 0.25)
		var holder := Node3D.new()
		lib.batch(holder, "oak", [Transform3D.IDENTITY])
		var one := holder.get_child(0) as MultiMeshInstance3D
		var begun: bool = one.multimesh.mesh == lib.distant.oak
		lib.detail(one, 0)
		var near_whole: bool = one.multimesh.mesh == lib.cache.oak and one.material_override == lib.near_material
		lib.detail(one, 1)
		var mid_far: bool = one.multimesh.mesh == lib.far.oak
		lib.detail(one, 2)
		lib.batch(holder, "urban", [Transform3D.IDENTITY])
		lib.detail(holder.get_child(1), 2)
		check("a tile switches tree and building shapes in their original batches",
			begun and near_whole and mid_far and one.multimesh.mesh == lib.distant.oak and (holder.get_child(1) as MultiMeshInstance3D).multimesh.mesh == lib.distant.urban
			and land.PROP_NEAR < land.PROP_FAR)
		var dense: Array = []
		dense.resize(lib.near_limit.oak + 1)
		dense.fill(Transform3D.IDENTITY)
		var grove := Node3D.new()
		lib.batch(grove, "oak", dense)
		var trees := grove.get_child(0) as MultiMeshInstance3D
		lib.detail(trees, 0)
		check("dense nearby grove uses the untextured authored proxy in one batch", grove.get_child_count() == 1 and trees.multimesh.mesh == lib.proxy.oak and trees.material_override == lib.distance_material)
		check("shared close atlas has both its color and ORM textures", lib.near_material.get_shader_parameter("color_atlas") != null and lib.near_material.get_shader_parameter("orm_atlas") != null)
		grove.free()
		holder.free()
	if land.get("prop_library") != null:
		var count := 0
		var unsupported := 0
		var obstructing := 0
		var real_clearance := INF
		var mesh_support_error := 0.0
		var actual_meshes := {}
		var radii := {}
		# The circular envelope admits any yaw. Check actual vertices of every shape, including proxies.
		var single_surfaced := true
		for kind: String in land.prop_library.KINDS:
			var radius := 0.0
			for tier: Dictionary in [land.prop_library.cache, land.prop_library.proxy, land.prop_library.far, land.prop_library.distant]:
				var m: Mesh = tier[kind]
				single_surfaced = single_surfaced and m.get_surface_count() == 1
				for vtx: Vector3 in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					radius = maxf(radius, Vector2(vtx.x, vtx.z).length())
			radii[kind] = radius
		check("all 36 imported models and procedural silhouettes are single-surface", single_surfaced)
		var oversize := 0
		var shared_foundations := 0
		var buried_plazas := 0
		var reproducible := true
		var new_families := {}
		for region in land.REGIONS:
			var rk := Vector2i(floori(region[1].x / land.TILE), floori(region[1].y / land.TILE))
			var records: Array = land.prop_records(rk)
			reproducible = reproducible and records == land.prop_records(rk)
			# A region's central tile may be entirely occupied by the highway interchange.
			# Include its neighboring landscape, while retaining every placement check.
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				records.append_array(land.prop_records(rk+offset))
			check("region has characteristic plants or settlements: " + region[0], not records.is_empty())
			for prop in records:
				if prop.kind in ["service","wind","solar","basalt"]: new_families[prop.kind]=true
				count += 1
				oversize += int(radii[prop.kind] * prop.scale > prop.radius)
				for city: Dictionary in v.sim.cities:
					shared_foundations += int(prop.p.distance_to(Vector2(city.cx, city.cy)) < 8800.0 + prop.radius)
				for site: Dictionary in v.network_world.scenery.landmarks:
					shared_foundations += int(prop.p.distance_to(Vector2(site.x, site.y)) < 1700.0 + prop.radius)
				if prop.kind == "service":
					for sx in [-1, 0, 1]:
						for sz in [-1, 0, 1]:
							var corner := Vector2(sx * 116.0, sz * 81.5).rotated(prop.yaw) * float(prop.scale)
							var gap: float = prop.height + prop.lift - land.surface_at(prop.p + corner)
							buried_plazas += int(gap < 0.16 or gap >= 5.0 * prop.scale)
				unsupported += int(absf(prop.height - land.surface_at(prop.p)) > 0.01)
				var mk := Vector2i(floori(prop.p.x/land.TILE),floori(prop.p.y/land.TILE))
				if not actual_meshes.has(mk): actual_meshes[mk] = land.make_mesh(mk).surface_get_arrays(0)
				var data: Array = actual_meshes[mk]
				var local: Vector2 = prop.p-Vector2(mk)*land.TILE
				var cx := floori(local.x/land.STEP)
				var cy := floori(local.y/land.STEP)
				var frac: Vector2 = local/land.STEP-Vector2(cx,cy)
				var tri: int = (cy*land.GRID+cx)*6+(3 if frac.x+frac.y>1.0 else 0)
				var va: Vector3 = data[Mesh.ARRAY_VERTEX][data[Mesh.ARRAY_INDEX][tri]]
				var vb: Vector3 = data[Mesh.ARRAY_VERTEX][data[Mesh.ARRAY_INDEX][tri+1]]
				var vc: Vector3 = data[Mesh.ARRAY_VERTEX][data[Mesh.ARRAY_INDEX][tri+2]]
				var normal := (vb-va).cross(vc-va)
				var support := va.y-(normal.x*(local.x-va.x)+normal.z*(-local.y-va.z))/normal.y
				mesh_support_error=maxf(mesh_support_error,absf(support-prop.height))
				obstructing += int(not land.clear_at(prop.p, prop.radius))
				var pc := Vector2i(floori(prop.p.x/1000),floori(prop.p.y/1000))
				for dx in range(-1,2):
					for dy in range(-1,2):
						for sample in road_index.get(pc+Vector2i(dx,dy),[]):
							real_clearance = minf(real_clearance,prop.p.distance_to(sample[0])-sample[1]-prop.radius)
		check("props sit on the actual rendered triangles", unsupported == 0 and count > 300)
		check("intercity service courts, energy sites and basalt spires all placed",new_families.size()==4)
		check("independent mesh triangle planes support prop anchors (%.4f m)" % mesh_support_error,mesh_support_error<0.01)
		check("plaza pavement clears the terrain and each foundation still meets it", buried_plazas == 0)
		check("props stay outside the authored city and landmark compounds", shared_foundations == 0)
		check("all rendered vertices fit inside the protected footprint at every yaw and scale", oversize == 0)
		check("replaying the tile seed reproduces its props, positions, scales and facing", reproducible)
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

