## The bay doors (Luke, 2026-11-25): "Whenever a pilot enters a vehicle and goes through the startup process, the
## 'start engines' button should trigger the bay door to raise, and the pilot can enter the map from there. If they
## exit the craft, the bay door should shut again." And "The garage should exit immediately to the map chosen from the
## previous screen." Seated, through the pilot's own controls (garage_walker.gd's signals): the door stays down on
## BATT and ENGINE alone, rises on START, refuses a launch until it is up, comes down on stepping out (the engines left
## running) and again on a shutdown in the seat, goes up on boarding a craft whose engines run; then the launch, from the
## pilot's control, flies the craft onto the menu's map with no starting pad.
## Headless: --headless -s res://tests/test_garage_bay_door.gd -- --mute
extends SceneTree

const Route := preload("res://release/garage_route.gd")
const Garage := preload("res://garage/garage.gd")
const Doors := preload("res://garage/bay_doors.gd")
const Prompts := preload("res://garage/garage_prompts.gd")
const View := preload("res://view/craft_view.gd")
const Settings := preload("res://release/game_settings.gd")
const UI := preload("res://release/release_config.gd")
const Fleet := preload("res://sim/pilot_craft.gd")
const GARAGE := "res://garage/garage.tscn"
const CRAFT := "vesper"
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("  %s  %s" % ["ok  " if ok else "FAIL", label])
	return ok


func _scene(path: String, seconds := 20.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while (current_scene == null or current_scene.scene_file_path != path) and Time.get_ticks_msec() < until:
		await process_frame
	return current_scene != null and current_scene.scene_file_path == path


## Frames until `done` holds or `seconds` pass (the garage runs on the wall clock); returns the seconds it took (or -1).
func _until(done: Callable, seconds: float) -> float:
	var from := Time.get_ticks_usec()
	var waited := 0.0
	while not done.call() and waited < seconds:
		await process_frame
		waited = (Time.get_ticks_usec() - from) / 1e6
	return waited if done.call() else -1.0


func _others_shut(doors: Doors, bay: String) -> bool:
	for id: String in Fleet.GARAGE_BAYS:
		if id != bay and doors.phase(id) != "shut":
			return false
	return true


func _run() -> void:
	Engine.max_fps = 120
	var prefs_before := Settings.prefs_path
	Settings.prefs_path = "user://test-bay-door-%d.cfg" % OS.get_process_id()
	Route.enter(self, false, "network")
	if check(await _scene(GARAGE), "The garage opens bound for the Network"):
		await _visit(current_scene)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = prefs_before
	print("GARAGE BAY DOOR %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))


func _visit(garage) -> void:
	var doors: Doors = garage.environment.doors
	var walker = garage.walker
	walker.set_physics_process(false)
	check(doors != null and doors.bays == Fleet.GARAGE_BAYS, "Each bay has its door, numbered as its curtain")
	var all_shut := true
	for id: String in Fleet.GARAGE_BAYS:
		all_shut = all_shut and doors.phase(id) == "shut" and doors.fraction(id) == 0.0
	check(all_shut, "Every bay door is down when the visit begins")
	var door: Transform3D = garage.environment.door_transform(CRAFT)
	var nose: Transform3D = garage.environment.seat_transform(CRAFT)
	check(absf(door.origin.z - nose.origin.z) < .01 and absf(absf(door.origin.x) - 34.83) < .01
		and (-nose.basis.z).dot((door.origin - nose.origin).normalized()) > .99,
		"The %s's door is in the side wall dead ahead of its seat, %.1f m away" % [CRAFT, nose.origin.distance_to(door.origin)])

	walker.set_seated(false, garage.environment.boarding_transform(CRAFT))
	walker.interact_requested.emit()
	if not check(garage.seated_craft == CRAFT and walker.seated, "Board the " + CRAFT):
		return
	var runup = garage.environment.bay_node(CRAFT).get_node("Runup")
	var startup: StartupSequence = runup.startup
	await process_frame
	check(doors.phase(CRAFT) == "shut", "Boarding a cold craft leaves its door down")
	walker.launch_requested.emit()
	await process_frame
	check(current_scene == garage and not garage._departing and garage._launch_refused == Garage.DOOR_SHUT,
		"Launch is refused with the door down, and says why: \"%s\"" % garage._launch_refused)
	check(Prompts.door_line(doors.phase(CRAFT), "F") == "START opens bay door", "The seated prompt says START opens the door")

	runup.work("batt", 1)
	await _until(func() -> bool: return startup.batt and startup.power > .99, 2.0)
	runup.work("engine", 1)      # (the guard up ...)
	runup.work("engine", 1)      # (... and the switch under it on)
	await _until(func() -> bool: return startup.master and startup.charge > .99, 3.0)
	await process_frame
	check(startup.batt and startup.master and not Garage.engines_lit(startup) and doors.phase(CRAFT) == "shut",
		"BATT and ENGINE alone leave the door down")
	runup.work("start", 1)
	await process_frame
	check(startup.starting() and doors.phase(CRAFT) == "opening", "START sends the door up at once")
	check(_others_shut(doors, CRAFT), "Only the seated bay's door moves")
	var rising := [doors.fraction(CRAFT)]
	var waited := await _until(func() -> bool:
		rising.append(doors.fraction(CRAFT))
		if doors.phase(CRAFT) == "opening" and rising.size() == 30:
			walker.launch_requested.emit()
		return doors.is_open(CRAFT), Doors.OPEN_TIME + 1.0)
	check(garage._launch_refused == Garage.DOOR_RISING, "... the refusal saying the door is still rising")
	var monotonic := true
	for k in range(1, rising.size()):
		monotonic = monotonic and rising[k] >= rising[k - 1]
	check(current_scene == garage and not garage._departing, "A launch while the door rises is refused")
	check(waited > Doors.OPEN_TIME - .3 and waited < Doors.OPEN_TIME + .5 and monotonic and doors.fraction(CRAFT) == 1.0,
		"The door rolls steadily up into its hood in %.1f s" % waited)
	check(startup.all_running(), "Both engines idle by the time the door is up")
	check(Prompts.door_line(doors.phase(CRAFT), "F") == "F  Launch flight", "With the door up the prompt offers the launch")

	walker.interact_requested.emit()
	await process_frame
	check(not walker.seated and startup.all_running() and doors.phase(CRAFT) == "closing",
		"Stepping out, the engines left running, brings the door down")
	waited = await _until(func() -> bool: return doors.phase(CRAFT) == "shut", Doors.CLOSE_TIME + 1.0)
	check(waited > Doors.CLOSE_TIME - .3 and doors.fraction(CRAFT) == 0.0, "... shut in %.1f s" % waited)

	walker.interact_requested.emit()
	await process_frame
	check(walker.seated and startup.all_running() and doors.phase(CRAFT) == "opening",
		"Boarding a craft whose engines run sends its door up")
	await _until(func() -> bool: return doors.is_open(CRAFT), Doors.OPEN_TIME + 1.0)
	walker.cockpit_control_requested.emit("power")      # (the one-touch control: running, it shuts everything down)
	await _until(func() -> bool: return not Garage.engines_lit(startup), 1.0)
	await process_frame
	check(not Garage.engines_lit(startup) and doors.phase(CRAFT) == "closing", "Shutting the engines down in the seat brings it down")
	await _until(func() -> bool: return doors.phase(CRAFT) == "shut", Doors.CLOSE_TIME + 1.0)
	walker.cockpit_control_requested.emit("power")      # (and from cold the one-touch start works through to START)
	var lit := await _until(func() -> bool: return Garage.engines_lit(startup), 4.0)
	await process_frame
	check(lit >= 0.0 and doors.phase(CRAFT) == "opening", "The one-touch start raises it as its start is pressed, %.1f s in" % lit)
	await _until(func() -> bool: return doors.is_open(CRAFT), Doors.OPEN_TIME + 1.0)

	View.skip_pad = false
	walker.launch_requested.emit()
	check(garage._departing, "With the door up, the pilot's launch leaves at once")
	if not check(await _scene(UI.GAME_SCENE), "... straight into the flight"):
		return
	var flight = current_scene
	check(flight.sim.P.vehicle == CRAFT and flight.sim.kind == "network", "... in the %s, on the map chosen on the menu (%s)" % [flight.sim.P.vehicle, flight.sim.kind])
	check(flight.pad == null and not bool(flight.sim.P.get("pads", false)) and not View.skip_pad and not View.pad_start,
		"... and on the map itself, not on a starting pad")
