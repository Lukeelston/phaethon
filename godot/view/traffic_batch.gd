## Two persistent instance buffers per type. A vehicle occupies exactly one buffer.
extends MultiMeshInstance3D

const PAINT := preload("res://art/traffic/fleet.tres")
var distant: MultiMesh
var capacity: int
var writer := Writer.new()

## Each model writes its two RenderingServer buffers in a stable vehicle order.
## Publish the final instance counts after every vehicle has chosen its tier.
class Writer:
	var capacity := 0
	var radius_sq := 0.0
	var near_count := 0
	var far_count := 0
	var near_rid: RID
	var far_rid: RID
	var has_colors := false
	var has_boards := false

	func put(pose: Transform3D, eye: Vector3, color: Color, board: float) -> void:
		if near_count + far_count >= capacity:
			return
		var target: RID
		var slot: int
		if pose.origin.distance_squared_to(eye) <= radius_sq:
			target = near_rid
			slot = near_count
			near_count += 1
		else:
			target = far_rid
			slot = far_count
			far_count += 1
		RenderingServer.multimesh_instance_set_transform(target, slot, pose)
		if has_colors:
			RenderingServer.multimesh_instance_set_color(target, slot, color)
		if has_boards:
			RenderingServer.multimesh_instance_set_custom_data(target, slot, Color(board, 0, 0, 1))

func configure(model: PackedScene, slots: int, radius: float, bounds: AABB, colors := true, livery := false) -> void:
	var imported := model.instantiate()
	capacity = slots
	writer.capacity = slots
	writer.radius_sq = radius * radius
	multimesh = _buffer(imported.get_node("Detail").mesh, slots, colors, livery)
	distant = _buffer(imported.get_node("Distance").mesh, slots, colors, livery)
	writer.near_rid = multimesh.get_rid()
	writer.far_rid = distant.get_rid()
	writer.has_colors = colors
	writer.has_boards = livery
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
	writer.put(pose, eye, color, number_board)

func finish_frame(warm := false) -> void:
	if warm and writer.near_count == 0:
		multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, -60, -40)))
		writer.near_count = 1
	multimesh.visible_instance_count = writer.near_count
	distant.visible_instance_count = writer.far_count
	writer.near_count = 0
	writer.far_count = 0
