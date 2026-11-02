## Compound meshes from primitives: one ArrayMesh per model (one draw call, or one MultiMesh
## of them), each part carrying its own vertex colour. Use with vertex_colors() as the material.
##   MeshKit.compound([[Mesh, Transform3D, Color], ...]) -> ArrayMesh
##   MeshKit.compound(parts, into)                        appends as a new surface of `into`
## Parts may be primitives (BoxMesh, CylinderMesh, ...) or ArrayMeshes (rounded_box()).
## Godot fronts are CLOCKWISE: for a front face, (p1 - p0).cross(p2 - p0) points INTO the surface.
extends RefCounted


static func compound(parts: Array, into: ArrayMesh = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var mesh: Mesh = p[0]
		var xf: Transform3D = p[1]
		var col: Color = p[2]
		var arr: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx = arr[Mesh.ARRAY_INDEX]
		var order: Array = range(verts.size()) if idx == null or (idx as PackedInt32Array).is_empty() else Array(idx)
		var nb := xf.basis.inverse().transposed()
		for i in order:
			st.set_color(col)
			st.set_normal((nb * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	return st.commit(into)


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl(r_top: float, r_bot: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func ball(r: float, segs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


static func _sp(t: float, e: float) -> float:
	return signf(t) * pow(absf(t), e)


## A box with rounded edges and corners: a superellipsoid. n ~ 4 is a soft pebble, ~ 10 a box
## with small radii (the radius scales with each side, so thin slabs stay crisp on their faces).
static func rounded_box(size: Vector3, n := 8.0, seg := 18) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var e := 2.0 / n
	var en := 2.0 - e
	var cols := seg * 2
	for i in seg + 1:
		var u := -PI / 2.0 + PI * i / seg
		for j in cols + 1:
			var v := -PI + TAU * j / cols
			var p := Vector3(h.x * _sp(cos(u), e) * _sp(cos(v), e), h.y * _sp(sin(u), e), h.z * _sp(cos(u), e) * _sp(sin(v), e))
			var nrm := Vector3(_sp(cos(u), en) * _sp(cos(v), en) / h.x, _sp(sin(u), en) / h.y, _sp(cos(u), en) * _sp(sin(v), en) / h.z)
			st.set_normal(nrm.normalized() if nrm.length() > 1e-9 else Vector3(0, signf(u), 0))
			st.set_uv(Vector2(float(j) / cols, float(i) / seg))
			st.add_vertex(p)
	# winding: test one equator quad against its outward direction, then use that order throughout
	var probe_i := seg / 2
	var flip := false
	var pa := _rb_point(h, e, probe_i, 0, seg, cols)
	var pb := _rb_point(h, e, probe_i, 1, seg, cols)
	var pc := _rb_point(h, e, probe_i + 1, 0, seg, cols)
	flip = (pb - pa).cross(pc - pa).dot(pa) > 0.0
	for i in seg:
		for j in cols:
			var a := i * (cols + 1) + j
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			for tri in [[a, b, c], [b, d, c]]:
				st.add_index(tri[0])
				st.add_index(tri[2] if flip else tri[1])
				st.add_index(tri[1] if flip else tri[2])
	return st.commit()


static func _rb_point(h: Vector3, e: float, i: int, j: int, seg: int, cols: int) -> Vector3:
	var u := -PI / 2.0 + PI * i / seg
	var v := -PI + TAU * j / cols
	return Vector3(h.x * _sp(cos(u), e) * _sp(cos(v), e), h.y * _sp(sin(u), e), h.z * _sp(cos(u), e) * _sp(sin(v), e))


## Wrap a mesh round a vertical arc of radius r centred at (0, y, r) (in front of +z: the
## viewer's side). x becomes arc length, +z moves toward the centre; normals turn with the arc.
## `offset` is added to every vertex first (so a part keeps its place on the arc). The source
## needs enough vertices along x to curve (BoxMesh.subdivide_width, rounded_box seg).
static func bend(mesh: Mesh, offset: Vector3, r: float) -> ArrayMesh:
	var arr: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	out_v.resize(verts.size())
	out_n.resize(verts.size())
	for i in verts.size():
		var v := verts[i] + offset
		var phi := v.x / r
		out_v[i] = Vector3(0.0, v.y, r) + (r - v.z) * Vector3(sin(phi), 0.0, -cos(phi))
		out_n[i] = Basis(Vector3.UP, -phi) * norms[i]
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	res[Mesh.ARRAY_VERTEX] = out_v
	res[Mesh.ARRAY_NORMAL] = out_n
	res[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res)
	return m


## Where a point (x along the arc, y, d toward the viewer) lands on bend()'s arc, and the
## Y rotation that turns a +z-facing node to face the centre.
static func on_arc(x: float, y: float, d: float, r: float) -> Transform3D:
	var phi := x / r
	return Transform3D(Basis(Vector3.UP, -phi), Vector3(0.0, y, r) + (r - d) * Vector3(sin(phi), 0.0, -cos(phi)))


## Transform helper: translate, then optional rotation (Euler, radians), then scale.
static func at(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos)


static func vertex_colors(unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true   # colours are authored like albedo_color, not linear
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Polished metal (or glossy paint with metallic < 1): mirrors the sky. Vertex colours tint it.
static func polished(metallic := 1.0, roughness := 0.16, vertex_tint := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = metallic
	m.roughness = roughness
	m.metallic_specular = 0.7
	if vertex_tint:
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
	return m
