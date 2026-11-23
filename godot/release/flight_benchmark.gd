## Drives the shipping flight view with one 60 Hz recording sample per draw. Wall time
## remains free-running. Track construction, the warm-up and the memory query are untimed.
extends Node

const View := preload("res://view/craft_view.gd")
const COURSES := ["eridanus", "network"]
const PASSES := 3
const WARMUP := 180
const SAMPLES := 1800
const STEPS := 8
const FLIGHT_DELTA := STEPS * View.DT

class Samples:
	var walls := PackedFloat64Array()
	var cpus := PackedFloat64Array()
	var gpus := PackedFloat64Array()

	func accumulate(wall: PackedFloat64Array, cpu: PackedFloat64Array, gpu: PackedFloat64Array) -> void:
		walls.append_array(wall)
		cpus.append_array(cpu)
		gpus.append_array(gpu)

var frame_updates_finished_usec := 0
var profile: DirAccess
var report_path := "user://flight_benchmark.json"

func _ready() -> void:
	process_priority = 2147483647   # time through child updates as well as the main flight view
	_run.call_deferred()

func _process(_delta: float) -> void:
	frame_updates_finished_usec = Time.get_ticks_usec()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("A rendered window or OpenXR session is required.")
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--benchmark-out="):
			report_path = arg.trim_prefix("--benchmark-out=")
		elif arg != "--benchmark":
			_fail("Unsupported benchmark option: " + arg)
			return
	View.vehicle_override = View.CraftSimScript.PilotCraft.STANDARD
	View.job_override = "none"
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var steady := {"eridanus": [], "network": []}
	var samples := {"eridanus": Samples.new(), "network": Samples.new()}
	var cold := {}
	for cycle in PASSES + 1:
		for track: String in COURSES:
			var result := await _fly(track, null if cycle == 0 else samples[track])
			if result.is_empty():
				return
			if cycle == 0:
				cold[track] = result
				print("FLIGHT BENCHMARK conditioning ", track, " ", result.fps, " FPS")
			else:
				steady[track].append(result)
				print("FLIGHT BENCHMARK steady ", cycle, " ", track, " ", result.fps, " FPS")
	var courses := []
	for track in COURSES:
		courses.append(pooled_report(track, cold[track], steady[track], samples[track]))
	var report := make_report(courses)
	var out := FileAccess.open(report_path, FileAccess.WRITE)
	if out == null:
		_fail("Cannot write %s: %s" % [report_path, error_string(FileAccess.get_open_error())])
		return
	out.store_line(JSON.stringify(report, "\t", true, true))
	out.flush()
	if out.get_error() != OK:
		_fail("Could not finish writing " + report_path)
		return
	out.close()
	print("FLIGHT BENCHMARK PASS ", ProjectSettings.globalize_path(report_path))
	get_tree().quit()

func _fly(track: String, steady_samples: Samples) -> Dictionary:
	profile = DirAccess.create_temp("phaethon-benchmark")
	if profile == null:
		_fail("Could not create the disposable flight profile.")
		return {}
	View.best_dir = profile.get_current_dir() + "/"
	View.GameSettings.prefs_path = View.best_dir + "game_settings.cfg"
	var directory := "res://tests/replay/" if OS.has_feature("editor") else "res://release/replays/"
	var fixture := directory + track + "_inputs.json"
	var inputs = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	if not inputs is Array or inputs.size() < WARMUP + SAMPLES:
		_fail("Missing or short recording: " + fixture)
		return {}
	for i in WARMUP + SAMPLES:
		var row = inputs[i]
		if not row is Array or row.size() != 5:
			_fail("Invalid input at frame %d in %s" % [i, fixture])
			return {}
	View.track_override = track
	View.spot_override = "city:ERIDANUS" if track == "network" else ""
	var scene := load("res://vr.tscn" if OS.has_feature("pcvr") else "res://main.tscn") as PackedScene
	var flight: View = scene.instantiate()
	flight.benchmark_flight = true
	flight.replay = inputs
	add_child(flight)
	flight.set_process(false)
	flight.set_process_unhandled_key_input(false)
	if flight.wind_audio:
		flight.wind_audio.collect_booms(true)   # background synthesis is part of scene construction
	if track == "network":
		# The recording departs Eridanus toward decreasing sample indices.
		var city: Dictionary = flight.sim.cities[flight.sim.net.from]
		flight.sim.respawn_on(city.road, city.i, -1)
	var viewport := get_viewport()
	var rid := viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in WARMUP:
		flight._process(FLIGHT_DELTA)
		await get_tree().process_frame
	var walls := PackedFloat64Array()
	var cpus := PackedFloat64Array()
	var gpus := PackedFloat64Array()
	var first_draw := Engine.get_frames_drawn()
	var before := Time.get_ticks_usec()
	for i in SAMPLES:
		var start := Time.get_ticks_usec()
		flight._process(FLIGHT_DELTA)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		walls.append((now - before) / 1000.0)
		before = now
		cpus.append((frame_updates_finished_usec - start) / 1000.0)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if gpu > 0.0:
			gpus.append(gpu)
	if Engine.get_frames_drawn() - first_draw != SAMPLES:
		_fail("Rendering was interrupted during " + track)
		return {}
	if flight.sim.track_name != track or flight.sub != (WARMUP + SAMPLES) * STEPS or flight.replay_i != WARMUP + SAMPLES:
		_fail("Flight did not consume exactly the prescribed recording on " + track)
		return {}
	if steady_samples:
		steady_samples.accumulate(walls, cpus, gpus)
	var pod = flight.sim.pod
	var result := course_report(track, walls, cpus, gpus)
	result["display"] = display_info(viewport)
	result["fixture_sha256"] = FileAccess.get_sha256(fixture)
	result["final_pod_m"] = [pod.x, pod.y, pod.z]
	result["physics_steps"] = flight.sub
	result["scene_nodes"] = get_tree().get_node_count()
	result["loaded_resources"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	result["process_working_set_bytes"] = working_set()
	var vram := int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	result["video_memory_used_bytes"] = vram if vram > 0 else null
	flight.queue_free()
	await get_tree().process_frame
	return result

## The conditioning cycle encounters each world once. All subsequent frames
## contribute equally to FPS and percentiles; snapshots come from the final pass.
static func pooled_report(track: String, cold: Dictionary, steady: Array, samples: Samples) -> Dictionary:
	var report: Dictionary = steady.back().duplicate()
	report.merge(course_report(track, samples.walls, samples.cpus, samples.gpus), true)
	report["physics_steps"] = 0
	for sample in steady:
		report.physics_steps += sample.physics_steps
	report["conditioning"] = cold
	report["passes"] = steady
	return report

static func course_report(track: String, walls: PackedFloat64Array, cpu: PackedFloat64Array, gpu: PackedFloat64Array) -> Dictionary:
	var wall: Dictionary = distribution(walls)
	return {"track": track, "measured_frames": walls.size(), "fps": 1000.0 / float(wall.mean),
		"frame_ms": wall, "main_thread_ms": distribution(cpu), "gpu_ms": distribution(gpu),
		"gpu_samples": gpu.size()}

static func distribution(values: PackedFloat64Array) -> Variant:
	if values.is_empty():
		return null
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for sample in sorted:
		total += sample
	var result := {"mean": total / sorted.size()}
	for percentile in [50, 95, 99]:
		var index := ceili(sorted.size() * percentile / 100.0) - 1
		result["p%d" % percentile] = sorted[index]
	return result

static func display_info(viewport: Viewport) -> Dictionary:
	var xr := XRServer.primary_interface
	var size := Vector2i(viewport.get_texture().get_size())
	var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	var mode := "pcvr_xr_off" if OS.has_feature("pcvr") else "desktop"
	if viewport.use_xr and xr and xr.is_initialized():
		mode = "openxr"
		size = xr.get_render_target_size()
		hz = float(xr.get("display_refresh_rate")) if "display_refresh_rate" in xr else 0.0
	return {"mode": mode, "render_size_px": [size.x, size.y], "refresh_hz": hz if hz > 0 else null,
		"scale_3d": viewport.scaling_3d_scale, "msaa_3d": viewport.msaa_3d}

static func working_set() -> Variant:
	# Release templates do not expose process RAM through MEMORY_STATIC. Query
	# Windows once after the flight, outside every timing sample.
	var output := []
	var code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
		"(Get-Process -Id %d).WorkingSet64" % OS.get_process_id()], output)
	if code == 0 and not output.is_empty():
		var value := str(output[0]).strip_edges()
		if value.is_valid_int() and value.to_int() > 0:
			return value.to_int()
	return null

static func make_report(courses: Array) -> Dictionary:
	return {"schema_version": 2, "edition": "pcvr" if OS.has_feature("pcvr") else "desktop",
		"engine": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"conditioning_passes_per_track": 1, "steady_passes_per_track": PASSES, "warmup_frames": WARMUP, "fixed_step_s": View.DT, "steps_per_input": STEPS, "courses": courses}

func _fail(message: String) -> void:
	push_error("FLIGHT BENCHMARK FAIL " + message)
	get_tree().quit(1)
