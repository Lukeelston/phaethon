## Realism spike: formed bodies for the Network's traffic. network_traffic.gd still lays out
## each kind as a list of parts baked once into one batched mesh (one draw per kind, as before);
## this swaps the rounded boxes that stood for hulls, canopies and engine pods for lofted
## shapes with a nose, a shoulder line and a tail, and tags every part with its material so
## traffic_body.gdshader can give paint a clear coat, glazing a mirror and metal a real sheen.
##   TrafficModels.upgrade(kind, parts, dark, glass, metal)   # once per kind, before compound()
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
enum { CAR, SLOW, DEMON, TRANSPORT, RACER }   # network_traffic.gd's order
static var hd := true
# Material class, carried in vertex alpha (instances are opaque, so alpha survives the tint).
const PAINT := 1.0
const TRIM := 0.8
const METAL := 0.6
const GLASS := 0.4

# Stations along the body, nose (-z) to tail: [z, half width, bottom, top, squareness].
const HULL := {
	CAR: [[-5.9, 0.35, 0.80, 1.02, 2.4], [-5.3, 1.15, 0.50, 1.22, 3.0], [-3.6, 1.80, 0.32, 1.50, 3.6],
		[-1.0, 2.0, 0.25, 1.70, 4.2], [2.6, 2.0, 0.25, 1.75, 4.2], [4.9, 1.85, 0.35, 1.62, 3.6], [5.9, 1.5, 0.6, 1.35, 3.0]],
	SLOW: [[-6.9, 1.6, 0.9, 2.3, 3.5], [-6.3, 2.3, 0.45, 3.0, 4.5], [-4.5, 2.5, 0.3, 3.22, 5.5],
		[5.0, 2.5, 0.3, 3.25, 5.5], [6.5, 2.35, 0.4, 3.1, 4.5], [6.9, 2.1, 0.7, 2.8, 3.5]],
	DEMON: [[-6.5, 0.2, 0.7, 0.9, 2.2], [-5.4, 0.62, 0.5, 1.05, 2.6], [-3.0, 0.95, 0.36, 1.22, 3.0],
		[0.5, 1.0, 0.33, 1.28, 3.2], [4.5, 0.95, 0.36, 1.25, 3.0], [6.3, 0.7, 0.5, 1.1, 2.6]],
	TRANSPORT: [[-8.25, 2.52, 0.93, 4.37, 16.0], [-8.17, 2.575, 0.88, 4.42, 16.0], [8.17, 2.575, 0.88, 4.42, 16.0], [8.25, 2.52, 0.93, 4.37, 16.0]],
	RACER: [[-7.0, 0.15, 0.72, 0.86, 2.2], [-5.8, 0.55, 0.52, 1.0, 2.6], [-3.0, 0.92, 0.38, 1.2, 3.0],
		[1.0, 1.0, 0.35, 1.25, 3.2], [5.0, 0.9, 0.4, 1.2, 3.0], [7.0, 0.55, 0.55, 1.05, 2.6]],
}
const CANOPY := {
	CAR: [[-3.1, 0.55, 1.42, 1.52, 2.4], [-2.2, 1.12, 1.48, 2.2, 2.6], [-0.4, 1.34, 1.55, 2.6, 2.8], [1.4, 1.22, 1.6, 2.48, 2.8], [2.5, 0.75, 1.62, 1.95, 2.4]],
	DEMON: [[-2.9, 0.45, 1.15, 1.25, 2.3], [-1.8, 0.8, 1.2, 1.62, 2.5], [-0.6, 0.85, 1.22, 1.68, 2.6], [0.9, 0.6, 1.22, 1.45, 2.4]],
	RACER: [[-3.2, 0.4, 1.12, 1.2, 2.3], [-2.0, 0.72, 1.16, 1.56, 2.5], [-0.5, 0.75, 1.18, 1.6, 2.6], [1.4, 0.5, 1.18, 1.36, 2.4]],
}
const NACELLE := [[-2.7, 0.2, 0.55, 0.9, 2.2], [-1.8, 0.5, 0.3, 1.15, 2.4], [1.5, 0.54, 0.22, 1.22, 2.6], [5.0, 0.5, 0.26, 1.18, 2.4], [6.1, 0.42, 0.34, 1.1, 2.2]]
# Which of each kind's first parts are the hull and the canopy it replaces (-1: keeps its own glazing).
const SWAP := {CAR: [0, 1], SLOW: [0, -1], DEMON: [0, 1], TRANSPORT: [1, -1], RACER: [0, 1]}


static func upgrade(kind: int, parts: Array, dark: Color, glass: Color, metal: Color) -> void:
	for i in parts.size():
		var c: Color = parts[i][2]
		var material := TRIM if c.is_equal_approx(dark) else (METAL if c.is_equal_approx(metal) else (GLASS if c.is_equal_approx(glass) else PAINT))
		parts[i][2] = Color(c.r, c.g, c.b, material)
		# The engine pods the side loop adds to the two racers: painted rounded boxes, 8.8 m long.
		if i >= 4 and material == PAINT and parts[i][0] is ArrayMesh and kind in [DEMON, RACER]:
			var x: float = (parts[i][1] as Transform3D).origin.x
			parts[i][0] = loft(NACELLE, 14)
			parts[i][1] = Kit.at(Vector3(x, 0.0, 0.0))
	parts[SWAP[kind][0]][0] = loft(HULL[kind], 24)
	parts[SWAP[kind][0]][1] = Transform3D.IDENTITY
	if SWAP[kind][1] >= 0:
		parts[SWAP[kind][1]][0] = loft(CANOPY[kind], 18)
		parts[SWAP[kind][1]][1] = Transform3D.IDENTITY
	_extras(kind, parts)


# Shut lines along each body (m from its middle, nose negative), its shoulder crease and rib pitch.
const LINES := {
	CAR: [Vector4(-2.9, -0.9, 1.1, 3.4), 1.25, 0.0],
	SLOW: [Vector4(-4.9, -1.6, 1.6, 4.9), 1.55, 0.0],
	DEMON: [Vector4(-3.4, 2.4, 1000.0, 1000.0), 1000.0, 0.0],
	TRANSPORT: [Vector4(-4.1, 0.0, 4.1, 1000.0), 1000.0, 0.55],
	RACER: [Vector4(-3.6, 2.8, 1000.0, 1000.0), 1000.0, 0.0],
}


static func material(kind: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/traffic_body.gdshader")
	m.set_shader_parameter("cuts", LINES[kind][0])
	m.set_shader_parameter("belt", LINES[kind][1])
	m.set_shader_parameter("ribs", LINES[kind][2])
	return m


## The fittings a real vehicle carries: intakes, skids, bumpers, fins, door gear.
static func _fit(parts: Array, mesh: Mesh, at: Vector3, material: float, rot := Vector3.ZERO) -> void:
	parts.append([mesh, Kit.at(at, rot), Color(1.0, 1.0, 1.0, material)])


static func _extras(kind: int, parts: Array) -> void:
	match kind:
		CAR:
			_fit(parts, Kit.box(Vector3(2.4, 0.22, 0.5)), Vector3(0, 0.62, -5.5), TRIM)             # intake
			_fit(parts, Kit.cyl(0.02, 0.02, 0.6, 6), Vector3(0.5, 2.8, 1.0), METAL)                   # aerial
			for side in [-1.0, 1.0]:
				_fit(parts, Kit.box(Vector3(0.22, 0.14, 8.5)), Vector3(side * 1.35, 0.2, 0.2), METAL)    # skids
				_fit(parts, Kit.rounded_box(Vector3(0.9, 0.3, 0.5), 4.0, 6), Vector3(side * 1.45, 1.1, -5.35), GLASS)   # lamp fairings
				for x in [0.45, 1.2]:
					_fit(parts, Kit.box(Vector3(0.06, 0.3, 0.9)), Vector3(side * x, 0.42, 5.5), TRIM)        # diffuser
		SLOW:
			_fit(parts, Kit.box(Vector3(3.0, 0.35, 0.12)), Vector3(0, 3.0, -6.6), GLASS)            # destination board
			for end in [-1.0, 1.0]:
				_fit(parts, Kit.rounded_box(Vector3(4.4, 0.3, 0.35), 4.0, 6), Vector3(0, 0.75, end * 6.9), METAL)   # bumpers
			for side in [-1.0, 1.0]:
				_fit(parts, Kit.box(Vector3(0.08, 0.08, 9.0)), Vector3(side * 1.9, 3.3, 0.5), METAL)     # roof rails
		DEMON, RACER:
			var pod_x := 1.92 if kind == DEMON else 1.4
			for side in [-1.0, 1.0]:
				_fit(parts, Kit.cyl(0.55, 0.55, 0.14, 20), Vector3(side * pod_x, 0.72, -1.6), METAL, Vector3(PI / 2, 0, 0))   # intake rings
				_fit(parts, Kit.box(Vector3(0.9, 0.05, 0.5)), Vector3(side * 0.8, 0.8, -4.6), PAINT, Vector3(0.12, 0, 0))     # canards
				_fit(parts, Kit.box(Vector3(0.06, 0.9, 1.6)), Vector3(side * (0.5 if kind == DEMON else 0.0), 1.6, 5.4), PAINT)   # fins
		TRANSPORT:
			for x in [-1.8, -0.6, 0.6, 1.8]:
				_fit(parts, Kit.box(Vector3(0.08, 3.2, 0.08)), Vector3(x, 2.65, 8.3), METAL)             # door bars
			for i in parts.size():   # the roof cap is painted sheet, not a mirror for the suns
				if is_equal_approx((parts[i][2] as Color).a, METAL) and parts[i][0] is BoxMesh and (parts[i][0] as BoxMesh).size.z > 17.0 and (parts[i][0] as BoxMesh).size.x > 5.0:
					parts[i][2] = Color(0.5, 0.5, 0.5, TRIM)


## A closed skin through the stations: rounded-rectangle sections, eased from one to the next.
static func loft(stations: Array, around: int) -> ArrayMesh:
	var rings := []
	for k in stations.size() - 1:
		for step in 5:
			rings.append(_ease(stations, k, step / 5.0))
	rings.append(stations[-1])
	var verts := PackedVector3Array()
	for s in rings:
		var yc: float = (s[2] + s[3]) * 0.5
		var hh: float = (s[3] - s[2]) * 0.5
		for j in around:
			var th := TAU * j / around
			verts.append(Vector3(s[1] * Kit._sp(cos(th), 2.0 / s[4]), yc + hh * Kit._sp(sin(th), 2.0 / s[4]), s[0]))
	var normals := PackedVector3Array()
	var count := rings.size()
	for r in count:
		var centre := Vector3(0, (rings[r][2] + rings[r][3]) * 0.5, rings[r][0])
		for j in around:
			var along := verts[mini(r + 1, count - 1) * around + j] - verts[maxi(r - 1, 0) * around + j]
			var round_it := verts[r * around + (j + 1) % around] - verts[r * around + (j + around - 1) % around]
			var n := along.cross(round_it).normalized()
			normals.append(n if n.dot(verts[r * around + j] - centre) >= 0.0 else -n)
	var index := PackedInt32Array()
	for r in count - 1:
		for j in around:
			var a := r * around + j
			var b := r * around + (j + 1) % around
			index.append_array([a, a + around, b, b, a + around, b + around])   # clockwise from outside: Godot's front face
	for cap in [0, count - 1]:   # close the nose and the tail
		var middle := verts.size()
		verts.append(Vector3(0, (rings[cap][2] + rings[cap][3]) * 0.5, rings[cap][0]))
		normals.append(Vector3(0, 0, -1.0 if cap == 0 else 1.0))
		for j in around:
			var here: int = cap * around + j
			var next: int = cap * around + (j + 1) % around
			index.append_array([middle, here, next] if cap == 0 else [middle, next, here])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ease(stations: Array, k: int, t: float) -> Array:
	var out := []
	for field in 5:
		var p0: float = stations[maxi(k - 1, 0)][field]
		var p1: float = stations[k][field]
		var p2: float = stations[k + 1][field]
		var p3: float = stations[mini(k + 2, stations.size() - 1)][field]
		# Catmull-Rom, held between the two stations' values so a section never overshoots.
		var v := 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t)
		out.append(clampf(v, minf(p1, p2), maxf(p1, p2)) if field > 0 else lerpf(p1, p2, t))
	return out
