## Baked surface dressing shared by the circuits and Eridanus' town stages.
extends RefCounted

const KERB_WIDTH := 3.0
const EDGE_INSET := KERB_WIDTH + 0.35
const EDGE_WHITE := Color(0.87, 0.87, 0.82)


## Store the worn racing line in the road's vertex colours. R minus G decodes to a
## signed offset in 64 m units. The centre stays neutral between consecutive turns.
static func bake_turn(groove: PackedColorArray, widths: PackedFloat64Array, first: int, last: int, turn: float) -> void:
	for i in range(first, last + 1):
		var t := float(i - first) / (last + 1 - first)
		var from_end := minf(t, 1.0 - t)
		var outside := smoothstep(0.0, 0.12, from_end)
		var apex := smoothstep(0.12, 0.5, from_end)
		var shift := turn * minf(widths[i] * 0.5, 100.0) * (0.74 * apex - 0.16 * outside) / 64.0
		groove[i] = Color(maxf(0.0, shift), maxf(0.0, -shift), 0.0)


## A clockwise, upward-facing strip on either bank. Its normals follow the banking.
static func strip(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (d - a).cross(b - a).normalized()
	var top := normal.y > 0.0
	if not top:
		normal = -normal
	for v in ([a, b, c, a, c, d] if top else [a, d, c, a, c, b]):
		st.set_color(color)
		st.set_normal(normal)
		st.add_vertex(v)


## Painted precast block with a chamfer on the track side. Both faces share the
## existing decoration mesh, so a whole corner still draws in one batch.
static func kerb(st: SurfaceTool, inner0: Vector3, outer0: Vector3, inner1: Vector3, outer1: Vector3, i: int) -> void:
	var color := Color(0.70, 0.15, 0.105) if i % 2 == 0 else Color(0.85, 0.84, 0.79)
	var lip := Vector3.UP * 0.05
	var crown := Vector3.UP * 0.20
	var bevel0 := inner0.lerp(outer0, 0.25) + crown
	var bevel1 := inner1.lerp(outer1, 0.25) + crown
	strip(st, inner0 + lip, bevel0, bevel1, inner1 + lip, color.darkened(0.12))
	strip(st, bevel0, outer0 + crown, outer1 + crown, bevel1, color)
