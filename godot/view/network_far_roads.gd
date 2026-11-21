## Static low-detail pavement: the route exists on the horizon before furniture streams.
extends Node3D
const STRIDE := 8
const BLOCK := 400 # ~9.6 km, bounded AABBs for renderer culling
const UNDER_DECK := 8.0 # coarse chords stay below the detailed curves during handoff
var pieces := []
var vertex_count := 0
func build(world) -> void:
	var material := ShaderMaterial.new()
	material.shader = preload("res://view/network_far_roads.gdshader")
	for r in world.sim.roads.size():
		var road = world.sim.roads[r]
		var pressure_route: bool = r == world.sim.NET_PRESSURE[0]
		for first in range(0,road.N-1,BLOCK):
			var end := mini(first+BLOCK,road.N-1)
			if pressure_route and world.sim.in_pressure(r, first) and world.sim.in_pressure(r, end):
				continue
			var origin: Vector2 = world._wxy(r,first)
			var vertices := PackedVector3Array()
			var indices := PackedInt32Array()
			var samples := range(first,end,STRIDE)
			samples.append(end)
			for i in samples:
				for side in [-1.0,1.0]:
					var off: float = side*road.w[i]*0.5
					# _p handles both carried shafts and twisting recovery decks.
					var h: float = world._h(r,i)-UNDER_DECK
					vertices.append(world._p(road,origin.x,origin.y,i,off,h))
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
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var instance := MeshInstance3D.new()
			instance.mesh=mesh
			instance.material_override=material
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.visibility_range_end=110000
			instance.position=Vector3(origin.x,0,-origin.y)
			add_child(instance)
			pieces.append([instance,origin,r,first,end])
			vertex_count+=vertices.size()
func sync(ox: float,oy: float) -> void:
	position=Vector3(-ox,0,oy)
