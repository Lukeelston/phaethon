## A garage visit starts a new parked flight at the destination the pilot entered from.
extends RefCounted

const UI := preload("res://release/release_config.gd")
const View := preload("res://view/craft_view.gd")
const Craft := preload("res://sim/pilot_craft.gd")
const Sim := preload("res://sim/craft_sim.gd")
const GARAGE_SCENE := "res://garage/garage.tscn"

static var is_xr := false
static var arrival_craft := ""
static var _destination := "network"
static var _overrides: Array = []
# Per-craft switch positions and engine state for this workshop visit (each craft's paint is the menus' for it,
# view/livery.gd's per-craft keys, read again wherever it is built).
# Scene nodes, audio players and held controls stay with the scene that owns them.
static var _bays: Dictionary = {}
# What enter_parked handed the arriving craft's bay from its flight: its live MODE and SLIDE. The bay shows them and a
# launch flies them, but the pilot did not move them in this visit, so a launch saves only what has changed since.
static var _handed: Dictionary = {}


static func enter(tree: SceneTree, xr: bool, course: String) -> void:
	if UI.course_index(course) < 0:
		return
	is_xr = xr
	arrival_craft = ""
	_bays = {}
	_handed = {}
	_destination = course
	_overrides = UI.course_overrides(course)
	tree.call_deferred("change_scene_to_file", GARAGE_SCENE)


## The menus' Fly button: at once, in the craft last used, with its saved switches (the paint is read where the
## craft is built, from the same saved choice). A course with its own start handling keeps it: the saved handling is
## left out there, the slide still comes (the ruling of 2026-11-25: a Grand Prix starts in Starfighter whatever was
## saved).
static func fly(tree: SceneTree, xr: bool, course: String) -> void:
	if UI.course_index(course) < 0:
		return
	var craft: String = UI.Settings.selected_craft()
	var route := UI.course_overrides(course)
	start_flight(tree, xr, craft, route, {craft: _for_track(UI.Settings.craft_setup(craft), route[0])})


## Does a track start in a handling of its own? The sim's own test (sim/craft_sim.gd:831, CraftSim.new): a track in its
## COURSES starts in Starfighter, Carving in the default Speedcraft, unless a handling is asked for.
static func _track_sets_handling(track: String) -> bool:
	return Sim.COURSES.has(track)


## A set-up for a flight on `track`, or saved from one: on a track that sets its own start handling the handling is the
## course's business both ways (it is neither applied nor saved there); the slide always is.
static func _for_track(setup: Dictionary, track: String) -> Dictionary:
	var kept := setup.duplicate()
	if _track_sets_handling(track):
		kept.erase("handling")
	return kept


## A MODE or SLIDE switch the pilot threw in a flight on `track` (view/craft_view.gd save_thrown): saved to the craft's
## set-up, but for a handling thrown on a track that sets its own.
static func save_thrown(craft_id: String, track: String, thrown: Dictionary) -> void:
	UI.Settings.set_craft_setup(craft_id, _for_track(thrown, track))


static func enter_parked(tree: SceneTree, flight: View, xr: bool) -> void:
	if not flight.can_visit_garage():
		return
	var sim = flight.sim
	var track: String = sim.track_name if sim.course else sim.kind
	var job := "emergency" if not sim.job.is_empty() else "none"
	is_xr = xr
	arrival_craft = sim.P.vehicle
	var arrival: Dictionary = _bays.get(arrival_craft, {})
	var parked := flight.parked_systems()
	arrival.merge(parked, true)
	_bays[arrival_craft] = arrival
	# (its bay's for this visit, not the store's: the set-up is what the pilot sets, never a flight's live state)
	_handed = {arrival_craft: parked}
	_destination = "emergency" if job == "emergency" else UI.course_for(track, View.spot_override)
	_overrides = [track, job, View.spot_override]
	tree.call_deferred("change_scene_to_file", GARAGE_SCENE)


static func destination_label() -> String:
	var index := UI.course_index(_destination)
	return UI.COURSES[index].name if index >= 0 else _destination.capitalize()


static func take_parked_bays() -> Dictionary:
	var bays := _bays
	_bays = {}
	return bays


static func launch_flight(tree: SceneTree, craft_id: String, bays: Dictionary = {}) -> void:
	if craft_id not in Craft.ORDER:
		return
	arrival_craft = ""
	var bay: Dictionary = bays.get(craft_id, {})
	var route := _overrides if not _overrides.is_empty() else UI.course_overrides(_destination)
	# The flight, as a Fly from the menu starts it: the craft's saved set-up (the handling left to a course that sets
	# its own), with what its bay shows on top (a switch the pilot moved there is his hand on it, wherever he goes).
	var setup := _for_track(UI.Settings.craft_setup(craft_id), route[0])
	setup.merge(bay, true)
	var flying := bays.duplicate()
	flying[craft_id] = setup
	UI.Settings.set_selected_craft(craft_id)
	UI.Settings.set_craft_setup(craft_id, _moved(craft_id, bay))
	_handed = {}
	start_flight(tree, is_xr, craft_id, route, flying)


## Of a bay's switches, those the pilot moved in this visit: not those a parked flight handed it (enter_parked) and
## still as they were.
static func _moved(craft_id: String, bay: Dictionary) -> Dictionary:
	var handed: Dictionary = _handed.get(craft_id, {})
	var moved := {}
	for key in bay:
		var same: bool = handed.has(key) and typeof(handed[key]) == typeof(bay[key]) and handed[key] == bay[key]
		if not same:
			moved[key] = bay[key]
	return moved


## Shared with the launch buttons on both title menus. CLI overrides are still resolved
## by the flight as usual. A held selection trigger cannot launch a newly entered XR craft.
static func start_flight(tree: SceneTree, xr: bool, craft_id: String, route: Array, bays: Dictionary = {}) -> void:
	_bays = bays.duplicate()
	View.vehicle_override = craft_id
	View.garage_on_entry = _bays.get(craft_id, {})
	View.track_override = route[0]
	View.job_override = route[1]
	View.spot_override = route[2]
	View.pad_start = true
	if xr:
		var cockpit = load("res://vr/vr_cockpit.gd")
		cockpit.require_neutral_on_entry = true
		cockpit.cold_on_entry = true
		var scene := "res://vr/quest_flight.tscn" if OS.has_feature("questflight") else "res://vr.tscn"
		tree.call_deferred("change_scene_to_file", scene)
	else:
		tree.change_scene_to_file(UI.GAME_SCENE)


static func return_to_menu(tree: SceneTree) -> void:
	arrival_craft = ""
	_bays = {}
	_handed = {}
	# (each menu chooses the course the visit was bound for again: the headset's, and the desktop's)
	var menu = load("res://release/vr_menu.gd" if is_xr else "res://release/menu.gd")
	menu.remembered_course = _destination if UI.course_index(_destination) >= 0 else "network"
	tree.call_deferred("change_scene_to_file", UI.VR_MENU_SCENE if is_xr else UI.MENU_SCENE)
