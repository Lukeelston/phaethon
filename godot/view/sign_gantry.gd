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
var spans := {}
var carriers := {}
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

## Twin aluminum blanks with folded edges and bolted vertical channels between them.
## Local origin is the center of the front legend, z=0 the truss centerline.
func carrier(size: Vector2) -> Mesh:
	if carriers.has(size):
		return carriers[size]
	var parts := []
	var blank := _blank(size)
	for side in [-1.0, 1.0]:
		parts.append([blank, Kit.at(Vector3(0,0,side * (FACE_Z-0.23))), COLLAR])
		for row in [-0.33, 0.32]:
			parts.append([Kit.box(Vector3(size.x*0.97, 0.78, 0.9)), Kit.at(Vector3(0,row*size.y,side*2.69)), CHANNEL])
	var n := maxi(2, roundi(size.x / 22.0))
	for j in n:
		var x := size.x * ((float(j)+0.5)/n-0.5)
		parts.append([Kit.box(Vector3(0.94,size.y*0.90,4.72)), Kit.at(Vector3(x,0,0)), ZINC])
	carriers[size] = Kit.compound(parts)
	return carriers[size]

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
