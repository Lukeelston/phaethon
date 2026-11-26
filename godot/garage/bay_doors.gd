## The six roller doors in the side walls, one ahead of each bay's nose (garage_environment.gd _shutter). Luke,
## 2026-11-25: "the 'start engines' button should trigger the bay door to raise, and the pilot can enter the map from
## there. If they exit the craft, the bay door should shut again." garage.gd asks for a door open while the seated
## pilot's engines start or run and shut otherwise; a craft leaves for its flight only through a door fully up.
##
## The curtain's lift is drawn by its shader (workshop_shutter.gdshader reads INSTANCE_CUSTOM.r, in metres) and the hood
## lamp's colour by its own (bay_door_lamp.gdshader: green shut, amber flashing while the door runs, amber steady open).
## The travel is kept here as well, as the headless renderer keeps no MultiMesh instance data: tests read `fraction`.
extends Node

signal motion_started(bay: String, opening: bool)
signal motion_finished(bay: String, opened: bool)

const LIFT := 4.80          # the bottom rail rises from the sill to the hood's mouth (the curtain mesh: 0.10 to 4.89 m)
const OPEN_TIME := 5.0      # a high-speed roller door's run, about a metre a second: the engines idle in 3.6 s
const CLOSE_TIME := 6.0     # ... and down a little slower, as such doors close

var bays: Array = []        # bay ids, by the number printed on each curtain (sim/pilot_craft.gd GARAGE_BAYS)
var _travel: PackedFloat32Array
var _goal: PackedFloat32Array
var _curtains: MultiMesh
var _lamps: MultiMesh


func setup(order: Array, curtains: MultiMesh, lamps: MultiMesh) -> void:
	bays = order.duplicate()
	_curtains = curtains
	_lamps = lamps
	_travel.resize(bays.size())
	_goal.resize(bays.size())
	_travel.fill(0.0)
	_goal.fill(0.0)
	for i in bays.size():
		_draw(i)
	set_process(false)


## Ask a bay's door to open or to shut: it starts at once from wherever it stands.
func set_open(bay: String, open: bool) -> void:
	var i := bays.find(bay)
	if i < 0:
		return
	var goal := 1.0 if open else 0.0
	if _goal[i] == goal:
		return
	_goal[i] = goal
	if _travel[i] != goal:
		motion_started.emit(bay, open)
		_draw(i)
		set_process(true)


## How far up a bay's door stands, 0 shut .. 1 open (eased as the motor starts and stops).
func fraction(bay: String) -> float:
	var i := bays.find(bay)
	return smoothstep(0.0, 1.0, _travel[i]) if i >= 0 else 0.0


## Up and stopped: a craft can leave through it.
func is_open(bay: String) -> bool:
	var i := bays.find(bay)
	return i >= 0 and _travel[i] == 1.0 and _goal[i] == 1.0


## "shut", "opening", "open" or "closing".
func phase(bay: String) -> String:
	var i := bays.find(bay)
	if i < 0:
		return "shut"
	if _travel[i] == _goal[i]:
		return "open" if _goal[i] == 1.0 else "shut"
	return "opening" if _goal[i] == 1.0 else "closing"


func _process(delta: float) -> void:
	var moving := false
	for i in bays.size():
		if _travel[i] == _goal[i]:
			continue
		var opening := _goal[i] == 1.0
		_travel[i] = move_toward(_travel[i], _goal[i], delta / (OPEN_TIME if opening else CLOSE_TIME))
		_draw(i)
		if _travel[i] == _goal[i]:
			motion_finished.emit(bays[i], opening)
		else:
			moving = true
	if not moving:
		set_process(false)


func _draw(i: int) -> void:
	var up := smoothstep(0.0, 1.0, _travel[i])
	if _curtains:
		_curtains.set_instance_custom_data(i, Color(up * LIFT, 0, 0, 0))
	if _lamps:
		var running := _travel[i] != _goal[i]
		_lamps.set_instance_custom_data(i, Color(0.0 if _travel[i] == 0.0 and not running else 1.0, 1.0 if running else 0.0, 0, 0))
