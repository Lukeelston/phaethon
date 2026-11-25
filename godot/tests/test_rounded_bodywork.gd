## Manufactured rounded boxes must have clean poles and finite unit normals.
extends SceneTree
const Kit := preload("res://view/mesh_kit.gd")

func _initialize() -> void:
	var bad := 0
	for size: Vector3 in [Vector3(2.5, 1.06, 0.45), Vector3(0.78, 0.022, 1.18)]:
		for exponent: float in [6.0, 8.0]:
			var mesh := Kit.rounded_box(size, exponent, 32)
			var arrays := mesh.surface_get_arrays(0)
			var p: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for normal in n:
				if not normal.is_finite() or absf(normal.length() - 1.0) > 0.0001:
					bad += 1
			var collapsed := 0
			for i in range(0, idx.size(), 3):
				if (p[idx[i+1]] - p[idx[i]]).cross(p[idx[i+2]] - p[idx[i]]).length_squared() < 1e-20:
					collapsed += 1
			bad += collapsed
			var polar := 0
			for v in p:
				if absf(absf(v.y) - size.y * 0.5) < 1e-7 and Vector2(v.x, v.z).length() > 1e-6:
					polar += 1
			bad += polar
			print("ROUNDED BODYWORK ", size, " n=", exponent, " collapsed=", collapsed, " offset poles=", polar)
	print("ROUNDED BODYWORK ", "PASS" if bad == 0 else "FAIL", " (", bad, " defects)")
	quit(0 if bad == 0 else 1)
