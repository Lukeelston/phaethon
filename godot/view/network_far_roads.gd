## Static low-detail pavement: the route exists on the horizon before furniture streams.
extends Node3D
const STRIDE := 8
const BLOCK := 400 # ~9.6 km, bounded AABBs for renderer culling
const UNDER_DECK := 8.0 # coarse chords stay below the detailed curves during handoff
var pieces := []
var vertex_count := 0
var _material: ShaderMaterial
## How far the camera draws (CraftView.reach): on the ground the ribbons fade out between 80 and 100 km,
## as they did; from high up (Mount Hyperion's summit) they run on to the camera's reach.
func set_reach(reach: float) -> void:
	var far := maxf(110000.0, reach)
	for piece in pieces:
		(piece[0] as GeometryInstance3D).visibility_range_end = far
	if _material != null:
		_material.set_shader_parameter("fade", Vector2(80000.0, 100000.0) if reach <= 120000.0 else Vector2(reach - 70000.0, reach - 10000.0))
func build(world) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://view/network_far_roads.gdshader")
	_material = material
	for r in world.sim.roads.size():
		var road = world.sim.roads[r]
		var has_aprons: bool = not road.apl.is_empty()
		var pressure_route: bool = r == world.sim.NET_PRESSURE[0]
		for first in range(0,road.N-1,BLOCK):
			var end := mini(first+BLOCK,road.N-1)
			if pressure_route and world.sim.in_pressure(r, first) and world.sim.in_pressure(r, end):
				continue
			var origin: Vector2 = world._wxy(r,first)
			var vertices := PackedVector3Array()
			var glass_edges := PackedVector2Array()
			var indices := PackedInt32Array()
			var stride := _stride(world,r,first,end)
			var samples := range(first,end,stride)
			samples.append(end)
			for i in samples:
				var half_width: float = road.w[i] * 0.5
				var left := half_width
				var right := half_width
				var paved_left := half_width
				var paved_right := half_width
				if has_aprons:
					left += road.apl[i]
					right += road.apr[i]
					# The near glass begins at the old ramp's foot and ends at the moved wall.
					var ramp := CraftSim.net_edge_span(road.w[i])
					if left > half_width or (world.scenic != null and world.scenic.open(r, i, true)):
						paved_left -= ramp
					if right > half_width or (world.scenic != null and world.scenic.open(r, i, false)):
						paved_right -= ramp
				# _p handles both carried shafts and twisting recovery decks.
				var h: float = world._h(r,i)-UNDER_DECK
				for off: float in [-right, left]:
					vertices.append(world._p(road,origin.x,origin.y,i,off,h))
					if has_aprons:
						# Signed distances past the left and right pavement edges; positive on glass.
						glass_edges.append(Vector2(off - paved_left, -off - paved_right))
			for row in samples.size()-1:
				if pressure_route and world.sim.in_pressure(r, samples[row]) and world.sim.in_pressure(r, samples[row + 1]):
					continue
				var a := row*2
				indices.append_array(PackedInt32Array([a,a+2,a+1,a+1,a+2,a+3]))
			if indices.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices
			arrays[Mesh.ARRAY_INDEX]=indices
			if not glass_edges.is_empty():
				arrays[Mesh.ARRAY_TEX_UV] = glass_edges
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var instance := MeshInstance3D.new()
			instance.mesh=mesh
			instance.material_override=material
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end=110000
			instance.position=Vector3(origin.x,0,-origin.y)
			add_child(instance)
			pieces.append([instance,origin,r,first,end,stride])
			vertex_count+=vertices.size()
## The widest stride whose chords stay under the deck over this block. A climb that steepens fast (the
## face of Helios: 15 to 75 degrees in three kilometres) lifts a 190 m chord 20 m over the road it spans.
## Most blocks are settled from the heights the ribbon reads anyway: a chord twice as long sags four times
## as far, so a flat enough second difference at the stride answers without reading every sample.
func _stride(world,r: int,first: int,end: int) -> int:
	var coarse := PackedFloat32Array()
	for i in range(first,end+1,STRIDE):
		coarse.append(world._h(r,i))
	var guess := 0.0
	for k in range(1,coarse.size()-1):
		guess=maxf(guess,((coarse[k-1]+coarse[k+1])*0.5-coarse[k])*0.25)
	if guess<1.5:
		return STRIDE
	var heights := PackedFloat32Array()
	for i in range(first,end+1):
		heights.append(world._h(r,i))
	var stride := STRIDE
	while stride>1:
		var worst := 0.0
		for a in range(first,end,stride):
			var b := mini(a+stride,end)
			for m in range(a+1,b):
				worst=maxf(worst,lerpf(heights[a-first],heights[b-first],float(m-a)/float(b-a))-heights[m-first])
		if worst<=UNDER_DECK-1.0:
			break
		stride/=2
	return stride
func sync(ox: float,oy: float) -> void:
	position=Vector3(-ox,0,oy)
