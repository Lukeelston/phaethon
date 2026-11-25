extends Node3D

const Fleet := preload("res://sim/pilot_craft.gd")
const Route := preload("res://release/garage_route.gd")
const Workshop := preload("res://garage/garage_environment.gd")
const Walker := preload("res://garage/garage_walker.gd")
const PilotModel := preload("res://garage/pilot_model.gd")
const ParkedCockpit := preload("res://garage/garage_cockpit.gd")
const Runup := preload("res://garage/garage_runup.gd")
const Prompts := preload("res://garage/garage_prompts.gd")
const WheelGrip := preload("res://garage/inspection_wheel_grip.gd")
const ShopAudio := preload("res://garage/workshop_audio.gd")

var environment: Workshop
var walker: Walker
var pilot: PilotModel
var seated_craft := ""
var _cockpit: ParkedCockpit
var _runups: Dictionary[String, Runup] = {}
var _exterior_screening := 0.0
var _touching_hands: Array[XRController3D] = []
var _prompts: Prompts
var _nearby := ""
var _near_rotor := false
var _wheel_grip := WheelGrip.new()
var _using_pad := false
var _departing := false
var _boarding := false


func _ready() -> void:
	environment = Workshop.new()
	environment.name = "Workshop"
	add_child(environment)
	var returning := Route.take_parked_bays()
	for id: String in returning:
		var bay: Dictionary = returning[id]
		if Fleet.ORDER.has(id) and (bay.has("startup") or bay.has("handling") or bay.has("slide")):
			_runup_for(id, bay.get("startup")).apply_switches(bay)
	walker = Walker.new()
	walker.name = "Walker"
	walker.allow_xr = Route.is_xr
	add_child(walker)
	pilot = PilotModel.new()
	pilot.name = "Pilot"
	walker.set_pilot(pilot)
	var arrival := environment.spawn_transform()
	if Fleet.ORDER.has(Route.arrival_craft):
		arrival = environment.boarding_transform(Route.arrival_craft)
	walker.set_seated(false, arrival)
	if not OS.get_cmdline_user_args().has("--mute"):
		var sound := ShopAudio.new()
		sound.name = "ShopAudio"
		add_child(sound)
		sound.exterior_screening_changed.connect(_screen_parked_engines)
		sound.setup(walker, environment.get_node("ServiceEntry"), environment.inspection)
	walker.interact_requested.connect(interact)
	walker.launch_requested.connect(launch_flight)
	walker.back_requested.connect(return_to_menu)
	walker.cockpit_control_requested.connect(_work_control)
	_prompts = Prompts.new()
	add_child(_prompts)
	_prompts.setup(walker.xr_live)
	_update_prompt()
	Runup.prewarm_switches(self)


func _process(delta: float) -> void:
	if _departing:
		return
	if not seated_craft.is_empty():
		_operate_cockpit(delta)
	var nearby := environment.nearest_bay(walker.global_position) if seated_craft.is_empty() else ""
	var at_rotor := _at_rotor()
	if walker.xr_live and at_rotor:
		_wheel_grip.update(environment.inspection, walker.tracked_hands(false), delta)
	elif _near_rotor:
		_wheel_grip.clear(environment.inspection)
	if nearby != _nearby or at_rotor != _near_rotor or _using_pad != walker.using_gamepad:
		_update_prompt()
	elif walker.xr_live and seated_craft.is_empty() and not at_rotor:
		_prompts.place_on_marker(environment.marker_guide(nearby,walker.global_position))


func _at_rotor() -> bool:
	if not seated_craft.is_empty() or _boarding:
		return false
	var station := environment.inspection
	var feet := station.to_local(walker.global_position)
	if feet.z < 1.04 or feet.z > 2.07 or absf(feet.x - Workshop.Inspection.HANDWHEEL.x) > .90:
		return false
	if walker.xr_live:
		return true
	var eye := walker.eye_transform()
	return -eye.basis.z.dot(eye.origin.direction_to(station.rotor_contact_point())) > .32


func _screen_parked_engines(amount: float) -> void:
	_exterior_screening = amount
	for runup: Runup in _runups.values():
		runup.screen_exterior(amount)


func _runup_for(id: String, power: StartupSequence = null) -> Runup:
	if not _runups.has(id):
		var bay := environment.bay_node(id) as Workshop.Parked
		var runup := Runup.new()
		runup.name = "Runup"
		bay.add_child(runup)
		runup.setup(bay, power)
		runup.screen_exterior(_exterior_screening)
		_runups[id] = runup
	return _runups[id]


func _work_control(control: String) -> void:
	if not _departing and not seated_craft.is_empty():
		_runups[seated_craft].work(control)


func _operate_cockpit(delta: float) -> void:
	var runup := _runups[seated_craft]
	var hands := walker.cockpit_hands()
	for hand in _touching_hands:
		if not hands.has(hand):
			_cockpit.forget_overhead_hand(hand)
	_touching_hands = hands
	for hand in hands:
		for hit: Array in _cockpit.poll_overhead(hand, delta):
			runup.work(hit[0], hit[1])
	runup.set_controls(walker.cockpit_input())
	_cockpit.sync_runup(runup.startup, runup.controls, runup.telemetry, delta, pilot)
	_prompts.set_runup_status(runup.status_text())


func interact() -> void:
	if _departing or _boarding:
		return
	if seated_craft != "":
		leave_seat()
		return
	if _at_rotor():
		environment.inspection.spin_rotor()
		return
	var craft := environment.nearest_bay(walker.global_position)
	if not Fleet.ORDER.has(craft):
		return
	var bay := environment.bay_node(craft) as Workshop.Parked
	if _cockpit == null or _cockpit.get_parent() != bay:
		if _cockpit != null:
			_cockpit.queue_free()
		_cockpit = ParkedCockpit.new()
		_cockpit.name = "OccupiedCockpit"
		_cockpit.hide()
		bay.add_child(_cockpit)
		if walker.xr_live:
			_boarding = true
			_prompts.boarding(str(Fleet.NAMES[craft]))
			await _cockpit.build(craft, _next_frame, bay.paint)
			_boarding = false
			if _departing or not is_inside_tree():
				return
			if environment.nearest_bay(walker.global_position) != craft:
				_update_prompt()
				return
		else:
			_cockpit.build(craft, Callable(), bay.paint)
	_cockpit.show()
	environment.set_cockpit_visible(craft, false)
	seated_craft = craft
	pilot.set_seat_vehicle(craft)
	walker.set_seated(true, environment.seat_transform(craft))
	var runup := _runup_for(craft)
	runup.set_seated(true, _cockpit.overhead.pods if _cockpit.overhead else {})
	walker.set_cockpit_grips(_cockpit.throttle_grips())
	_operate_cockpit(0.0)
	_update_prompt()


func leave_seat() -> void:
	if _departing or seated_craft.is_empty():
		return
	var craft := seated_craft
	_runups[craft].set_seated(false)
	_cockpit.reset_overhead_hands()
	_touching_hands.clear()
	seated_craft = ""
	walker.set_seated(false, environment.boarding_transform(craft))
	environment.set_cockpit_visible(craft, true)
	# Keep one cab warm so the pilot can check a detail from inside and outside.
	_cockpit.hide()
	_update_prompt()


func launch_flight() -> void:
	if _departing or seated_craft.is_empty():
		return
	_departing = true
	var bays := {}
	for id: String in Fleet.ORDER:
		var bay := environment.bay_node(id) as Workshop.Parked
		var data := {"paint": bay.paint}
		if _runups.has(id):
			var runup := _runups[id]
			data.merge(runup.switch_settings)
			if runup.operated:
				data.startup = runup.startup
		bays[id] = data
	Route.launch_flight(get_tree(), seated_craft, bays)


func return_to_menu() -> void:
	if _departing:
		return
	_departing = true
	Route.return_to_menu(get_tree())


func _next_frame(_stage: String) -> void:
	await get_tree().process_frame


func _update_prompt() -> void:
	_nearby = environment.nearest_bay(walker.global_position) if seated_craft.is_empty() else ""
	_using_pad = walker.using_gamepad
	_near_rotor = _at_rotor()
	if _near_rotor:
		_prompts.show_rotor(_using_pad, environment.inspection.global_transform)
		return
	var craft := _nearby if seated_craft.is_empty() else seated_craft
	var craft_name := str(Fleet.NAMES.get(craft, ""))
	var anchor := environment.spawn_transform()
	if not seated_craft.is_empty():
		anchor = environment.seat_transform(craft)
	elif walker.xr_live:
		anchor = environment.marker_guide(craft,walker.global_position)
	_prompts.show_controls(craft_name, not seated_craft.is_empty(), Route.destination_label(), _using_pad, anchor)
