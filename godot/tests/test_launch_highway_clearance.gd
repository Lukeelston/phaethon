## The launch and its source highway share pavement after their ramp has curved away.
## Probe committed asphalt/deco on BOTH roads at five stations on EVERY launch.
## Internal walls must be open to the real body; the exposed outer walls must remain solid.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const STATIONS := [0.0, 500.0, 1000.0, 1500.0, 2000.0]
const DT := 1.0 / 480.0
var sim
var world
var failures := 0
var probes := 0
var obstructions := 0
var internal_walls := 0
var outer_walls := 0
var worst := 0.0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)

func _parent_sample(j: Array, child: int) -> int:
	var u := float(child - int(j[4])) / maxf(1.0, float(int(j[5]) - int(j[4])))
	return roundi(lerpf(float(j[1]), float(j[2]), u if int(j[6]) > 0 else 1.0 - u))

func _run() -> void:
	sim = Sim.new({"track": "network", "handling": "speed"})
	world = World.new()
	root.add_child(world)
	world.build(sim, null)
	_check("all interchange and Mesa launches are present", sim.jumps.size() == 21)
	for jump in sim.jumps:
		var launch := int(jump[0])
		var L = sim.roads[launch]
		var fork: Array = []
		for ji in L.jx:
			var j: Array = sim.junctions[ji]
			if int(j[3]) == launch and int(j[4]) == 0 and sim.roads[int(j[0])].name.begins_with("R"):
				fork = j
		_check(L.name + " keeps its ramp fork", not fork.is_empty())
		if fork.is_empty():
			continue
		var ramp := int(fork[0])
		var R = sim.roads[ramp]
		var mouth: int = 0 if int(fork[6]) > 0 else R.N - 1
		var entrance: Array = []
		for ji in R.jx:
			var j: Array = sim.junctions[ji]
			if int(j[3]) == ramp and int(j[4]) <= mouth and mouth <= int(j[5]):
				entrance = j
		_check(L.name + " retains highway to ramp to launch guidance", not entrance.is_empty())
		if entrance.is_empty():
			continue
		var highway := int(entrance[0])
		var highway_hint := _parent_sample(entrance, mouth)
		var old_bad := obstructions
		var old_n := probes
		for metres in STATIONS:
			var li := _distance_sample(L, metres)
			var centre := Vector2(L.px[li], L.py[li])
			var tangent := Vector2(L.tx[li], L.ty[li])
			sim._nearest_on(highway, centre.x, centre.y, highway_hint, 240)
			var hi: int = sim._n_i
			_probe_mesh(launch, li, highway, hi, centre, tangent)
			_probe_mesh(highway, hi, launch, li, centre, tangent)
			_probe_walls(launch, li)
			_probe_walls(highway, hi)
		# Beyond the shared pavement, both launch barriers must become solid again.
		var clear_i := _distance_sample(L, 3000.0)
		_probe_walls(launch, clear_i)
		sim._nearest_on(highway, L.px[clear_i], L.py[clear_i], highway_hint, 240)
		_probe_walls(highway, sim._n_i)
		print("LAUNCH OVERLAP %s / %s: %d triangle probes, %d obstructions" % [L.name, sim.roads[highway].name, probes - old_n, obstructions - old_bad])
	_check("real asphalt and concrete were sampled throughout", probes > 1000)
	_check("neither road protrudes into the other's drivable surface", obstructions == 0)
	_check("shared internal edges were exercised", internal_walls > 50)
	_check("exposed outer guardrails were exercised", outer_walls >= 100)
	print("LAUNCH HIGHWAY CLEARANCE %s (%d failures; %d probes; %d obstructions; worst %.3f m; %d internal / %d outer walls)" % ["PASS" if failures == 0 else "FAIL", failures, probes, obstructions, worst, internal_walls, outer_walls])
	quit(int(failures > 0))

func _distance_sample(R, metres: float) -> int:
	var distance := 0.0
	var i := 0
	while i < R.N - 2 and distance < metres:
		distance += R.len[i]
		i += 1
	return i

func _chunk(r: int, chunk: int) -> Array:
	var key := Vector2i(r, chunk)
	if not world.chunks.has(key):
		world._build_chunk(r, chunk)
	return world.chunks[key]

func _probe_mesh(r: int, at: int, q: int, hint: int, centre: Vector2, tangent: Vector2) -> void:
	var first := maxi(0, at - 2) / World.CH
	var last := mini(sim.roads[r].N - 2, at + 2) / World.CH
	for chunk in range(first, last + 1):
		var entry := _chunk(r, chunk)
		var mesh: ArrayMesh = entry[0].get_node("road").mesh
		for surface in mini(2, mesh.get_surface_count()): # asphalt, concrete/edge paint/walls
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for k in vertices.size():
					indices.append(k)
			for ti in range(0, indices.size(), 3):
				var a := vertices[indices[ti]]
				var b := vertices[indices[ti + 1]]
				var c := vertices[indices[ti + 2]]
				for point in [a, (a + b) / 2.0, (a + b + c) / 3.0]:
					var xy := Vector2(point.x + float(entry[1]), -point.z + float(entry[2]))
					if absf((xy - centre).dot(tangent)) > 36.0:
						continue
					sim._nearest_on(q, xy.x, xy.y, hint, 160)
					if sim._n_off or absf(sim._n_lat) >= sim._n_w / 2.0 - 3.0:
						continue
					var deck: float = sim.net_height(q, sim._n_i + sim._n_t)
					# These first two kilometres are level; ignore underside/overhead structures.
					if point.y < deck - 0.25 or point.y > deck + 16.0:
						continue
					var expected: float = deck + Sim.net_edge(sim._n_w, sim._n_lat).x
					var intrusion: float = point.y - expected
					probes += 1
					worst = maxf(worst, intrusion)
					if intrusion > 0.25:
						obstructions += 1
						if obstructions <= 6:
							print("INTRUSION %s -> %s at %s surface %d: %.3f m" % [sim.roads[r].name, sim.roads[q].name, xy, surface, intrusion])

func _probe_walls(r: int, i: int) -> void:
	var R = sim.roads[r]
	var deck: float = sim.net_height(r, float(i))
	for side in [-1.0, 1.0]:
		var edge := Vector2(R.px[i] + R.nx[i] * R.w[i] / 2.0 * side, R.py[i] + R.ny[i] * R.w[i] / 2.0 * side)
		var internal := false
		var boundary := false
		# Include the other quadrant's ramp too: the highway's opposite edge can be
		# another legitimate exit. The physical query does not use declared joins.
		for near in sim.net_near(edge.x, edge.y):
			var q := int(near[0])
			if q == r:
				continue
			sim._nearest_on(q, edge.x, edge.y, int(near[1]), 10)
			if sim._n_off or absf(sim.net_height(q, sim._n_i + sim._n_t) - deck) > 2.0:
				continue
			var clearance: float = sim._n_w / 2.0 - absf(sim._n_lat)
			internal = internal or clearance > 4.0
			boundary = boundary or absf(clearance) <= 4.0
		if not internal and boundary:
			continue # an exact shared boundary does not promise room for a two-metre body
		sim.respawn_on(r, i, 1)
		var body = sim.pod
		body.x = edge.x - R.nx[i] * side * 0.5
		body.y = edge.y - R.ny[i] * side * 0.5
		body.contact = [false, false]
		sim._collide_walls(body, [[body.x, body.y, 2.0]], DT)
		if internal:
			internal_walls += 1
			_check("%s sample %d side %+.0f shared pavement has no wall contact" % [R.name, i, side], not body.contact[0])
		else:
			outer_walls += 1
			_check("%s sample %d side %+.0f outer guardrail stays solid" % [R.name, i, side], body.contact[0])
			_check("%s sample %d side %+.0f outer guardrail stays visible" % [R.name, i, side], _has_wall(r, i, side, deck))

func _has_wall(r: int, i: int, side: float, deck: float) -> bool:
	var R = sim.roads[r]
	var entry := _chunk(r, mini(i, R.N - 2) / World.CH)
	var mesh: ArrayMesh = entry[0].get_node("road").mesh
	if mesh.get_surface_count() < 2:
		return false
	var vertices: PackedVector3Array = mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var wall_floor: float = deck + Sim.net_edge(R.w[i], R.w[i] / 2.0).x
	var outward := Vector3(R.nx[i] * side, 0.0, -R.ny[i] * side)
	var origin: Vector3 = Vector3(R.px[i] - float(entry[1]), wall_floor + 0.7, -(R.py[i] - float(entry[2]))) + outward * (R.w[i] / 2.0 - 2.0)
	# Move 1 cm into this segment: at the exact station the ray lies on the
	# shared float32 triangle edge and rounding can reject both adjacent faces.
	origin += Vector3(R.tx[i], 0.0, -R.ty[i]) * 0.01
	# A straight guardrail can span several road rows without a vertex at this
	# station. Test the actual visible face crossing the station, not its topology.
	for k in range(0, vertices.size() - 2, 3):
		var hit = Geometry3D.ray_intersects_triangle(origin, outward, vertices[k], vertices[k + 1], vertices[k + 2])
		if hit != null and (hit as Vector3).distance_to(origin) < 4.0:
			return true
	return false
