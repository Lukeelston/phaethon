## Shared cockpit finishes and small manufactured parts. Static parts are baked into their
## owner's compound mesh; none of these helpers creates nodes or per-frame work.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
static var _finishes: Dictionary = {}
static var hd := true   # false before the first finish is made: v0.3.2's procedural grain


static func powder_coat() -> StandardMaterial3D:
	return _finish("powder", 0.12, 0.78, 0.20)


static func machined() -> StandardMaterial3D:
	return _finish("machined", 0.94, 0.30, 0.08)


## Realism spike: brushed stainless for the nose cage. Mirror chrome turned the tubes into
## flat strips of sky; a satin tube blurs the sky and ground into a believable round.
static func satin() -> StandardMaterial3D:
	return _finish("satin", 1.0, 0.45, 0.10)


static func leather() -> StandardMaterial3D:
	return _finish("leather", 0.0, 0.62, 0.12)


static func webbing() -> StandardMaterial3D:
	return _finish("webbing", 0.0, 0.85, 0.12)


## The longitudinal walnut cut repeats along the boards. The finer finishes use a
## square tile so the weave and casting marks retain their scale around corners.
static func deck_finish(key: String) -> StandardMaterial3D:
	match key:
		"carbon": return _finish(key, 0.15, 0.40, 0.10)
		"walnut": return _finish(key, 0.0, 0.42, 0.12)
		"casting": return _finish(key, 0.08, 0.56, 0.14)
		"porcelain": return _finish(key, 0.0, 0.25, 0.02)
	return painted_metal()


## A finish in one flat colour, for parts that carry no vertex colours of their own.
static func tinted(key: String, colour: Color) -> StandardMaterial3D:
	var id := "%s:%s" % [key, colour.to_html()]
	if not _finishes.has(id):
		var base: StandardMaterial3D
		match key:
			"powder": base = powder_coat()
			"leather": base = leather()
			"carbon", "walnut", "casting", "porcelain": base = deck_finish(key)
			"webbing": base = webbing()
			"satin": base = satin()
			"machined": base = machined()
			_: base = rubber()
		var mat := base.duplicate() as StandardMaterial3D
		mat.vertex_color_use_as_albedo = false
		mat.albedo_color = colour
		_finishes[id] = mat
	return _finishes[id]


static func rubber() -> StandardMaterial3D:
	return _finish("rubber", 0.0, 0.94, 0.15)


static func painted_metal() -> StandardMaterial3D:
	return _finish("paint", 0.34, 0.43, 0.07)


static func indicator() -> StandardMaterial3D:
	if not _finishes.has("indicator"):
		var mat := Kit.vertex_colors()
		mat.roughness = 0.23
		mat.emission_enabled = true
		mat.emission = Color(0.32, 0.32, 0.32)
		mat.emission_energy_multiplier = 0.35
		_finishes.indicator = mat
	return _finishes.indicator


static func _finish(key: String, metal: float, rough: float, contrast: float) -> StandardMaterial3D:
	if _finishes.has(key):
		return _finishes[key]
	var mat := Kit.polished(metal, rough)
	mat.metallic_specular = 0.55 if key == "machined" else 0.35
	var maps := "res://art/finish/%s" % key
	if hd and ResourceLoader.exists(maps + "_normal.png"):
		# Realism spike (tools/art_finishes_hd.py): a 128 mm seamless tile per finish, with
		# real relief and roughness instead of a shaded 64-pixel grain.
		mat.albedo_texture = load(maps + "_shade.png")
		mat.normal_enabled = true
		mat.normal_texture = load(maps + "_normal.png")
		mat.roughness = 1.0
		mat.roughness_texture = load(maps + "_data.png")
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.uv1_triplanar = true
		mat.uv1_triplanar_sharpness = 4.0
		mat.uv1_scale = Vector3.ONE / 0.128
		match key:
			"walnut":
				mat.uv1_scale = Vector3(4, 3, 1.3)
				mat.normal_scale = .25
			"carbon": mat.uv1_scale = Vector3.ONE * 11.0
			"casting":
				mat.uv1_scale = Vector3.ONE * 6.0
				mat.normal_scale = .45
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_finishes[key] = mat
		return mat
	# Triplanar local coordinates survive MeshKit's compound batching (which has no UVs).
	# A repeating 32 mm tile makes the grain sub-millimetre. Mipmaps prevent headset shimmer.
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var hash_value: int = (x * 1973) ^ (y * 9277) ^ 89173
			hash_value = (hash_value ^ (hash_value >> 13)) * 15731
			hash_value = (hash_value ^ (hash_value >> 7)) & 65535
			var grain := float(hash_value) / 65535.0
			if key == "machined":
				grain = 0.75 * (0.5 + 0.5 * sin(float(y) * 2.41)) + 0.25 * grain
			var shade := 1.0 - contrast * grain
			img.set_pixel(x, y, Color(shade, shade, shade))
	img.generate_mipmaps()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3.ONE * 31.25
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_finishes[key] = mat
	return mat


## A shallow plate with chamfered corners and an actual bevel along its top and bottom edge.
## Far fewer triangles than using a superellipsoid for every panel.
static func beveled_plate(size: Vector3, bevel := 0.002) -> ArrayMesh:
	var b := minf(bevel, size.y * 0.45)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [
		_plate_ring(size.x * 0.5 - b, size.z * 0.5 - b, -size.y * 0.5, b),
		_plate_ring(size.x * 0.5, size.z * 0.5, -size.y * 0.5 + b, b * 2.0),
		_plate_ring(size.x * 0.5, size.z * 0.5, size.y * 0.5 - b, b * 2.0),
		_plate_ring(size.x * 0.5 - b, size.z * 0.5 - b, size.y * 0.5, b)]
	for r in 3:
		for i in 8:
			var j := (i + 1) % 8
			var mid: Vector3 = (rings[r][i] + rings[r][j]) * 0.5
			var out := Vector3(mid.x, -b if r == 0 else b if r == 2 else 0.0, mid.z).normalized()
			_quad(st, rings[r][i], rings[r][j], rings[r + 1][j], rings[r + 1][i], out)
	for i in 8:
		_triangle(st, Vector3(0, -size.y * 0.5, 0), rings[0][i], rings[0][(i + 1) % 8], Vector3.DOWN)
		_triangle(st, Vector3(0, size.y * 0.5, 0), rings[3][i], rings[3][(i + 1) % 8], Vector3.UP)
	return st.commit()


static func _plate_ring(hx: float, hz: float, y: float, cut: float) -> Array[Vector3]:
	return [Vector3(-hx + cut, y, -hz), Vector3(hx - cut, y, -hz),
		Vector3(hx, y, -hz + cut), Vector3(hx, y, hz - cut),
		Vector3(hx - cut, y, hz), Vector3(-hx + cut, y, hz),
		Vector3(-hx, y, hz - cut), Vector3(-hx, y, -hz + cut)]


## An open annulus: the toggle shaft occupies its hole, rather than a disc pretending to be a washer.
static func washer(inner: float, outer: float, height: float, segments := 16) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		var ra := Vector3(cos(a), 0, sin(a))
		var rb := Vector3(cos(b), 0, sin(b))
		var up := Vector3.UP * height * 0.5
		_quad(st, ra * inner + up, rb * inner + up, rb * outer + up, ra * outer + up, Vector3.UP)
		_quad(st, ra * inner - up, rb * inner - up, rb * outer - up, ra * outer - up, Vector3.DOWN)
		_quad(st, ra * outer - up, rb * outer - up, rb * outer + up, ra * outer + up, (ra + rb).normalized())
		_quad(st, ra * inner - up, rb * inner - up, rb * inner + up, ra * inner + up, -(ra + rb).normalized())
	return st.commit()


## Staggered raised teeth give the grip a real diamond knurl, with flat machined end caps.
static func knurled_knob(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 32
	const ROWS := 4
	for row in ROWS:
		for i in SEGMENTS:
			var a := _knurl_point(i, row, radius, height)
			var b := _knurl_point((i + 1) % SEGMENTS, row, radius, height)
			var c := _knurl_point((i + 1) % SEGMENTS, row + 1, radius, height)
			var d := _knurl_point(i, row + 1, radius, height)
			var out := Vector3(a.x + b.x, 0, a.z + b.z).normalized()
			_quad(st, a, b, c, d, out)
	for i in SEGMENTS:
		_triangle(st, Vector3(0, -height * 0.5, 0), _knurl_point(i, 0, radius, height), _knurl_point((i + 1) % SEGMENTS, 0, radius, height), Vector3.DOWN)
		_triangle(st, Vector3(0, height * 0.5, 0), _knurl_point(i, ROWS, radius, height), _knurl_point((i + 1) % SEGMENTS, ROWS, radius, height), Vector3.UP)
	return st.commit()


static func _knurl_point(i: int, row: int, radius: float, height: float) -> Vector3:
	var angle := TAU * i / 32.0
	var r := radius - (0.0012 if (i + row) % 2 == 0 or row == 0 or row == 4 else 0.0)
	return Vector3(cos(angle) * r, -height * 0.5 + height * row / 4.0, sin(angle) * r)


## Button-head fastener. The six flat socket walls end above the mounting face,
## so the surrounding panel cannot fill the recess. Vertex colour shades its bore.
static func socket_screw(radius: float, finish: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 24:
		var rings := []
		for j: int in [segment, segment + 1]:
			var angle := TAU * j / 24.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			var flat := .36 / cos(fposmod(angle, PI / 3) - PI / 6)
			var points := []
			for section: Vector2 in [Vector2(1, -.04), Vector2(1, .14), Vector2(.88, .30),
					Vector2(.65, .37), Vector2(flat + .065, .37), Vector2(flat, .29), Vector2(flat, .035)]:
				points.append((radial * section.x + Vector3.UP * section.y) * radius)
			rings.append(points)
		for i in 6:
			st.set_color(finish.darkened(.52) if i == 5 else finish)
			var direction := (rings[0][i] as Vector3).slide(Vector3.UP).normalized()
			if i >= 4:
				direction = -direction
			_quad(st, rings[0][i], rings[1][i], rings[1][i+1], rings[0][i+1],
				Vector3.UP + direction if i != 5 else direction)
		st.set_color(finish.darkened(.78))
		_triangle(st, Vector3.UP * radius * .035, rings[0][6], rings[1][6], Vector3.UP)
	return st.commit()


## Two head halves leave an actual recessed screwdriver slot. The tapered outer edge seats
## into a countersink; use a dark backing washer beneath it to reveal the recess.
static func slotted_screw(radius := 0.004) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_slot := radius * 0.16
	var start := asin(half_slot / radius)
	for side in [-1.0, 1.0]:
		var top: Array[Vector3] = []
		var lower: Array[Vector3] = []
		for i in 9:
			var a := lerpf(start, PI - start, i / 8.0)
			top.append(Vector3(cos(a) * radius, 0.0007, sin(a) * radius * side))
			lower.append(Vector3(cos(a) * radius * 0.78, -0.001, sin(a) * radius * 0.78 * side))
		for i in 7:
			_triangle(st, top[0], top[i + 1], top[i + 2], Vector3.UP)
		for i in 9:
			var j := (i + 1) % 9
			var mid := (top[i] + top[j]) * 0.5
			var out := Vector3(0, 0, -side) if i == 8 else Vector3(mid.x, 0, mid.z).normalized()
			_quad(st, top[i], top[j], lower[j], lower[i], out)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_triangle(st, a, b, c, outward)
	_triangle(st, a, c, d, outward)


static func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(c if (b - a).cross(c - a).dot(outward) > 0.0 else b)
	st.add_vertex(b if (b - a).cross(c - a).dot(outward) > 0.0 else c)
