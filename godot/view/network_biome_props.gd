## Regional silhouettes, shared by instanced batches. All dimensions are real metres.
## The growing things come in three shapes: whole, a far shape of about a fifth of the triangles that
## keeps the outline and the colours, and a distant one of a few dozen (a tree 4 km off is a dozen
## pixels tall in the headset, one 12 km off three; the jungle plants nine hundred to a tile out to
## 30 km, and drawn whole they were half a frame's GPU time there). The landscape says which a tile's
## batches draw (detail()), by how near the craft is.
extends RefCounted
const Kit := preload("res://view/mesh_kit.gd")
static var far_shapes := true   # (timings: false draws everything whole, as it was)
var cache := {}
var far := {}                   # kind -> its far shape (the kinds without one draw whole at any distance)
var distant := {}               # kind -> its distant shape
var material: ShaderMaterial
func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/network_props.gdshader")
	for kind in ["oak", "pine", "snowpine", "palm", "mangrove", "reeds", "scrub", "cactus", "rock", "farm", "outpost", "stilt", "urban", "industrial", "service", "solar", "wind", "basalt"]:
		cache[kind] = _make(kind)
	for kind in ["oak", "mangrove", "palm", "pine", "snowpine", "scrub"]:
		far[kind] = _make_far(kind)
		distant[kind] = _make_distant(kind)

## A growing thing's far shape: the same trunk, crown and colours in a few plain solids.
func _make_far(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	match kind:
		"oak", "mangrove":
			cyl(p,1.2,2.7,22,Vector3(0,11,0),bark,4)
			for k in [0, 3, 5]:   # three of its seven crowns, grown to fill the others' places
				var a: float = k*2.399
				var at := Vector3(cos(a)*(6+k)*0.7,24+(k%3)*4,sin(a)*(6+k)*0.7)
				p.append([Kit.ball(1.0,6),Kit.at(at,Vector3.ZERO,Vector3(10,8,11)*1.5),green*(0.72+0.055*k)])
		"palm":
			cyl(p,0.7,2,46,Vector3(0,23,0),bark,4)
			for k in 5:           # five fronds for seven
				var a := TAU*k/5
				p.append([Kit.ball(1,4),Kit.at(Vector3(cos(a)*11,44,sin(a)*11),Vector3(0,-a,0.2),Vector3(17,2.4,5.5)),green*(0.8+k*0.035)])
		"pine", "snowpine":
			cyl(p,0.5,1.6,33,Vector3(0,16.5,0),bark,4)
			cyl(p,0.2,12,20,Vector3(0,14,0),Color(0.12,0.25,0.18),6)
			cyl(p,0.2,7.5,18,Vector3(0,27,0),Color(0.12,0.25,0.18),6)
			if kind == "snowpine":
				cyl(p,0,9,13,Vector3(0,18,0),Color(0.85,0.89,0.91),6)
				cyl(p,0,5.5,12,Vector3(0,31,0),Color(0.85,0.89,0.91),6)
		"scrub":
			for z in [0.0, 4.0]:
				p.append([Kit.ball(1.0,6),Kit.at(Vector3(2.5,2,z),Vector3.ZERO,Vector3(5.5,2.6,3.6)),Color(0.43,0.43,0.28)])
	return Kit.compound(p)

## ... and its distant one: a trunk and one solid for the crown.
func _make_distant(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	match kind:
		"oak", "mangrove":
			cyl(p,1.5,2.7,22,Vector3(0,11,0),bark,3)
			p.append([Kit.ball(1.0,6),Kit.at(Vector3(0,27,0),Vector3.ZERO,Vector3(21,11,21)),green*0.86])
		"palm":
			cyl(p,0.9,2,46,Vector3(0,23,0),bark,3)
			p.append([Kit.ball(1.0,6),Kit.at(Vector3(0,44.5,0),Vector3.ZERO,Vector3(22,3.2,22)),green*0.88])
		"pine", "snowpine":
			cyl(p,0.2,11,34,Vector3(0,19,0),Color(0.12,0.25,0.18),5)
			if kind == "snowpine":
				cyl(p,0,7.5,20,Vector3(0,27,0),Color(0.85,0.89,0.91),5)
		"scrub":
			p.append([Kit.ball(1.0,4),Kit.at(Vector3(2.5,2,2),Vector3.ZERO,Vector3(5.5,2.6,5.5)),Color(0.43,0.43,0.28)])
	return Kit.compound(p)

## Which shape a batch draws: 0 whole (its tile is near the craft), 1 its far shape, 2 its distant one.
func detail(batch: MultiMeshInstance3D, level: int) -> void:
	var kind := String(batch.name)
	var mesh: Mesh = cache[kind]
	if far_shapes and level > 0 and far.has(kind):
		mesh = distant[kind] if level > 1 else far[kind]
	if batch.multimesh.mesh != mesh:
		batch.multimesh.mesh = mesh

static func triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var index = arrays[Mesh.ARRAY_INDEX]
		n += (index.size() if index != null and index.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

func box(parts: Array, size: Vector3, p: Vector3, c: Color, angle := 0.0) -> void:
	parts.append([Kit.box(size), Kit.at(p,Vector3(0,angle,0)),c])
func cyl(parts: Array, top: float, bottom: float, h: float, p: Vector3, c: Color, sides := 8) -> void:
	parts.append([Kit.cyl(top,bottom,h,sides),Kit.at(p),c])
func ball(parts: Array, size: Vector3, p: Vector3, c: Color) -> void:
	parts.append([Kit.ball(1.0,8),Kit.at(p,Vector3.ZERO,size),c])

## Split, uneven rock faces instead of smooth inflated ellipsoids. Flat normals
## retain a readable silhouette at speed; every instance shares this one mesh.
func stone(parts: Array, size: Vector3, at: Vector3, color: Color) -> void:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:=[]
	for level in 3:
		for k in 7:
			var angle:=TAU*k/7.0+level*0.13
			var radius: float=[0.95,1.0,0.65][level]*(0.87+0.13*sin(k*7.13+level*3.1))
			rings.append(Vector3(cos(angle)*size.x*radius,(-0.55+level*0.7)*size.y+sin(k*2.7+level)*size.y*0.12,sin(angle)*size.z*radius))
	for level in 2:
		for k in 7:
			var a: Vector3=rings[level*7+k]
			var b: Vector3=rings[level*7+(k+1)%7]
			var c: Vector3=rings[(level+1)*7+(k+1)%7]
			var d: Vector3=rings[(level+1)*7+k]
			for tri in [[a,b,c],[a,c,d]]:
				st.set_normal((tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized())
				for v in tri: st.add_vertex(v)
	for k in range(1,6):
		var a: Vector3=rings[14]
		var b: Vector3=rings[14+k]
		var c: Vector3=rings[15+k]
		st.set_normal((c-a).cross(b-a).normalized())
		for v in [a,b,c]: st.add_vertex(v)
	parts.append([st.commit(),Kit.at(at),color])

func _make(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	var concrete := Color(0.57,0.57,0.52)
	var metal := Color(0.33,0.39,0.41)
	var window := Color(0.17,0.31,0.37)
	match kind:
		"service":
			box(p,Vector3(250,14,190),Vector3(0,-7,0),Color(0.28,0.28,0.27))
			box(p,Vector3(65,22,36),Vector3(-60,11,-45),Color(0.66,0.58,0.45))
			box(p,Vector3(70,3,40),Vector3(-60,24,-45),metal)
			box(p,Vector3(55,7,0.5),Vector3(-60,15,-26.8),window)
			for x in [-65,-15,35,85]:
				cyl(p,1,1.5,25,Vector3(x,12.5,25),concrete)
				box(p,Vector3(29,5,12),Vector3(x,3,50),Color(0.45,0.53,0.55))
			box(p,Vector3(200,3,43),Vector3(10,27,25),Color(0.74,0.69,0.56))
			box(p,Vector3(200,1,1),Vector3(10,27,47),Color(1.0,0.55,0.12))
			cyl(p,1,2,75,Vector3(115,37.5,-65),metal)
			box(p,Vector3(22,10,3),Vector3(115,73,-65),Color(0.8,0.48,0.17))
			# Delivery bay, roof equipment and a few parked service vehicles.
			box(p,Vector3(12,13,0.8),Vector3(-80,6.5,-26.5),metal)
			for k in 3:
				box(p,Vector3(7,3,8),Vector3(-80+k*18,27,-47),concrete)
				var parked:=Vector3(-85+k*31,2,-80)
				box(p,Vector3(19,4,8),parked,Color(0.32+k*0.15,0.37,0.36))
				box(p,Vector3(8,2.7,7),parked+Vector3(-1,3,0),window)
				for side in [-1,1]:
					box(p,Vector3(23,0.15,0.6),parked+Vector3(0,-1.8,side*7),Color(0.78,0.73,0.57))
		"solar":
			box(p,Vector3(240,12,240),Vector3(0,-6,0),Color(0.44,0.39,0.29))
			for x in 6:
				for z in 6:
					var at := Vector3((x-2.5)*36,6,(z-2.5)*36)
					cyl(p,0.6,1,8,at-Vector3(0,2,0),metal,4)
					p.append([Kit.box(Vector3(30,0.7,26)),Kit.at(at,Vector3(-0.22,0,0)),Color(0.11,0.22,0.32)])
			box(p,Vector3(20,9,14),Vector3(100,4.5,105),concrete)
		"wind":
			cyl(p,7,10,12,Vector3(0,0,0),concrete)
			cyl(p,2,5,135,Vector3(0,67.5,0),Color(0.77,0.79,0.76))
			box(p,Vector3(7,7,18),Vector3(0,135,0),metal)
			for k in 3:
				var a := k*TAU/3.0+0.3
				p.append([Kit.box(Vector3(4,66,1.2)),Kit.at(Vector3(sin(a)*34,135+cos(a)*34,11),Vector3(0,0,-a)),Color(0.82,0.83,0.79)])
		"basalt":
			for k in 9:
				var a := k*2.399
				var h := 35.0+(k%4)*22.0
				cyl(p,8,12,h,Vector3(cos(a)*k*7,h*0.5-5,sin(a)*k*7),Color(0.19+k*0.01,0.20+k*0.008,0.20+k*0.008),6)
		"oak", "mangrove":
			var swamp := kind == "mangrove"
			cyl(p,1.2,2.7,22,Vector3(0,11,0),bark)
			for k in 7:
				var a := k*2.399
				var at := Vector3(cos(a)*(6+k),22+(k%3)*5,sin(a)*(6+k))
				var scale:=0.75+0.11*(k%3)
				ball(p,Vector3(10,8,11)*scale,at,green*(0.72+0.055*k))
				var branch:=at-Vector3(0,13,0)
				p.append([Kit.cyl(0.35,1.0,branch.length(),5),Transform3D(Basis(Quaternion(Vector3.UP,branch.normalized())),Vector3(0,13,0)+branch*0.5),bark])
				if swamp:
					p.append([Kit.cyl(0.6,1.2,12,5),Kit.at(Vector3(cos(a)*3,5,sin(a)*3),Vector3(sin(a)*0.5,0,cos(a)*0.5)),bark])
		"pine", "snowpine":
			cyl(p,0.5,1.6,33,Vector3(0,16.5,0),bark)
			for k in 4:
				cyl(p,0.2,12-k*2.2,16,Vector3(0,12+k*6,0),Color(0.12,0.25,0.18))
				if kind == "snowpine":
					cyl(p,0,10-k*2,12,Vector3(0,15+k*6,0),Color(0.85,0.89,0.91))
		"palm":
			cyl(p,0.7,2,46,Vector3(0,23,0),bark)
			ball(p,Vector3(6,4,6),Vector3(0,46,0),green)
			for k in 7:
				var a := TAU*k/7
				p.append([Kit.ball(1,8),Kit.at(Vector3(cos(a)*11,44,sin(a)*11),Vector3(0,-a,0.2),Vector3(17,2.4,4.5)),green*(0.8+k*0.025)])
		"reeds":
			for k in 11:
				var a := k*2.399
				var at := Vector3(cos(a)*k,3+k%3,sin(a)*k)
				cyl(p,0,0.9,at.y*2,at,Color(0.40,0.43,0.20),4)
		"scrub":
			for k in 4:
				ball(p,Vector3(4,2.5,3),Vector3((k%2)*5,2,(k/2)*4),Color(0.43,0.43,0.28))
		"cactus":
			cyl(p,1.3,1.7,17,Vector3(0,8.5,0),Color(0.27,0.39,0.25))
			for s in [-1.0,1.0]:
				box(p,Vector3(7,2,2),Vector3(s*3,8+s*2,0),Color(0.25,0.35,0.20))
				cyl(p,0.7,1,7,Vector3(s*6,11+s*2,0),green)
		"rock":
			stone(p,Vector3(16,11,13),Vector3(0,6,0),Color(0.41,0.40,0.37))
			stone(p,Vector3(8,7,11),Vector3(12,3,6),Color(0.47,0.45,0.40))
			stone(p,Vector3(5,3,4),Vector3(-12,1,9),Color(0.35,0.35,0.33))
		"farm":
			box(p,Vector3(96,8,105),Vector3(0,-3,0),Color(0.48,0.43,0.29))
			box(p,Vector3(38,18,24),Vector3(-14,9,0),Color(0.61,0.40,0.26))
			p.append([Kit.cyl(0,25,11,4),Kit.at(Vector3(-14,23,0),Vector3(0,PI/4,0),Vector3(1,1,0.75)),Color(0.31,0.32,0.32)])
			for k in 3:
				cyl(p,7,7,25,Vector3(24,12.5,(k-1)*19),metal)
				cyl(p,0,7,5,Vector3(24,27.5,(k-1)*19),concrete)
			for k in 8:
				box(p,Vector3(75,0.7,2.0),Vector3(0,1,32+k*2.5),Color(0.35,0.44,0.16))
		"stilt":
			for x in [-12,12]:
				for z in [-10,10]:
					cyl(p,0.8,1,15,Vector3(x,6,z),bark)
			box(p,Vector3(30,2,27),Vector3(0,12,0),bark)
			box(p,Vector3(24,10,20),Vector3(0,18,0),Color(0.55,0.49,0.34))
			p.append([Kit.cyl(0,21,7,4),Kit.at(Vector3(0,26,0),Vector3(0,PI/4,0)),Color(0.29,0.32,0.26)])
			box(p,Vector3(14,4,0.5),Vector3(0,19,10.1),window)
		"urban":
			box(p,Vector3(260,18,250),Vector3(0,-9,0),Color(0.24,0.26,0.26))
			for k in 6:
				var at := Vector3((k%3-1)*75,0,(k/3*2-1)*70)
				var h := 24.0+(k%3)*15.0
				box(p,Vector3(46,h,45),at+Vector3.UP*h/2,concrete*(0.80+k*0.03))
				box(p,Vector3(50,3,49),at+Vector3.UP*h,metal)
				for floor_id in range(1,int(h/5)):
					for side in [-1,1]:
						box(p,Vector3(39,2,0.5),at+Vector3(0,floor_id*5,side*22.6),window)
						box(p,Vector3(0.5,2,37),at+Vector3(side*23.1,floor_id*5,0),window)
				box(p,Vector3(8,4,8),at+Vector3(8,h+3,-5),metal)
				box(p,Vector3(6,8,0.6),at+Vector3(-9,4,22.7),window)
				box(p,Vector3(13,1,5),at+Vector3(-9,9,24),metal)
			# Quiet feeder streets, pavements and planted courtyards.
			for s in [-1,1]:
				box(p,Vector3(245,0.2,2),Vector3(0,0.2,s*27),Color(0.65,0.65,0.58))
				ball(p,Vector3(7,9,7),Vector3(s*110,10,0),green)
		"industrial", "outpost":
			box(p,Vector3(120,10,100),Vector3(0,-4,0),Color(0.42,0.42,0.37))
			box(p,Vector3(53,18,34),Vector3(-20,10,8),concrete)
			box(p,Vector3(55,2,37),Vector3(-20,20,8),metal)
			box(p,Vector3(38,7,0.5),Vector3(-20,13,25.1),window)
			for k in 3:
				cyl(p,8,8,20,Vector3(25,10,k*23-22),Color(0.63,0.63,0.60))
			cyl(p,0.4,1.2,65,Vector3(-46,32,-35),metal,6)
			box(p,Vector3(18,0.8,2),Vector3(-46,54,-35),metal)
			if kind == "industrial":
				for k in 2:
					cyl(p,4,7,70,Vector3(40+k*14,35,-38),Color(0.34,0.33,0.31))
			else:
				for k in 4:
					box(p,Vector3(16,0.6,10),Vector3(-38+k*22,4,-35),Color(0.13,0.23,0.32))
	return Kit.compound(p)

func batch(parent: Node3D, kind: String, transforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = distant[kind] if far_shapes and distant.has(kind) else cache[kind]   # (most tiles are distant ones: the landscape says when one is nearer)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = kind
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 38000 # shader fades individual fragments before this bound
	instance.set_instance_shader_parameter("stream_reveal",0.0)
	parent.add_child(instance)
