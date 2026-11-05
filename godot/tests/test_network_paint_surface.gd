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
		for kind in 4:
			var st:=SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if kind==0: world._chevron(st,road,ox,oy,i,world._h(r,i),way)
			elif kind==1: world._approach_arrow(st,road,ox,oy,i,world._h(r,i),way,0)
			elif kind==2:
				world._up=normal
				world._strip(st,road,ox,oy,i,road.w[i]*0.275-1.75,road.w[i]*0.275+1.75,world._h(r,i)+0.12,world._h(r,i+1)+0.12,Color.WHITE)
			else:
				var along: Vector3=Vector3(road.tx[i],0,-road.ty[i])*way
				world._across(st,road,ox,oy,i,world._h(r,i),along*25,along*39,Color.WHITE)
			var mesh:=st.commit()
			var verts: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			for k in range(0,verts.size(),3):
				for point in [verts[k],verts[k+1],verts[k+2],(verts[k]+verts[k+1]+verts[k+2])/3.0]:
					# Move a fraction into the painted triangle to avoid float rounding at
					# the deck's exact outer edge; cast along this paint face's normal.
					point=point.lerp((verts[k]+verts[k+1]+verts[k+2])/3.0,0.002)
					var ray_normal:=normals[k]
					var best:=INF
					for t in range(0,indices.size(),3):
						var hit=Geometry3D.ray_intersects_triangle(point+ray_normal*10,-ray_normal,grid.rv[indices[t]],grid.rv[indices[t+1]],grid.rv[indices[t+2]])
						if hit!=null:
							var distance: float=ray_normal.dot(point-hit)
							if absf(distance)<absf(best): best=distance
					if absf(best-0.1)>0.005:
						if failed<6: print("PAINT PROBE r=",r," i=",i," point=",point," clearance=",best)
						failed+=1
					worst=maxf(worst,absf(best-0.1))
					probes+=1
