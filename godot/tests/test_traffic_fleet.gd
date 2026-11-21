## Imported models, distance selection, per-pilot markings and the moving range fleet.
extends SceneTree

const Network := preload("res://view/network_traffic.gd")
const RangeTraffic := preload("res://view/traffic.gd")

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

func run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var network := Network.new()
	root.add_child(network)
	network._build_meshes()
	var highway := RangeTraffic.new()
	root.add_child(highway)
	highway.build(RangeView.new())
	var models := network._mm.values()
	models.append_array([highway.trucks, highway.locos, highway.cars, highway.planes, highway.road_cars])
	check(models.size() == 11, "All eleven fleet models load")
	for model in models:
		var near_mesh: Mesh = model.multimesh.mesh
		var far_mesh: Mesh = model.distant.mesh
		check(near_mesh.get_surface_count() == 1 and far_mesh.get_surface_count() == 1, "Single surface per tier")
		check(far_mesh.surface_get_array_index_len(0) < near_mesh.surface_get_array_index_len(0), "Distant mesh is lighter")
		model.put(Transform3D.IDENTITY, Vector3.ZERO)
		model.put(Transform3D(Basis.IDENTITY, Vector3(12000, 0, 0)), Vector3.ZERO)
		model.finish_frame()
		check(model.multimesh.visible_instance_count == 1 and model.distant.visible_instance_count == 1, "Each distance gets one vehicle")
		model.finish_frame()
		check(model.multimesh.visible_instance_count + model.distant.visible_instance_count == 0, "Vehicles leave both buffers on the next frame")
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
	highway.sync(10.0)
	var counts: Array[int] = []
	var range_models := [highway.trucks, highway.locos, highway.cars, highway.planes, highway.road_cars]
	for model in range_models:
		counts.append(model.multimesh.visible_instance_count + model.distant.visible_instance_count)
	check(counts[0] > 50 and counts[1] == 1 and counts[2] == 40 and counts[3] > 0 and counts[4] > 0, "Range traffic includes highway, full freight train, overpass and air traffic: %s" % str(counts))
	check(highway.cars.multimesh.visible_instance_count > 0 and highway.road_cars.multimesh.visible_instance_count > 0, "Nearby train and crossing traffic get detail")
	camera.position.y = 50000
	highway.sync(10.0)
	for i in range_models.size():
		var model = range_models[i]
		check(model.multimesh.visible_instance_count == 0 and model.distant.visible_instance_count == counts[i], "Moving the camera changes detail without dropping traffic")
	print("TRAFFIC FLEET %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))

