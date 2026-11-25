## Open the real desktop and headset menus, walk to the parked fleet, board and
## dismount, and launch the chosen vehicle through the same controls used in play.
## Run headless with --xr-mode off -s res://tests/test_pilot_garage.gd -- --mute
extends SceneTree

const UI := preload("res://release/release_config.gd")
const Fleet := preload("res://sim/pilot_craft.gd")
const Settings := preload("res://release/game_settings.gd")
const Flat := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const GARAGE := "res://garage/garage.tscn"
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok


func _key(code: Key) -> void:
	for down in [true, false]:
		_key_state(code, down)


func _key_state(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _scene(path: String) -> bool:
	var until := Time.get_ticks_msec() + 15000
	while current_scene == null or current_scene.scene_file_path != path:
		if Time.get_ticks_msec() > until:
			return check(false, "Expected scene " + path)
		await process_frame
	await process_frame
	return true


func _enter_menu(xr: bool) -> bool:
	var path := UI.VR_MENU_SCENE if xr else UI.MENU_SCENE
	change_scene_to_file(path)
	if not await _scene(path):
		return false
	var menu = current_scene
	var button := menu.find_child("Garage", true, false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "Garage button in " + path):
		return false
	if xr:
		menu.set_process(false)
		menu.choose_course("range")
		menu.focus_row(menu.buttons.find(button))
		menu.consume_controller(0.0, false, true)
		menu.consume_controller(0.0, true, true)
	else:
		button.pressed.emit()
	if not await _scene(GARAGE):
		return false
	return check(current_scene.get("walker") is CharacterBody3D and current_scene.get("environment") is Node3D,
		"The garage starts with its walking pilot and workshop")


func _move(walker, toward: Vector3) -> void:
	var eye: Basis = walker.eye_transform().basis
	var forward := -eye.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var input := Vector2(toward.dot(right), -toward.dot(forward))
	walker.step_locomotion(input.limit_length(), STEP)


func _walk_to(walker, goal: Vector3) -> bool:
	for n in 650:
		var offset := goal - Vector3(walker.global_position)
		offset.y = 0.0
		if offset.length() < .16:
			return true
		await physics_frame
		_move(walker, offset.normalized())
	return false


func _walk_against(walker, start: Transform3D, direction: Vector3) -> bool:
	walker.set_seated(false, start)
	for n in 130:
		await physics_frame
		_move(walker, direction)
		for k in walker.get_slide_collision_count():
			if walker.get_slide_collision(k).get_normal().dot(direction) < -.45:
				return true
	return false


func _check_boarding_lane(walker: CharacterBody3D, aisle_x: float, gate: Vector3, id: String) -> void:
	# Sweep the standing pilot through the middle and both sides of the painted
	# opening. Lift the feet slightly so the floor doesn't register as an obstacle.
	for offset: float in [-.50, 0.0, .50]:
		var at := Vector3(aisle_x, gate.y + .025, gate.z + offset)
		var across := Vector3(gate.x - aisle_x, 0.0, 0.0)
		check(not walker.test_move(Transform3D(Basis.IDENTITY,at), across),
			"Clear marked boarding lane for %s at offset %.2f m" % [id, offset])


func _floor_and_bays(garage) -> void:
	var workshop = garage.environment
	var walker = garage.walker
	walker.set_physics_process(false)
	var lobby: Transform3D = workshop.spawn_transform()
	check(not walker.seated and garage.seated_craft == "" and walker.global_position.distance_to(lobby.origin) < .2,
		"A new visit starts on foot at the public entrance")
	check(garage.pilot.find_children("*", "MeshInstance3D", true, false).size() > 0, "The walking pilot wears a rendered suit")
	_key(KEY_V)
	check(walker.third_person, "The pilot can inspect the suit on foot")
	_key(KEY_V)
	check(not walker.third_person, "Returning to the walking camera restores first person")
	_key(KEY_E)
	_key(KEY_F)
	await process_frame
	check(current_scene == garage and garage.seated_craft.is_empty(), "The entrance cannot board or launch a distant craft")
	var first: Transform3D = workshop.boarding_transform(Fleet.ORDER[0])
	var aisle := Vector3(lobby.origin.x, 0, first.origin.z)
	var reached: bool = await _walk_to(walker, aisle) and await _walk_to(walker, first.origin)
	check(reached and workshop.nearest_bay(walker.global_position) == Fleet.ORDER[0], "Walk along the floor to the first boarding point")
	var blocked: bool = await _walk_against(walker, first, -first.basis.z)
	check(blocked, "Walking toward the parked pod meets a hull collision")
	var near_wall := Transform3D(Basis.IDENTITY, Vector3(0, 0, 21.5))
	blocked = await _walk_against(walker, near_wall, Vector3.BACK)
	check(blocked and walker.global_position.z < 23.5, "The outside wall stops the pilot on its inside")
	var rear_lane := Transform3D(Basis.IDENTITY, Vector3(0, .025, -workshop.HALF_Z + 2.5))
	check(not walker.test_move(rear_lane, Vector3.RIGHT * (workshop.HALF_X - 3.0)),
		"The rear east passage is clear behind the Basilisk's pod and engines")
	var prior_cabin: WeakRef
	for id: String in Fleet.ORDER:
		var bay: Node3D = workshop.bay_node(id)
		var boarding: Transform3D = workshop.boarding_transform(id)
		var seat: Transform3D = workshop.seat_transform(id)
		if not check(bay != null and workshop.nearest_bay(boarding.origin) == id, "Identifiable boarding point for " + id):
			continue
		_check_boarding_lane(walker, lobby.origin.x, boarding.origin, id)
		walker.set_seated(false, boarding)
		var exterior := bay.find_child("DisplayCockpit", true, false) as Node3D
		if not check(exterior != null and exterior.is_visible_in_tree(), "On foot the " + id + " exterior is displayed"):
			continue
		for cycle in 2:
			var cached = prior_cabin.get_ref() if prior_cabin else null
			_key(KEY_E)
			if not check(walker.seated and garage.seated_craft == id, "Board " + id):
				break
			var fitting := bay.get_node_or_null("OccupiedCockpit")
			if cached != null:
				if cycle == 1:
					check(fitting == cached, "Reboarding the same bay reuses its cached cockpit")
				else:
					await process_frame
					await process_frame
					check(prior_cabin.get_ref() == null, "Changing airframes releases the previous cabin")
			check(fitting != null and fitting.get("vehicle") == id and not exterior.is_visible_in_tree() and fitting.find_children("*", "MeshInstance3D", true, false).size() > 0,
				"Boarding installs visible cockpit geometry for " + id)
			var eye: Transform3D = walker.eye_transform()
			walker.step_locomotion(Vector2(0, -1), STEP)
			check(eye.origin.distance_to(seat.origin) < .06 and walker.eye_transform().origin.distance_to(eye.origin) < .001,
				"Seated pilot eye remains at the " + id + " controls")
			if fitting == null:
				break
			prior_cabin = weakref(fitting)
			_key(KEY_E)
			await process_frame
			await process_frame
			check(not walker.seated and garage.seated_craft == "" and walker.global_position.distance_to(boarding.origin) < .2,
				"Exit on the boarding side of " + id)
			var retained = prior_cabin.get_ref()
			check(exterior.is_visible_in_tree() and (retained == null or not retained.is_visible_in_tree()),
				"Dismount restores the exterior and removes the occupied cockpit from view")


func _indicator_pair(workshop, id: String) -> Vector2i:
	var first := Fleet.ORDER.find(id) * 2
	# The headless renderer discards MultiMesh instance data.
	if DisplayServer.get_name() == "headless":
		return Vector2i(workshop._lamp_states[first], workshop._lamp_states[first + 1])
	var lenses: MultiMesh = workshop.get_node("BayEngineIndicators").multimesh
	return Vector2i(roundi(2.0 * lenses.get_instance_custom_data(first).r),
		roundi(2.0 * lenses.get_instance_custom_data(first + 1).r))


func _fly_and_return(garage, xr: bool) -> void:
	var id := "orrery" if xr else "vesper"
	garage.walker.set_physics_process(true)
	var finishes := {}
	for craft: String in Fleet.ORDER:
		finishes[craft] = garage.environment.bay_node(craft).paint
	check(finishes.vesper == "violet" and finishes.orrery == UI.Livery.FACTORY,
		"Only the selected Vesper wears the pilot's violet paint")
	var at: Transform3D = garage.environment.boarding_transform(id)
	garage.walker.set_seated(false, at)
	_key(KEY_E)
	if not check(garage.seated_craft == id, "Board selected launch craft " + id):
		return
	var bay = garage.environment.bay_node(id)
	var runup = bay.get_node("Runup")
	var systems: StartupSequence = runup.startup
	var stands: Transform3D = bay.model.pod.global_transform
	var secondaries: Array = []
	for engine: Node3D in bay.model.engines:
		secondaries.append(engine.global_transform)
	check(not systems.batt and not systems.all_running(), "Fresh workshop airframe is cold")
	check(garage.environment._lamp_states.count(0) == 2 * Fleet.ORDER.size(),
		"Every bay starts with both service windows dark")
	_key(KEY_I)
	var deadline := Time.get_ticks_msec() + 16000
	var staggered := false
	var signals: Array[Vector2i] = []
	while not systems.all_running() and Time.get_ticks_msec() < deadline:
		staggered = staggered or systems.stage[0] != systems.stage[1]
		var pair := _indicator_pair(garage.environment, id)
		if signals.is_empty() or signals.back() != pair:
			signals.append(pair)
		await process_frame
	check(signals == [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)]
		and _indicator_pair(garage.environment, id) == Vector2i(2,2),
		"The sign shows each engine cranking amber and reaching green idle in firing order")
	check(garage.environment._lamp_states.count(0) == 2 * (Fleet.ORDER.size() - 1),
		"Only the occupied bay's indicators light")
	check(systems.all_running() and staggered and garage.walker.seated and current_scene == garage,
		"Left and right engines start in sequence while the seated pilot stays in the workshop")
	var grips: Array = bay.get_node("OccupiedCockpit").throttle_grips()
	var idle: Transform3D = grips[0].global_transform
	var other: Transform3D = grips[1].global_transform
	_key_state(KEY_W, true)
	await create_timer(0.4).timeout
	check(not idle.is_equal_approx(grips[0].global_transform) and other.is_equal_approx(grips[1].global_transform),
		"The left throttle moves its own handle when operated through player input")
	_key_state(KEY_W, false)
	_key(KEY_P)
	check(not systems.park and stands.is_equal_approx(bay.model.pod.global_transform)
		and secondaries[0].is_equal_approx(bay.model.engines[0].global_transform)
		and secondaries[1].is_equal_approx(bay.model.engines[1].global_transform),
		"Releasing the park brake leaves the pod and both engines fixed to their service stands")
	_key(KEY_P)
	runup.work("handling", 1)
	runup.work("slide", -1)
	_key(KEY_E)
	_key(KEY_E)
	check(garage.walker.seated and bay.get_node("Runup").startup == systems and systems.all_running(),
		"Stepping out and returning keeps this airframe running")
	var old: WeakRef = weakref(garage)
	_key(KEY_F)
	if not await _scene("res://vr.tscn" if xr else UI.GAME_SCENE):
		return
	var flight = current_scene
	check((flight is Cockpit if xr else flight is Flat) and flight.sim.P.vehicle == id and Settings.selected_craft() == id,
		"Launch the actual selected craft in its flight mode")
	check(flight.sim.kind == ("range" if xr else "network"), "Launch preserves the selected destination")
	check(UI.Livery.current == finishes[id], "Launch uses the finish the pilot saw from the aisle")
	check(flight.sim.P.handling == "starfighter", "The physical handling switch carries its selected mode onto the pad")
	check(old.get_ref() == null, "Flight releases the garage")
	if xr:
		check(flight.startup == systems and flight.startup.all_running() and flight.startup.park and not Cockpit.slide_feel,
			"The runway receives the exact startup, park brake and slide switch state the pilot left in the bay")
		flight.menu_open(true)
		for choice in ["options", "garage"]:
			for index in flight.menu.items.size():
				if flight.menu.key() == choice:
					break
				flight.menu.move(1)
			if not check(flight.menu.key() == choice, "Parked headset menu offers " + choice):
				return
			flight.menu_choose()
		if not await _scene(GARAGE):
			return
		garage = current_scene
		_check_returned_finishes(garage, finishes)
		check(not garage.walker.seated and garage.environment.nearest_bay(garage.walker.global_position) == id,
			"Headset dismount arrives alongside the craft it flew")
		var returned = garage.environment.bay_node(id).get_node("Runup")
		check(returned.startup == systems and returned.startup.all_running() and not returned.telemetry.slide
			and returned.telemetry.handling == "starfighter", "Headset return restores that flight's engines and switches")
		check(_indicator_pair(garage.environment, id) == Vector2i(2,2),
			"Stepping out of a running craft from flight immediately restores its two green windows")
		_key(KEY_E)
		_key(KEY_I)
		await process_frame
		await process_frame
		check(_indicator_pair(garage.environment, id) == Vector2i.ZERO,
			"Shutting down the craft extinguishes both bay indicators")
		_key(KEY_E)
		_key(KEY_ESCAPE)
		if await _scene(UI.VR_MENU_SCENE):
			check(current_scene.selected_course == "range", "Headset garage returns to its selected course on the title")
		return
	var pause_menu = root.get_node("ReleasePause")
	var speed: float = flight.sim.eL.vx
	flight.sim.eL.vx = 8.0
	_key(KEY_ESCAPE)
	var moving_button := pause_menu.find_child("Garage", true, false) as Button
	check(not flight.can_visit_garage() and (moving_button == null or not moving_button.is_visible_in_tree() or moving_button.disabled),
		"A moving engine prevents dismount even while paused")
	pause_menu.resume_game()
	flight.sim.eL.vx = speed
	var x: float = flight.sim.pod.x
	flight.sim.pod.x += 10.0
	check(not flight.can_visit_garage(), "A stopped craft away from its launch site cannot dismount")
	flight.sim.pod.x = x
	_key(KEY_ESCAPE)
	var button := pause_menu.find_child("Garage", true, false) as Button
	if not check(button != null and button.is_visible_in_tree() and not button.disabled, "The pause menu permits dismount at the launch site"):
		pause_menu.set_paused(false)
		return
	button.pressed.emit()
	if not await _scene(GARAGE):
		return
	garage = current_scene
	_check_returned_finishes(garage, finishes)
	check(not paused and not garage.walker.seated and garage.environment.nearest_bay(garage.walker.global_position) == id,
		"Leave the parked flight on foot alongside the same craft")
	_key(KEY_ESCAPE)
	if await _scene(UI.MENU_SCENE):
		check(current_scene is Control, "Walking back returns to the desktop title")


func _check_returned_finishes(garage, expected: Dictionary) -> void:
	for craft: String in Fleet.ORDER:
		check(garage.environment.bay_node(craft).paint == expected[craft],
			"Returning to the workshop preserves the finish on " + craft)


func _run() -> void:
	var settings_before := Settings.prefs_path
	var had_vr_prefs := FileAccess.file_exists(Cockpit.PREFS)
	var vr_prefs := FileAccess.get_file_as_bytes(Cockpit.PREFS) if had_vr_prefs else PackedByteArray()
	Settings.prefs_path = "user://test-garage-%d.cfg" % OS.get_process_id()
	Settings.set_selected_craft("vesper")
	Settings.set_choice("paint", "violet")
	if await _enter_menu(false):
		await _floor_and_bays(current_scene)
		await _fly_and_return(current_scene, false)
	if await _enter_menu(true):
		await _fly_and_return(current_scene, true)
	if FileAccess.file_exists(Settings.prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.prefs_path))
	Settings.prefs_path = settings_before
	if had_vr_prefs:
		var file := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		file.store_buffer(vr_prefs)
		file.close()
	elif FileAccess.file_exists(Cockpit.PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS))
	print("PILOT GARAGE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(int(failures > 0))
