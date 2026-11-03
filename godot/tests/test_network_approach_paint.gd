## The amber pavement route must begin on the highway and continue through each ramp.
extends SceneTree
const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	if not ok:
		failed += 1
		print("FAIL ", label)

func _run() -> void:
	var sim = Sim.new({"track": "network", "handling": "speed"})
	var world = World.new()
	root.add_child(world)
	world.build(sim, null)
	var routes = world.get("_approaches")
	_check("amber approach routes exist", routes is Dictionary)
	if not routes is Dictionary:
		quit(1)
		return
	var highway_routes := 0
	var ramp_routes := 0
	var vertices := 0
	for r in routes:
		var R = sim.roads[r]
		for guide in routes[r]:
			if R.name.begins_with("R"):
				ramp_routes += 1
				_check(R.name + " route runs through its mouth to the fork", int(guide[1]) - int(guide[0]) >= 35 and float(guide[3]) == 0.0)
			else:
				highway_routes += 1
				_check(R.name + " gives four miles of amber guidance", (int(guide[1]) - int(guide[0])) * 24.0 >= 6400.0)
				_check(R.name + " guidance occupies the approach's right lane", float(guide[3]) * float(guide[2]) < -60.0)
			var at := (int(guide[0]) + int(guide[1])) / 2
			var key := Vector2i(r, at / World.CH)
			world._build_chunk(r, key.y)
			var node: Node3D = world.chunks[key][0]
			for child in node.get_children():
				if not child is MeshInstance3D or child.name != "road":
					continue
				for si in child.mesh.get_surface_count():
					if child.mesh.surface_get_material(si) != world._strip_mat:
						continue
					var arrays: Array = child.mesh.surface_get_arrays(si)
					for col in arrays[Mesh.ARRAY_COLOR]:
						if absf(col.r - World.JUMP_AMBER.r) + absf(col.g - World.JUMP_AMBER.g) + absf(col.b - World.JUMP_AMBER.b) < 0.01:
							vertices += 1
	_check("twenty highway and twenty ramp approaches", highway_routes == 20 and ramp_routes == 20)
	_check("guidance is present in the committed glowing road mesh", vertices > 1000)
	print("APPROACH PAINT ", "PASS" if failed == 0 else "FAIL", " highways=", highway_routes, " ramps=", ramp_routes, " amber vertices=", vertices)
	quit(0 if failed == 0 else 1)
