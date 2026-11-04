## Test emitted paint vertices/interiors against actual graded and banked deck triangles.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
var failed := 0
var probes := 0
var worst := 0.0
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var sim = Sim.new({"track":"network"})
	var world = World.new()
	root.add_child(world)
	world.build(sim,null)
	for jump in sim.jumps:
		var r := int(jump[0])
		for fraction in [0.45,0.9]:
			_probe(world,sim,r,int((sim.roads[r].N-1)*fraction))
	for twist in sim.NET_TWISTS:
		for fraction in [0.25,0.5,0.75]:
			_probe(world,sim,int(twist[0]),int(lerpf(float(twist[1]),float(twist[2]),fraction)))
	print("PAINT SURFACE ","PASS" if failed==0 else "FAIL"," probes=",probes," failed=",failed," max deviation=",worst)
	world.free()
	quit(0 if failed==0 else 1)

## Independent ray tests against the same committed triangle geometry the player sees.
## A centreline height projection is insufficient on twisted/curved cross-sections.
func _probe(world,sim,r: int,i: int) -> void:
	var road=sim.roads[r]
	var ox: float=road.px[i]
	var oy: float=road.py[i]
	var grid: Dictionary={"r":r,"ox":ox,"oy":oy,"u0":0.0,"rv":PackedVector3Array(),"rn":PackedVector3Array(),"ru":PackedVector2Array(),"rows":0,"cols":0,"joins":true}
	var section: Dictionary=world._section(road.w[i])
	for row in range(i-8,i+9): world._road_row(grid,road,section,row,world._h(r,row))
	var indices: PackedInt32Array=world._grid_index(grid.rows,grid.cols)
	var normal: Vector3=world.shaft.at(r,float(i))[5] if world.shaft.on(r,float(i)) else Vector3.UP
	for way in [-1.0,1.0]:
		for kind in 2:
			var st:=SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if kind==0: world._chevron(st,road,ox,oy,i,world._h(r,i),way)
			else: world._approach_arrow(st,road,ox,oy,i,world._h(r,i),way,0)
			var mesh:=st.commit()
			var verts: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for k in range(0,verts.size(),3):
				for point in [verts[k],verts[k+1],verts[k+2],(verts[k]+verts[k+1]+verts[k+2])/3.0]:
					var best:=INF
					for t in range(0,indices.size(),3):
						var hit=Geometry3D.ray_intersects_triangle(point+normal*10,-normal,grid.rv[indices[t]],grid.rv[indices[t+1]],grid.rv[indices[t+2]])
						if hit!=null:
							var distance: float=normal.dot(point-hit)
							if absf(distance)<absf(best): best=distance
					if best<0.03 or best>0.32:
						if failed<6: print("PAINT PROBE r=",r," i=",i," point=",point," clearance=",best)
						failed+=1
					worst=maxf(worst,absf(best-0.1))
					probes+=1
