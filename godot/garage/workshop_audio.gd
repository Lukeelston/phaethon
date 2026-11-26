## Acoustic sources fixed to the workshop and its door. Leave no emitters in
## the following scene when the pilot goes out to the track.
extends Node3D

signal exterior_screening_changed(amount: float)

const Walker := preload("res://garage/garage_walker.gd")
const Inspection := preload("res://garage/inspection_station.gd")
const Annex := preload("res://garage/workshop_annex.gd")
const RoomAir := preload("res://audio/workshop/hall_air.wav")
const Grille := preload("res://audio/workshop/intake.wav")
const Motor := preload("res://audio/workshop/door_motor.wav")
const Seal := preload("res://audio/workshop/door_seal.wav")
const Bearing := preload("res://audio/workshop/wheel_bearing.wav")
const Soles := [
	preload("res://audio/workshop/sole_1.wav"), preload("res://audio/workshop/sole_2.wav"),
	preload("res://audio/workshop/sole_3.wav"), preload("res://audio/workshop/sole_4.wav"),
	preload("res://audio/workshop/sole_5.wav"), preload("res://audio/workshop/sole_6.wav"),
]

var _boots: Array[AudioStreamPlayer3D] = []
var _supply: AudioStreamPlayer3D
var _exhaust: AudioStreamPlayer3D
var _interior := false
var _portal_open := false
var _screening := 0.0
var _vent_fade: Tween
var _motor: AudioStreamPlayer3D
var _stop: AudioStreamPlayer3D
var _bearing: AudioStreamPlayer3D
var _door_ramp: Tween
var _random := RandomNumberGenerator.new()
var _last_take := -1
var _bay_doors: Node                 # garage/bay_doors.gd: the six roller doors ...
var _bay_door_at: Callable           # ... and where a bay's door hangs (its hood, in the hall's space)
var _rollers := {}                   # bay -> [drive, stop]: each door's own voices, made the first time it runs
var _roller_ramps := {}


func setup(walker: Walker, entry: Annex, station: Inspection, doors: Node = null, door_at := Callable()) -> void:
	var room := AudioStreamPlayer.new()
	room.name = "RoomTone"
	room.stream = RoomAir
	room.volume_db = -68.0
	add_child(room)
	room.play()
	# The broad diffuse air above stays quiet. Each grille has a much shorter
	# reach, with a separate starting phase, like independent fans on one duct.
	_supply = _emitter("HallSupply", Grille, entry.to_global(Vector3(-2.83,1.69,.46)), 3.2, 27.0)
	_supply.volume_db = -68.0
	_supply.play()
	_exhaust = _emitter("AnnexReturn", Grille, entry.to_global(Vector3(-4.79,2.66,-5.50)), 1.75, 9.0)
	_exhaust.pitch_scale = .83
	_exhaust.volume_db = -68.0
	_exhaust.play(2.27)
	create_tween().tween_property(room, "volume_db", -29.0, .38)
	_mix_ventilation(.38)
	# Track which face of the door the listener occupies, including a pilot
	# relocated to the room. One static trigger needs no per-frame raycasts.
	var interior := Area3D.new()
	interior.name = "WorkshopInterior"
	interior.collision_layer = 0
	interior.collision_mask = walker.collision_layer
	interior.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(Annex.HALF_WIDTH * 2.0, Annex.CEILING, Annex.FRONT - Annex.BACK)
	var zone := CollisionShape3D.new()
	zone.shape = shape
	interior.add_child(zone)
	add_child(interior)
	interior.global_transform = entry.global_transform.translated_local(Vector3(0, Annex.CEILING*.5, (Annex.FRONT + Annex.BACK)*.5))
	interior.body_entered.connect(_listener_crossed.bind(true))
	interior.body_exited.connect(_listener_crossed.bind(false))
	_boots.append(_emitter("BootL", null, walker.global_position, 1.65, 10.0))
	_boots.append(_emitter("BootR", null, walker.global_position, 1.65, 10.0))
	walker.boot_planted.connect(_footfall)
	var header := entry.to_global(Vector3(0,2.46,.13))
	_motor = _emitter("DoorDrive", Motor, header, 2.30, 18.0)
	_stop = _emitter("DoorStop", Seal, entry.to_global(Vector3(0,1.15,.14)), 1.70, 14.0)
	entry.motion_started.connect(_door_started)
	entry.motion_finished.connect(_door_finished)
	_bearing = _emitter("SpindleBearing", Bearing, station.rotor_contact_point(), 1.0, 4.5)
	station.rotor_speed_changed.connect(_wheel_speed_changed)
	if doors != null and door_at.is_valid():
		_bay_doors = doors
		_bay_door_at = door_at
		doors.motion_started.connect(_roller_started)
		doors.motion_finished.connect(_roller_finished)


## A bay door's drive, from its hood, and the bottom rail's seal at the sill: the service door's own recordings,
## pitched down for a curtain eleven metres wide and carried across the hall to the seat at the far end of the bay.
func _roller(bay: String) -> Array:
	if not _rollers.has(bay):
		var hood: Transform3D = _bay_door_at.call(bay)
		var drive := _emitter("RollerDrive_" + bay, Motor, hood * Vector3(0, 5.05, .20), 5.0, 48.0)
		var stop := _emitter("RollerStop_" + bay, Seal, hood * Vector3(0, .25, .15), 4.0, 42.0)
		_rollers[bay] = [drive, stop]
	return _rollers[bay]


func _roller_started(bay: String, opening: bool) -> void:
	var drive: AudioStreamPlayer3D = _roller(bay)[0]
	if _roller_ramps.has(bay):
		(_roller_ramps[bay] as Tween).kill()
	if not drive.playing:
		drive.volume_db = -47.0
		drive.pitch_scale = .55
		drive.play()
	var ramp := create_tween().set_parallel(true)
	ramp.tween_property(drive, "pitch_scale", .80 if opening else .72, .35)
	ramp.tween_property(drive, "volume_db", -11.0 if opening else -12.5, .20)
	_roller_ramps[bay] = ramp


func _roller_finished(bay: String, opened: bool) -> void:
	var voices := _roller(bay)
	var drive: AudioStreamPlayer3D = voices[0]
	var stop: AudioStreamPlayer3D = voices[1]
	if _roller_ramps.has(bay):
		(_roller_ramps[bay] as Tween).kill()
	var ramp := create_tween().set_parallel(true)
	ramp.tween_property(drive, "pitch_scale", .52, .16)
	ramp.tween_property(drive, "volume_db", -47.0, .16)
	ramp.chain().tween_callback(drive.stop)
	_roller_ramps[bay] = ramp
	if not opened:      # (the rail landing on the sill; an opened door stops against its hood, the drive's own stop)
		stop.pitch_scale = .74
		stop.volume_db = -9.0
		stop.play()


func _listener_crossed(_body: Node3D, inside: bool) -> void:
	_interior = inside
	_mix_ventilation(.32)


func _mix_ventilation(seconds: float) -> void:
	if _vent_fade:
		_vent_fade.kill()
	_vent_fade = create_tween().set_parallel(true)
	# The louvres are on opposite sides of a laminated window and a pair of
	# sliding leaves. Distant duct noise still leaks through their seals.
	_vent_fade.tween_property(_supply, "volume_db", -22.0 if _interior and not _portal_open else -15.0, seconds)
	_vent_fade.tween_property(_exhaust, "volume_db", -24.0 if not _interior and not _portal_open else -16.0, seconds)
	var screening := 1.0 if _interior and not _portal_open else 0.0
	if not is_equal_approx(_screening, screening):
		_vent_fade.tween_method(_screen_engines, _screening, screening, seconds)


func _screen_engines(amount: float) -> void:
	_screening = amount
	exterior_screening_changed.emit(amount)


func _wheel_speed_changed(radians_per_second: float) -> void:
	var rate := absf(radians_per_second)
	# At the end of the coast the bearing has already faded into the room.
	# Never leave a looping voice on a stationary bench.
	if rate < .08:
		if _bearing.playing:
			_bearing.stop()
		return
	var relative_rate := rate / Inspection.PUSH_SPEED
	_bearing.pitch_scale = .70 + .36 * minf(relative_rate, 2.0)
	_bearing.volume_db = -21.0 + .86 * linear_to_db(minf(relative_rate, 1.7))
	if not _bearing.playing:
		_bearing.play()


func _emitter(label: String, stream: AudioStream, at: Vector3, near: float, reach: float) -> AudioStreamPlayer3D:
	var source := AudioStreamPlayer3D.new()
	source.name = label
	source.stream = stream
	source.unit_size = near
	source.max_distance = reach
	source.max_db = -5.0
	add_child(source)
	source.global_position = at
	return source


func _footfall(side: int, at: Vector3, speed: float) -> void:
	var shoe := _boots[side]
	# Keep adjacent strikes distinct across both feet. Use a local RNG so
	# walking around the shop never changes the next race's random sequence.
	var choices := Soles.size() if _last_take < 0 else Soles.size() - 1
	var take := _random.randi_range(0, choices - 1)
	if take >= _last_take and _last_take >= 0:
		take += 1
	_last_take = take
	shoe.global_position = at + Vector3.UP * .025
	shoe.stream = Soles[take]
	shoe.pitch_scale = _random.randf_range(.965, 1.045)
	shoe.volume_db = lerpf(-17.0, -9.0, clampf(speed / Walker.WALK_SPEED, 0.0, 1.0))
	shoe.play()


func _door_started(opening: bool) -> void:
	_portal_open = opening
	_mix_ventilation(Annex.OPEN_TIME if opening else Annex.CLOSE_TIME)
	if _door_ramp:
		_door_ramp.kill()
	if not _motor.playing:
		_motor.volume_db = -47.0
		_motor.pitch_scale = .71
		_motor.play()
	_door_ramp = create_tween().set_parallel(true)
	_door_ramp.tween_property(_motor, "pitch_scale", 1.02 if opening else .88, .19)
	_door_ramp.tween_property(_motor, "volume_db", -13.5 if opening else -15.0, .09)


func _door_finished(opened: bool) -> void:
	if _door_ramp:
		_door_ramp.kill()
	_door_ramp = create_tween().set_parallel(true)
	_door_ramp.tween_property(_motor, "pitch_scale", .72, .085)
	_door_ramp.tween_property(_motor, "volume_db", -47.0, .085)
	_door_ramp.chain().tween_callback(_motor.stop)
	_stop.pitch_scale = 1.13 if opened else .92
	_stop.volume_db = -19.0 if opened else -12.0
	_stop.play()
