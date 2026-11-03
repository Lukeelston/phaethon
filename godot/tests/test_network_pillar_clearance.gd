## Supports share one render/collision source. Their square footprint must clear every other
## road's pavement/furniture volume, including parallel overlaps and height changes across it.
## The K0/K2 witnesses are generated-map regressions; the tiny real TrackPaths isolate geometry.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var sim := Sim.new({"track": "network"})
	var world := World.new()
	world.sim = sim
	for name in ["K0", "K2"]:
		var r := -1
		for k in sim.roads.size():
			if sim.roads[k].name == name:
				r = k
		_check("generated %s exists" % name, r >= 0)
		if r < 0:
			continue
		var bad_id := -(r * 1000000 + 7280 * 2 + 1)
		var specs := world.pillar_specs(r, 7280)
		_check("%s/7280 support cannot pierce the highway below" % name, specs.all(func(p): return int(p.id) != bad_id))
		var x := 299901.20 if name == "K0" else 434004.28
		var y := 165598.40 if name == "K0" else 299995.38
		_check("%s collision index also omits that support" % name,
			world.obstacles_near(x, y, 80.0).all(func(p): return int(p.id) != bad_id))
	_check("pre-build queries leave the streaming grid untouched", world.grid.is_empty())
	root.add_child(world)
	world.build(sim, null)
	for name in ["K0", "K2"]:
		for r in sim.roads.size():
			if sim.roads[r].name == name:
				var bad_id := -(r * 1000000 + 7280 * 2 + 1)
				_check("%s/7280 also clears with the built world's grid" % name,
					world.pillar_specs(r, 7280).all(func(p): return int(p.id) != bad_id))
	_rendered_templates(world)
	world.free()
	_template_fixture()
	# The source deck is 100 m up, with square 14 m supports at (0,-20) and (0,+20).
	_case("perpendicular road through both supports", [Vector2(0,-100), Vector2(0,100)], 20.0, 0.0, 0.0, [])
	_case("parallel road clips footprint though centre is outside", [Vector2(-100,-32), Vector2(100,-32)], 12.0, 0.0, 0.0, [-2])
	_case("parallel road clips the outer furniture envelope", [Vector2(-100,-33.5), Vector2(100,-33.5)], 12.0, 0.0, 0.0, [-2])
	_case("parallel road beyond footprint keeps both", [Vector2(-100,-50), Vector2(100,-50)], 12.0, 0.0, 0.0, [-1,-2])
	_case("diagonal road clips only the square's corner", [Vector2(-100,-134), Vector2(100,66)], 2.0, 0.0, 0.0, [-2])
	_case("diagonal near miss keeps both", [Vector2(-100,-142), Vector2(100,58)], 2.0, 0.0, 0.0, [-1,-2])
	_case("road entirely above support keeps both", [Vector2(0,-100), Vector2(0,100)], 20.0, 200.0, 200.0, [-1,-2])
	_case("road and its furniture below support base keep both", [Vector2(0,-100), Vector2(0,100)], 20.0, -60.0, -60.0, [-1,-2])
	_case("ramp crosses support top away from nearest centre", [Vector2(-20,-20), Vector2(20,-20)], 12.0, 150.0, 70.0, [-2])
	_case("ramp only falls below top outside footprint keeps both", [Vector2(-20,-20), Vector2(20,-20)], 12.0, 170.0, 90.0, [-1,-2])
	print("NETWORK PILLAR CLEARANCE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _rendered_templates(world) -> void:
	var r := -1
	for k in world.sim.roads.size():
		if world.sim.roads[k].name == "N2":
			r = k
	_check("N2 exists for the rendered template regression", r >= 0)
	if r < 0:
		return
	_check("N2 crossing and ordinary chunks need different supports",
		world.pillar_specs(r,3120).is_empty() and world.pillar_specs(r,3240).size() == 2)
	_rendered_template_pair(world,r,3120,3240,"N2",false)


func _template_fixture() -> void:
	var sim := Sim.new({"track":"range"})
	sim.kind = "network"
	var points := []
	for i in 241:
		points.append(Vector2(i*24,0))
	sim.roads.append(_road(points,100.0))
	sim.roads.append(_road([Vector2(960,-100),Vector2(960,100)],20.0))
	# A power-of-two Hermite interval keeps each evaluated row exactly flat, so this
	# exercises the real cache without changing its production equality tolerance.
	sim._net_h = {0:[[0,600.0,0.0],[256,600.0,0.0]],1:[[0,0.0,0.0],[1,0.0,0.0]]}
	var world := World.new()
	root.add_child(world)
	world.build(sim,null)
	_check("template fixture crossing clears two supports, ordinary chunk retains two",
		world.pillar_specs(0,40).is_empty() and world.pillar_specs(0,160).size() == 2)
	_rendered_template_pair(world,0,40,160,"flat fixture",true)
	world.free()


func _rendered_template_pair(world, r: int, blocked: int, clear: int, label: String, require_template: bool) -> void:
	# The same straight road, width, height and decoration phase used to share one mesh.
	# Exercise both cache orders: a normal exemplar must not restore a blocked support,
	# and a crossing exemplar must not erase the ordinary chunk's supports.
	for order in [[clear,blocked],[blocked,clear]]:
		world._deco_templates.clear()
		for sample in order:
			var key := Vector2i(r,int(sample) / World.CH)
			world._start_chunk(r,key.y)
			if require_template:
				_check("%s/%d is eligible for cached decoration" % [label,sample],world._job.template_key != "")
			world._work(Time.get_ticks_usec() + 60000000)
			var mesh: ArrayMesh = world.chunks[key][0].get_node("road").mesh
			var support_triangles := 0
			for surface in range(1,mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices := PackedInt32Array() if arrays[Mesh.ARRAY_INDEX] == null else arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
				for i in range(0,indices.size() if not indices.is_empty() else vertices.size(),3):
					var low := INF
					for j in 3:
						low = minf(low,vertices[indices[i+j] if not indices.is_empty() else i+j].y)
					if low < 1.0:
						support_triangles += 1
			_check("rendered %s/%d after exemplar %d has %d support triangles" % [label,sample,order[0],support_triangles],
				(support_triangles == 0) if sample == blocked else (support_triangles > 0))
		for sample in order:
			var key := Vector2i(r,int(sample) / World.CH)
			world.chunks[key][0].free()
			world.chunks.erase(key)


func _case(label: String, points: Array, width: float, h0: float, h1: float, expected: Array) -> void:
	var sim := Sim.new({"track": "range"})
	sim.kind = "network"
	sim.roads.clear()
	sim.roads.append(_road([Vector2(0,0),Vector2(24,0)], 100.0))
	sim.roads.append(_road(points, width))
	sim._net_h = {0: [[0,100.0,0.0],[1,100.0,0.0]],
		1: [[0,h0,(h1-h0)/24.0],[1,h1,(h1-h0)/24.0]]}
	var world := World.new()
	world.sim = sim
	var actual: Array = world.pillar_specs(0, 0).map(func(p): return int(p.id))
	_check("%s: %s" % [label, actual], actual == expected)
	# Collision output must use the same filtered support list, without putting a hidden box back.
	var colliding: Array = world.obstacles_near(0.0, 0.0, 50.0).filter(func(p): return int(p.id) == -1 or int(p.id) == -2).map(func(p): return int(p.id))
	colliding.sort()
	var want := expected.duplicate()
	want.sort()
	_check(label + " collision agrees", colliding == want)
	world.free()


func _road(points: Array, width: float) -> Sim.TrackPath:
	var road := Sim.TrackPath.new()
	road.N = points.size()
	for i in points.size():
		var delta: Vector2 = points[mini(i + 1, points.size() - 1)] - points[maxi(0, i - 1)]
		var t := delta.normalized()
		road.px.append(points[i].x)
		road.py.append(points[i].y)
		road.tx.append(t.x)
		road.ty.append(t.y)
		road.nx.append(-t.y)
		road.ny.append(t.x)
		road.len.append(delta.length())
		road.w.append(width)
		road.mode.append(1)
	return road


func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("  ok   " if ok else "  FAIL ") + label)
