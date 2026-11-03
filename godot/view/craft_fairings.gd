## Swept, low-profile fairings. Coordinates stay inside the original hardpoint
## layout; these change appearance only, never collision or handling dimensions.
extends RefCounted
const Kit := preload("res://view/mesh_kit.gd")

static func nacelle() -> ArrayMesh:
	var sections := [[-3.68, 1.14, 0.43], [-3.3, 1.20, 0.48], [-2.0, 1.20, 0.48],
		[-1.7, 1.20, 0.48], [0.6, 1.16, 0.46], [1.6, 1.10, 0.41], [2.45, 1.08, 0.39]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in sections.size() - 1:
		for j in 48:
			var points := []
			for c in [[s,j], [s+1,j], [s+1,j+1], [s,j+1]]:
				var sec: Array = sections[c[0]]
				var angle := TAU * float(c[1]) / 48.0
				points.append(Vector3(sec[1] * Kit._sp(cos(angle), 0.4), sec[2] * Kit._sp(sin(angle), 0.4), sec[0]))
			for i in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(points[i])
	st.generate_normals()
	return st.commit()

## A swept polygon extruded across its local X, capped on both faces.
static func fin(profile: PackedVector2Array, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for k in range(1, profile.size() - 1):
			for idx in ([0, k, k + 1] if side < 0.0 else [0, k + 1, k]):
				var p := profile[idx]
				st.add_vertex(Vector3(side * thickness / 2.0, p.x, p.y))
	for k in profile.size():
		var a := profile[k]
		var b := profile[(k + 1) % profile.size()]
		var corners := [Vector3(-thickness/2, a.x, a.y), Vector3(thickness/2, a.x, a.y), Vector3(thickness/2, b.x, b.y), Vector3(-thickness/2, b.x, b.y)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(corners[i])
	st.generate_normals()
	return st.commit()

static func fan_blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in 5:
		var corners := []
		for c in [[r,0], [r+1,0], [r+1,1], [r,1]]:
			var t := float(c[0]) / 5.0
			var radius := lerpf(0.09, 0.35, t)
			var a: float = t * 0.42 + c[1] * lerpf(0.30, 0.18, t)
			corners.append(Vector3(radius*sin(a), radius*cos(a), (c[1] - 0.5)*0.055))
		for i in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(corners[i])
	st.generate_normals()
	return st.commit()
