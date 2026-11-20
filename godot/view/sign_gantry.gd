## Reusable galvanized highway furniture. All members of a span share one mesh.
## Geometry is in road-local coordinates, with its feet on the shoulder deck.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const ZINC := Color(0.62, 0.66, 0.66)
const CHANNEL := Color(0.43, 0.48, 0.49)
const COLLAR := Color(0.73, 0.75, 0.72)
const CONCRETE := Color(0.52, 0.50, 0.45, 0.0)
const RAIL_Y := 42.0
const FACE_Z := 3.5
enum Back { EXPOSED, ID_PLATE, SECOND_FACE }
const ID_SCALE := Vector2(0.57, 0.43)
const ID_HEIGHT := 0.20
var spans := {}
var carriers := {}
var service_rails := {}
var metal := ShaderMaterial.new()

func _init() -> void:
	metal.shader = preload("res://view/gantry_finish.gdshader")

func _tube(parts: Array, a: Vector3, b: Vector3, radius: float, tint: Color) -> void:
	var dir := b - a
	var basis := Basis(Quaternion(Vector3.UP, dir.normalized()))
	parts.append([Kit.cyl(radius, radius, dir.length(), 8), Transform3D(basis, (a+b)*0.5), tint])

func span(half_width: float) -> Mesh:
	var key := roundi(half_width * 10.0)
	if spans.has(key):
		return spans[key]
	var parts := []
	for side in [-1.0, 1.0]:
		var x := half_width * float(side)
		# Each footing bears on a concrete outrigger cast into the deck edge,
		# including on the elevated expressways.
		parts.append([Kit.box(Vector3(11.4,2.3,7.4)), Kit.at(Vector3(x-side*2.65,-1.15,0)), CONCRETE])
		parts.append([Kit.box(Vector3(4.9, 2.4, 6.4)), Kit.at(Vector3(x, 0.8, 0)), CONCRETE])
		parts.append([Kit.box(Vector3(4.3, 0.42, 5.7)), Kit.at(Vector3(x, 2.12, 0)), CHANNEL])
		for z in [-1.65, 1.65]:
			_tube(parts, Vector3(x, 2.3, z), Vector3(x, RAIL_Y+4.1, z), 1.03, ZINC)
			for y in [2.65, RAIL_Y-3.1, RAIL_Y+3.1]:
				parts.append([Kit.cyl(1.23, 1.23, 0.68, 10), Kit.at(Vector3(x,y,z)), COLLAR])
			for dx in [-1.6, 1.6]:
				parts.append([Kit.cyl(0.24, 0.24, 0.34, 6), Kit.at(Vector3(x+dx,2.48,z)), ZINC])
	# A box truss with alternating Warren diagonals on both faces and transverse ties.
	var bays := maxi(4, roundi(2.0 * half_width / 14.0))
	for z in [-1.65, 1.65]:
		for y in [RAIL_Y-3.1, RAIL_Y+3.1]:
			_tube(parts, Vector3(-half_width,y,z), Vector3(half_width,y,z), 0.72, ZINC)
		for j in bays:
			var x0 := lerpf(-half_width, half_width, float(j)/bays)
			var x1 := lerpf(-half_width, half_width, float(j+1)/bays)
			var dy := 3.1 if j % 2 == 0 else -3.1
			_tube(parts, Vector3(x0,RAIL_Y-dy,z), Vector3(x1,RAIL_Y+dy,z), 0.43, CHANNEL)
			if z > 0.0:
				_tube(parts, Vector3(x0,RAIL_Y-dy,-z), Vector3(x0,RAIL_Y-dy,z), 0.36, ZINC)
	spans[key] = Kit.compound(parts)
	return spans[key]

## The reverse side exposes the extruded panel flanges and the beams clamping
## the assembly to the truss. Only genuinely two-way signs get a second full blank.
func carrier(size: Vector2, back := Back.EXPOSED) -> Mesh:
	var key := Vector3(size.x, size.y, back)
	if carriers.has(key):
		return carriers[key]
	var parts := []
	var blank := _blank(size)
	parts.append([blank, Kit.at(Vector3(0, 0, FACE_Z-0.23)), COLLAR])
	var rows := maxi(2, roundi(size.y / 4.6))
	var flange := Kit.box(Vector3(size.x*0.985, 0.30, 0.68))
	for row in range(1, rows):
		var y := size.y * (float(row)/rows - 0.5)
		parts.append([flange, Kit.at(Vector3(0, y, 2.78)), ZINC])
	var count := maxi(2, roundi(size.x / 24.0))
	var web := Kit.box(Vector3(0.54, size.y*0.92, 4.92))
	var lip := Kit.box(Vector3(1.72, size.y*0.92, 0.30))
	var clamp_bar := Kit.box(Vector3(2.65, 0.52, 0.54))
	for column in count:
		var x := size.x * ((float(column)+0.5)/count - 0.5)
		parts.append([web, Kit.at(Vector3(x, 0, -0.04)), CHANNEL])
		parts.append([lip, Kit.at(Vector3(x, 0, -2.58)), ZINC])
		for y in [-0.30, 0.30]:
			parts.append([clamp_bar, Kit.at(Vector3(x, y*size.y, -2.92)), COLLAR])
	if back == Back.SECOND_FACE:
		parts.append([blank, Kit.at(Vector3(0, 0, 0.23-FACE_Z)), COLLAR])
	elif back == Back.ID_PLATE:
		parts.append([_blank(size*ID_SCALE), Kit.at(Vector3(0, size.y*ID_HEIGHT, 0.23-FACE_Z)), COLLAR])
	carriers[key] = Kit.compound(parts)
	return carriers[key]

## Folded maintenance tread on triangulated outriggers. Model the openings
## between the longitudinal bars so the sky shows through from underneath.
func service_rail(size: Vector2) -> Mesh:
	if service_rails.has(size):
		return service_rails[size]
	var parts := []
	var width := size.x * 0.94
	var y := -size.y * 0.5 - 0.88
	var depth := size.y * 0.115
	var outside := FACE_Z + depth
	var bays := maxi(3, roundi(width / 17.0))
	for index in range(bays + 1):
		var x := width * (float(index)/bays - 0.5)
		parts.append([Kit.box(Vector3(0.45,0.45,outside+1.0)), Kit.at(Vector3(x,y,(outside-1.0)*0.5)), ZINC])
		_tube(parts,Vector3(x,y-1.85,0.0),Vector3(x,y,outside-0.40),0.24,CHANNEL)
	for bar in 5:
		var z := FACE_Z + depth * bar/4.0
		parts.append([Kit.box(Vector3(width,0.34,0.28)), Kit.at(Vector3(0,y+0.26,z)), COLLAR])
	service_rails[size] = Kit.compound(parts)
	return service_rails[size]

## Sheet silhouette and shallow extruded rim. Its center fan avoids alpha edges on the metal.
func _blank(size: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := size.y * 0.055
	var rim := PackedVector2Array()
	for c in 4:
		var sx := 1 if c in [0,3] else -1
		var sy := 1 if c in [0,1] else -1
		var center := Vector2(sx,sy) * (size*0.5 - Vector2.ONE * radius)
		for s in 6:
			var angle := (float(c) + float(s)/5.0) * PI/2.0
			rim.append(center + Vector2(cos(angle),sin(angle))*radius)
	for i in rim.size():
		var a := rim[i]
		var b := rim[(i+1)%rim.size()]
		var af := Vector3(a.x,a.y,0.16)
		var bf := Vector3(b.x,b.y,0.16)
		var ab := Vector3(a.x,a.y,-0.16)
		var bb := Vector3(b.x,b.y,-0.16)
		st.set_normal(Vector3.BACK)
		for p in [Vector3(0,0,0.16),bf,af]: st.add_vertex(p)
		st.set_normal(Vector3.FORWARD)
		for p in [Vector3(0,0,-0.16),ab,bb]: st.add_vertex(p)
		st.set_normal(Vector3(b.y-a.y,a.x-b.x,0).normalized())
		for p in [af,bf,ab,bf,bb,ab]: st.add_vertex(p)
	return st.commit()
