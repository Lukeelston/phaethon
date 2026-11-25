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
const Livery := preload("res://view/livery.gd")
const Settings := preload("res://release/game_settings.gd")
const REFUSED_RUNNING := "Shut the engines down first"      # (a run-up bay keeps its paint)

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
var _refused := ""          # why the last change at the bay in front of the pilot was refused ("" none) ...
var _refused_bay := ""      # ... and at which bay


func _ready() -> void:
	# A parked Phaethon or Talon arrives at the Phaethon's bay standing as it flew.
	if Fleet.bay_of(Route.arrival_craft) == Fleet.STANDARD:
		Settings.set_phaethon_body(Route.arrival_craft)
	environment = Workshop.new()
	environment.name = "Workshop"
	add_child(environment)
	var returning := Route.take_parked_bays()
	for id: String in returning:
		var bay: Dictionary = returning[id]
		var at := Fleet.bay_of(id)
		# (keyed by the craft that stood in each bay: the Phaethon's bay's switches only if that body stands there now)
		if at.is_empty() or environment.bay_craft(at) != id:
			continue
		if bay.has("startup") or bay.has("handling") or bay.has("slide"):
			_runup_for(at, bay.get("startup")).apply_switches(bay)
	walker = Walker.new()
	walker.name = "Walker"
	walker.allow_xr = Route.is_xr
	add_child(walker)
	pilot = PilotModel.new()
	pilot.name = "Pilot"
	walker.set_pilot(pilot)
	var arrival := environment.spawn_transform()
	if Fleet.has_bay(Route.arrival_craft):
		arrival = environment.boarding_transform(Fleet.bay_of(Route.arrival_craft))
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
	walker.bay_control_requested.connect(_work_bay)
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
		_runups[Fleet.bay_of(seated_craft)].work(control)


## On foot at a bay (garage_walker.gd bay_control_requested): "paint" takes the next paint on the row for the craft
## standing there (view/livery.gd choices_for, wrapping), saved at once under its key (the one the flight and the menus
## read), and the bay's craft is built again in it; "body", at the Phaethon's bay only, stands the other body there
## (the Phaethon or the Talon, saved: Settings.phaethon_body), in its own saved paint. Either is refused, and the
## prompt says why, while that bay's engines run.
func _work_bay(control: String) -> void:
	if _departing or _boarding or not seated_craft.is_empty() or _at_rotor():
		return
	var bay := environment.nearest_bay(walker.global_position)
	if not Fleet.GARAGE_BAYS.has(bay):
		return
	var craft := environment.bay_craft(bay)
	if control not in ["paint", "body"] or (control == "body" and bay != Fleet.STANDARD):
		return
	if not _bay_cold(bay):
		_refused = REFUSED_RUNNING
		_refused_bay = bay
		_update_prompt()
		return
	if control == "paint":
		var ids := Livery.ids_for(craft)
		Settings.set_choice(Livery.key_for(craft), ids[(ids.find(Livery.saved_for(craft)) + 1) % ids.size()])
		_rebuild_bay(bay, craft)
	else:
		var body := Fleet.TALON if craft == Fleet.STANDARD else Fleet.STANDARD
		Settings.set_phaethon_body(body)
		_rebuild_bay(bay, body, false)      # (another craft: its bay's switches start at their defaults)
	_refused = ""
	_update_prompt()


## Is a bay's craft cold: no run-up, or one with the battery off and both engines off?
func _bay_cold(bay: String) -> bool:
	if not _runups.has(bay):
		return true
	var startup := _runups[bay].startup
	return not startup.batt and startup.stage[0] == "off" and startup.stage[1] == "off"


## Build a cold bay's craft again in place (garage_environment.gd rebuild_bay), as `craft` in its saved paint. The cab
## built for it goes, so the next boarding builds it in the new paint; its run-up is set up again on the new airframe,
## with the switches moved in this visit (`keep_switches`).
func _rebuild_bay(bay: String, craft: String, keep_switches := true) -> void:
	var moved := {}
	if _runups.has(bay):
		if keep_switches:
			moved = _runups[bay].switch_settings.duplicate()
		_runups[bay].free()
		_runups.erase(bay)
	if _cockpit != null and _cockpit.get_parent() == environment.bay_node(bay):
		_cockpit.free()
		_cockpit = null
	environment.rebuild_bay(bay, craft, Livery.built(craft))
	if not moved.is_empty():
		_runup_for(bay).apply_switches(moved)


## The name of the paint a craft wears, as its row names it ("Factory", "Cobalt blue").
func _paint_name(craft: String) -> String:
	var ids := Livery.ids_for(craft)
	return str(Livery.choices_for(craft)[maxi(0, ids.find(Livery.saved_for(craft)))][1])


func _operate_cockpit(delta: float) -> void:
	var runup := _runups[Fleet.bay_of(seated_craft)]
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
	var at := environment.nearest_bay(walker.global_position)
	if not Fleet.GARAGE_BAYS.has(at):
		return
	var craft := environment.bay_craft(at)      # (in the Phaethon's bay, the Phaethon or the Talon)
	var bay := environment.bay_node(at) as Workshop.Parked
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
			if environment.nearest_bay(walker.global_position) != at:
				_update_prompt()
				return
		else:
			_cockpit.build(craft, Callable(), bay.paint)
	_cockpit.show()
	environment.set_cockpit_visible(at, false)
	seated_craft = craft
	pilot.set_seat_vehicle(craft)
	walker.set_seated(true, environment.seat_transform(at))
	var runup := _runup_for(at)
	runup.set_seated(true, _cockpit.overhead.pods if _cockpit.overhead else {})
	walker.set_cockpit_grips(_cockpit.throttle_grips())
	_operate_cockpit(0.0)
	_update_prompt()


func leave_seat() -> void:
	if _departing or seated_craft.is_empty():
		return
	var at := Fleet.bay_of(seated_craft)
	_runups[at].set_seated(false)
	_cockpit.reset_overhead_hands()
	_touching_hands.clear()
	seated_craft = ""
	walker.set_seated(false, environment.boarding_transform(at))
	environment.set_cockpit_visible(at, true)
	# Keep one cab warm so the pilot can check a detail from inside and outside.
	_cockpit.hide()
	_update_prompt()


func launch_flight() -> void:
	if _departing or seated_craft.is_empty():
		return
	_departing = true
	var bays := {}
	for id: String in Fleet.GARAGE_BAYS:
		var data := {}      # (its paint is its own saved choice: view/livery.gd, read again by the flight)
		if _runups.has(id):
			var runup := _runups[id]
			data.merge(runup.switch_settings)
			if runup.operated:
				data.startup = runup.startup
		bays[environment.bay_craft(id)] = data      # (under the craft standing there: the Phaethon's bay's may be the Talon's)
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
	var craft := environment.bay_craft(_nearby) if seated_craft.is_empty() else seated_craft
	var craft_name := str(Fleet.NAMES.get(craft, ""))
	var anchor := environment.spawn_transform()
	if not seated_craft.is_empty():
		anchor = environment.seat_transform(craft)
	elif walker.xr_live:
		anchor = environment.marker_guide(_nearby,walker.global_position)
	if _refused_bay != _nearby or not seated_craft.is_empty():
		_refused = ""
	var paint := _paint_name(craft) if seated_craft.is_empty() and not craft.is_empty() else ""
	var body := craft_name if seated_craft.is_empty() and _nearby == Fleet.STANDARD else ""
	_prompts.show_controls(craft_name, not seated_craft.is_empty(), Route.destination_label(), _using_pad, anchor, paint, _refused, body)
