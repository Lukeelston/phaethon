## The climbs in and out of each parked craft (Luke, 2026-11-25: "a live transition animation for the pilot to get into
## and out of each individual craft in the garage"; garage/boarding.gd). For each bay, and the Talon in the Phaethon's:
##   wired        the board key starts a climb in; the walker is held, the prompts put away, nothing launches
##   smooth       the helmet's eye never jumps between two frames (90 a second), no boot goes through the floor, and
##                where the climb leaves him is where the stock pose takes over (seated, or standing at the gate)
##   canopy       it opens all the way while he climbs, and is shut again after him
##   seated       at the end of the climb in he is seated in that craft, the cab working; the view is the walker's own
##   out          the board key again climbs him out: on his feet at the gate, the display pod whole again, the cab hidden
##   skip         pressed again during a climb, it finishes at once, the canopy shut
##   instant      interact() and leave_seat() (the release checks call them) still seat and stand him at once
## Prints CLIMB lines (each climb's length). Its own settings file for the run.
## Run headless with --xr-mode off -s res://tests/test_garage_climbs.gd -- --mute
extends SceneTree

const Pilot := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const GARAGE := "res://garage/garage.tscn"
const STEP := 1.0 / 90.0
const MAX_EYE_STEP := 0.07      # m between two frames: 6.3 m/s, past any part of a climb
const SEAM := 0.03              # m the eye may move where the stock pose takes over
var checks := 0
var failures := 0
var _settings_before := ""


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func _run() -> void:
	_settings_before = Settings.prefs_path
	Settings.prefs_path = "user://test-garage-climbs-%d.cfg" % OS.get_process_id()
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--craft="):
			only = arg.trim_prefix("--craft=")
	for body in ["phaethon", "talon"]:
		if not only.is_empty() and body == "talon" and only != "talon":
			continue
		Settings.set_phaethon_body(body)
		Route.enter(self, false, "network")
		var garage = await _garage()
		if garage == null:
			check(false, "The garage opens")
			break
		var bays: Array = Pilot.GARAGE_BAYS if body == "phaethon" else [Pilot.STANDARD]
		for id: String in bays:
			if not only.is_empty() and garage.environment.bay_craft(id) != only:
				continue
			await _climbs(garage, id, body == "phaethon" and id == Pilot.STANDARD)
		if body == "phaethon" and (only.is_empty() or only == "phaethon"):
			await _skip_and_instant(garage)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = _settings_before
	print("GARAGE CLIMBS %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _garage() -> Node:
	var until := Time.get_ticks_msec() + 30000
	while current_scene == null or current_scene.scene_file_path != GARAGE or not current_scene.is_node_ready():
		if Time.get_ticks_msec() > until:
			return null
		await process_frame
	for tick in 3:
		await process_frame
	return current_scene


func _climbs(garage, id: String, by_key: bool) -> void:
	var hall = garage.environment
	var walker = garage.walker
	var craft: String = hall.bay_craft(id)
	var bay: Node3D = hall.bay_node(id)
	var floor_y: float = (bay.global_transform * Vector3(0, -0.72, 0)).y
	# from a little off the gate, turned partly away, as a player walks up
	var gate: Transform3D = hall.boarding_transform(id)
	walker.set_seated(false, Transform3D(gate.basis.rotated(Vector3.UP, 0.7), gate.origin + gate.basis.x * 0.5 - gate.basis.z * -0.6))
	await process_frame
	if by_key:
		_key(KEY_E)
	else:
		garage._board_button()
	var climb = garage._climb
	if not check(climb != null and walker.scripted, "%s: the board key starts a climb in, the walker held" % craft):
		return
	garage.launch_flight()
	check(not garage._departing, "%s: nothing launches while he climbs" % craft)
	var run := _play(garage, climb, floor_y)
	check(run.eye_step <= MAX_EYE_STEP, "%s in: the eye moves at most %.3f m a frame (%.3f)" % [craft, MAX_EYE_STEP, run.eye_step])
	check(run.low >= floor_y + 0.06, "%s in: no boot through the floor (lowest ankle %.3f above it)" % [craft, run.low - floor_y])
	check(run.open >= 0.999, "%s in: the canopy opens all the way (%.3f)" % [craft, run.open])
	check(run.seam <= SEAM, "%s in: the stock seated pose takes over where the climb left him (%.3f m)" % [craft, run.seam])
	check(garage.seated_craft == craft and walker.seated and not walker.scripted, "%s: seated in it at the end" % craft)
	check(get_root().get_viewport().get_camera_3d() == walker.camera, "%s: the walker's own view after the climb in" % craft)
	check(garage._climb == null and garage._canopy_rigs[id].amount == 0.0, "%s: the canopy shut after him" % craft)
	var climb_in: float = run.arrived
	# out
	garage._board_button()
	climb = garage._climb
	if not check(climb != null and garage.seated_craft.is_empty(), "%s: the board key climbs him out" % craft):
		return
	run = _play(garage, climb, floor_y)
	check(run.eye_step <= MAX_EYE_STEP, "%s out: the eye moves at most %.3f m a frame (%.3f)" % [craft, MAX_EYE_STEP, run.eye_step])
	check(run.low >= floor_y + 0.06, "%s out: no boot through the floor (lowest ankle %.3f above it)" % [craft, run.low - floor_y])
	check(run.open >= 0.999, "%s out: the canopy opens all the way (%.3f)" % [craft, run.open])
	check(run.seam <= SEAM, "%s out: the stock standing pose takes over where the climb left him (%.3f m)" % [craft, run.seam])
	check(not walker.seated and walker.global_position.distance_to(gate.origin) < 0.05, "%s: on his feet at the gate" % craft)
	check(bay.model.pod.visible and bay.model.pod.mesh != null and not garage._cockpit.visible and garage._lent.is_empty(),
			"%s: the display pod whole again, the cab hidden" % craft)
	print("CLIMB %s in %.2f s, out %.2f s" % [craft, climb_in, run.arrived])


## Step a climb to its end by hand: the largest eye step, the lowest ankle, how far the canopy opened, the seam.
func _play(garage, climb, floor_y: float) -> Dictionary:
	var pilot = garage.pilot
	var eye: Vector3 = pilot.global_transform * pilot.eye_point()
	var run := {"eye_step": 0.0, "low": INF, "open": 0.0, "seam": 0.0, "arrived": 0.0}
	var t := 0.0
	while not climb.pilot_done and t < 30.0:
		climb.advance(STEP)
		t += STEP
		var now: Vector3 = pilot.global_transform * pilot.eye_point()
		if not climb.pilot_done:
			run.eye_step = maxf(run.eye_step, now.distance_to(eye))
			var shot: Dictionary = pilot.snapshot()
			for ankle: Vector3 in shot.ankles:
				run.low = minf(run.low, (pilot.global_transform * ankle).y)
		else:
			run.seam = now.distance_to(eye)
			run.arrived = t
		eye = now
		run.open = maxf(run.open, climb.rig.amount)
	while garage._climb == climb and t < 40.0:
		climb.advance(STEP)
		t += STEP
		run.open = maxf(run.open, climb.rig.amount)
	return run


func _skip_and_instant(garage) -> void:
	var hall = garage.environment
	var walker = garage.walker
	walker.set_seated(false, hall.boarding_transform(Pilot.KILN))
	await process_frame
	garage._board_button()
	var climb = garage._climb
	for i in 40:
		climb.advance(STEP)
	garage._board_button()
	check(garage.seated_craft == Pilot.KILN and walker.seated and garage._climb == null and garage._canopy_rigs[Pilot.KILN].amount == 0.0,
			"Pressed again during a climb, it finishes at once, the canopy shut")
	garage.leave_seat()
	check(not walker.seated and garage.seated_craft.is_empty(), "leave_seat() stands him at once")
	garage.interact()
	check(walker.seated and garage.seated_craft == Pilot.KILN and garage._climb == null, "interact() seats him at once")
	garage.leave_seat()
	await process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
