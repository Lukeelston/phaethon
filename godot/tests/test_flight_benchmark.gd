## Pure report and replay checks. Does not start a flight scene or read/write pilot preferences.
extends SceneTree

const Bench := preload("res://release/flight_benchmark.gd")
const View := preload("res://view/craft_view.gd")

func _initialize() -> void:
	var failures := 0
	var wall := PackedFloat64Array([10.0, 4.0, 1.0])
	var cpu := PackedFloat64Array([1.5, 2.5, 3.5])
	var course := Bench.course_report("eridanus", wall, cpu, PackedFloat64Array())
	failures += check(course.frame_ms == {"mean": 5.0, "p50": 4.0, "p95": 10.0, "p99": 10.0}, "wall clock percentiles")
	failures += check(course.fps == 200.0 and course.measured_frames == 3, "FPS from elapsed wall time")
	failures += check(course.main_thread_ms.mean == 2.5 and course.gpu_ms == null and course.gpu_samples == 0, "independent and unsupported counters")
	course = Bench.course_report("network", wall, cpu, PackedFloat64Array([2.0, 4.0]))
	failures += check(course.gpu_ms.mean == 3.0 and course.gpu_samples == 2, "available GPU readings")
	# One slow frame in the second pass must affect the pooled mean and p95.
	var samples := Bench.Samples.new()
	samples.accumulate(PackedFloat64Array([2.0, 2.0]), cpu, PackedFloat64Array([1.0]))
	samples.accumulate(PackedFloat64Array([2.0, 10.0]), cpu, PackedFloat64Array([3.0]))
	var passes := [{"physics_steps": 16}, {"physics_steps": 16, "scene_nodes": 123}]
	var pooled := Bench.pooled_report("network", {"fps": 999.0}, passes, samples)
	failures += check(pooled.fps == 250.0 and pooled.frame_ms.p95 == 10.0 and pooled.gpu_ms.mean == 2.0 and pooled.measured_frames == 4, "all steady samples pooled; cold timings kept separately")
	failures += check(pooled.conditioning.fps == 999.0 and pooled.passes == passes and pooled.physics_steps == 32 and pooled.scene_nodes == 123, "per-pass evidence and final memory snapshot")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(Bench.make_report([course])))
	failures += check(roundtrip.has_all(["schema_version", "engine", "edition", "renderer", "cpu", "gpu", "steady_passes_per_track", "conditioning_passes_per_track", "warmup_frames", "fixed_step_s", "steps_per_input", "courses"]), "report headers")
	failures += check(roundtrip.courses[0].track == "network" and roundtrip.schema_version == 2, "serialized report version and course")

	# Real rows through the flight view. No scene _ready, hence no menu, player record or VR prefs.
	for track: String in Bench.COURSES:
		var view := View.new()
		view.sim = View.CraftSimScript.new({"track": track})
		view.replay = JSON.parse_string(FileAccess.get_file_as_string("res://tests/replay/%s_inputs.json" % track))
		var row: Array = view.replay[0]
		for i in 8:
			view._sim_step()
		failures += check(view.sub == 8 and view.replay_i == 1 and view.inp.thrL == row[0] and view.inp.thrR == row[1] and view.inp.brkL == row[2] and view.inp.brkR == row[3], track + " fixed input cadence")
		failures += check(view.handling_ask == ["", "speed", "starfighter"][int(row[4])], track + " recorded handling channel")
		view.free()
	print("FLIGHT BENCHMARK ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> int:
	if not ok:
		printerr("FAIL ", label)
	return 0 if ok else 1
