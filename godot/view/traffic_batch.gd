## Two persistent instance buffers per type. A vehicle occupies exactly one buffer.
extends MultiMeshInstance3D

const PAINT := preload("res://art/traffic/fleet.tres")
var distant: MultiMesh
var capacity: int
var _detail_radius_sq: float
var _near_count := 0
var _far_count := 0

func configure(model: PackedScene, slots: int, radius: float, bounds: AABB, colors := true, livery := false) -> void:
	var imported := model.instantiate()
	capacity = slots
	_detail_radius_sq = radius * radius
	multimesh = _buffer(imported.get_node("Detail").mesh, slots, colors, livery)
	distant = _buffer(imported.get_node("Distance").mesh, slots, colors, livery)
	imported.free()
	material_override = PAINT
	custom_aabb = bounds
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var far_batch := MultiMeshInstance3D.new()
	far_batch.name = "Distance"
	far_batch.multimesh = distant
	far_batch.material_override = PAINT
	far_batch.custom_aabb = bounds
	far_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_batch)

static func _buffer(mesh: Mesh, slots: int, colors: bool, livery: bool) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = colors
	batch.use_custom_data = livery
	batch.mesh = mesh
	batch.instance_count = slots
	batch.visible_instance_count = 0
	return batch

func put(pose: Transform3D, eye: Vector3, color := Color.WHITE, number_board := 0.0) -> void:
	if _near_count + _far_count >= capacity:
		return
	var target: MultiMesh
	var index: int
	if pose.origin.distance_squared_to(eye) <= _detail_radius_sq:
		target = multimesh
		index = _near_count
		_near_count += 1
	else:
		target = distant
		index = _far_count
		_far_count += 1
	target.set_instance_transform(index, pose)
	if target.use_colors:
		target.set_instance_color(index, color)
	if target.use_custom_data:
		target.set_instance_custom_data(index, Color(number_board, 0, 0, 1))

func finish_frame(warm := false) -> void:
	if warm and _near_count == 0:
		multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, -60, -40)))
		_near_count = 1
	multimesh.visible_instance_count = _near_count
	distant.visible_instance_count = _far_count
	_near_count = 0
	_far_count = 0

