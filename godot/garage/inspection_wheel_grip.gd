## Couples one tracked grip to the inspection handwheel. A grip already held
## on approach or tracking recovery must open before it can acquire the rim.
extends RefCounted

const Station := preload("res://garage/inspection_station.gd")
const GRAB_REACH := .060
const RELEASE_REACH := .145

var _owner: XRController3D
var _held: Dictionary[XRController3D, bool] = {}
var _last_angle := 0.0
var _sample_elapsed := 0.0


func clear(station: Station) -> void:
	if _owner:
		station.release_rotor()
	_owner = null
	_held.clear()


func update(station: Station, hands: Array[XRController3D], delta: float) -> void:
	for previous: XRController3D in _held.keys():
		if not hands.has(previous):
			_held.erase(previous)
	if _owner and not hands.has(_owner):
		station.release_rotor()
		_owner = null
	for hand in hands:
		var was_held := _held.get(hand, true) as bool
		var pressure := hand.get_float("grip")
		var is_held := pressure > .35 if was_held else pressure >= .65
		_held[hand] = is_held
		# The grip pose is at the palm. Only its movement around the shaft
		# rotates the wheel; a wrist twist at a stationary point cannot.
		var offset := station.global_basis.inverse() * (hand.global_position - station.rotor_contact_point())
		var angle := atan2(offset.y, offset.x)
		var distance := station.rotor_contact_distance(hand.global_position)
		var off_axis := Vector2(offset.x, offset.y).length() >= .05
		if hand == _owner:
			if not is_held or distance > RELEASE_REACH or not off_axis:
				station.release_rotor()
				_owner = null
			else:
				# A render frame can reuse the previous XR pose. Estimate speed
				# over distinct hand samples so an intervening duplicate does
				# not cut the bearing voice or cancel the inertia on release.
				_sample_elapsed += delta
				var step := wrapf(angle - _last_angle, -PI, PI)
				if absf(step) >= .006:
					station.turn_rotor(step, _sample_elapsed)
					_last_angle = angle
					_sample_elapsed = 0.0
				elif _sample_elapsed >= .05:
					station.turn_rotor(0.0, _sample_elapsed)
					_sample_elapsed = 0.0
		elif _owner == null and is_held and not was_held and off_axis and distance <= GRAB_REACH:
			_owner = hand
			_last_angle = angle
			_sample_elapsed = 0.0
			station.turn_rotor(0.0, delta)
			hand.trigger_haptic_pulse("haptic", 0.0, .14, .025, 0.0)
