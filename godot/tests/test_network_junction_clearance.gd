## Junction shoulders must not protrude above the adjoining road's drivable surface.
## Uses the generated country and real committed mesh, not the wall-opening predicate.
## Also probes triangle interiors/deco on both roads, compares the bounded nearest search
## against a wide reference throughout the country, and resolves real body road/contact state.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
var sim
var world

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	sim = Sim.new({"track": "network", "handling": "speed"})
	world = World.new()
	root.add_child(world)
	world.build(sim, null)
	# The countdown for the initial streaming pass can expire between
	# registering a chunk and committing its road mesh.
	if not world._job.is_empty():
		world._work(Time.get_ticks_usec() + 60000000)
	var bad := 0
	var checked := 0
	var worst := 0.0
	for j in sim.junctions:
		var r := int(j[3])
		var R = sim.roads[r]
		if not R.name.begins_with("R11") and R.role != "on":
			continue
		var q := int(j[0])
		var c0 := int(j[4])
		var c1 := int(j[5])
		for i in range(c0, c1 + 1, 8):
			var key := Vector2i(r, mini(i / World.CH, (R.N - 2) / World.CH))
			if not world.chunks.has(key):
				world._build_chunk(key.x, key.y)
			var entry: Array = world.chunks[key]
			var mesh: ArrayMesh = (entry[0].get_node("road") as MeshInstance3D).mesh
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for p in vertices:
				var x: float = p.x + entry[1]
				var y: float = -p.z + entry[2]
				var u := float(i - c0) / maxf(1.0, c1 - c0)
				var hint := roundi(lerpf(j[1], j[2], u if int(j[6]) > 0 else 1.0 - u))
				sim._nearest_on(q, x, y, hint, 80)
				# The broad flat highway interior is unambiguously drivable. Raised ramp
				# vertices here form the mesh the pilot currently has to drive through.
				if sim._n_off or absf(sim._n_lat) > sim._n_w / 2.0 - 65.0:
					continue
				var h: float = sim.net_height(q, sim._n_i + sim._n_t)
				if absf(h - sim.net_height(r, float(i))) > 2.0:
					continue
				checked += 1
				var intrusion := p.y - h
				worst = maxf(worst, intrusion)
				if intrusion > 0.25:
					bad += 1
		print("JOIN %s -> %s %s" % [R.name, sim.roads[q].name, j])
	print("junction flat-lane clearance: %d vertices checked, %d obstructing, worst %.3f m" % [checked, bad, worst])
	var search := _check_search()
	var triangles := _check_triangles()
	var drive := _check_drive()
	var good := checked > 500 and bad == 0 and search and triangles and drive
	print("NETWORK JUNCTION CLEARANCE ", "PASS" if good else "FAIL")
	quit(0 if good else 1)

func _check_search() -> bool:
	var n := 0
	var mismatched := 0
	var error := 0.0
	for j in sim.junctions:
		for reverse in [false, true]:
			var r := int(j[0]) if reverse else int(j[3])
			var lo := int(j[1]) if reverse else int(j[4])
			var hi := int(j[2]) if reverse else int(j[5])
			var R = sim.roads[r]
			for i in range(maxi(0, lo - 4), mini(R.N - 1, hi + 4) + 1, 8):
				for fraction in [-1.0, -0.9, -0.8, -0.7, 0.7, 0.8, 0.9, 1.0]:
					var off: float = R.w[i] / 2.0 * fraction
					var actual: Vector4 = world._joined_surface(r, i, off)
					var expected := INF
					for ji in R.sjx:
						var J: Array = sim.surface_junctions[ji]
						var on_a := int(J[0]) == r
						var z0 := int(J[1]) if on_a else int(J[4])
						var z1 := int(J[2]) if on_a else int(J[5])
						if i < z0 - 4 or i > z1 + 4:
							continue
						var q := int(J[3]) if on_a else int(J[0])
						var target_lo := int(J[4]) if on_a else int(J[1])
						var target_hi := int(J[5]) if on_a else int(J[2])
						var hint := (target_lo + target_hi) / 2
						# Transfer merges can span more than 600 samples. Cover the whole
						# interval: a truncated interior search can mistake its artificial
						# endpoint for pavement thousands of metres from the actual point.
						var reach := maxi(150, (target_hi - target_lo + 1) / 2 + 8)
						sim._nearest_on(q, R.px[i] + R.nx[i] * off, R.py[i] + R.ny[i] * off, hint, reach)
						if not sim._n_off and absf(sim._n_lat) < sim._n_w / 2.0 - 1.0:
							expected = minf(expected, sim.net_height(q, sim._n_i + sim._n_t) + Sim.net_edge(sim._n_w, sim._n_lat).x)
					n += 1
					if is_inf(actual.x) != is_inf(expected):
						mismatched += 1
						if mismatched < 4:
							print("SEARCH MISMATCH %s sample %d offset %.1f actual %s expected %s" % [R.name, i, off, actual.x, expected])
					elif not is_inf(expected):
						error = maxf(error, absf(actual.x - expected))
	print("junction search: %d offsets across all joins, %d corridor mismatches, max height error %.6f m" % [n, mismatched, error])
	return mismatched == 0 and error < 0.001

func _check_triangles() -> bool:
	var probes := 0
	var obstructed := 0
	var high := 0.0
	for j in sim.junctions:
		var child := int(j[3])
		if sim.roads[child].name != "R11WN" and sim.roads[child].name != "OEridanus":
			continue
		for reverse in [false, true]:
			var r := int(j[0]) if reverse else child
			var q := child if reverse else int(j[0])
			var lo := int(j[1]) if reverse else int(j[4])
			var hi := int(j[2]) if reverse else int(j[5])
			var hint := (int(j[4]) + int(j[5])) / 2 if reverse else (int(j[1]) + int(j[2])) / 2
			for chunk in range(lo / World.CH, mini(hi / World.CH, (sim.roads[r].N - 2) / World.CH) + 1):
				var key := Vector2i(r, chunk)
				if not world.chunks.has(key):
					world._build_chunk(r, chunk)
				var entry: Array = world.chunks[key]
				var mesh: ArrayMesh = (entry[0].get_node("road") as MeshInstance3D).mesh
				for surface in mini(mesh.get_surface_count(), 2): # asphalt and concrete/edge lines
					var arrays := mesh.surface_get_arrays(surface)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var indices := PackedInt32Array()
					if arrays[Mesh.ARRAY_INDEX] != null:
						indices = arrays[Mesh.ARRAY_INDEX]
					if indices.is_empty():
						for index in verts.size():
							indices.append(index)
					for ti in range(0, indices.size(), 3):
						var a := verts[indices[ti]]
						var b := verts[indices[ti + 1]]
						var c := verts[indices[ti + 2]]
						for p in [(a + b) / 2.0, (a + b + c) / 3.0]:
							sim._nearest_on(q, p.x + entry[1], -p.z + entry[2], hint, 150)
							if sim._n_off or absf(sim._n_lat) > sim._n_w / 2.0 - 65.0:
								continue
							var intrusion: float = p.y - sim.net_height(q, sim._n_i + sim._n_t)
							if intrusion < -0.25 or intrusion > 12.0:
								continue # underside or intentional overhead structure
							probes += 1
							high = maxf(high, intrusion)
							if intrusion > 0.25:
								obstructed += 1
								if obstructed < 4:
									print("TRIANGLE %s -> %s surface %d intrudes %.3f m" % [sim.roads[r].name, sim.roads[q].name, surface, intrusion])
	print("junction triangles: %d asphalt/deco interior probes, %d obstructing, worst %.3f m" % [probes, obstructed, high])
	return probes > 500 and obstructed == 0

func _check_drive() -> bool:
	var contacts := 0
	var error := 0.0
	var n := 0
	for j in sim.junctions:
		var r := int(j[3])
		var R = sim.roads[r]
		if R.name != "R11WN" and R.name != "OEridanus":
			continue
		for i in range(int(j[4]), int(j[5]) + 1, 2):
			sim.respawn_on(r, i, 1)
			var b = sim.pod
			sim._collide_walls(b, [[b.x, b.y, 2.0]], 1.0 / 480.0)
			if b.contact[0]:
				contacts += 1
			var ride: Vector2 = sim.surface_at(b.x, b.y, b.hint, b.path)
			error = maxf(error, absf(ride.x - sim.net_height(r, float(i))))
			n += 1
	print("junction drive: %d real body placements, %d wall contacts, max centreline surface error %.3f m" % [n, contacts, error])
	return n > 100 and contacts == 0 and error < 0.25
