## A wall-mounted repeater for all twelve engines and the rotor inspection bench.
## Installed during environment construction, before returned run-ups are restored.
extends Node3D

signal rotor_speed_changed(radians_per_second: float)

const Fleet := preload("res://sim/pilot_craft.gd")
const Airframe := preload("res://garage/parked_airframe.gd")
const Runup := preload("res://garage/garage_runup.gd")
const Fixtures := preload("res://garage/inspection_station.glb")
const Glass := preload("res://garage/inspection_annunciator.gdshader")
const Legends := preload("res://garage/inspection_readouts.png")
const STAGES := ["off", "wait", "crank", "catch", "run"]
const HANDWHEEL := Vector3(.996, 1.338, .826)
const MAX_SPEED := 6.5  # rad/s
const PUSH_SPEED := 2.8
const BEARING_DRAG := 1.65  # rad/s²
const RUNOUT_MM := .080  # Authored eccentricity of the measured cylindrical land.
const DIAL_MM_PER_REV := .50  # 50 divisions, 0.01 mm per graduation.

var _windows := MultiMesh.new()
var _stage_indices := PackedByteArray()
var _rotor: Node3D
var _needle: Node3D
var _held := false
var rotor_angle := 0.0
var rotor_speed := 0.0


func install(garage: Node3D, wall: Transform3D) -> void:
	name = "FleetInspection"
	transform = wall
	garage.add_child(self)
	var fixtures := Fixtures.instantiate()
	add_child(fixtures)
	_rotor = fixtures.get_node("RotatingAssembly")
	_needle = fixtures.get_node("IndicatorNeedle")
	set_process(false)
	var body := StaticBody3D.new()
	body.name = "CounterCollision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.60, .965, .86)
	shape.shape = box
	shape.position = Vector3(0, .4825, .48)
	body.add_child(shape)
	add_child(body)

	var glass := ShaderMaterial.new()
	glass.shader = Glass
	glass.set_shader_parameter("legends", Legends)
	var window := QuadMesh.new()
	window.size = Vector2(.366, .082)
	window.material = glass
	_windows.transform_format = MultiMesh.TRANSFORM_3D
	_windows.use_custom_data = true
	_windows.mesh = window
	_windows.instance_count = Fleet.ORDER.size() * 2
	_stage_indices.resize(_windows.instance_count)
	var readouts := MultiMeshInstance3D.new()
	readouts.name = "Readouts"
	readouts.multimesh = _windows
	readouts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(readouts)

	for row in Fleet.ORDER.size():
		var bay: Airframe = garage.bay_node(Fleet.ORDER[row])
		bay.engine_stage_changed.connect(_set_engine_stage.bind(row))
		var runup := bay.get_node_or_null("Runup") as Runup
		for engine in 2:
			# Physical windows line up with the machined recesses in the authored panel.
			var at := Vector3([-.055, .425][engine], 1.972 - row * .138, .154)
			var index := row * 2 + engine
			_windows.set_instance_transform(index, Transform3D(Basis.IDENTITY, at))
			_windows.set_instance_custom_data(index, Color(0, 0, 0, 1))
			if runup and runup.startup:
				_set_engine_stage(engine, runup.startup.stage[engine], row)


func engine_stage(row: int, engine: int) -> String:
	return STAGES[_stage_indices[row * 2 + engine]]


func _set_engine_stage(engine: int, stage: String, row: int) -> void:
	var index := row * 2 + engine
	var value := STAGES.find(stage)
	if value >= 0 and _stage_indices[index] != value:
		_stage_indices[index] = value
		_windows.set_instance_custom_data(index, Color(float(value) / 4.0, 0, 0, 1))


func rotor_contact_point() -> Vector3:
	return to_global(HANDWHEEL)


func rotor_contact_distance(world_point: Vector3) -> float:
	var point := to_local(world_point) - HANDWHEEL
	# Accept the open spaces between spokes. A tracked hand has appreciable
	# width and can grab the travelling handle in front of the wheel as well.
	var edge := maxf(0, Vector2(point.x, point.y).length() - .109)
	var depth := maxf(0, absf(point.z) - .016)
	var on_wheel := Vector2(edge, depth).length()
	var grip := Vector2(-.050, .086).rotated(rotor_angle)
	var from_grip := Vector3(point.x-grip.x, point.y-grip.y, point.z-clampf(point.z, .020, .049))
	return minf(on_wheel, maxf(0, from_grip.length() - .016))


func spin_rotor(direction: float = 1.0) -> void:
	if _held or not is_finite(direction) or is_zero_approx(direction):
		return
	_set_rotor_speed(clampf(rotor_speed + signf(direction) * PUSH_SPEED, -MAX_SPEED, MAX_SPEED))
	set_process(not is_zero_approx(rotor_speed))


func turn_rotor(delta_angle: float, delta: float) -> void:
	_held = true
	set_process(false)
	if not is_finite(delta_angle) or not is_finite(delta) or delta <= 0.0 or absf(delta_angle) < .0001:
		_set_rotor_speed(0.0)
		return
	# A lost tracking frame or an angle crossing ±π cannot launch the fixture.
	var sample_time := minf(delta, .12)
	var step := clampf(wrapf(delta_angle, -PI, PI), -MAX_SPEED * sample_time, MAX_SPEED * sample_time)
	_rotate_by(step)
	_set_rotor_speed(step / delta)


func release_rotor() -> void:
	if _held:
		_held = false
		set_process(not is_zero_approx(rotor_speed))


func _process(delta: float) -> void:
	var moving_time := minf(delta, absf(rotor_speed) / BEARING_DRAG)
	var next_speed := move_toward(rotor_speed, 0.0, BEARING_DRAG * delta)
	_rotate_by((rotor_speed + next_speed) * .5 * moving_time)
	_set_rotor_speed(next_speed)
	if is_zero_approx(next_speed):
		set_process(false)


func _rotate_by(step: float) -> void:
	rotor_angle = wrapf(rotor_angle + step, -PI, PI)
	_rotor.rotation.z = rotor_angle
	# At zero the land's offset is tangent to the probe. A quarter turn later
	# it has lifted the stylus by 0.08 mm. The dial's positive scale is clockwise.
	_needle.rotation.z = -TAU * RUNOUT_MM * sin(rotor_angle) / DIAL_MM_PER_REV


func _set_rotor_speed(speed: float) -> void:
	if rotor_speed != speed:
		rotor_speed = speed
		rotor_speed_changed.emit(speed)
