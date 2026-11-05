## Neighbouring chunks must share identical shoulder vertices at physical merges.
## Different facet counts can create a vertical ledge even when both chunks
## independently pass the centreline/guardrail clearance checks.
extends SceneTree
const Sim:=preload("res://sim/craft_sim.gd")
const World:=preload("res://view/network_world.gd")
var failed:=0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var sim=Sim.new({"track":"network"})
	var world=World.new()
	root.add_child(world)
	world.build(sim,null)
	var cases:={}
	for ji in range(sim.junctions.size(),sim.surface_junctions.size()):
		var join: Array=sim.surface_junctions[ji]
		for side in [0,3]:
			var r:=int(join[side])
			for sample in [int(join[side+1])-4,int(join[side+2])+4]:
				var k: int=sample/World.CH
				for boundary in [k,k+1]:
					if boundary>0 and (boundary+1)*World.CH<sim.roads[r].N:
						cases[Vector2i(r,boundary)]=true
	var worst:=0.0
	for key in cases:
		var rows:=[]
		for k in [key.y-1,key.y]:
			var chunk_key:=Vector2i(key.x,k)
			if not world.chunks.has(chunk_key) or world.chunks[chunk_key][0].get_node_or_null("road")==null: world._build_chunk(key.x,k)
			var entry: Array=world.chunks[chunk_key]
			var vertices: PackedVector3Array=entry[0].get_node("road").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var cols:=vertices.size()/(World.CH+1)
			var row:=vertices.slice(vertices.size()-cols) if k==key.y-1 else vertices.slice(0,cols)
			for i in row.size(): row[i]+=Vector3(entry[1],0,-entry[2])
			rows.append(row)
		if rows[0].size()!=rows[1].size():
			failed+=1
			if failed<5: print("SEAM facet mismatch ",key,": ",rows[0].size()," vs ",rows[1].size())
		else:
			for i in rows[0].size(): worst=maxf(worst,rows[0][i].distance_to(rows[1][i]))
	failed+=int(worst>0.08)
	print("CHUNK SEAMS ","PASS" if failed==0 else "FAIL"," boundaries=",cases.size()," mismatches=",failed," worst=",worst)
	world.free()
	quit(int(failed>0))
