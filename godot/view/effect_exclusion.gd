## Exterior dust/vapor clearance follows the DRAWN cabin, including the VR head-pivoted rig,
## its shell shudder, road carry and floating origin. Effects call this after the owner's process
## has placed the camera; their earlier sync() runs before VR has moved the current rig.
extends RefCounted


static func apply(view, materials: Array) -> void:
	if view == null or view.craft == null:
		return
	var craft = view.craft
	var frame: Transform3D = craft.pod.global_transform
	if craft.pod_frame:
		var rig: Node3D = craft.pod_frame
		var shell := rig.get_node_or_null("shell") as Node3D
		frame = shell.global_transform if shell else rig.global_transform
		frame *= Transform3D(Basis.IDENTITY, Vector3(0.0, craft.POD_FRAME_UP, 0.0))
	var inverse := frame.affine_inverse()
	for material: ShaderMaterial in materials:
		material.set_shader_parameter("effect_world_to_pod", inverse)
		material.set_shader_parameter("effect_mask_enabled", true)
