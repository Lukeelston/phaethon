## Fixed geographic terrain. Only render transforms depend on the floating origin.
## Shared 512 m vertices, with whole road-adjacent triangles held below the decks.
extends Node3D
const TILE := 8192.0
const STEP := 512.0
const GRID := 16
const RANGE := 5
const MAX_TILES := 121
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
var prop_library
var water_material: ShaderMaterial
var clouds: MeshInstance3D
var _environment: Environment
var prop_slices_max := 0.0
var _decor_job := {}
const PROP_CELL := 256.0

func build(sim, world) -> void:
	_sim = sim
	_world = world
	world.scenery_ground_height = -4.0
	noise.seed = 28471
	noise.frequency = 0.00011
	noise.fractal_octaves = 4
	detail.seed = 734
	detail.frequency = 0.0006
	detail.fractal_octaves = 3
	material = ShaderMaterial.new()
	material.shader = preload("res://view/network_terrain.gdshader")
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
			var c := Vector2i(floori(p.x / STEP), floori(p.y / STEP))
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
	clouds.position.y = 12000
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = preload("res://view/network_clouds.gdshader")
	clouds.material_override = cloud_material
	add_child(clouds)
	if world.view != null:
		for child in world.view.get_children():
			if child is WorldEnvironment:
				_environment = child.environment

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
	if factor == 0.0:
		return -4.0
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
	return lerpf(-4.0, h, factor)

func color_at(p: Vector2) -> Color:
	var w := weights(p)
	var col := Color(0,0,0,1)
	var n := detail.get_noise_2dv(p)
	var h := height_at(p)
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
	return col

## Exact piecewise-linear height of the visible two triangles, also used by prop feet.
func surface_at(p: Vector2) -> float:
	var c := Vector2(floorf(p.x / STEP), floorf(p.y / STEP)) * STEP
	var f := (p - c) / STEP
	var a := height_at(c)
	var b := height_at(c + Vector2(STEP,0))
	var d := height_at(c + Vector2(0,STEP))
	if f.x + f.y <= 1.0:
		return a + (b-a)*f.x + (d-a)*f.y
	var e := height_at(c + Vector2(STEP,STEP))
	return e + (d-e)*(1.0-f.x) + (b-e)*(1.0-f.y)

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
func prop_records(key: Vector2i, first := 0, count := 64) -> Array:
	var records := []
	var rng := RandomNumberGenerator.new()
	var origin := Vector2(key)*TILE
	for group in range(first,mini(first+count,64)):
		rng.seed = int(key.x)*73856093 ^ int(key.y)*19349663 ^ (937 + group*83492791)
		var anchor := origin + Vector2(rng.randf(),rng.randf())*TILE
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
		for k in number:
			var p := anchor + Vector2(rng.randf_range(-240,240),rng.randf_range(-240,240))
			var scale := rng.randf_range(0.75,1.8)
			if region == "jungle" and kind == "oak": scale *= 1.7
			var radius := (185.0 if kind == "urban" else (90.0 if kind in ["farm","industrial","outpost"] else 35.0))*scale
			if not clear_at(p,radius): continue
			var h := surface_at(p)
			var slope := maxf(absf(surface_at(p+Vector2(radius,0))-h),absf(surface_at(p+Vector2(0,radius))-h)) / radius
			if slope > (0.045 if kind in ["urban","farm","outpost","industrial","stilt"] else 0.5): continue
			if h < -2.0 and region == "swamp" and kind not in ["mangrove","reeds","stilt"]: continue
			records.append({"kind":kind,"p":p,"height":h,"radius":radius,"scale":scale,"yaw":rng.randf()*TAU})
	return records

func _decorate_slice() -> void:
	var start := Time.get_ticks_usec()
	var key: Vector2i = _decor_job.key
	var batches: Dictionary = _decor_job.batches
	for prop in prop_records(key,_decor_job.group,4):
		if not batches.has(prop.kind): batches[prop.kind] = []
		var local: Vector2 = prop.p-Vector2(key)*TILE
		batches[prop.kind].append(Transform3D(Basis(Vector3.UP,prop.yaw).scaled(Vector3.ONE*prop.scale),Vector3(local.x,prop.height,-local.y)))
	_decor_job.group += 4
	if _decor_job.group == 64:
		var root := Node3D.new()
		tiles[key].node.add_child(root)
		tiles[key].deco = root
		for kind in batches:
			prop_library.batch(root,kind,batches[kind])
		_decor_job.clear()
	prop_slices_max = maxf(prop_slices_max,float(Time.get_ticks_usec()-start)/1000.0)

func _water(key: Vector2i, node: Node3D) -> void:
	# Below road level. Only wetland tiles, with shoreline supplied by their terrain.
	if weights((Vector2(key)+Vector2.ONE*0.5)*TILE)[5]<0.60: return
	var instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(TILE,TILE)
	instance.mesh = plane
	instance.position = Vector3(TILE/2,-2.0,-TILE/2)
	instance.material_override = water_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(instance)

func vertex_at(key: Vector2i, x: int, y: int) -> Vector3:
	var p := Vector2(key) * TILE + Vector2(x,y) * STEP
	return Vector3(x * STEP, height_at(p), -y * STEP)

func _new_job(key: Vector2i) -> Dictionary:
	return {"key":key, "row":0, "vertices":PackedVector3Array(), "colors":PackedColorArray(), "normals":PackedVector3Array(), "uvs":PackedVector2Array()}

func _rows(job: Dictionary, count: int) -> void:
	var key: Vector2i = job.key
	for y in range(job.row, mini(job.row + count, GRID + 1)):
		for x in GRID + 1:
			var p := Vector2(key)*TILE + Vector2(x,y)*STEP
			job.vertices.append(vertex_at(key,x,y))
			job.colors.append(color_at(p))
			job.uvs.append(Vector2(p.x,-p.y)/256.0)
			job.normals.append(Vector3(height_at(p-Vector2(STEP,0))-height_at(p+Vector2(STEP,0)), STEP*2.0, height_at(p+Vector2(0,STEP))-height_at(p-Vector2(0,STEP))).normalized())
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
		if not _decor_job.is_empty() and (absi(_decor_job.key.x-c.x)>2 or absi(_decor_job.key.y-c.y)>2):
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
			add_child(node)
			_water(_job.key,node)
			tiles[_job.key] = {"node":node, "key":_job.key}
			_job.clear()
	for key in tiles:
		tiles[key].node.position = Vector3(key.x*TILE-ox,0,-key.y*TILE+oy)
	for key in tiles:
		var near := absi(key.x-center.x)<=2 and absi(key.y-center.y)<=2
		var tile: Dictionary = tiles[key]
		if not near and tile.has("deco"):
			tile.deco.queue_free()
			tile.erase("deco")
		elif near and not tile.has("deco") and _decor_job.is_empty():
			_decor_job = {"key":key,"group":0,"batches":{}}
	if not _decor_job.is_empty() and Time.get_ticks_usec()-start<1800:
		_decorate_slice()
	clouds.material_override.set_shader_parameter("world_offset",Vector2(fposmod(ox,2304000.0),fposmod(-oy,2304000.0)))
	if _environment != null:
		var w := weights(Vector2(ox,oy))
		_environment.fog_density = 0.00011 + w[5]*0.00009 + w[6]*0.00005 + w[3]*0.00002
		_environment.fog_light_color = Color(0.58,0.68,0.80).lerp(Color(0.63,0.69,0.65),w[5]*0.25+w[6]*0.15).lerp(Color(0.76,0.69,0.58),w[3]*0.3)
	max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec()-start)/1000.0)

func _outside(key: Vector2i) -> bool:
	return absi(key.x-center.x)>RANGE or absi(key.y-center.y)>RANGE
