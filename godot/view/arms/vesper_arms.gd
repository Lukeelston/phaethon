## The Vesper pulse wheel rides on the forward starboard sill. Four independent
## quarter rings nest like a fan inside one bay, then open into one transducer.
extends "res://view/arms/hull_hatches.gd"

const HATCHES := "res://art/arms/vesper_hatches.glb"
const WELL := Vector3(.89, -.101, -.78)
const RAM_OFFSET := Vector3(.067, 0, .076)
const RAISED := Vector3(1.052, .372, -.881)
const OUTER_PIN := Vector3(.32, 0, 1)
const FORE_PIVOT := Vector3(1.033, .010, -1.05)
const AFT_PIVOT := Vector3(1.113, .010, -.80)
const RADIUS := .306
const STACK := .043
const CERAMIC := Color("#d9d4e7")
const TITANIUM := Color("#6a6477")
var _lift: Node3D
var _head: Node3D
var _piston: Node3D
var _rods: MeshInstance3D
var _sectors: Array[MeshInstance3D] = []


func build(hull: Node3D) -> void:
	if is_instance_valid(_skin):
		return
	var pivots: Array[Vector3] = [FORE_PIVOT, AFT_PIVOT]
	install(hull, hull as MeshInstance3D, load(HATCHES), pivots)
	hinges[0].name = &"ForeLeaf"
	hinges[1].name = &"AftLeaf"
	for hinge in hinges:
		var skin: MeshInstance3D = hinge.get_node("Skin")
		var backing := piece(hinge, &"HatchBacking", _inner_skin(skin.mesh), Finish.powder_coat(), skin.position)
		backing.position.y -= .004

	var foot := WELL+RAM_OFFSET
	var feet := [
		[_well_liner(), Transform3D.IDENTITY, GRAPHITE],
		[Finish.beveled_plate(Vector3(.122,.028,.146),.008),
				Kit.at(Vector3(foot.x,-.359,foot.z)), TITANIUM],
		[Kit.cyl(.035,.044,.197,16),Kit.at(Vector3(foot.x,-.245,foot.z)),TITANIUM],
	]
	piece(self,&"LiftWell",Kit.compound(feet,null,true),Finish.powder_coat())
	_piston = Node3D.new()
	_piston.name = &"LiftTrunnion"
	add_child(_piston)
	_piston.position = foot
	var barrels := []
	var rods := []
	for x in [-.026,.026]:
		barrels.append([Kit.cyl(.025,.027,.071,16),Kit.at(Vector3(x,-.072,0)),TITANIUM])
		barrels.append([Kit.cyl(.029,.029,.012,16),Kit.at(Vector3(x,-.037,0)),BRONZE])
		rods.append([Kit.cyl(.017,.017,1,12),Kit.at(Vector3(x,.5,0)),SILVER])
	piece(_piston,&"RamSleeves",Kit.compound(barrels,null,true),Finish.powder_coat())
	_rods = piece(_piston,&"TwinLiftRods",Kit.compound(rods,null,true),Finish.machined(),Vector3.DOWN*.042)
	_lift = Node3D.new()
	_lift.name = &"PulseCarriage"
	add_child(_lift)
	var yoke := [[Finish.beveled_plate(Vector3(.115,.021,.042),.006),
			Kit.at(RAM_OFFSET*.5+Vector3.DOWN*.016,Vector3(0,-.845,0)),TITANIUM]]
	piece(_lift,&"CantYoke",Kit.compound(yoke,null,true),Finish.machined())
	_head = Node3D.new()
	_head.name = &"CantBearing"
	_lift.add_child(_head)
	var hub := [
		[Kit.cyl(.071,.083,.076,24),Kit.at(Vector3(0,-.027,0)),TITANIUM],
		[Kit.cyl(.058,.071,.024,24),Kit.at(Vector3(0,.019,0)),BRONZE],
		[Kit.cyl(.044,.052,.020,20),Kit.at(Vector3(0,.035,0)),CERAMIC],
	]
	piece(_head,&"WaveHub",Kit.compound(hub,null,true),Finish.machined())

	var carrier := [
		[_arc(.2533,.2927,.028,1.0,89.0),Transform3D.IDENTITY,TITANIUM],
		[_arc(.240,.253,.037,1.0,89.0),Transform3D.IDENTITY,SILVER],
		[_arc(.293,RADIUS,.037,1.0,89.0),Transform3D.IDENTITY,CERAMIC],
	]
	for degrees: float in [9.0,81.0]:
		var turn := Transform3D(Basis(Vector3.UP,deg_to_rad(degrees)),Vector3.ZERO)
		carrier.append([Finish.beveled_plate(Vector3(.206,.017,.024),.005),
				turn * Kit.at(Vector3(.149,-.007,0)),BRONZE])
		carrier.append([Finish.beveled_plate(Vector3(.073,.042,.027),.006),
				turn * Kit.at(Vector3(.273,0,0)),CERAMIC])
	var shoe := Kit.compound(carrier,null,true)
	var glass := Kit.compound([
		[_arc(.258,.289,.012,13.0,43.0),Kit.at(Vector3.UP*.020),Color.WHITE],
		[_arc(.258,.289,.012,47.0,77.0),Kit.at(Vector3.UP*.020),Color.WHITE],
	],null,true)
	var lens := luminous(Color("#765aa8"),Color("#f3bcff"))
	for i in 4:
		var quadrant := piece(_head,"EmitterQuadrant%d" % (i+1),shoe,Finish.machined())
		piece(quadrant,&"FluxWindows",glass,lens)
		_sectors.append(quadrant)
	# Pulse origin rides at the center bearing. The tipped ring rotates independently
	# so its normal never steers the gameplay pulse.
	muzzle(_lift,&"PulseOrigin",Vector3.ZERO)
	set_deploy(0.0)


## Both faces are visible on an open leaf. The reverse shell follows the painted
## skin exactly so the liner cannot poke through the outside of the curved panel.
static func _inner_skin(mesh: Mesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0,indices.size(),3):
		for j in [0,2,1]:
			var id := indices[t+j]
			st.set_color(GRAPHITE)
			st.set_normal(-normals[id])
			st.add_vertex(positions[id])
	st.index()
	return st.commit()


## The tray follows the same tapered foredeck coordinates as the painted leaves.
static func _well_liner() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := PackedVector3Array()
	var floor := PackedVector3Array()
	for uv: Vector2 in [Vector2(.757,-1.17),Vector2(1.081,-1.17),
			Vector2(1.081,-.67),Vector2(.757,-.67)]:
		var x := uv.x+.32*(uv.y+.9)
		rim.append(Vector3(x,-.026,uv.y))
		floor.append(Vector3(x,-.374,uv.y))
	Finish._quad(st,floor[0],floor[1],floor[2],floor[3],Vector3.UP)
	var center := (rim[0]+rim[2])*.5
	for i in 4:
		var j := (i+1)%4
		Finish._quad(st,rim[i],rim[j],floor[j],floor[i],center-(rim[i]+rim[j])*.5)
	st.index()
	return st.commit()


## A chamfered annular sector, including the two end caps revealed while it fans out.
static func _arc(inner: float, outer: float, thickness: float, from_deg: float, to_deg: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thickness*.5
	var b := minf(h*.48,(outer-inner)*.2)
	var section := PackedVector2Array([Vector2(inner,-h+b),Vector2(inner+b,-h),
			Vector2(outer-b,-h),Vector2(outer,-h+b),Vector2(outer,h-b),Vector2(outer-b,h),
			Vector2(inner+b,h),Vector2(inner,h-b)])
	var steps := ceili((to_deg-from_deg)/7.5)
	for i in steps:
		var a := deg_to_rad(lerpf(from_deg,to_deg,float(i)/steps))
		var z := deg_to_rad(lerpf(from_deg,to_deg,float(i+1)/steps))
		var ra := Vector3(cos(a),0,-sin(a))
		var rz := Vector3(cos(z),0,-sin(z))
		for j in section.size():
			var p := section[j]
			var n := section[(j+1)%section.size()]
			var normals := [(ra*(n.y-p.y) + Vector3.UP*(p.x-n.x)).normalized(),
				(rz*(n.y-p.y) + Vector3.UP*(p.x-n.x)).normalized()]
			var corner := [ra*p.x+Vector3.UP*p.y,rz*p.x+Vector3.UP*p.y,
					rz*n.x+Vector3.UP*n.y,ra*n.x+Vector3.UP*n.y]
			for k: int in [0,2,1,0,3,2]:
				st.set_normal(normals[1 if k in [1,2] else 0])
				st.add_vertex(corner[k])
	for angle in [from_deg,to_deg]:
		var a := deg_to_rad(angle)
		var spoke := Vector3(cos(a),0,-sin(a))
		var outward := Vector3(sin(a),0,cos(a)) * (1 if angle == from_deg else -1)
		var mid := spoke * (inner+outer)*.5
		for j in section.size():
			var p := section[j]
			var n := section[(j+1)%section.size()]
			var p3 := spoke*p.x+Vector3.UP*p.y
			var n3 := spoke*n.x+Vector3.UP*n.y
			var verts := [mid,n3,p3] if (p3-mid).cross(n3-mid).dot(outward)>0 else [mid,p3,n3]
			for v: Vector3 in verts:
				st.set_normal(outward)
				st.add_vertex(v)
	st.index()
	return st.commit()


func set_deploy(t: float) -> void:
	if not pose(t):
		return
	var doors := smoothstep(0.0,.23,_deployed)
	var swing := Basis(OUTER_PIN.normalized(), deg_to_rad(-156)*doors)
	for hinge in hinges:
		hinge.basis = swing
	# Lift the edge-on cassette vertically through the shoulder. The carriage
	# swings out only once the nested sectors have passed the rail.
	var lift := smoothstep(.025,.68,_deployed)
	var reach := smoothstep(.39,.81,_deployed)
	_lift.position = Vector3(lerpf(WELL.x,RAISED.x,reach),lerpf(WELL.y,RAISED.y,lift),
			lerpf(WELL.z,RAISED.z,reach))
	var travel := _lift.position-WELL
	_piston.basis = Basis(Quaternion(Vector3.UP,travel.normalized())) if travel.length_squared() > .000001 else Basis.IDENTITY
	_rods.scale.y = travel.length()+.026
	var tilt := smoothstep(.44,.96,_deployed)
	_head.basis = Basis(Vector3.UP,deg_to_rad(18)*(1.-tilt)) * Basis(Vector3.RIGHT,deg_to_rad(58)*tilt) \
			* Basis(Vector3.BACK,deg_to_rad(-90)*(1.-tilt)) * Basis.from_scale(Vector3.ONE*.79)
	var fan := smoothstep(.23,.93,_deployed)
	var nest := 1.0-smoothstep(.922,1.0,_deployed)
	for i in _sectors.size():
		var angle: float = [0.0,-90.0,90.0,180.0][i]
		_sectors[i].rotation.y = deg_to_rad(angle)*fan
		_sectors[i].position.y = (float(i)-1.5)*STACK*nest
