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
# The engraved face (tools/art_inspection_station.py printed_faces: BOARD, FACE_W/H, ROW_TOP/STEP), in metres from its
# top left corner, which is FACE here; its print is 1919 x 927 px of a 2048 x 1024 texture. Each row's airframe is
# engraved left-set at NAME_X in 70 px type (NAME_EM); the longest of the six is 0.35 m.
const Lettering := preload("res://art/signs/RG2014D.ttf")
const FACE := Vector3(-1.67, 2.35, .138)
const FACE_SIZE := Vector2(2.40, 1.16)
const ROW_TOP := .378
const ROW_STEP := .138
const NAME_X := .313
const NAME_EM := .0875
const NAME_COVER := Rect2(.300, -.047, .400, .094)   # over a row's engraved name: from its left, about the row's middle
const ROW_BLANK_X := .800                            # a bare stretch of the same row, as wide, which the cover shows

var _windows := MultiMesh.new()
var _panel_print: Material
var _covers := {}        # row -> the cover over its engraved name (name_row), made when first wanted
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
	var legends := fixtures.get_node_or_null("PanelLegends") as MeshInstance3D
	if legends != null and legends.mesh != null:
		_panel_print = legends.get_active_material(0)
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
	_windows.instance_count = Fleet.GARAGE_BAYS.size() * 2
	_stage_indices.resize(_windows.instance_count)
	var readouts := MultiMeshInstance3D.new()
	readouts.name = "Readouts"
	readouts.multimesh = _windows
	readouts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(readouts)

	for row in Fleet.GARAGE_BAYS.size():
		var bay: Airframe = garage.bay_node(Fleet.GARAGE_BAYS[row])
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


## A row's airframe named in print over its engraving (`words`), or "" for the engraving to stand: the craft the board
## was made for. The board is engraved with the hall's six; the Talon stands in the Phaethon's bay
## (garage_environment.gd _name_bay), and its row then names it.
func name_row(row: int, words: String) -> void:
	var cover: Node3D = _covers.get(row)
	if words.is_empty():
		if cover != null:
			cover.visible = false
		return
	if cover == null:
		cover = _name_cover(row)
		_covers[row] = cover
	cover.visible = true
	(cover.get_node("Name") as Label3D).text = words.to_upper()


## The cover over a row's engraved name: a patch of the row's own bare ground (the panel's print, so it is the panel's
## colour and finish in any light), and on it the name in the engraving's type, size and place.
func _name_cover(row: int) -> Node3D:
	var middle := ROW_TOP + row * ROW_STEP
	var patch := NAME_COVER
	patch.position.y += middle
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for corner: Vector2 in [patch.position, Vector2(patch.end.x, patch.position.y), patch.end, Vector2(patch.position.x, patch.end.y)]:
		points.append(_on_face(corner, .0006))
		uvs.append(_print_uv(corner + Vector2(ROW_BLANK_X - patch.position.x, 0)))
		normals.append(Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _panel_print)
	var cover := MeshInstance3D.new()
	cover.name = "NameCover%02d" % [row + 1]
	cover.mesh = mesh
	cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := Label3D.new()
	label.name = "Name"
	label.font = Lettering
	label.font_size = 140
	label.pixel_size = NAME_EM / 140.0
	label.outline_size = 0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.double_sided = false
	label.modulate = Color("#f4f2e4")
	label.shaded = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label.position = _on_face(Vector2(NAME_X, middle + .001), .0012)
	cover.add_child(label)
	add_child(cover)
	return cover


## A point of the engraved face (metres from its top left corner), `proud` of it, here.
func _on_face(at: Vector2, proud: float) -> Vector3:
	return FACE + Vector3(at.x, -at.y, proud)


## ... and where the panel's print has it.
func _print_uv(at: Vector2) -> Vector2:
	return (Vector2(.5, .5) + at / FACE_SIZE * Vector2(1919, 927)) / Vector2(2048, 1024)


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
