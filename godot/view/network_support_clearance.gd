## Static supports must not occupy another road's pavement/furniture volume. Reuse the world's
## chunk grid, then cache only nearby exact envelopes. No map-wide segment scan while streaming.
extends RefCounted

const Shaft := preload("res://view/network_shaft.gd")
const CH := 40
const CELL := 8000.0
const SIDE_MARGIN := 1.0   # outer mast/beacon reaches 0.85 m beyond the pavement
const DECK := 5.0
const FURNITURE_H := 25.0   # 24 m mast and its beacon, above the banked edge
const FACES := [[0,1,5,4], [2,6,7,3], [0,4,6,2], [1,3,7,5], [0,2,3,1], [4,5,7,6]]

var sim
var shaft
var grid: Dictionary
var heights: Array
var geometry := {}   # Vector2i(road,chunk) -> local prism rows + segment AABBs


func setup(s, carried, source_grid: Dictionary, sample_heights: Array) -> void:
	sim = s
	shaft = carried
	heights = sample_heights
	grid = {} if source_grid.is_empty() else source_grid
	if grid.is_empty():
		# pillar_specs is also called before build() (collision/tests). A path's arc length is
		# a conservative bound on its displacement; this fallback visits chunks, not every row.
		if shaft == null:
			shaft = Shaft.new()
			shaft.setup(sim)
		for r in sim.roads.size():
			var road: CraftSim.TrackPath = sim.roads[r]
			var radius: float = CH * float(Array(road.len).max()) + float(Array(road.w).max()) * 0.5 + 64.0
			for first in range(0, road.N - 1, CH):
				var x := float(road.px[first])
				var y := float(road.py[first])
				if shaft.on(r, float(first)):
					var at: Array = shaft.at(r, float(first))
					x = at[0]
					y = at[1]
				for gx in range(floori((x-radius)/CELL), floori((x+radius)/CELL)+1):
					for gy in range(floori((y-radius)/CELL), floori((y+radius)/CELL)+1):
						var key := Vector2i(gx,gy)
						if not grid.has(key):
							grid[key] = []
						grid[key].append([r, first / CH, x, y, radius])


func blocks(owner: int, pillar: Dictionary) -> bool:
	var half: float = pillar.halfSize
	var seen := {}
	for gx in range(floori((pillar.x-half)/CELL), floori((pillar.x+half)/CELL)+1):
		for gy in range(floori((pillar.y-half)/CELL), floori((pillar.y+half)/CELL)+1):
			for entry in grid.get(Vector2i(gx,gy), []):
				var key := Vector2i(entry[0],entry[1])
				if key.x == owner or seen.has(key):
					continue
				seen[key] = true
				var dx: float = pillar.x - entry[2]
				var dy: float = pillar.y - entry[3]
				var reach: float = entry[4] + half * sqrt(2.0)
				if dx*dx + dy*dy > reach*reach:
					continue
				if _hits_chunk(key, pillar):
					return true
	return false


func _row(r: int, i: int, ox: float, oy: float) -> PackedVector3Array:
	var road: CraftSim.TrackPath = sim.roads[r]
	var h: float = heights[r][i] if r < heights.size() else sim.net_height(r,float(i))
	var centre := Vector3(road.px[i]-ox, road.py[i]-oy, h)
	var left := Vector3(road.nx[i], road.ny[i], 0)
	var up := Vector3(0,0,1)
	if shaft != null and shaft.on(r,float(i)):
		var at: Array = shaft.at(r,float(i))
		centre = Vector3(float(at[0])-ox,float(at[1])-oy,at[2])
		var l: Vector3 = at[4]
		var n: Vector3 = at[5]
		left = Vector3(l.x,-l.z,l.y)
		up = Vector3(n.x,-n.z,n.y)
	var half: float = road.w[i] * 0.5 + SIDE_MARGIN
	var top := CraftSim.net_edge(road.w[i],road.w[i]*0.5).x + FURNITURE_H
	return PackedVector3Array([centre-left*half-up*DECK, centre+left*half-up*DECK,
		centre-left*half+up*top, centre+left*half+up*top])


func _chunk(key: Vector2i) -> Dictionary:
	if geometry.has(key):
		return geometry[key]
	var road: CraftSim.TrackPath = sim.roads[key.x]
	var first := key.y * CH
	var last := mini(first + CH,road.N-1)
	var ox := float(road.px[first])
	var oy := float(road.py[first])
	var rows: Array[PackedVector3Array] = []
	var bounds: Array[AABB] = []
	for i in range(first,last+1):
		rows.append(_row(key.x,i,ox,oy))
		if rows.size() > 1:
			var box := AABB(rows[-2][0],Vector3.ZERO)
			for p in rows[-2] + rows[-1]:
				box = box.expand(p)
			bounds.append(box)
	var result := {"ox":ox,"oy":oy,"rows":rows,"bounds":bounds}
	geometry[key] = result
	return result


func _hits_chunk(key: Vector2i, pillar: Dictionary) -> bool:
	var chunk := _chunk(key)
	var half := float(pillar.halfSize)
	var x: float = pillar.x - chunk.ox
	var y: float = pillar.y - chunk.oy
	var box := AABB(Vector3(x-half,y-half,pillar.zMin),Vector3(half*2,half*2,pillar.zMax-pillar.zMin))
	var rows: Array = chunk.rows
	for i in (chunk.bounds as Array).size():
		if not (chunk.bounds[i] as AABB).grow(0.001).intersects(box):
			continue
		var points: PackedVector3Array = rows[i] + rows[i+1]
		var low := INF
		var high := -INF
		# Clipping the closed prism's faces yields its vertical interval over the actual square
		# footprint. Sampling only its centre or using whole-segment min heights misses ramps.
		for face in FACES:
			for triangle in [[face[0],face[1],face[2]],[face[0],face[2],face[3]]]:
				var poly := PackedVector3Array([points[triangle[0]],points[triangle[1]],points[triangle[2]]])
				poly = _clip(poly,0,x-half,true)
				poly = _clip(poly,0,x+half,false)
				poly = _clip(poly,1,y-half,true)
				poly = _clip(poly,1,y+half,false)
				for p in poly:
					low = minf(low,p.z)
					high = maxf(high,p.z)
		if low <= float(pillar.zMax) + 0.001 and high >= float(pillar.zMin) - 0.001:
			return true
	return false


static func _clip(poly: PackedVector3Array, axis: int, limit: float, greater: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	if poly.is_empty():
		return out
	var previous := poly[-1]
	var was_inside := previous[axis] >= limit if greater else previous[axis] <= limit
	for current in poly:
		var inside := current[axis] >= limit if greater else current[axis] <= limit
		if inside != was_inside:
			out.append(previous.lerp(current,(limit-previous[axis])/(current[axis]-previous[axis])))
		if inside:
			out.append(current)
		previous = current
		was_inside = inside
	return out
