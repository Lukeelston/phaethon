## Actual emitted furniture: cache equivalence and far-end-only junction openings.
extends SceneTree
const Sim:=preload("res://sim/craft_sim.gd")
const World:=preload("res://view/network_world.gd")
var failed:=0
func _initialize() -> void: _run.call_deferred()
func check(label: String,ok: bool) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	failed+=int(not ok)
func _run() -> void:
	var sim=Sim.new({"track":"network"})
	var world=World.new()
	root.add_child(world)
	world.build(sim,null)
	if not world._job.is_empty(): world._work(Time.get_ticks_usec()+60000000)
	_cache(world,sim)
	_openings(world,sim)
	world.free()
	print("NETWORK FURNITURE ","PASS" if failed==0 else "FAIL")
	quit(int(failed>0))
func _cache(world,sim) -> void:
	var key:=Vector2i(0,80)
	world._build_chunk(key.x,key.y) # prime this exact template
	var meshes:=[]
	var origin:=Vector2.ZERO
	for use_cache in [false,true]: # leave the cached instance alive for the origin-shift check
		world.chunks[key][0].free()
		world.chunks.erase(key)
		world._start_chunk(key.x,key.y)
		check("straight road has an eligible CPU decoration template",not world._job.template.is_empty())
		if not use_cache:
			world._job.template=[]
			world._job.template_key=""
		world._work(Time.get_ticks_usec()+60000000)
		var entry: Array=world.chunks[key]
		meshes.append(entry[0].get_node("road").mesh)
		origin=Vector2(entry[1],entry[2])
	var equal: bool=meshes[0].get_surface_count()==meshes[1].get_surface_count()
	var worst:=0.0
	if equal:
		for surface in meshes[0].get_surface_count():
			var a: Array=meshes[0].surface_get_arrays(surface)
			var b: Array=meshes[1].surface_get_arrays(surface)
			equal=equal and a[Mesh.ARRAY_VERTEX].size()==b[Mesh.ARRAY_VERTEX].size()
			equal=equal and meshes[0].surface_get_material(surface)==meshes[1].surface_get_material(surface)
			for channel in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:
				equal=equal and a[channel]==b[channel]
			if not equal: break
			for i in a[Mesh.ARRAY_VERTEX].size(): worst=maxf(worst,a[Mesh.ARRAY_VERTEX][i].distance_to(b[Mesh.ARRAY_VERTEX][i]))
	check("cached and freshly generated decoration geometry/materials agree",equal and worst<0.01)
	var shifted:=origin+Vector2(1200,-3700)
	world.sync(shifted.x,shifted.y)
	check("floating origin moves cached road once",world.chunks[key][0].position.distance_to(Vector3(-1200,0,-3700))<0.01)
func _openings(world,sim) -> void:
	var cases:=0
	var intrusions:=0
	for join in sim.junctions:
		var r:=int(join[3])
		var road=sim.roads[r]
		for i in range(maxi(0,int(join[4])-3),mini(road.N-1,int(join[5])+3)):
			for side in [-1.0,1.0]:
				if world._open(r,i,side) or not world._open(r,i+1,side): continue
				world._start_chunk(r,i/World.CH)
				var job: Dictionary=world._job
				job.c0=i
				job.c1=i+1
				job.template=[]
				job.deco_spans[i-i%4]=false
				world._sample(job,road,i)
				var arrays: Array=job.st[1].commit_to_arrays()
				var band: Color=(World.BAND_SF if road.mode[i]==0 else World.BAND)[(i/4)%2]
				var hw: float=road.w[i+1]*0.5
				var at: Vector3=world._p(road,job.ox,job.oy,i+1,side*hw,world._h(r,i+1)+Sim.net_edge(road.w[i+1],hw).x+World.WALL_H)
				for k in (arrays[Mesh.ARRAY_VERTEX].size() if arrays[Mesh.ARRAY_VERTEX]!=null else 0):
					if arrays[Mesh.ARRAY_COLOR][k].is_equal_approx(band) and arrays[Mesh.ARRAY_VERTEX][k].distance_to(at)<0.1: intrusions+=1
				job.node.free()
				world.chunks.erase(job.key)
				world._job={}
				cases+=1
				if cases>=8: break
			if cases>=8: break
		if cases>=8: break
	check("far-end-only junction openings contain no wall tips (%d cases)"%cases,cases>=8 and intrusions==0)
