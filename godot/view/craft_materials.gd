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


## Turned button head with a broached hex socket. Profile normals follow the crown
## around the whole head; each of the six tool flats keeps its own normal.
static func socket_screw(radius: float, finish: Color, compact := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 18 if compact else 24
	# Radius and height in units of the head radius. The socket coordinates use
	# its apothem, so its walls stay flat between the six internal corners.
	var crown := PackedVector2Array([Vector2(.97, -.035), Vector2(1, .02), Vector2(1, .11),
		Vector2(.985, .16), Vector2(.935, .235), Vector2(.84, .305),
		Vector2(.72, .354), Vector2(.61, .37), Vector2(.515, .37)])
	var socket := PackedVector2Array([Vector2(.398, .37), Vector2(.383, .363),
		Vector2(.361, .331), Vector2(.352, .305), Vector2(.352, .04)])
	if compact:
		# At the scale of an MFD screw the missing intermediate bands are under 0.1 mm.
		crown = PackedVector2Array([Vector2(1, -.035), Vector2(1, .12), Vector2(.92, .245),
			Vector2(.74, .345), Vector2(.515, .37)])
		socket = PackedVector2Array([Vector2(.398, .37), Vector2(.36, .325),
			Vector2(.352, .285), Vector2(.352, .04)])
	var circle := PackedVector3Array()
	for i in sides:
		var angle := TAU * i / sides
		circle.append(Vector3(cos(angle), 0, sin(angle)))
	var crown_normals := PackedVector2Array()
	for i in crown.size():
		var tangent := Vector2.ZERO
		if i > 0:
			tangent += crown[i - 1].direction_to(crown[i])
		if i + 1 < crown.size():
			tangent += crown[i].direction_to(crown[i + 1])
		crown_normals.append(Vector2(tangent.y, -tangent.x).normalized())
	crown_normals[-1] = Vector2(0,1)
	st.set_color(finish)
	for j in crown.size() - 1:
		for i in sides:
			for corner: Vector2i in [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0),
					Vector2i(0,1), Vector2i(1,1), Vector2i(1,0)]:
				var row := j + corner.x
				var ray := circle[(i + corner.y) % sides]
				st.set_normal(ray * crown_normals[row].x + Vector3.UP * crown_normals[row].y)
				st.add_vertex((ray * crown[row].x + Vector3.UP * crown[row].y) * radius)
	# Use one quad per tool flat at each depth. A triangular fan joins its two
	# corners to the adjacent sector of the turned crown.
	var arc := sides / 6
	for side in 6:
		var first := side * arc
		var left := circle[first]
		var right := circle[(first + arc) % sides]
		var flat := (left + right).normalized()
		var hex_scale := 1.0 / left.dot(flat)
		var land := PackedVector3Array()
		for k in arc + 1:
			land.append((circle[(first + k) % sides] * crown[-1].x + Vector3.UP * crown[-1].y) * radius)
		for ray: Vector3 in [left, right]:
			land.append((ray * socket[0].x * hex_scale + Vector3.UP * socket[0].y) * radius)
		st.set_color(finish)
		st.set_normal(Vector3.UP)
		var triangles := [0,1,4, 1,5,4, 1,2,5, 2,3,5] if compact else [0,1,5, 1,2,5, 2,6,5, 2,3,6, 3,4,6]
		for k: int in triangles:
			st.add_vertex(land[k])
		for j in socket.size() - 1:
			var tangent := socket[j].direction_to(socket[j + 1])
			var before := Vector2.LEFT if j == 0 else socket[j - 1].direction_to(socket[j])
			var after := tangent if j + 2 == socket.size() else socket[j + 1].direction_to(socket[j + 2])
			var start := (tangent + before).normalized()
			var end := (tangent + after).normalized()
			st.set_color(finish.darkened(.52) if j == socket.size() - 2 else finish)
			for corner: Vector2i in [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0),
					Vector2i(0,1), Vector2i(1,1), Vector2i(1,0)]:
				var p := socket[j + corner.x]
				var n := start if corner.x == 0 else end
				var ray := left if corner.y == 0 else right
				st.set_normal(flat * n.y - Vector3.UP * n.x)
				st.add_vertex((ray * p.x * hex_scale + Vector3.UP * p.y) * radius)
		st.set_color(finish.darkened(.78))
		var bottom := Vector3.UP * radius * socket[-1].y
		_triangle(st, bottom, bottom + left * socket[-1].x * hex_scale * radius,
			bottom + right * socket[-1].x * hex_scale * radius, Vector3.UP)
	st.index()
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
