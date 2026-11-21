## Fixed geographic terrain. Only render transforms depend on the floating origin.
## Shared 512 m vertices, with whole road-adjacent triangles held below the decks.
extends Node3D
const Outlook := preload("res://view/outlook.gd")      # the hour and weather: they thicken and colour the fog set here every frame
const Helios := preload("res://view/helios.gd")        # the one giant mountain: it stands over whatever the regions make there
const TILE := 8192.0
const STEP := 512.0
const GRID := 16
const RANGE := 8
const MAX_TILES := 289
const PROP_RANGE := 4
const GROUPS := 96
const REGIONS := [
	["plains", Vector2(300000, 300000), 65000.0, Color(0.37, 0.49, 0.20), 140.0],
	["tundra", Vector2(300000, 500000), 65000.0, Color(0.48, 0.48, 0.34), 240.0],
	["rocky", Vector2(100000, 300000), 65000.0, Color(0.42, 0.43, 0.40), 4400.0],
	["desert", Vector2(70862, 513131), 65000.0, Color(0.73, 0.52, 0.29), 700.0],
	["snow", Vector2(529137, 513131), 65000.0, Color(0.79, 0.84, 0.87), 5600.0],
	["swamp", Vector2(300000, 100000), 65000.0, Color(0.22, 0.32, 0.20), 45.0],
	["jungle", Vector2(100000, 100000), 65000.0, Color(0.12, 0.30, 0.15), 800.0],
	["urban", Vector2(329137, 313131), 13000.0, Color(0.39, 0.42, 0.38), 15.0],
	["mesa", Vector2(529137, 86869), 65000.0, Color(0.64, 0.32, 0.18), 2000.0],
]
var clearance := {} # vertex grid -> smooth factor; zero protects entire road triangles
var tiles := {}
var pending: Array[Vector2i] = []
var center := Vector2i(999999, 999999)
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var material: ShaderMaterial
var max_slice_ms := 0.0
var _job := {}
var _sim
var _world
var road_protection := {}
var road_anchors := {}
var prop_library
var water_material: ShaderMaterial
const CLOUD_BASE := 4200.0   # m: the cumulus deck (the cirrus is drawn through it, higher)
var clouds: MeshInstance3D
var _environment: Environment
var prop_slices_max := 0.0
var _lattice := {}           # grid vertex -> its height, each worked out once (lattice_height)
var _tile_root: Node3D       # every tile hangs from this: it is all that moves each frame
var _anchor_x := INF         # where the tiles' own places are measured from (moved when the craft is ANCHOR_REACH off it)
var _anchor_y := INF
const ANCHOR_REACH := 1024.0
var _revealing: Array[Vector2i] = []        # tiles still fading in
var _deco_revealing: Array[Vector2i] = []   # ... and tiles whose props are
var _deco_far := false       # the centre moved: props out of range are to go
var _deco_want := true       # some tile in range may still lack its props
const DECOR_SLICE_US := 400  # a prop slice's work (it does a group at least)
var profiling := false       # (a harness's: this frame's parts into `profile`, usec)
var profile := {}
var _decor_job := {}
var scenic = null            # the scenic roads' land (view/network_scenic.gd), when the world has any
var far_helios: MeshInstance3D   # the mountain whole, for beyond the tiles (view/helios.gd far_mesh)
var _scenic_tiles := {}   # coarse lookup for authored land, including interior mountain passes
const PROP_CELL := 256.0

func build(sim, world) -> void:
	_sim = sim
	_world = world
	world.scenery_ground_height = -4.0
	world.landscape = self   # the road's banks take this land's colours and material
	scenic = world.scenic
	if scenic != null:
		for box: Rect2i in scenic.boxes:
			var lo := Vector2i((Vector2(box.position) * scenic.CELL / TILE).floor())
			var hi := Vector2i((Vector2(box.end) * scenic.CELL / TILE).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					_scenic_tiles[Vector2i(x, y)] = true
	noise.seed = 28471
	noise.frequency = 0.00011
	noise.fractal_octaves = 4
	detail.seed = 734
	detail.frequency = 0.0006
	detail.fractal_octaves = 3
	_tile_root = Node3D.new()
	_tile_root.name = "tiles"
	add_child(_tile_root)
	material = ShaderMaterial.new()
	material.shader = preload("res://view/network_terrain.gdshader")
	material.set_shader_parameter("terrain_detail", load("res://art/terrain/terrain_detail.png"))
	prop_library = preload("res://view/network_biome_props.gd").new()
	water_material = ShaderMaterial.new()
	water_material.shader = preload("res://view/network_water.gdshader")
	# Rasterize every road with a bounded gap, using the actual carried geometry.
	# Cache occupied sample cells before expanding: long parallel lanes share work.
	var road_cells := {}
	for r in sim.roads.size():
		var road = sim.roads[r]
		for i in range(0, road.N, 4):
			var p: Vector2 = world._wxy(r, i)
			if i%32 == 0:
				var tile_key := Vector2i(floori(p.x/TILE),floori(p.y/TILE))
				if not road_anchors.has(tile_key): road_anchors[tile_key] = []
				road_anchors[tile_key].append([p,Vector2(road.nx[i],road.ny[i])])
			var c := Vector2i(floori(p.x / STEP), floori(p.y / STEP))
			# a scenic road's land is its own (a mountainside, a sea cliff): flattened only at its ends, where it rejoins the open ground
			if scenic == null or not (scenic.on(r, i - 120) and scenic.on(r, i + 120)):
				road_cells[c] = maxi(int(road_cells.get(c, 0)), ceili((float(road.w[i]) * 0.5 + 220.0) / STEP) + 1)
			var pc := Vector2i(floori(p.x/PROP_CELL),floori(p.y/PROP_CELL))
			var pr := ceili((float(road.w[i])*0.5+90.0)/PROP_CELL)
			for dx in range(-pr,pr+1):
				for dy in range(-pr,pr+1):
					road_protection[pc+Vector2i(dx,dy)] = true
	for c in road_cells:
		var radius: int = road_cells[c]
		for x in range(-radius, radius + 2):
			for y in range(-radius, radius + 2):
				clearance[c + Vector2i(x, y)] = 0.0
	# Keep the authored city towers and landmark compounds on their level foundations.
	for city in sim.cities:
		_flatten_disc(Vector2(city.cx, city.cy), 8800.0)
	for lm in world.scenery.landmarks:
		_flatten_disc(Vector2(lm.x, lm.y), 1700.0)
	# Eight-neighbor distance transform: broad graded valleys outside the road buffer.
	var frontier: Array = clearance.keys()
	for ring in range(1, 9):
		var next := []
		for c in frontier:
			for d in [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]:
				var q: Vector2i = c + d
				if not clearance.has(q):
					clearance[q] = smoothstep(0.0, 9.0, float(ring))
					next.append(q)
		frontier = next
	clouds = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(360000,360000)
	clouds.mesh = plane
	clouds.position.y = CLOUD_BASE
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = preload("res://view/network_clouds.gdshader")
	cloud_material.set_shader_parameter("cloud_cover", load("res://art/sky/cloud_cover.png"))
	cloud_material.set_shader_parameter("clearing", Helios.CLEARING)
	clouds.material_override = cloud_material
	add_child(clouds)
	if world.view != null:
		for child in world.view.get_children():
			if child is WorldEnvironment:
				_environment = child.environment
	far_helios = MeshInstance3D.new()
	far_helios.name = "helios_far"
	far_helios.mesh = Helios.far_mesh(self)
	var far_material := ShaderMaterial.new()
	far_material.shader = preload("res://view/helios_far.gdshader")
	far_helios.material_override = far_material
	far_helios.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_helios)

func setup_ground(ground_material: ShaderMaterial) -> void:
	var centers := PackedVector3Array()
	var colors := PackedColorArray()
	for region in REGIONS:
		centers.append(Vector3(region[1].x,region[1].y,region[2]))
		colors.append(region[3])
	ground_material.set_shader_parameter("network_on",true)
	ground_material.set_shader_parameter("regions",centers)
	ground_material.set_shader_parameter("region_colors",colors)

func _flatten_disc(p: Vector2, radius: float) -> void:
	var c := Vector2i(floori(p.x / STEP), floori(p.y / STEP))
	var r := ceili(radius / STEP) + 1
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			if Vector2(x, y).length() * STEP <= radius + STEP * 1.5:
				clearance[c + Vector2i(x,y)] = 0.0

func weights(p: Vector2) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var sum := 0.0
	for region in REGIONS:
		var d: float = maxf(p.distance_to(region[1]) / float(region[2]), 0.035)
		var w := 1.0 / (d * d * d * d)
		values.append(w)
		sum += w
	for i in values.size():
		values[i] /= sum
	return values

func region_at(p: Vector2) -> String:
	var w := weights(p)
	var best := 0
	for i in w.size():
		if w[i] > w[best]:
			best = i
	return REGIONS[best][0]

func height_at(p: Vector2) -> float:
	var c := Vector2i(roundi(p.x / STEP), roundi(p.y / STEP))
	var factor: float = clearance.get(c, 1.0)
	if _scenic_tiles.has(Vector2i((p / TILE).floor())):
		var mine: Vector2 = scenic.land(c, p)
		if mine.x >= 1.0:
			return mine.y
		if mine.x > 0.0:
			return lerpf(_country(p, factor), mine.y, mine.x)
	return _country(p, factor)


## The land with no scenic road's say: level by a road, the open country away from one; the mountain
## over either (no road but its own goes near it).
func _country(p: Vector2, factor: float) -> float:
	if factor == 0.0:
		return maxf(-4.0, Helios.land(p)) if Helios.on(p) else -4.0
	return _open_height(p, factor)


## The open country's height at p: the regions' own shapes, graded down toward the roads.
func _open_height(p: Vector2, factor: float) -> float:
	var w := weights(p)
	var n := clampf(0.5 + noise.get_noise_2dv(p) * 0.65, 0.0, 1.0)
	var small := detail.get_noise_2dv(p)
	var ridge := pow(1.0 - absf(noise.get_noise_2dv(p * 0.72)), 4.0)
	var h := 0.0
	for i in w.size():
		var shape := n * n
		if i in [2, 4]:
			shape = ridge * (0.3 + 0.7 * n) + small * 0.04
		elif i == 3:
			shape = 0.12 + 0.35 * n + 0.08 * sin(p.x / 1900.0 + 4.0 * n)
		elif i == 8:
			shape = smoothstep(0.32, 0.62, n) * 0.65 + small * 0.035
		h += w[i] * float(REGIONS[i][4]) * shape
	# Wetlands alternate low grassy hummocks and shallow open water.
	h -= w[5] * 9.0
	if h > 0.0:
		h *= Helios.country(p)      # (the regions' relief gives way to the mountain round it)
	h = lerpf(-4.0, h, factor)
	if Helios.on(p):
		h = maxf(h, Helios.land(p) + Helios.rough(p))
	return h

func color_at(p: Vector2, known_height := NAN) -> Color:
	var w := weights(p)
	var col := Color(0,0,0,1)
	var n := detail.get_noise_2dv(p)
	var h := height_at(p) if is_nan(known_height) else known_height
	for i in w.size():
		var c: Color = REGIONS[i][3]
		if i == 4:
			c = Color(0.70,0.77,0.80).lerp(Color(0.88,0.92,0.94), smoothstep(400.0, 1750.0, h))
		elif i == 2:
			c = Color(0.28,0.35,0.22).lerp(c, smoothstep(250.0, 1400.0, h))
		elif i == 0:
			c = c.lerp(Color(0.60,0.56,0.29), smoothstep(-0.1,0.55,n) * 0.65)
		elif i == 1:
			c = c.lerp(Color(0.72,0.76,0.73), smoothstep(0.1,0.6,n) * 0.65)
		col += c * w[i]
	col *= 0.90 + n * 0.15
	col.a = w[0] # grassland fraction for fixed geographic field patterns in the shader
	if Helios.on(p):
		col = Helios.colour(col, h, n)
	# the coast: sand on the beach and the seabed, the sea's own colour under the water's edge
	if scenic != null and h < 7.0 and p.x < scenic.coast_hi + 700.0 and p.x < scenic.coast_x(p.y) + 700.0:
		col = (scenic.SAND as Color).lerp(col, smoothstep(4.0, 7.0, h))
	return col

## Exact piecewise-linear height of the visible two triangles, also used by prop feet.
func surface_at(p: Vector2) -> float:
	var ci := Vector2i(floori(p.x / STEP), floori(p.y / STEP))
	var f := (p - Vector2(ci) * STEP) / STEP
	var a := lattice_height(ci)
	var b := lattice_height(ci + Vector2i(1, 0))
	var d := lattice_height(ci + Vector2i(0, 1))
	if f.x + f.y <= 1.0:
		return a + (b-a)*f.x + (d-a)*f.y
	var e := lattice_height(ci + Vector2i(1, 1))
	return e + (d-e)*(1.0-f.x) + (b-e)*(1.0-f.y)


## The height at the grid's vertex c (c * STEP), worked out once and kept: a tile's mesh wants each
## one six times (itself, its colour, four neighbours' normals), a prop's footing up to twelve.
func lattice_height(c: Vector2i) -> float:
	var h = _lattice.get(c)
	if h == null:
		if _lattice.size() > 160000:   # (two streaming ranges' worth: start over rather than grow for ever)
			_lattice.clear()
		h = height_at(Vector2(c) * STEP)
		_lattice[c] = h
	return h

func clear_at(p: Vector2, radius := 80.0) -> bool:
	var lo := Vector2i(floori((p.x-radius)/PROP_CELL),floori((p.y-radius)/PROP_CELL))
	var hi := Vector2i(floori((p.x+radius)/PROP_CELL),floori((p.y+radius)/PROP_CELL))
	for x in range(lo.x,hi.x+1):
		for y in range(lo.y,hi.y+1):
			var c := Vector2i(x,y)
			if road_protection.has(c):
				return false
	return true

## Records are deterministic and retain world positions for clearance/support tests.
func prop_records(key: Vector2i, first := 0, count := GROUPS) -> Array:
	var records := []
	var rng := RandomNumberGenerator.new()
	var origin := Vector2(key)*TILE
	for group in range(first,mini(first+count,GROUPS)):
		rng.seed = int(key.x)*73856093 ^ int(key.y)*19349663 ^ (937 + group*83492791)
		var anchor := origin + Vector2(rng.randf(),rng.randf())*TILE
		# Additional inhabited clusters follow the highway corridor, not city centers.
		if group>=64 and road_anchors.has(key):
			var choices: Array = road_anchors[key]
			var road_anchor: Array = choices[rng.randi_range(0,choices.size()-1)]
			anchor = road_anchor[0]+road_anchor[1]*rng.randf_range(900,2400)*(1 if group%2==0 else -1)
			# Keep each record inside its owner tile for predictable streaming distance.
			if not Rect2(origin,Vector2.ONE*TILE).has_point(anchor): continue
		var region := region_at(anchor)
		var kind := "oak"
		var number := 7
		match region:
			"plains":
				kind = "oak" if group%4 == 0 else "scrub"
				number = 3
			"tundra":
				kind = "rock" if group%3 == 0 else "scrub"
				number = 3
			"rocky": kind = "pine" if group%3 != 0 else "rock"
			"snow": kind = "snowpine" if surface_at(anchor)<1700 else "rock"
			"desert", "mesa":
				kind = "cactus" if group%3 == 0 else "rock"
				number = 3
			"swamp": kind = "mangrove" if group%3 != 0 else "reeds"
			"jungle":
				kind = "palm" if group%3 == 0 else "oak"
				number = 12
			"urban":
				kind = "urban"
				number = 1
		if group%13 == 0 and region != "urban":
			kind = "farm" if region == "plains" else ("stilt" if region in ["swamp","jungle"] else "outpost")
			number = 1
		if region == "mesa" and group%13 == 0:
			kind = "industrial"
		if group>=64 and group%4==0:
			kind = "service" if group%8==0 else ("solar" if region in ["desert","mesa"] else ("basalt" if region == "jungle" else "wind"))
			number = 1
		for k in number:
			var p := anchor + Vector2(rng.randf_range(-240,240),rng.randf_range(-240,240))
			var scale := rng.randf_range(0.75,1.8)
			if scenic != null and (scenic.is_sea(p) or scenic.covered(p)): continue   # nothing in the sea, nothing under the road's own land
			if region == "jungle" and kind == "oak": scale *= 1.7
			var building := kind in ["urban","farm","industrial","outpost","stilt","service","solar","wind"]
			var radius := (185.0 if kind == "urban" else (180.0 if kind in ["service","solar","wind"] else (90.0 if kind in ["farm","industrial","outpost","basalt"] else 35.0)))*scale
			if not clear_at(p,radius): continue
			var h := surface_at(p)
			if h > Helios.TREE_LINE and Helios.on(p) and (kind != "rock" or h > 5200.0): continue   # up the mountain: rock over the trees, then nothing
			var slope := maxf(absf(surface_at(p+Vector2(radius,0))-h),absf(surface_at(p+Vector2(0,radius))-h)) / radius
			if slope > (0.045 if building else 0.5): continue
			if h < -2.0 and region == "swamp" and kind not in ["mangrove","reeds","stilt"]: continue
			records.append({"kind":kind,"p":p,"height":h,"radius":radius,"scale":scale,"yaw":rng.randf()*TAU})
	return records

func _decorate_slice() -> void:
	var start := Time.get_ticks_usec()
	var key: Vector2i = _decor_job.key
	var batches: Dictionary = _decor_job.batches
	while int(_decor_job.group) < GROUPS:   # a group at a time, to a budget (it was always four: up to 2 ms in the jungle)
		for prop in prop_records(key, _decor_job.group, 1):
			if not batches.has(prop.kind): batches[prop.kind] = []
			var local: Vector2 = prop.p-Vector2(key)*TILE
			batches[prop.kind].append(Transform3D(Basis(Vector3.UP,prop.yaw).scaled(Vector3.ONE*prop.scale),Vector3(local.x,prop.height,-local.y)))
		_decor_job.group += 1
		if Time.get_ticks_usec() - start >= DECOR_SLICE_US:
			break
	if _decor_job.group == GROUPS:
		var root := Node3D.new()
		tiles[key].node.add_child(root)
		tiles[key].deco = root
		tiles[key].deco_born = Time.get_ticks_msec()
		for kind in batches:
			prop_library.batch(root,kind,batches[kind])
		_deco_revealing.append(key)
		_deco_want = true   # (the next tile's turn)
		_decor_job.clear()
	prop_slices_max = maxf(prop_slices_max,float(Time.get_ticks_usec()-start)/1000.0)

func _water(key: Vector2i, node: Node3D) -> void:
	if scenic != null and _sea(key, node): return
	# Below road level. Only wetland tiles, with shoreline supplied by their terrain.
	if weights((Vector2(key)+Vector2.ONE*0.5)*TILE)[5]<0.60: return
	var instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(TILE,TILE)
	instance.mesh = plane
	instance.position = Vector3(TILE/2,-2.0,-TILE/2)
	instance.material_override = water_material
	instance.set_instance_shader_parameter("world_offset",Vector2((key.x+0.5)*TILE,-(key.y+0.5)*TILE))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)

## The sea over a tile: its water on every square with a corner seaward of the coast (the squares
## the shore crosses too: their land stands out of it). True if the tile has any.
func _sea(key: Vector2i, node: Node3D) -> bool:
	if key.x * TILE > scenic.coast_hi + 100.0:
		return false
	var wet := PackedByteArray()
	wet.resize((GRID + 1) * (GRID + 1))
	var any := false
	for y in GRID + 1:
		for x in GRID + 1:
			var p := Vector2(key) * TILE + Vector2(x, y) * STEP
			wet[y * (GRID + 1) + x] = int(p.x < scenic.coast_x(p.y) + 40.0)
			any = any or wet[y * (GRID + 1) + x] == 1
	if not any:
		return false
	var verts := PackedVector3Array()
	for y in GRID:
		for x in GRID:
			var a := y * (GRID + 1) + x
			if wet[a] + wet[a + 1] + wet[a + GRID + 1] + wet[a + GRID + 2] == 0:
				continue
			var x0 := x * STEP
			var z0 := -y * STEP
			verts.append_array(PackedVector3Array([Vector3(x0, 0, z0), Vector3(x0, 0, z0 - STEP), Vector3(x0 + STEP, 0, z0),
				Vector3(x0 + STEP, 0, z0), Vector3(x0, 0, z0 - STEP), Vector3(x0 + STEP, 0, z0 - STEP)]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "sea"
	instance.mesh = mesh
	instance.position = Vector3(0.0, scenic.SEA, 0.0)
	instance.material_override = water_material
	instance.set_instance_shader_parameter("world_offset", Vector2(key.x * TILE, -key.y * TILE))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)
	return true


func vertex_at(key: Vector2i, x: int, y: int) -> Vector3:
	var p := Vector2(key) * TILE + Vector2(x,y) * STEP
	return Vector3(x * STEP, height_at(p), -y * STEP)

func _new_job(key: Vector2i) -> Dictionary:
	return {"key":key, "row":0, "vertices":PackedVector3Array(), "colors":PackedColorArray(), "normals":PackedVector3Array(), "uvs":PackedVector2Array()}

func _rows(job: Dictionary, count: int) -> void:
	var key: Vector2i = job.key
	var corner := key * GRID
	for y in range(job.row, mini(job.row + count, GRID + 1)):
		for x in GRID + 1:
			var p := Vector2(key)*TILE + Vector2(x,y)*STEP
			var c := corner + Vector2i(x, y)
			var h := lattice_height(c)
			job.vertices.append(Vector3(x * STEP, h, -y * STEP))
			job.colors.append(color_at(p, h))
			job.uvs.append(Vector2(p.x,-p.y)/256.0)
			job.normals.append(Vector3(lattice_height(c + Vector2i(-1, 0)) - lattice_height(c + Vector2i(1, 0)), STEP*2.0,
				lattice_height(c + Vector2i(0, 1)) - lattice_height(c + Vector2i(0, -1))).normalized())
	job.row = mini(job.row + count, GRID + 1)

func _mesh(job: Dictionary) -> ArrayMesh:
	var indices := PackedInt32Array()
	var verts: PackedVector3Array = job.vertices
	for y in GRID:
		for x in GRID:
			var a := y*(GRID+1)+x
			indices.append_array(PackedInt32Array([a,a+GRID+1,a+1,a+1,a+GRID+1,a+GRID+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = job.normals
	arrays[Mesh.ARRAY_TEX_UV] = job.uvs
	arrays[Mesh.ARRAY_COLOR] = job.colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func make_mesh(key: Vector2i) -> ArrayMesh:
	var job := _new_job(key)
	_rows(job, GRID + 1)
	return _mesh(job)

func sync(ox: float, oy: float) -> void:
	var start := Time.get_ticks_usec()
	var c := Vector2i(floori(ox/TILE),floori(oy/TILE))
	if c != center:
		center = c
		_deco_far = true
		_deco_want = true
		if not _decor_job.is_empty() and (absi(_decor_job.key.x-c.x)>PROP_RANGE or absi(_decor_job.key.y-c.y)>PROP_RANGE):
			_decor_job.clear()
		pending.clear()
		if not _job.is_empty() and _outside(_job.key):
			_job.clear()
		for key in tiles.keys():
			if _outside(key):
				tiles[key].node.queue_free()
				tiles.erase(key)
		for x in range(-RANGE,RANGE+1):
			for y in range(-RANGE,RANGE+1):
				var key := c+Vector2i(x,y)
				if not tiles.has(key) and (_job.is_empty() or _job.key != key):
					pending.append(key)
		pending.sort_custom(func(a,b): return Vector2(a-c).length_squared() < Vector2(b-c).length_squared())
	# The tiles hang from one node, and that is all that moves with the craft each frame (placing each
	# of 289 tiles each frame was a quarter of a millisecond of script). Their own places are measured
	# from an anchor that follows the craft a kilometre at a time, so the numbers stay small and exact.
	if absf(ox - _anchor_x) > ANCHOR_REACH or absf(oy - _anchor_y) > ANCHOR_REACH:
		_anchor_x = ox
		_anchor_y = oy
		for key in tiles:
			tiles[key].node.position = _tile_place(key)
	_tile_root.position = Vector3(_anchor_x - ox, 0.0, oy - _anchor_y)
	if _job.is_empty() and not pending.is_empty():
		_job = _new_job(pending.pop_front())
	if not _job.is_empty():
		_rows(_job,2)
		if _job.row == GRID+1:
			var node := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = _mesh(_job)
			mi.material_override = material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
			node.position = _tile_place(_job.key)
			_tile_root.add_child(node)
			_water(_job.key,node)
			tiles[_job.key] = {"node":node, "key":_job.key, "born":Time.get_ticks_msec()}
			_revealing.append(_job.key)
			_deco_want = true
			_job.clear()
	var t_rows := Time.get_ticks_usec()
	for k in range(_revealing.size() - 1, -1, -1):   # the tiles still fading in: a handful
		var key: Vector2i = _revealing[k]
		if not tiles.has(key):
			_revealing.remove_at(k)
			continue
		var reveal := clampf(float(Time.get_ticks_msec()-tiles[key].born)/1800.0,0.0,1.0)
		for surface in tiles[key].node.get_children():
			if surface is MeshInstance3D: surface.set_instance_shader_parameter("stream_reveal",reveal)
		if reveal>=1.0:
			tiles[key].revealed=true
			_revealing.remove_at(k)
	var t_place := Time.get_ticks_usec()
	if _deco_far:   # the centre moved: props out of range go
		_deco_far = false
		for key in tiles:
			var tile: Dictionary = tiles[key]
			if tile.has("deco") and (absi(key.x-center.x)>PROP_RANGE or absi(key.y-center.y)>PROP_RANGE):
				tile.deco.queue_free()
				tile.erase("deco")
				tile.erase("deco_revealed")
	if _deco_want and _decor_job.is_empty():   # the next tile in range without its props (none: nothing more to look for until something changes)
		_deco_want = false
		for key in tiles:
			if absi(key.x-center.x)<=PROP_RANGE and absi(key.y-center.y)<=PROP_RANGE and not tiles[key].has("deco"):
				_decor_job = {"key":key,"group":0,"batches":{}}
				break
	for k in range(_deco_revealing.size() - 1, -1, -1):
		var key: Vector2i = _deco_revealing[k]
		if not tiles.has(key) or not tiles[key].has("deco"):
			_deco_revealing.remove_at(k)
			continue
		var tile: Dictionary = tiles[key]
		var reveal := clampf(float(Time.get_ticks_msec()-tile.deco_born)/1800.0,0.0,1.0)
		for batch in tile.deco.get_children():
			batch.set_instance_shader_parameter("stream_reveal",reveal)
		if reveal>=1.0:
			tile.deco_revealed=true
			_deco_revealing.remove_at(k)
	var t_deco := Time.get_ticks_usec()
	if not _decor_job.is_empty() and Time.get_ticks_usec()-start<1800:
		_decorate_slice()
	if profiling:
		profile = {"rows_us": t_rows - start, "place_us": t_place - t_rows, "deco_loop_us": t_deco - t_place, "decor_slice_us": Time.get_ticks_usec() - t_deco}
	clouds.material_override.set_shader_parameter("world_offset",Vector2(fposmod(ox,2304000.0),fposmod(-oy,2304000.0)))
	far_helios.position = Vector3(Helios.CENTRE.x - ox, 0.0, oy - Helios.CENTRE.y)
	clouds.material_override.set_shader_parameter("clearing_at", Vector2(far_helios.position.x, far_helios.position.z))
	far_helios.visible = Vector2(ox, oy).distance_to(Helios.CENTRE) < 160000.0
	# The air thins with height: from up the mountain the country below is seen through less of it.
	var eye := get_viewport().get_camera_3d() if is_inside_tree() else null
	var thin := Outlook.air_between(eye.global_position.y if eye != null else 0.0, 0.0)
	Outlook.thin_air(thin)
	if _environment != null:
		var w := weights(Vector2(ox,oy))
		# (the place's own afternoon air, then what the hour and the weather make of it: view/outlook.gd)
		_environment.fog_density = (0.00011 + w[5]*0.00009 + w[6]*0.00005 + w[3]*0.00002) * Outlook.fog_scale() * thin
		_environment.fog_light_color = Outlook.haze(Color(0.58,0.68,0.80).lerp(Color(0.63,0.69,0.65),w[5]*0.25+w[6]*0.15).lerp(Color(0.76,0.69,0.58),w[3]*0.3))
	max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec()-start)/1000.0)


## A tile's place under the tiles' node: against the anchor.
func _tile_place(key: Vector2i) -> Vector3:
	return Vector3(key.x * TILE - _anchor_x, 0.0, -key.y * TILE + _anchor_y)

func _outside(key: Vector2i) -> bool:
	return absi(key.x-center.x)>RANGE or absi(key.y-center.y)>RANGE
