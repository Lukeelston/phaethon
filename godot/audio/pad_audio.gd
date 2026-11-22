## Four mono sources fixed to the apron. The station keys its own short clearance signal
## when the boom reaches its stop. A hot arrival never replays the previous crew's departure.
extends RefCounted

const DIR := "res://audio/pad/"
const BUS := &"StartPad"
const EARSHOT := 95.0
var cart: AudioStreamPlayer3D
var lead: AudioStreamPlayer3D
var gate: AudioStreamPlayer3D
var clearance: AudioStreamPlayer3D
var nearby := false
var was_plugged := false
var was_released := false
var awaiting_gate := false


func setup(pad: Node3D, cart_at: Vector3, plug_at: Vector3, hinge: Node3D, station_sign: Node3D) -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, &"Master")
	cart = _player(pad, cart_at, preload("res://audio/pad/cart.wav"), 6, -16)
	lead = _player(pad, plug_at, preload("res://audio/pad/lead.wav"), 3, -4)
	gate = _player(hinge, Vector3.ZERO, preload("res://audio/pad/gate.wav"), 40, -1)
	clearance = _player(station_sign, Vector3.ZERO, null, 19, -6)


func _player(parent: Node3D, at: Vector3, sound: AudioStream, distance: float, db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.position = at
	p.bus = BUS
	p.stream = sound
	p.unit_size = distance
	p.volume_db = db
	p.max_db = 0
	p.max_distance = EARSHOT
	parent.add_child(p)
	return p


func change_station(id: String) -> void:
	leave()
	# (a station with no recorded call stays silent, without an error in the log)
	var call := DIR + "clear_" + id + ".wav"
	clearance.stream = load(call) if not id.is_empty() and ResourceLoader.exists(call) else null


func leave() -> void:
	cart.stop()
	lead.stop()
	gate.stop()
	clearance.stop()
	awaiting_gate = false
	nearby = false


func sync(in_range: bool, plugged: bool, released: bool, open: float) -> void:
	if not in_range:
		if nearby:
			leave()
		return
	if plugged and not cart.playing:
		cart.play()
	elif not plugged and cart.playing:
		cart.stop()
	if nearby:
		if was_plugged and not plugged:
			lead.play()
		if released and not was_released:
			gate.play()
			awaiting_gate = true
		elif was_released and not released:
			gate.stop()
			clearance.stop()
			awaiting_gate = false
		if awaiting_gate and open >= 1.0:
			if clearance.stream != null:
				clearance.play()
			awaiting_gate = false
	was_plugged = plugged
	was_released = released
	nearby = true
