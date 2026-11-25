## Explicit XR-off diagnostic of the shipped VR scenes. Never verifies headset tracking.
extends Node

const View := preload("res://view/craft_view.gd")
const Cockpit := preload("res://vr/vr_cockpit.gd")
const Boot := preload("res://release/vr_boot.gd")
const Paint := preload("res://view/livery.gd")
const Settings := preload("res://release/game_settings.gd")
const UI := preload("res://release/release_config.gd")
const Stops := ["range", "gp", "eridanus", "emergency", "network", "carving", "network", "aurora", "range"]

var checks := 0
var failures := 0
var evidence := ""
var _started_ms := 0
var _finished := false
var _prefs_existed := false
var _prefs_before := PackedByteArray()
var _settings_existed := false
var _settings_before := PackedByteArray()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_ms = Time.get_ticks_msec()
	evidence = OS.get_user_data_dir().path_join("pcvr-verification")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="):
			evidence = arg.trim_prefix("--evidence=")
	_run.call_deferred()

func _process(_delta: float) -> void:
	if not _finished and Time.get_ticks_msec() - _started_ms > 120000:
		check("VR scene diagnostic finishes within 120 seconds", false)
		_finish()

func check(label: String, passed: bool) -> bool:
	checks += 1
	if not passed:
		failures += 1
	print(("PASS " if passed else "FAIL ") + label)
	return passed

func frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func has_textured_road(world: Node) -> bool:
	if world == null:
		return false
	for instance: MeshInstance3D in world.find_children("*", "MeshInstance3D", true, false):
		if not instance.mesh:
			continue
		for i in instance.mesh.get_surface_count():
			var material := instance.get_active_material(i) as ShaderMaterial
			if material and material.shader == preload("res://view/asphalt.gdshader"):
				var detail := material.get_shader_parameter("pavement_detail") as Texture2D
				if detail and detail.get_width() > 0:
					return true
	return false

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP pcvr-", name, " screenshot: headless display")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(name + " VR scene screenshot saved", image.save_png(evidence.path_join("pcvr-" + name + ".png")) == OK)

## The fleet's atlas is baked into both meshes. Check the material the pilot sees in each.
func _garage_atlas_matches(bay: Node3D, repaint: bool, enamel := Color.WHITE) -> bool:
	var shell := bay.get_node_or_null("OccupiedCockpit/ParkedShell/PodHull") as MeshInstance3D
	if not shell:
		return false
	var body: Mesh = bay.model.fleet.part(&"Cab")
	for mesh: Mesh in [body, shell.mesh]:
		if not mesh or mesh.get_surface_count() == 0:
			return false
		var material := mesh.surface_get_material(0) as ShaderMaterial
		if not material or (material.get_shader_parameter("repaint") == true) != repaint:
			return false
		if repaint:
			var actual: Color = material.get_shader_parameter("to_r")      # (the enamel's colour: view/fleet_airframe.gd repaint, mask channel R)
			if not actual.is_equal_approx(enamel):
				return false
	return true


## Exercise the shipped garage from its menu row before continuing the flight tour.
func _visit_garage() -> bool:
	var menu = get_tree().current_scene
	var course: String = menu.selected_course
	var row := menu.find_child("Garage", true, false) as Button
	if not check("VR menu offers Pilot garage", row != null and menu.buttons.has(row) and not row.disabled):
		return false
	var saved_craft := Settings.selected_craft()
	# Each craft keeps its own paint (view/livery.gd key_for: "paint_vesper", "paint_kiln"): the Vesper's cobalt,
	# the Kiln's Factory, put back after.
	var paint_keys := [Paint.key_for("vesper"), Paint.key_for("kiln")]
	var saved_paints := [Paint.saved_for("vesper"), Paint.saved_for("kiln")]
	var previous_live := Paint.current
	Settings.set_selected_craft("vesper")
	Settings.set_choice(paint_keys[0], "cobalt")
	Settings.set_choice(paint_keys[1], Paint.FACTORY)
	# Make inadvertent use of the global flight paint visible in both parked cabs.
	Paint.current = "crimson"
	menu.set_process(false)
	menu.focus_row(menu.buttons.find(row))
	menu.consume_controller(0.0, false, true)
	menu.consume_controller(0.0, true, true)
	await get_tree().scene_changed
	var garage = get_tree().current_scene
	if not check("controller confirm opens the garage on foot", garage.scene_file_path == "res://garage/garage.tscn" and garage.get("walker") != null and not garage.walker.seated):
		return false
	garage.walker.set_seated(false, garage.environment.boarding_transform("vesper"))
	garage.walker.interact_requested.emit()
	if not check("the packaged Vesper cockpit can be boarded", garage.walker.seated and garage.seated_craft == "vesper"):
		return false
	var vesper: Node3D = garage.environment.bay_node("vesper")
	check("Vesper carries its own saved cobalt paint inside and outside",
		_garage_atlas_matches(vesper, true, Paint.coat("paint", "cobalt")))
	garage.walker.interact_requested.emit()
	check("dismount returns to Vesper's boarding point", not garage.walker.seated and garage.environment.nearest_bay(garage.walker.global_position) == "vesper")
	garage.walker.set_seated(false, garage.environment.boarding_transform("kiln"))
	garage.walker.interact_requested.emit()
	var kiln: Node3D = garage.environment.bay_node("kiln")
	check("adjacent Kiln keeps its own factory atlas inside and outside", _garage_atlas_matches(kiln, false))
	garage.walker.interact_requested.emit()
	check("boarding both bays restores incoming global paint", Paint.current == "crimson")
	Paint.current = previous_live
	for k in paint_keys.size():
		Settings.set_choice(paint_keys[k], saved_paints[k])
	Settings.set_selected_craft(saved_craft)
	garage.walker.back_requested.emit()
	await get_tree().scene_changed
	var returned = get_tree().current_scene
	return check("leaving the garage restores the VR menu and course", returned.scene_file_path == "res://release/vr_menu.tscn" and returned.selected_course == course)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(evidence.path_join("profile"))
	View.best_dir = evidence.path_join("profile/")
	_settings_existed = FileAccess.file_exists(Settings.PREFS)
	if _settings_existed:
		_settings_before = FileAccess.get_file_as_bytes(Settings.PREFS)
	_prefs_existed = FileAccess.file_exists(Cockpit.PREFS)
	if _prefs_existed:
		_prefs_before = FileAccess.get_file_as_bytes(Cockpit.PREFS)
	var xr := XRServer.find_interface("OpenXR")
	var xr_live := xr != null and xr.is_initialized()
	if OS.has_feature("template"):
		var notices := OS.get_executable_path().get_base_dir().path_join("THIRD_PARTY.md")
		if not check("THIRD_PARTY.md ships beside the PC VR executable", FileAccess.file_exists(notices)):
			_finish()
			return
		check("export carries the pcvr feature", OS.has_feature("pcvr"))
		check("export defaults to VR boot", ProjectSettings.get_setting_with_override("application/run/main_scene") == "res://release/vr_boot.tscn")
		check("export separates VR user data", OS.get_user_data_dir().ends_with("Phaethon-VR"))
	if not check("diagnostic is explicitly authorized with XR off acknowledged", Boot.startup_route(xr_live, OS.get_cmdline_user_args()) == "diagnostic"):
		_finish()
		return
	print("PHYSICAL VR UNVERIFIED: this checks VR scene construction with OpenXR off, not headset tracking, rendering, controller feel or comfort.")
	if not check("VR evidence directory is absolute", evidence.is_absolute_path()):
		_finish()
		return
	if not check("VR evidence directory is available", DirAccess.make_dir_recursive_absolute(evidence) == OK):
		_finish()
		return
	var sample := load("res://audio/engines/v8_mip0.wav") as AudioStreamWAV
	check("VR engine audio PCM16 resource is present", sample != null and sample.format == AudioStreamWAV.FORMAT_16_BITS)
	check("VR engine manifest is present", FileAccess.file_exists("res://audio/engines/manifest.json"))
	check("VR ramjet manifest is present", FileAccess.file_exists("res://audio/ramjet/manifest.json"))   # (the engine audio loads it with the engines': without it the game is silent)
	var expected_scheme := "triggers"
	if FileAccess.file_exists(Cockpit.PREFS):
		var prefs = JSON.parse_string(FileAccess.get_file_as_string(Cockpit.PREFS))
		if prefs is Dictionary and Cockpit.QuestControlsScript.SCHEMES.has(prefs.get("scheme", "")):
			expected_scheme = prefs.scheme
	# This is a check of a craft that is running: instruments lit, levers live. The start-up from cold
	# has its own (tests/test_startup.gd); here the pilot's COLD START is taken as off.
	Cockpit.cold_start = false
	Cockpit._startup_loaded = true
	get_tree().change_scene_to_file("res://release/vr_menu.tscn")
	await get_tree().scene_changed
	await frames(3)
	await shot("main-menu")
	if DisplayServer.get_name() != "headless":
		var menu = get_tree().current_scene
		check("VR menu panel screenshot saved", menu.panel_view.get_texture().get_image().save_png(evidence.path_join("pcvr-menu-panel.png")) == OK)
	if not await _visit_garage():
		_finish()
		return
	var overlay = get_tree().root.get_node("ReleasePause")
	for index in Stops.size():
		var stop: String = Stops[index]
		var menu = get_tree().current_scene
		check(stop + " starts at the VR menu", menu.scene_file_path == "res://release/vr_menu.tscn")
		menu.set_process(false) # Explicitly XR-off diagnostic supplies controller samples below.
		var collisions := index % 2 == 1
		var partner_enabled := index % 2 == 0
		var pilot_craft: String = Settings.Craft.ORDER[index % Settings.Craft.ORDER.size()]
		Settings.set_selected_craft(pilot_craft)      # (the board has no craft row: the garage, or the craft last flown, chooses it)
		menu._showcase_changed()
		menu.collision_checkbox.button_pressed = collisions
		menu.partner_checkbox.button_pressed = partner_enabled
		check(stop + " obstacle checkbox persists", Settings.obstacle_collisions_enabled() == collisions)
		check(stop + " partner checkbox persists", Settings.driving_partner_enabled() == partner_enabled)
		menu.choose_course(stop)
		if stop == "carving" and DisplayServer.get_name() != "headless":
			await frames(2)
			await RenderingServer.frame_post_draw
			check("six-course VR panel captured", menu.panel_view.get_texture().get_image().save_png(evidence.path_join("carving-menu-panel.png")) == OK)
		check(stop + " selection keeps menu open", get_tree().current_scene == menu and menu.selected_course == stop)
		check(stop + " is chosen and named on Fly", menu.start_button.name == &"Fly" and menu.start_button.text == "Fly — " + UI.COURSES[UI.course_index(stop)].name)
		menu.focus_row(menu.start_index)
		menu.consume_controller(0.0, true, true)
		check(stop + " held entry trigger cannot launch", not menu.launching)
		menu.consume_controller(0.0, false, true)
		menu.consume_controller(0.0, true, true)
		await get_tree().scene_changed
		var view = get_tree().current_scene
		if not check(stop + " opens the real VR cockpit scene", view is Cockpit and view.scene_file_path == "res://vr.tscn"):
			_finish()
			return
		check(stop + " native track selection is correct", view._track() == ("network" if stop == "aurora" else stop))
		if stop == "aurora":
			check("VR Aurora starts at the southwest lock", view.sim.pod.path == view.sim.NET_PRESSURE[0]
				and view.sim.pod.hint < view.sim.NET_PRESSURE[1] and view.network_world.pressure_line.is_visible_in_tree())
		check(stop + " job selection is correct", not view.sim.job.is_empty() if stop == "emergency" else view.sim.job.is_empty())
		if stop == "carving":
			check("Carving starts in Speedcraft with visible corner guidance",view.sim.P.handling=="speed" and view.gp_world!=null and view.gp_world.corners.size()>10 and view.gp_world.chevrons>0)
		check(stop + " launch respects obstacle checkbox", view.sim.P.obstacleCollisions == collisions)
		if view.craft.Fleet.supports(pilot_craft):
			check(stop + " loads the packed cockpit", view.shell.get_node("PodHull").mesh == view.craft.fleet.part(&"Cab") and view.canopy.get_node("roof").mesh == view.craft.fleet.part(&"Roof"))
		check(stop + " launches " + pilot_craft, view.sim.P.vehicle == pilot_craft and (view.shell.find_child("ShrikePlate", true, false) != null) == (pilot_craft == "shrike"))
		check(stop + " launch builds the selected partner state", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		check(stop + " skill tracker and audio loaded", view.skill_score != null and view.skill_audio != null)
		check(stop + " has XR origin and camera", view.origin is XROrigin3D and view.cam is XRCamera3D)
		check(stop + " has both controller nodes", view.hands.get("left") is XRController3D and view.hands.get("right") is XRController3D)
		check(stop + " controller trackers are assigned", view.hands.left.tracker == &"left_hand" and view.hands.right.tracker == &"right_hand")
		check(stop + " cockpit instruments are constructed", view.interior != null and view.dashboard != null and view.mode_switch != null and view.canopy != null and view.minimap_panel != null)
		check(stop + " start panel hangs from the roof's header, and the craft is running", (view.overhead != null) == Canopy.roof_available() and view.startup.is_hot())
		if index == 0:
			for fitting in ["SegmentedCoaming", "InstrumentBezel"]:
				var panel := view.interior.get_node_or_null(fitting) as MeshInstance3D
				var finish: Material = panel.get_active_material(0) if panel and panel.mesh else null
				check(fitting + " has its imported PBR finish", finish is BaseMaterial3D and finish.albedo_texture != null and finish.normal_texture != null)
			for side in 2:
				check("engine %d carries its imported nacelle" % side, view.craft.engines[side].has_node("NacelleShell"))
				check("lever %d carries its grip and gate indicator" % side, view.lever_pivots[side].has_node("PilotGrip/GateIndicator"))
		check(stop + " uses default or saved control scheme", view.quest.scheme == expected_scheme)
		check(stop + " starts in its handling's first gear", view.quest.gear == (0 if view.sim.P.handling == "starfighter" else 1))
		check(stop + " remains an explicitly flat diagnostic", not get_viewport().use_xr)
		var before: float = view.sim.time
		var start := Vector2(view.sim.pod.x, view.sim.pod.y)
		# This is synthetic input in an XR-off window. Windows can clear a held
		# key on a focus change while the new scene opens; reassert the requested
		# test input each frame so that the movement check actually receives it.
		for frame in 45:
			key(KEY_E, true)
			await frames(1)
		key(KEY_E, false)
		check(stop + " simulation advances", view.sim.time > before)
		if stop == "network":
			check("Eridanus solar aperture and cooling galleries are present", view.network_world.scenery.has_node("EridanusSolarAperture") and view.network_world.scenery.has_node("EridanusCoolingGalleries"))
			check("Eridanus bay frames are live in streamed road chunks", view.network_world.find_child("ShelterBays", true, false) is MultiMeshInstance3D)
			check("moving craft receives the local terminal light", view.terminal_lighting != null and view.terminal_lighting.fixture.is_visible_in_tree())
		if view.quest.scheme == "triggers":
			view.quest.set_gear(4)
			await frames(2)
			var speed_mode: bool = view.sim.P.handling == "speed"
			check(stop + " top gear reaches physics and audio for the actual handling", bool(view.inp.get("gearOverdrive", false)) == speed_mode and view._engine_inp().get("gearIndex", -1) == (4 if speed_mode else 0))
			view.quest.set_gear(3)
			await frames(2)
			check(stop + " downshift disables overdrive", not bool(view.inp.get("gearOverdrive", true)))
			view.quest.set_gear(0)
		if stop == "emergency":
			check("emergency job remains in a valid stage", view.sim.job.has("stage") and str(view.sim.job.stage) != "")
		else:
			check(stop + " keyboard can move the cockpit", Vector2(view.sim.pod.x, view.sim.pod.y).distance_to(start) > 0.05)
		key(KEY_X, true)
		await frames(2)
		key(KEY_X, false)
		check(stop + " throttle cut works", view.inp.thrL == 0.0 and view.inp.thrR == 0.0)
		var was_muted := AudioServer.is_bus_mute(0)
		view.menu_open(true)
		check(stop + " quick-menu panel is visible", view.menu.open and view.menu_panel.visible and (view.menu_panel.get_node("words") as Label3D).text.contains("DRIVING PARTNER"))
		var hold_time: float = view.sim.time
		var score_time: float = view.skill_score.time
		var partner_position := Vector3.ZERO if view.partner == null else Vector3(view.partner.x, view.partner.y, view.partner.z)
		var traffic_tick: int = view.traffic_net._tick if view.traffic_net != null else 0
		await frames(3)
		check(stop + " quick menu freezes simulation", view.sim.time == hold_time)
		check(stop + " quick menu freezes skill tracking", view.skill_score.time == score_time)
		check(stop + " quick menu freezes partner", view.partner == null or Vector3(view.partner.x, view.partner.y, view.partner.z) == partner_position)
		check(stop + " quick menu freezes traffic", view.traffic_net == null or view.traffic_net._tick == traffic_tick)
		check(stop + " quick menu mutes output", AudioServer.is_bus_mute(0))
		view.menu.at = 0
		view.menu_choose()
		check(stop + " quick menu toggles partner immediately", view.partner_on != partner_enabled and (view.partner != null) != partner_enabled)
		view.menu_choose()
		if index == 0:
			await shot("quick-menu")
		view.menu_open(false)
		check(stop + " quick-menu close restores audio and input guard", not view.menu.open and not view.menu_panel.visible and AudioServer.is_bus_mute(0) == was_muted and view._await_neutral_controls)
		await frames(3)
		check(stop + " quick-menu resume advances simulation", view.sim.time > hold_time)
		key(KEY_ESCAPE, true)
		key(KEY_ESCAPE, false)
		overlay.set_paused(true)
		overlay.restart_game()
		overlay.return_to_menu()
		await frames(2)
		check(stop + " desktop pause cannot reroute VR", get_tree().current_scene == view and not get_tree().paused and not overlay.is_paused)
		var road_world: Node = view.range_world if stop == "range" else view.gp_world
		if stop in ["network", "aurora"]:
			road_world = view.network_world
		elif stop in ["eridanus", "emergency"]:
			road_world = view.course_world
		check(stop + " renders the packed surface on a road mesh", has_textured_road(road_world))
		if index < Stops.size() - 1:
			await shot(stop)
		view._respawn()
		check(stop + " restart starts a fresh skill run", view.skill_score.total == 0)
		check(stop + " restart keeps obstacle checkbox", view.sim.P.obstacleCollisions == collisions)
		check(stop + " restart keeps partner", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		if stop == "network":
			check("VR traffic follows obstacle checkbox", view.traffic_net.collide == collisions)
			for city in view.sim.cities:
				if city.name == "DUNES":
					view.sim.respawn_on(int(city.road), int(city.i), 1)
			view.enter_city_gp()
			await get_tree().scene_changed
			view = get_tree().current_scene
			check("VR city GP keeps obstacle checkbox", view.sim.track_name == "gp_dunes" and view.sim.P.obstacleCollisions == collisions)
			check("VR city GP keeps partner", view.partner_on == partner_enabled and (view.partner != null) == partner_enabled)
		var old: WeakRef = weakref(view)
		view.return_to_menu()
		await get_tree().scene_changed
		await frames(2)
		check(stop + " returns to VR menu and unloads flight", get_tree().current_scene.scene_file_path == "res://release/vr_menu.tscn" and old.get_ref() == null)
		check(stop + " menu remembers selection", get_tree().current_scene.selected_course == stop)
		check(stop + " menu restores obstacle checkbox", get_tree().current_scene.collision_checkbox.button_pressed == collisions)
		check(stop + " menu restores partner checkbox", get_tree().current_scene.partner_checkbox.button_pressed == partner_enabled)
	await frames(3)
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	for code in [KEY_E, KEY_X, KEY_ESCAPE]:
		key(code, false)
	if _prefs_existed:
		var prefs := FileAccess.open(Cockpit.PREFS, FileAccess.WRITE)
		if prefs:
			prefs.store_buffer(_prefs_before)
			prefs.close()
		check("VR diagnostic restores saved preferences", prefs != null and FileAccess.get_file_as_bytes(Cockpit.PREFS) == _prefs_before)
	elif FileAccess.file_exists(Cockpit.PREFS):
		check("VR diagnostic removes only preferences it created", DirAccess.remove_absolute(ProjectSettings.globalize_path(Cockpit.PREFS)) == OK)
	if _settings_existed:
		var settings := FileAccess.open(Settings.PREFS, FileAccess.WRITE)
		if settings:
			settings.store_buffer(_settings_before)
			settings.close()
		check("VR diagnostic restores exact game settings", settings != null and FileAccess.get_file_as_bytes(Settings.PREFS) == _settings_before)
	elif FileAccess.file_exists(Settings.PREFS):
		check("VR diagnostic removes only game settings it created", DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PREFS)) == OK)
	print("EXPORTED VR RELEASE %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	print("PHYSICAL VR UNVERIFIED: headset tracking, stereo rendering, controller feel and comfort still need a headset session.")
	get_tree().quit(0 if failures == 0 else 1)
