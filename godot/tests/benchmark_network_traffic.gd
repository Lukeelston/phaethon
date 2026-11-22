## Windowed desktop traffic CPU benchmark. From the repository root:
## Godot_v4.7.1-stable_win64_console.exe --path godot --xr-mode off --resolution 1280x720 --fixed-fps 120 --audio-driver Dummy -s res://tests/benchmark_network_traffic.gd -- --mute
## Eastbound E1, Basalt's N1 interchange. The city-side approaches of N1 and N3 are
## E1's joint highest-density interchanges (_target); the middle crossing is open country.
## Ordinary seeded traffic, at 1/120 s a frame. Run on an idle machine with the same renderer.
## For a window-free CPU comparison, add --headless before -s and --cpu-only after --.
## This uses Godot’s dummy renderer. Compare these timings only to another --cpu-only run.
extends SceneTree

const View := preload("res://view/craft_view.gd")
const Traffic := preload("res://view/network_traffic.gd")
const STEP := 1.0 / 120.0
const START := 2208 # E1 begins at x=25 km, sample 2208 is x=78 km.
const FRAMES := 2400
const WARMUP := 2400
var view: View
var traffic: Traffic

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless and not "--cpu-only" in OS.get_cmdline_user_args():
		push_error("Run the traffic benchmark windowed for real MultiMesh uploads.")
		quit(1)
		return
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("Traffic measurement: ", "headless CPU, no GPU uploads" if headless else "windowed renderer")
	View.track_override = "network"
	View.job_override = "none"
	View.best_dir = OS.get_user_data_dir().path_join("bench_traffic_")
	view = View.new()
	root.add_child(view)
	view.set_process(false)
	traffic = view.traffic_net
	var obstacles := "--obstacles" in OS.get_cmdline_user_args()
	view.sim.P.obstacleCollisions = obstacles
	traffic.collide = obstacles
	print("Traffic obstacle feed enabled: ", obstacles)
	var road: Traffic.Simulation.TrackPath = view.sim.roads[0]
	assert(road.name == "E1")
	var demand: Array[int] = []
	for x in [100000.0, 300000.0, 500000.0]:
		var peak := 0
		for km in range(-22, 23):
			peak = maxi(peak, traffic._target(x + km * 1000.0, 100000.0))
		demand.append(peak)
	print("E1 production target on +/-22 km interchange approaches: N1/N2/N3 %s" % str(demand))
	_rail(START, 0.0)
	# Settle the production spawner at the entrance before moving the pilot.
	for frame in WARMUP:
		traffic.update(STEP)
		if frame % 24 == 0:
			await process_frame
	var timings := PackedFloat64Array()
	var at_190 := PackedFloat64Array()
	var crowded := PackedFloat64Array()
	var population := Vector2i(1000000, 0)
	var count_sum := 0
	var witness := 0
	for frame in FRAMES:
		_rail(START + (frame >> 1), 0.5 * (frame % 2))
		var begin := Time.get_ticks_usec()
		traffic.update(STEP)
		var ms := (Time.get_ticks_usec() - begin) / 1000.0
		var n := traffic.cars.size()
		timings.append(ms)
		if n == 190:
			at_190.append(ms)
		if n >= 190:
			crowded.append(ms)
		population.x = mini(population.x, n)
		population.y = maxi(population.y, n)
		count_sum += n
		if frame % 120 == 0:
			witness = _witness(witness, not headless)
		await process_frame
	print("E1/N1 x=78.0..106.8 km, 1440 m/s, seed 20261019, %d warm, %d measured, cars %d..%d mean %.2f, witness %d" % [WARMUP, FRAMES, population.x, population.y, float(count_sum) / FRAMES, witness])
	_report("all", timings)
	_report("190 cars", at_190)
	_report("190+ cars", crowded)
	var enough := crowded.size() >= 120 and not at_190.is_empty()
	if not enough:
		push_error("Rail missed its 190-car workload")
	view.free()
	quit(int(not enough))

func _rail(sample: int, fraction: float) -> void:
	var sim: Traffic.Simulation = view.sim
	var road := sim.roads[0]
	sim.respawn_on(0, sample, 1)
	var dx := road.px[sample + 1] - road.px[sample]
	var dy := road.py[sample + 1] - road.py[sample]
	for body in sim.bodies:
		body.x += dx * fraction
		body.y += dy * fraction
		body.vx = dx * 60.0
		body.vy = dy * 60.0
	view._follow_origin()
	view._place_camera(1.0)

# Once per simulated second, outside the timer. Exercise the rendered traffic as well
# as its simulation so a missing train, beacon, livery or distance tier changes the witness.
func _witness(previous: int, read_instances: bool) -> int:
	var state := [previous, traffic.spawned, traffic.switched]
	for c in traffic.cars:
		state.append([c.id, c.road, c.kind, c.dir, c.lane, snappedf(c.f, 0.00001), snappedf(c.lat, 0.001), snappedf(c.v, 0.001)])
	var batches: Array[MultiMesh] = [traffic._beams.multimesh]
	for batch in traffic._mm.values():
		batches.append(batch.multimesh)
		batches.append(batch.distant)
	for batch in batches:
		state.append(batch.visible_instance_count)
		if not read_instances:
			continue
		for i in batch.visible_instance_count:
			var pose := batch.get_instance_transform(i)
			state.append([pose.origin.snappedf(0.01), pose.basis.x.snappedf(0.0001), pose.basis.y.snappedf(0.0001), batch.get_instance_color(i)])
			if batch.use_custom_data:
				state.append(batch.get_instance_custom_data(i))
	return hash(state)

func _report(label: String, values: PackedFloat64Array) -> void:
	if values.is_empty():
		print("TRAFFIC %s: 0 frames" % label)
		return
	values.sort()
	var total := 0.0
	var over := 0
	for ms in values:
		total += ms
		over += int(ms >= 1.0)
	print("TRAFFIC %s: %d frames, mean %.3f p50 %.3f p95 %.3f p99 %.3f max %.3f ms, >=1 ms %d" % [label, values.size(), total / values.size(), values[ceili(values.size() * 0.50) - 1], values[ceili(values.size() * 0.95) - 1], values[ceili(values.size() * 0.99) - 1], values[-1], over])

