extends Node3D

const Fleet := preload("res://sim/pilot_craft.gd")
const Route := preload("res://release/garage_route.gd")
const Workshop := preload("res://garage/garage_environment.gd")
const Walker := preload("res://garage/garage_walker.gd")
const PilotModel := preload("res://garage/pilot_model.gd")
const ParkedCockpit := preload("res://garage/garage_cockpit.gd")
const Prompts := preload("res://garage/garage_prompts.gd")

var environment: Workshop
var walker: Walker
var pilot: PilotModel
var seated_craft := ""
var _cockpit: ParkedCockpit
var _prompts: Prompts
var _nearby := ""
var _using_pad := false
var _departing := false
var _boarding := false


func _ready() -> void:
	environment = Workshop.new()
	environment.name = "Workshop"
	add_child(environment)
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
	walker.interact_requested.connect(interact)
	walker.launch_requested.connect(launch_flight)
	walker.back_requested.connect(return_to_menu)
	_prompts = Prompts.new()
	add_child(_prompts)
	_prompts.setup(walker.xr_live)
	_update_prompt()


func _process(_delta: float) -> void:
	if _departing:
		return
	var nearby := environment.nearest_bay(walker.global_position) if seated_craft.is_empty() else ""
	if nearby != _nearby or _using_pad != walker.using_gamepad:
		_update_prompt()


func interact() -> void:
	if _departing or _boarding:
		return
	if seated_craft != "":
		leave_seat()
		return
	var craft := environment.nearest_bay(walker.global_position)
	if not Fleet.ORDER.has(craft):
		return
	var bay := environment.bay_node(craft)
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
			await _cockpit.build(craft, _next_frame)
			_boarding = false
			if _departing or not is_inside_tree():
				return
			if environment.nearest_bay(walker.global_position) != craft:
				_update_prompt()
				return
		else:
			_cockpit.build(craft)
	_cockpit.show()
	environment.set_cockpit_visible(craft, false)
	seated_craft = craft
	pilot.set_seat_vehicle(craft)
	walker.set_seated(true, environment.seat_transform(craft))
	_update_prompt()


func leave_seat() -> void:
	if _departing or seated_craft.is_empty():
		return
	var craft := seated_craft
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
	Route.launch_flight(get_tree(), seated_craft)


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
	var craft := _nearby if seated_craft.is_empty() else seated_craft
	var craft_name := str(Fleet.NAMES.get(craft, ""))
	var anchor := environment.spawn_transform()
	if not seated_craft.is_empty():
		anchor = environment.seat_transform(craft)
	elif not craft.is_empty():
		anchor = environment.boarding_transform(craft)
	_prompts.show_controls(craft_name, not seated_craft.is_empty(), Route.destination_label(), _using_pad, anchor)
