## Real generated roads and committed landmark meshes: clearance, bounded rendering
## cost, regional identity and floating-origin placement. No saved preferences used.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const Scenery := preload("res://view/network_scenery.gd")
var failed := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	var sim = Sim.new({"track": "network"})
	var world = World.new()
	root.add_child(world)
	world.build(sim, null)
	var art = world.scenery
	check("all15regional landmarks exist", art.landmarks.size() == 15)
	var styles := {}
	var vertices := 0
	var nearest := INF
	for landmark in art.landmarks:
		styles[landmark.biome] = true
		var mesh: ArrayMesh = landmark.node.mesh
		check("batched body and light surfaces", mesh.get_surface_count() == 2)
		var bounds := mesh.get_aabb()
		check("mesh fits declared horizontal radius", maxf(absf(bounds.position.x), absf(bounds.end.x)) < Scenery.RADIUS and maxf(absf(bounds.position.z), absf(bounds.end.z)) < Scenery.RADIUS)
		for sf in mesh.get_surface_count():
			vertices += mesh.surface_get_array_len(sf)
		# Query densely against actual generated/carried road geometry, independently
		# of the coarse placement mask. Keep the scene outside every road's footprint.
		for r in sim.roads.size():
			var R = sim.roads[r]
			for i in range(0, R.N, 8):
				var p: Vector2 = world._wxy(r, i)
				var clearance := p.distance_to(Vector2(landmark.x, landmark.y)) - float(R.w[i]) / 2.0 - Scenery.RADIUS
				nearest = minf(nearest, clearance)
	art.sync(300000.0, 299000.0)
	for landmark in art.landmarks:
		check("floating-origin placement", landmark.node.position.distance_to(Vector3(landmark.x - 300000, 0, -(landmark.y - 299000))) < 0.05)
	check("five regional silhouettes", styles.size() == 5)
	check("clear of every road with between-sample margin", nearest > 100.0)
	check("bounded static geometry", vertices < 50000)
	print("SCENERY geometry: %d vertices, nearest road clearance %.1f m" % [vertices, nearest])
	print("NETWORK SCENERY %s (%d checks, %d failures)" % ["PASS" if failed == 0 else "FAIL", checks, failed])
	quit(int(failed > 0))
