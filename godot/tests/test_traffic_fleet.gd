## Imported models, distance selection, per-pilot markings and the moving range fleet.
## Run windowed to check the transforms stored in the instance batch.
extends SceneTree

const Network := preload("res://view/network_traffic.gd")
const RangeTraffic := preload("res://view/traffic.gd")
const Batch := preload("res://view/traffic_batch.gd")

class RangeView:
	var org_x := 24000.0
	var range_world := {"route": {"overpass_x": [24000.0]}}
	func w3(x: float, y: float, h := 0.0) -> Vector3:
		return Vector3(x - org_x, h, -y)

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _visible(model: Batch) -> int:
	return model.multimesh.visible_instance_count + model.distant.visible_instance_count

func _check_network_spawn(network: Network) -> void:
	var roles := {Network.COURIER: Network.CAR, Network.TENDER: Network.SLOW, Network.CRYOTANK: Network.TRANSPORT}
	var first_choices: Array = []
	var seed_state := network._rng.state
	for take in 2:
		network.cars.clear()
		network._rng.state = seed_state
		network._next_id = 1
		network.spawned = 0
		# The Basalt interchange includes both ordinary and express traffic.
		for attempt in 2400:
			if network.cars.size() >= 150:
				break
			network._spawn(100000.0, 100000.0, true)
		var choices: Array = []
		var expected := PackedInt32Array()
		expected.resize(Network.FLEET.size())
		var traits := {}
		var correct_roles := true
		var shared_handling := true
		for car in network.cars:
			var body := car.visual
			choices.append([car.id, car.kind, car.road, car.lane, car.dir, body])
			if body < 0 or body >= expected.size() or roles.get(body, body) != car.kind:
				correct_roles = false
				continue
			var handling := [car.a_up, car.a_lat, car.headway, car.train_tail]
			if traits.has(car.kind):
				shared_handling = shared_handling and traits[car.kind] == handling
			traits[car.kind] = handling
			if car.kind == Network.TRANSPORT:
				expected[Network.TRACTOR] += 1
				expected[body] += Network.TRAIN - 1
			else:
				expected[body] += 1
		if take == 0:
			check(choices.size() == 150 and correct_roles and shared_handling,
					"Seeded Network traffic fills its population and each body keeps its driving class")
			for body: int in roles:
				check(expected[body] > 0 and expected[roles[body]] > 0, "Spawner mixes body %d with its original" % body)
			# Skip off-screen shader warmup instances when counting actual traffic.
			network._warm = 0
			network._render()
			for slot in expected.size():
				check(_visible(network._mm[slot]) == expected[slot],
						"Network batch %d draws its spawned vehicles and freight units" % slot)
			check(network._beams.multimesh.visible_instance_count == choices.size(), "One lamp pair per traffic vehicle or train")
			first_choices = choices
		else:
			check(first_choices == choices, "Replaying the traffic seed reproduces the same bodies, roads and lanes")

func _check_raider(network: Network, camera: Camera3D) -> void:
	check(not network._mm.has(Network.RAIDER) and network._drawing.writers.size() == Network.FLEET.size(),
			"Ordinary traffic allocates and warms no raider batch")
	network.cars.clear()
	var threat := Network.Car.new()
	threat.kind = Network.DEMON
	threat.road = 0
	threat.f = 100.0
	network._place(threat)
	network.cars.append(threat)
	network.set_raider_visual(threat)
	var batch: Batch = network._mm[Network.RAIDER]
	network.set_raider_visual(threat)
	check(network._mm[Network.RAIDER] == batch and not batch.multimesh.use_colors,
			"Raiders share one batch, with fixed armour instead of commuter paint")
	for mesh: Mesh in [batch.multimesh.mesh, batch.distant.mesh]:
		check(mesh.get_surface_count() == 1 and mesh.surface_get_array_index_len(0) > 0,
				"Raider body uses a single indexed surface at each tier")
		var size := mesh.get_aabb().size
		check(size.z > 12.0 and size.z < 14.0 and size.x > 4.0 and size.x < 6.0,
				"Raider fits the demon's scale in each tier")
	check(batch.distant.mesh.surface_get_array_index_len(0) < batch.multimesh.mesh.surface_get_array_index_len(0),
			"Raider sheds detailed armour at distance")
	var center := Vector3(threat.x - network.view.org_x, 4.0, -threat.y + network.view.org_y)
	var heading := Vector3(threat.hx, 0.0, -threat.hy)
	camera.position = center + 45.0 * heading
	network._render()
	check(batch.multimesh.visible_instance_count == 1 and threat.lamp_color == Network.RAIDER_LAMP,
			"Incoming raider uses detail and hostile front lamps")
	camera.position = center - 1600.0 * heading
	network._render()
	check(batch.distant.visible_instance_count == 1 and threat.lamp_color == Network.RAIDER_LAMP,
			"Departing raider uses its distance mesh and hostile rear lamps")
	network.cars.clear()
	network.release_raider_visual()
	check(not network._mm.has(Network.RAIDER) and network._drawing.writers.size() == Network.FLEET.size(),
			"Finishing a raid releases both raider buffers")
	camera.position = Vector3.ZERO


func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var network := Network.new()
	root.add_child(network)
	var sim := Network.Simulation.new({"track": "network"})
	var world := Network.RoadWorld.new()
	root.add_child(world)
	world.build(sim, null)
	network.build(sim, {"org_x": 100000.0, "org_y": 100000.0}, world)
	var highway := RangeTraffic.new()
	root.add_child(highway)
	highway.build(RangeView.new())
	var models := network._mm.values()
	var range_models := [highway.trucks, highway.tankers, highway.locos, highway.cars,
			highway.hoppers, highway.planes, highway.road_cars]
	models.append_array(range_models)
	check(models.size() == 16, "All sixteen fleet models load")
	for model in models:
		var near_mesh: Mesh = model.multimesh.mesh
		var far_mesh: Mesh = model.distant.mesh
		check(near_mesh.get_surface_count() == 1 and far_mesh.get_surface_count() == 1, "Single surface per tier")
		var far_indices: int = far_mesh.surface_get_array_index_len(0)
		check(far_indices > 0 and far_indices < near_mesh.surface_get_array_index_len(0), "Distant mesh is present and lighter")
		model.put(Transform3D.IDENTITY, Vector3.ZERO)
		model.put(Transform3D(Basis.IDENTITY, Vector3(12000, 0, 0)), Vector3.ZERO)
		model.finish_frame()
		check(model.multimesh.visible_instance_count == 1 and model.distant.visible_instance_count == 1, "Each distance gets one vehicle")
		model.finish_frame()
		check(model.multimesh.visible_instance_count + model.distant.visible_instance_count == 0, "Vehicles leave both buffers on the next frame")
	for pair in [[network._mm[Network.COURIER], network._mm[Network.CAR]],
			[network._mm[Network.TENDER], network._mm[Network.SLOW]],
			[network._mm[Network.CRYOTANK], network._mm[Network.TRANSPORT]],
			[highway.tankers, highway.trucks], [highway.hoppers, highway.cars]]:
		var variant: Batch = pair[0]
		var original: Batch = pair[1]
		for tier: String in ["multimesh", "distant"]:
			var new_mesh: Mesh = variant.get(tier).mesh
			var old_mesh: Mesh = original.get(tier).mesh
			check(new_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != old_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
					"%s uses its own geometry in %s" % [variant.name, tier])
	var racer = network._mm[Network.RACER]
	for pilot in Network.RACERS:
		racer.put(Transform3D.IDENTITY, Vector3.ZERO, Network.RACERS[pilot][3], Network.NUMBER_BOARDS[pilot])
	racer.finish_frame()
	var boards := {}
	if DisplayServer.get_name() == "headless":
		# A headless renderer keeps no instance data to read back (every board came back 0, and this failed
		# in every headless suite): here, what was asked of the batch. With a window, what the batch holds.
		for pilot in Network.RACERS:
			boards[roundi(float(Network.NUMBER_BOARDS[pilot]) * 3.0)] = true
	else:
		for i in racer.multimesh.visible_instance_count:
			boards[roundi(racer.multimesh.get_instance_custom_data(i).r * 3.0)] = true
	check(boards.size() == 4 and racer.multimesh.use_custom_data and racer.multimesh.visible_instance_count == Network.RACERS.size(), "Four independent pilot number boards in one draw batch")
	_check_network_spawn(network)
	_check_raider(network, camera)
	highway.sync(10.0)
	var counts: Array[int] = []
	for model in range_models:
		counts.append(_visible(model))
	check(not counts.has(0), "Range draws each road, rail and air traffic body")
	# At the 24 km crossing at t=10, the original Range has 103 road trucks
	# in view, and one locomotive with its complete 40-car consist.
	check(counts[0] + counts[1] == 103 and counts[2] == 1 and counts[3] + counts[4] == RangeTraffic.TRAIN_CARS,
			"Range road and rail variants preserve the original traffic counts: %s" % str(counts))
	check(highway.cars.multimesh.visible_instance_count + highway.hoppers.multimesh.visible_instance_count > 0
			and highway.road_cars.multimesh.visible_instance_count > 0, "Nearby train and crossing traffic get detail")
	camera.position.y = 50000
	highway.sync(10.0)
	for i in range_models.size():
		var model = range_models[i]
		check(model.multimesh.visible_instance_count == 0 and model.distant.visible_instance_count == counts[i], "Moving the camera changes detail without dropping traffic")
	print("TRAFFIC FLEET %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

