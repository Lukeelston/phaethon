## Committed shaft road rows, physical support exclusions and actual traffic instances.
## Run windowed to read the traffic instances.
extends SceneTree

const Sim := preload("res://sim/craft_sim.gd")
const World := preload("res://view/network_world.gd")
const Traffic := preload("res://view/network_traffic.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", label)

func _run() -> void:
	var sim = Sim.new({"track": "network", "obstacleCollisions": true})
	var world = World.new()
	root.add_child(world)
	world.build(sim, null)
	_check("twelve far shaft silhouettes", world.far_shafts.size() == 12)
	for sh in sim.shafts:
		var r := int(sh[0])
		var R = sim.roads[r]
		var apex := int(sh[1]) + roundi((PI * float(sh[3]) + float(sh[4])) / 24.0)
		world._build_chunk(r, apex / World.CH)
		var chunk: Array = world.chunks[Vector2i(r, apex / World.CH)]
		var mesh: ArrayMesh = chunk[0].get_node("road").mesh
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var section: Dictionary = world._section(R.w[apex])
		var row := apex % World.CH
		var good := true
		for k in section.o.size():
			var expected: Vector3 = world.shaft.point(r, float(apex), section.o[k], section.h[k] + 0.02, chunk[1], chunk[2])
			good = good and vertices[row * section.o.size() + k].distance_to(expected) < 0.01
		_check(R.name + " actual road mesh follows shaft frame", good)
		_check(R.name + " apex road normals face downward", normals[row * section.o.size() + World.EDGE_SEGS].y < -0.99)
		var pillars := 0
		for i in range(int(sh[1]) + 1, int(sh[2]), 6):
			pillars += world.pillar_specs(r, i).size()
		_check(R.name + " no rendered or collision pillars on carried stretch", pillars == 0)
	var traffic = Traffic.new()
	root.add_child(traffic)
	traffic.build(sim, {"org_x": 0.0, "org_y": 0.0}, world)
	traffic._warm = 0
	var sh: Array = sim.shafts[0]
	var r := int(sh[0])
	for fraction in [0.2, 0.5, 0.8]:
		for direction in [-1, 1]:
			var c = Traffic.Car.new()
			c.id = 7
			c.road = r
			c.f = lerpf(sh[1], sh[2], fraction)
			c.dir = direction
			c.kind = Traffic.TRANSPORT
			c.lat = 24.0
			c.v = 1000.0
			traffic._place(c)
			sim.respawn_on(r, int(c.f), direction)
			# (the feed gives the sim only what the craft can reach before the next frame: 144 m standing. At this
			# speed that is 500 m, the whole 300 m of the train, whose every car this checks)
			sim.pod.vx = 3000.0
			sim.pod.vy = 0.0
			traffic.view = {"org_x": c.x, "org_y": c.y}
			traffic.cars.clear()
			traffic.cars.append(c)
			traffic._render()
			traffic._feed()
			var tractor = traffic._mm[Traffic.TRACTOR]
			var trailer = traffic._mm[Traffic.TRANSPORT]
			var heads: int = tractor.multimesh.visible_instance_count + tractor.distant.visible_instance_count
			var trailers: int = trailer.multimesh.visible_instance_count + trailer.distant.visible_instance_count
			var next_index := {}
			var obstacles: Array = sim.obstacles.filter(func(o): return int(o.id) >= 7 * 32 and int(o.id) < 8 * 32)
			_check("shaft train renders and collides all cars", heads == 1 and trailers == Traffic.TRAIN - 1 and obstacles.size() == Traffic.TRAIN * 2)
			for k in Traffic.TRAIN:
				var f: float = c.f - direction * k * Traffic.TRAIN_GAP / 24.0
				var expected: Vector3 = world.shaft.point(r, f, c.lat, 1.0, c.x, c.y)
				var batch = tractor if k == 0 else trailer
				var buffer: MultiMesh = batch.multimesh if expected.length_squared() <= 500.0 * 500.0 else batch.distant
				var index: int = next_index.get(buffer, 0)
				var actual: Transform3D = buffer.get_instance_transform(index)
				next_index[buffer] = index + 1
				var up: Vector3 = world.shaft.at(r, f)[5]
				_check("shaft traffic bounds contain visible car", traffic._mm[Traffic.TRANSPORT].custom_aabb.has_point(expected))
				_check("shaft light bounds contain visible car", traffic._beams.custom_aabb.has_point(expected))
				_check("shaft train position and attitude %s/%s/%s" % [fraction, direction, k], actual.origin.distance_to(expected) < 0.02 and actual.basis.y.normalized().dot(up) > 0.9999)
				if obstacles.size() == Traffic.TRAIN * 2:
					_check("shaft train collision height tracks each rendered car", absf(float(obstacles[k * 2].zMin) - sim.net_height(r, f)) < 0.001)
	traffic.collide = false
	traffic._feed()
	_check("obstacle setting disables shaft traffic and pillars", sim.obstacles.is_empty())
	_check("corner signs use Speedcraft gears", World.gear_for(1500.0) == 1 and World.gear_for(2100.0) == 2 and World.gear_for(3000.0) == 3 and World.gear_for(5000.0) == 4)
	print("NETWORK SHAFT MESH %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
