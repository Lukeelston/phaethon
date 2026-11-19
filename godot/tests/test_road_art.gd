## Inspect the pavement data actually submitted by each world, including a 64 km
## origin wrap and the places where the Network's edge treatment must disappear.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const Network := preload("res://view/network_world.gd")
const Traffic := preload("res://view/network_traffic.gd")
const GP := preload("res://view/gp_world.gd")
const Course := preload("res://view/course_world.gd")
const RangeWorld := preload("res://view/range_world.gd")
const View := preload("res://view/craft_view.gd")
const Asphalt := preload("res://view/asphalt.gdshader")

var failures := 0
var finished_sections := 0
var detail_map: Texture2D

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	failures += int(not ok)

func _run() -> void:
	_network()
	for track in ["gp", "carving", "eridanus"]:
		_course(track)
	_range()
	if detail_map != null:
		var settings := ConfigFile.new()
		var loaded := settings.load(detail_map.resource_path + ".import") == OK
		_check("shared pavement includes mipmaps and preserves all four data channels",
			loaded and settings.get_value("params", "mipmaps/generate", false)
			and not settings.get_value("params", "process/premult_alpha", true)
			and not settings.get_value("params", "process/fix_alpha_border", true))
	# Godot logs a script error and returns to the caller if a probe aborts.
	_check("all road and junction probes reached their final assertions", finished_sections == 7)
	print("ROAD ART ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(int(failures > 0))

func _check_material(label: String, mat: Material) -> void:
	var texture: Texture2D
	if mat is ShaderMaterial and mat.shader == Asphalt:
		texture = mat.get_shader_parameter("pavement_detail") as Texture2D
	if detail_map == null:
		detail_map = texture
	_check(label + " uses the shared pavement map", texture != null and texture == detail_map)

func _deck(world, r: int, k: int) -> Mesh:
	var key := Vector2i(r, k)
	if not world.chunks.has(key) or not world.chunks[key][0].has_node("road"):
		world._build_chunk(r, k)
	return world.chunks[key][0].get_node("road").mesh

func _network() -> void:
	var sim = Sim.new({"track": "network"})
	var world = Network.new()
	root.add_child(world)
	world.build(sim, null)
	var stations: PackedFloat64Array = world._s[0]
	var boundary := 0
	for i in range(Network.CH, stations.size() - Network.CH, Network.CH):
		if stations[i] >= Network.ASPHALT_PERIOD:
			boundary = i / Network.CH
			break
	_check("Network crosses a full pavement period", boundary > 0)
	if boundary > 0:
		var before := _deck(world, 0, boundary - 1).surface_get_arrays(0)
		var after := _deck(world, 0, boundary)
		_check_material("Network highway", after.surface_get_material(0))
		var next := after.surface_get_arrays(0)
		var uv_a: PackedVector2Array = before[Mesh.ARRAY_TEX_UV]
		var uv_b: PackedVector2Array = next[Mesh.ARRAY_TEX_UV]
		var cols := uv_a.size() / (Network.CH + 1)
		var joined := uv_b.size() == uv_a.size() and before[Mesh.ARRAY_TEX_UV2] != null and next[Mesh.ARRAY_TEX_UV2] != null
		if joined:
			for col in cols:
				var a := uv_a.size() - cols + col
				joined = joined and absf(uv_a[a].x - uv_b[col].x - Network.ASPHALT_PERIOD) < 0.02 and is_equal_approx(uv_a[a].y, uv_b[col].y)
				joined = joined and before[Mesh.ARRAY_TEX_UV2][a].distance_to(next[Mesh.ARRAY_TEX_UV2][col]) < 0.02
		_check("both pavement coordinates agree along the full row at the 64 km wrap", joined)
	_check_open_edges(world, sim)
	_check_lanes(world, sim)
	var shelter: int = world._shelter_road
	var middle := int((world.halls[shelter][0] + world.halls[shelter][1]) / 2)
	var indoors := _deck(world, shelter, middle / Network.CH).surface_get_material(0) as ShaderMaterial
	_check_material("Eridanus terminal", indoors)
	var wells: Vector3 = indoors.get_shader_parameter("shelter")
	_check("terminal pavement retains its light-well spacing", wells.z > 0 and wells.y > wells.z)
	world.free()
	finished_sections += 1

func _check_open_edges(world, sim) -> void:
	var open_edges := 0
	var closed_edges := 0
	var correct := true
	for join in sim.junctions:
		var r := int(join[3])
		var k := int((join[4] + join[5]) / 2) / Network.CH
		var deck := _deck(world, r, k).surface_get_arrays(0)
		if deck[Mesh.ARRAY_TEX_UV2] == null:
			correct = false
			break
		var edges: PackedVector2Array = deck[Mesh.ARRAY_TEX_UV2]
		var rows := mini(Network.CH, int(sim.roads[r].N) - 1 - k * Network.CH) + 1
		var cols := edges.size() / rows
		for row in range(1, rows - 1):
			var i := k * Network.CH + row
			for side in [-1, 1]:
				var is_open: bool = world._open(r, i, float(side))
				if is_open != world._open(r, i - 1, float(side)) or is_open != world._open(r, i + 1, float(side)):
					continue
				var col := 0 if side < 0 else cols - 1
				var edge := edges[row * cols + col]
				var inside := edges[row * cols + col - int(side)]
				correct = correct and absf(edge.x) < 0.02 and inside.x > edge.x and absf(edge.y - float(not is_open)) < 0.01
				open_edges += int(is_open)
				closed_edges += int(not is_open)
		if open_edges > 8 and closed_edges > 8:
			break
	_check("junction edge mask follows open and closed walls (%d open, %d closed)" % [open_edges, closed_edges], correct and open_edges > 8 and closed_edges > 8)
	finished_sections += 1

func _lane_row(world, r: int, sample: int) -> PackedColorArray:
	var chunk := sample / Network.CH
	var first := chunk * Network.CH
	var mesh := _deck(world, r, chunk)
	var data: Variant = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	if data == null:
		return PackedColorArray()
	var colors: PackedColorArray = data
	var rows := mini(Network.CH, int(world.sim.roads[r].N) - first - 1) + 1
	var cols := colors.size() / rows
	var offset := (sample - first) * cols
	return colors.slice(offset, offset + cols)

func _check_lanes(world, sim) -> void:
	# Probe the actual uploaded colour at both sides of the centre quad. A
	# constant lane centre is wrong on this map: the narrow roads use 50 m.
	for lanes in [Traffic.LANES_HWY, Traffic.LANES_RAMP]:
		var r := 1 # E2 between launch and the first interchange
		var sample := 1000
		if lanes.size() == 4:
			for candidate in sim.roads.size():
				var road = sim.roads[candidate]
				if road.name.begins_with("R") and not world._approaches.has(candidate):
					r = candidate
					sample = road.N / 2
					break
		var colors := _lane_row(world, r, sample)
		var good := not colors.is_empty()
		for v in colors:
			var pitch := lerpf(50.0, 45.0, v.b)
			good = good and v.a < 0.01 and is_equal_approx(v.r, v.g)
			for k in lanes.size() - 1:
				var middle: float = (lanes[k] + lanes[k + 1]) * 0.5
				good = good and absf(middle - pitch * (k + 1 - lanes.size() / 2)) < 0.01
		_check("%d-lane road paints the midpoints between actual traffic lanes" % lanes.size(), good)
	var merge: Array = sim.junctions[0]
	var overlap: Array = sim.surface_junctions[sim.junctions.size()]
	var shaft: Array = sim.shafts[0]
	var exclusions := {
		"merge": Vector2i(merge[3], int((merge[4] + merge[5]) / 2)),
		"physical overlap": Vector2i(overlap[0], int((overlap[1] + overlap[2]) / 2)),
		"climb shaft": Vector2i(shaft[0], int((shaft[1] + shaft[2]) / 2)),
		"terminal hall": Vector2i(sim.cities[0].road, sim.cities[0].i),
		"launch spur": Vector2i(sim.jumps[0][0], int(sim.roads[sim.jumps[0][0]].N / 2)),
	}
	for r in world._approaches:
		var guide: Array = world._approaches[r][0]
		var label := "ramp amber route" if is_zero_approx(float(guide[3])) else "highway amber route"
		if not exclusions.has(label):
			exclusions[label] = Vector2i(r, int((guide[0] + guide[1]) / 2))
	_check("both amber approach types were exercised", exclusions.has("ramp amber route") and exclusions.has("highway amber route"))
	for label in exclusions:
		var location: Vector2i = exclusions[label]
		var colors := _lane_row(world, location.x, location.y)
		var clear := not colors.is_empty()
		for v in colors:
			clear = clear and v.a > 0.99
		_check(label + " is clear of traffic dividers", clear)
	finished_sections += 1

func _course(track: String) -> void:
	var sim = Sim.new({"track": track})
	var chunked := track == "eridanus"
	var world = Course.new() if chunked else GP.new()
	root.add_child(world)
	world.build(sim, null)
	var colours_by_mesh := {}
	var checked := 0
	var inside := true
	var clear_of_dividers := true
	for corner in world.corners:
		var row := int((corner[0] + corner[1]) / 2) if chunked else int(corner[1])
		var side := int(corner[2] if chunked else corner[3])
		var parent: Node = world.chunk_of(row)[0] if chunked else world
		var mesh := parent.get_child(0) as MeshInstance3D
		if colours_by_mesh.is_empty():
			_check_material(track, mesh.material_override)
		if not colours_by_mesh.has(mesh):
			colours_by_mesh[mesh] = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if colours_by_mesh[mesh] == null:
			inside = false
			break
		var colors: PackedColorArray = colours_by_mesh[mesh]
		var vertex := (row % Course.CHUNK if chunked else row) * 6
		var a := colors[vertex]
		var b := colors[vertex + 1]
		inside = inside and a == b and (a.r - a.g) * side > 0.0
		clear_of_dividers = clear_of_dividers and a.a > 0.99 and b.a > 0.99
		checked += 1
	_check(track + " groove follows the inside of each signed apex (%d corners)" % checked, inside and checked > 0)
	_check(track + " pavement omits Network traffic dividers", clear_of_dividers and checked > 0)
	if chunked and world.shade != null:
		var branch_deck: MeshInstance3D = world.shade.chunks[1][0].get_child(0)
		_check_material("Shade Line", branch_deck.material_override)
	world.free()
	finished_sections += 1

func _range() -> void:
	var sim = Sim.new({"track": "range"})
	var view := View.new()
	var world := RangeWorld.new()
	root.add_child(world)
	world.build(sim, view)
	var chunk := world._make_chunk(0)
	var asphalt_surfaces := 0
	var has_apron := false
	for child in chunk.get_children():
		if not child is MeshInstance3D:
			continue
		var mat := child.material_override as ShaderMaterial
		if mat == null or mat.shader != Asphalt:
			continue
		_check_material("Range pavement", mat)
		asphalt_surfaces += 1
		has_apron = has_apron or float(mat.get_shader_parameter("lane_half")) == 0.0
	_check("runway, highway and unrubbered apron retain separate road materials", asphalt_surfaces >= 3 and has_apron)
	# Count complete quads in the white paint batch. Validate the untouched
	# centreline clearance and mirrored lateral spacing of the threshold keys.
	var keys: Array[float] = []
	for child in chunk.get_children():
		if not child is MeshInstance3D or child.material_override != world.mats.line:
			continue
		var points: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in range(0, points.size(), 6):
			var bounds := AABB(points[i], Vector3.ZERO)
			for p in range(i + 1, i + 6):
				bounds = bounds.expand(points[p])
			if bounds.position.x > 0.0 and bounds.end.x < 100.0 and bounds.size.x > 32.0 and bounds.size.z > 2.0:
				keys.append(bounds.get_center().z)
	keys.sort()
	var symmetric := keys.size() == 12
	for i in keys.size() / 2:
		symmetric = symmetric and absf(keys[i] + keys[-1 - i]) < 0.02 and absf(keys[i]) > 10.0
	_check("runway launch threshold flanks the clear centreline symmetrically", symmetric)
	world.free()
	view.free()
	finished_sections += 1
