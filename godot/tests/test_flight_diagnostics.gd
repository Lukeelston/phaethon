## Short XR-off Network flight. Run with --headless --xr-mode off -s res://tests/test_flight_diagnostics.gd -- --mute
extends SceneTree

const Cockpit := preload("res://vr/vr_cockpit.gd")
const DT := 1.0 / 32.0

class HandsOff extends LeverInput:
	func _connected_pads() -> Array[int]:
		return []

# Read the actual print stream, including the startup line emitted while the scene enters the tree.
class FlightLog extends Logger:
	var lines := PackedStringArray()
	var mutex := Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		if message.begins_with("DIAG "):
			mutex.lock()
			lines.append(message.strip_edges())
			mutex.unlock()

	func matching(prefix: String) -> PackedStringArray:
		var result := PackedStringArray()
		mutex.lock()
		for line in lines:
			if line.begins_with(prefix):
				result.append(line)
		mutex.unlock()
		return result


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _run() -> void:
	var existed := FileAccess.file_exists(Cockpit.PREFS)
	var original := FileAccess.get_file_as_bytes(Cockpit.PREFS) if existed else PackedByteArray()
	Cockpit.track_override = "network"
	Cockpit.job_override = "none"
	Cockpit.best_dir = "user://test_flight_diagnostics_"
	var log := FlightLog.new()
	OS.add_logger(log)
	var flight := Cockpit.new()
	root.add_child(flight)
	flight.set_process(false)
	# The renderer publishes VRAM counters after it has drawn the scene.
	if RenderingServer.get_rendering_device() != null:
		for i in 3:
			await RenderingServer.frame_post_draw
	flight.levers = HandsOff.new()
	flight.quest.scheme = "triggers"
	_check("the boot log marks the headset target and rate unavailable with XR off", log.matching("DIAG headset:") == PackedStringArray([
		"DIAG headset: render_target=unavailable refresh=unavailable"]))
	_check("reported target and refresh values keep both dimensions and fractional Hz",
		Cockpit.FlightDiagnostics.headset_line(Vector2i(2400, 2600), 72.5) == "DIAG headset: render_target=2400x2600 refresh=72.50 Hz")
	_check("the Network autopilot engages", flight.set_autopilot(true))
	# Start one second before the minute. Keep every flight frame a normal, fixed delta.
	flight._memory_t = 59.0
	for i in 31:
		flight._process(DT)
	_check("memory and autopilot samples wait for their intervals",
		log.matching("DIAG memory:").is_empty() and log.matching("DIAG autopilot:").is_empty())
	# Four distinct commands, including partially applied brakes, on the sampled frame.
	flight.autopilot.hands(0.25, 0.55, 0.45, 0.30)
	flight._process(DT)
	var cmd := flight.inp
	var expected := "DIAG autopilot: levers=%.2f/%.2f brakes=%.2f/%.2f" % [cmd.thrL, cmd.thrR, cmd.brkL, cmd.brkR]
	_check("the autopilot line matches the sampled frame's applied levers and brakes",
		log.matching("DIAG autopilot:") == PackedStringArray([expected])
		and cmd.thrL != cmd.thrR and cmd.brkL != cmd.brkR and minf(cmd.brkL, cmd.brkR) > 0.0)
	var pilot := log.matching("DIAG input:")
	var craft := log.matching("DIAG craft:")
	_check("pilot inputs still show the idle hands", pilot.size() == 1 and pilot[0].contains("inp thr=0.00/0.00")
		and craft.size() == 1 and craft[0].contains("brk=0.00/0.00"))
	var memory := log.matching("DIAG memory:")
	var pattern := RegEx.create_from_string("^DIAG memory: system_used=(?:[0-9]+[.][0-9] MiB|unavailable) engine_static=(?:[0-9]+[.][0-9] MiB|unavailable) video_used=(?:[0-9]+[.][0-9] MiB|unavailable)$")
	_check("the minute's line includes scoped RAM and video counters with units or availability",
		memory.size() == 1 and pattern.search(memory[0]) != null
		and (not OS.is_debug_build() or not memory[0].contains("engine_static=unavailable"))
		and (RenderingServer.get_rendering_device() == null or not memory[0].ends_with("video_used=unavailable"))
		and (DisplayServer.get_name() != "headless" or memory[0].ends_with("video_used=unavailable")))
	flight.set_autopilot(false)
	for i in 32:
		flight._process(DT)
	_check("manual flight has no autopilot sample and no extra memory sample",
		log.matching("DIAG autopilot:").size() == 1 and log.matching("DIAG memory:").size() == 1)
	flight._memory_t += 58.0
	for i in 32:
		flight._process(DT)
	_check("the next minute produces one more memory line", log.matching("DIAG memory:").size() == 2)
	flight.free()
	OS.remove_logger(log)
	if existed and (not FileAccess.file_exists(Cockpit.PREFS) or FileAccess.get_file_as_bytes(Cockpit.PREFS) != original):
		var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		if file != null:
			file.store_buffer(original)
			file.close()
	elif not existed and FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	_check("the original preference bytes or absence are restored", FileAccess.file_exists(Cockpit.PREFS) == existed
		and (not existed or FileAccess.get_file_as_bytes(Cockpit.PREFS) == original))
	print("FLIGHT DIAGNOSTICS ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
