## Parked cockpit axes. The Touch shortcuts use the same pressure curves as flight.
extends RefCounted

const Quest := preload("res://input/quest_controls.gd")
const IDLE := {"thrL": 0.0, "thrR": 0.0, "brkL": 0.0, "brkR": 0.0}
const THROTTLES := ["thrL", "thrR"]
const GRAB_RADIUS := 0.10
const LEVER_SWEEP := PI / 3.0

var axes := IDLE.duplicate()
var handles: Array[Node3D] = []
var _quest := Quest.new()
var _neutral := [false, false]
var _grip_down := [false, false]
var _trigger_down := [false, false]
var _grabbing := [false, false]
var _offset := Vector2.ZERO
var _manual := Vector2(-1, -1)
var _desktop_neutral := false


func reset() -> void:
	axes = IDLE.duplicate()
	_quest = Quest.new()
	_neutral.fill(false)
	_grip_down.fill(false)
	_trigger_down.fill(false)
	_grabbing.fill(false)
	_manual = Vector2(-1, -1)
	_desktop_neutral = false


func desktop(keys: Vector2, brakes: Vector2, idle: bool, sticks: Vector2, triggers: Vector2,
		gamepad: bool, delta: float) -> void:
	if not _desktop_neutral:
		_desktop_neutral = keys == Vector2.ZERO and brakes == Vector2.ZERO and not idle \
				and sticks == Vector2.ZERO and triggers == Vector2.ZERO
		return
	for side in 2:
		var t: String = THROTTLES[side]
		var b := "brkL" if side == 0 else "brkR"
		if gamepad:
			axes[t] = sticks[side]
			axes[b] = triggers[side]
		else:
			axes[t] = 0.0 if idle else clampf(axes[t] + keys[side] * delta
					* (Quest.RATE_UP if keys[side] > 0.0 else Quest.RATE_DOWN), 0.0, 1.0)
			axes[b] = move_toward(axes[b], brakes[side], delta * (6.0 if brakes[side] > 0.0 else 8.0))


func _handle_angle(handle: Node3D, palm: Node3D) -> float:
	var pivot := handle.get_parent_node_3d()
	var radius := pivot.get_parent_node_3d().to_local(palm.global_position) - pivot.position
	return atan2(radius.z, radius.y)


func tracked(palms: Array[Node3D], triggers: Vector2, grips: Vector2, delta: float) -> void:
	for side in 2:
		if palms[side] == null:
			_neutral[side] = false
			_manual[side] = -1.0
		elif triggers[side] < .06 and grips[side] < Quest.GRIP_DZ:
			_neutral[side] = true
		if not _neutral[side]:
			triggers[side] = 0
			grips[side] = 0
		var trigger_down := triggers[side] > .06
		if trigger_down and not _trigger_down[side] and not _grabbing[1-side]:
			_manual[1-side] = -1.0
		_trigger_down[side] = trigger_down
		var down := grips[side] >= Quest.GRIP_ON
		var handle := handles[side] if side < handles.size() and is_instance_valid(handles[side]) else null
		if not down or handle == null:
			_grabbing[side] = false
		elif not _grip_down[side] and palms[side].global_position.distance_to(handle.global_position) <= GRAB_RADIUS:
			_grabbing[side] = true
			_offset[side] = axes[THROTTLES[side]] + _handle_angle(handle, palms[side]) / LEVER_SWEEP
		if _grabbing[side]:
			_manual[side] = clampf(_offset[side] - _handle_angle(handle, palms[side]) / LEVER_SWEEP, 0, 1)
			grips[side] = 0  # The squeeze is holding the handle.
		_grip_down[side] = down
	var pressure := _quest.update({"lt": triggers.x, "rt": triggers.y, "lg": grips.x, "rg": grips.y}, delta)
	for side in 2:
		var t: String = THROTTLES[side]
		axes[t] = _manual[side] if _manual[side] >= 0 else (pressure[t] if _neutral[1-side] else 0.0)
		var b := "brkL" if side == 0 else "brkR"
		axes[b] = pressure[b] if _neutral[side] and not _grabbing[side] else 0.0
