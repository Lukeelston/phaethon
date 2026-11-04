## Regional silhouettes, shared by instanced batches. All dimensions are real metres.
extends RefCounted
const Kit := preload("res://view/mesh_kit.gd")
var cache := {}
var material: ShaderMaterial
func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://view/network_scenery.gdshader")
	for kind in ["oak", "pine", "snowpine", "palm", "mangrove", "reeds", "scrub", "cactus", "rock", "farm", "outpost", "stilt", "urban", "industrial"]:
		cache[kind] = _make(kind)

func box(parts: Array, size: Vector3, p: Vector3, c: Color, angle := 0.0) -> void:
	parts.append([Kit.box(size), Kit.at(p,Vector3(0,angle,0)),c])
func cyl(parts: Array, top: float, bottom: float, h: float, p: Vector3, c: Color, sides := 8) -> void:
	parts.append([Kit.cyl(top,bottom,h,sides),Kit.at(p),c])
func ball(parts: Array, size: Vector3, p: Vector3, c: Color) -> void:
	parts.append([Kit.ball(1.0,8),Kit.at(p,Vector3.ZERO,size),c])

func _make(kind: String) -> ArrayMesh:
	var p := []
	var bark := Color(0.27,0.22,0.16)
	var green := Color(0.22,0.37,0.13)
	var concrete := Color(0.57,0.57,0.52)
	var metal := Color(0.33,0.39,0.41)
	var window := Color(0.17,0.31,0.37)
	match kind:
		"oak", "mangrove":
			var swamp := kind == "mangrove"
			cyl(p,1.2,2.7,22,Vector3(0,11,0),bark)
			for k in 5:
				var a := k*TAU/5.0
				var at := Vector3(cos(a)*10,25+(k%3)*4,sin(a)*10)
				ball(p,Vector3(12,9,12),at,green*(0.75+0.06*k))
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
			ball(p,Vector3(16,11,13),Vector3(0,6,0),Color(0.41,0.40,0.37))
			ball(p,Vector3(8,7,11),Vector3(12,3,6),Color(0.47,0.45,0.40))
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
					box(p,Vector3(39,2,0.5),at+Vector3(0,floor_id*5,22.6),window)
				box(p,Vector3(8,4,8),at+Vector3(8,h+3,-5),metal)
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
	mm.mesh = cache[kind]
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = kind
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 25000
	instance.visibility_range_end_margin = 6000
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(instance)
