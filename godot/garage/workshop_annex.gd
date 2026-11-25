## The Fleet Workshop beyond the garage aisle. The fixed room joins the garage's
## material batches. The two moving leaves share a mesh and wake only on approach.
extends Node3D

signal motion_started(opening: bool)
signal motion_finished(opened: bool)

const RoomFloor := preload("res://garage/workshop_room_floor.gdshader")
const Aggregate := preload("res://art/road/pavement_detail.png")
const RoomFittings := preload("res://garage/workshop_room_fittings.glb")
const PilotGear := preload("res://garage/pilot_suit.glb")
const WALL_OPENING := 2.52
const WALL_HEAD := 2.47
const FRONTAGE := 8.9
# The clear opening sits beyond the fully retracted east leaf. Its lower edge is
# visible from the measurement counter, with Basilisk's cockpit across the glass.
const OBSERVATION := Rect2(2.53,1.09,1.62,1.13)
const HALF_WIDTH := 5.20
const FRONT := -.24
const BACK := -7.20
const CEILING := 3.25
const LEAF_WIDTH := 1.19
const LEAF_HEIGHT := 2.36
const LEAF_Z := .14
const MEETING_SEAL := .012
const SLIDE := 1.23
const OPEN_TIME := .84
const CLOSE_TIME := 1.12
const DWELL := .65

var open_fraction := 0.0
var _leaves: Array[AnimatableBody3D] = []
var _occupants := 0
var _opening := false
var _dwell := 0.0
var _travel := 0.0
var _hall
var _glazing := StandardMaterial3D.new()


func build(hall: Node3D) -> void:
	set_physics_process(false)
	_hall = hall
	_hall._material("ServiceLiner", "#b6bbab", .18, .57)
	var liner: StandardMaterial3D = _hall._finishes.ServiceLiner
	liner.normal_enabled = true
	liner.normal_texture = _hall.PowderRelief
	liner.normal_scale = .11
	liner.uv1_triplanar = true
	liner.uv1_world_triplanar = true
	liner.uv1_scale = Vector3.ONE / .21
	_glazing.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glazing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glazing.albedo_color = Color(.48,.68,.68,.15)
	_glazing.roughness = .16
	_shell()
	_air_handling()
	_furnish()
	_lights()
	_threshold()
	_observation_window()
	_fit_doors(hall._finishes)
	_hall = null


func _box(finish: String, at: Vector3, size: Vector3, frame := Basis.IDENTITY) -> void:
	_hall._box(finish, position + at, size, frame)


func _solid(finish: String, at: Vector3, size: Vector3) -> void:
	_box(finish,at,size)
	_hall._block(position+at,size)


func _shell() -> void:
	var length := FRONT - BACK
	var center := (FRONT + BACK) * .5
	# A flush resin floor finishes exactly against the hall's floor edge.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(HALF_WIDTH*2+.22, -BACK+.12)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "ResinFloor"
	floor_node.mesh = floor_mesh
	floor_node.position.z = -floor_mesh.size.y * .5
	var resin := ShaderMaterial.new()
	resin.shader = RoomFloor
	resin.set_shader_parameter("aggregate",Aggregate)
	resin.set_shader_parameter("plane_center_z",floor_node.position.z)
	resin.set_shader_parameter("walls",Vector4(HALF_WIDTH, BACK, FRONT, WALL_OPENING*.5))
	floor_node.material_override = resin
	add_child(floor_node)
	# The large hall floor collider projects 0.25 m under the existing wall.
	var floor_end := BACK - .22
	_hall._block(position+Vector3(0,-.15,(floor_end-.25)*.5),Vector3(HALF_WIDTH*2+.44,.30,-floor_end-.25))

	var wall_height := CEILING + .1
	for side: float in [-1.0,1.0]:
		_solid("ServiceLiner",Vector3(side*(HALF_WIDTH+.11),wall_height*.5,center),Vector3(.22,wall_height,length+.44))
		_box("Blockwork",Vector3(side*(HALF_WIDTH-.020),.388,center),Vector3(.04,.776,length))
		_box("Rail",Vector3(side*(HALF_WIDTH-.036),.795,center),Vector3(.078,.039,length))
		for seam in 5:
			_box("Girder",Vector3(side*(HALF_WIDTH-.005),2.006,FRONT-.49-1.31*seam),Vector3(.014,2.38,.024))
		_box("Steel",Vector3(side*(HALF_WIDTH-.05),3.19,center),Vector3(.12,.12,length))
	_solid("ServiceLiner",Vector3(0,wall_height*.5,BACK-.11),Vector3(2*HALF_WIDTH+.44,wall_height,.22))
	# The counter is flush to the middle of this wall. Cap the dado on either side.
	for side: float in [-1.0,1.0]:
		# Butt each back course against the side piece's finished face.
		var wing := HALF_WIDTH - 1.9 - .040
		_box("Blockwork",Vector3(side*(1.9+wing*.5),.388,BACK+.019),Vector3(wing,.776,.038))
		wing = HALF_WIDTH - 1.9 - .075
		_box("Rail",Vector3(side*(1.9+wing*.5),.795,BACK+.038),Vector3(wing,.039,.078))
		for seam in 3:
			_box("Girder",Vector3(side*(2.05+seam*1.34),2.004,BACK+.005),Vector3(.024,2.38,.014))
	_solid("Roof",Vector3(0,CEILING+.075,center),Vector3(HALF_WIDTH*2+.44,.15,length+.44))
	for i in 5:
		var z := FRONT - .38 - 1.43*i
		_box("Girder",Vector3(0,CEILING-.045,z),Vector3(HALF_WIDTH*2,.090,.078))
	# Interior returns cover the external gable and align both door pockets.
	for side: float in [-1.0,1.0]:
		var width := HALF_WIDTH-WALL_OPENING*.5
		for slab in wall_pieces(Vector3(side*(HALF_WIDTH-width*.5),1.60,FRONT-.035),Vector3(width,3.2,.070)):
			_box("ServiceLiner",slab.get_center(),slab.size)
		_box("Blockwork",Vector3(side*(WALL_OPENING+width-.040)*.5,.388,FRONT-.089),Vector3(width-.040,.776,.038))
		_box("Steel",Vector3(side*(WALL_OPENING+width-.075)*.5,.795,FRONT-.094),Vector3(width-.075,.039,.062))
		_box("Girder",Vector3(side*1.205,1.21,FRONT-.068),Vector3(.09,2.42,.128))
	_box("ServiceLiner",Vector3(0,(WALL_HEAD+CEILING)*.5,FRONT-.035),Vector3(WALL_OPENING,CEILING-WALL_HEAD,.07))
	_box("Steel",Vector3(0,2.43,FRONT-.088),Vector3(2.53,.12,.15))


## Intersect the light opening with a real wall course, including its returns
## and collider. Kept in room coordinates (the origin has no X or Y offset).
static func wall_pieces(at: Vector3, size: Vector3) -> Array[AABB]:
	var wall := Rect2(at.x-size.x*.5,at.y-size.y*.5,size.x,size.y)
	var opening := wall.intersection(OBSERVATION)
	var result: Array[AABB] = []
	if not opening.has_area():
		result.append(AABB(at-size*.5,size))
		return result
	var sections: Array[Rect2] = [
		Rect2(wall.position,Vector2(opening.position.x-wall.position.x,wall.size.y)),
		Rect2(opening.end.x,wall.position.y,wall.end.x-opening.end.x,wall.size.y),
		Rect2(opening.position.x,wall.position.y,opening.size.x,opening.position.y-wall.position.y),
		Rect2(opening.position.x,opening.end.y,opening.size.x,wall.end.y-opening.end.y)]
	for section in sections:
		if section.has_area():
			result.append(AABB(Vector3(section.position.x,section.position.y,at.z-size.z*.5),
				Vector3(section.size.x,section.size.y,size.z)))
	return result


func _observation_window() -> void:
	var center := OBSERVATION.get_center()
	# The original gable column lands on a transfer lintel centred over its new jambs.
	_box("Steel",Vector3(center.x,OBSERVATION.end.y+.084,-.105),Vector3(OBSERVATION.size.x+.24,.168,.32))
	for x: float in [OBSERVATION.position.x,OBSERVATION.end.x]:
		_box("Girder",Vector3(x,center.y,.042),Vector3(.069,OBSERVATION.size.y,.781))
		for z: float in [-.356,.413]:
			_box("Rail",Vector3(x,center.y,z),Vector3(.081,OBSERVATION.size.y+.095,.043))
	for y: float in [OBSERVATION.position.y,OBSERVATION.end.y]:
		_box("Girder",Vector3(center.x,y,.042),Vector3(OBSERVATION.size.x,.063,.781))
		for z: float in [-.356,.413]:
			_box("Rail",Vector3(center.x,y,z),Vector3(OBSERVATION.size.x+.080,.084,.043))
	_box("Rail",Vector3(center.x,OBSERVATION.position.y-.040,-.404),Vector3(OBSERVATION.size.x+.15,.048,.174))
	var clear := OBSERVATION.size - Vector2(.068,.064)
	var pane := QuadMesh.new()
	pane.size = clear
	var glazing := MeshInstance3D.new()
	glazing.name = "ObservationGlass"
	glazing.position = Vector3(center.x,center.y,.305)
	glazing.mesh = pane
	glazing.material_override = _glazing
	glazing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glazing)
	_hall._block(position+glazing.position,Vector3(clear.x,clear.y,.014))
	# Dark glazing beads retain the laminated pane. Its centre stays clear.
	for x: float in [OBSERVATION.position.x+.038,OBSERVATION.end.x-.038]:
		_box("Plinth",Vector3(x,center.y,.305),Vector3(.024,clear.y,.044))
	for y: float in [OBSERVATION.position.y+.037,OBSERVATION.end.y-.037]:
		_box("Plinth",Vector3(center.x,y,.305),Vector3(clear.x,.022,.044))


func _furnish() -> void:
	var fittings := RoomFittings.instantiate() as Node3D
	fittings.name = "RoomFittings"
	add_child(fittings)
	var reel: MeshInstance3D = fittings.find_child("WindingDrum",true,false)
	reel.position = Vector3(-3.32,0,BACK)
	reel.visibility_range_end = 25.0
	var wall := position + reel.position
	_hall._block(wall + Vector3(0,1.68,.20),Vector3(.61,.61,.40))
	_hall._block(wall + Vector3(.25,1.07,.31),Vector3(.074,.66,.10))
	_hall._block(wall + Vector3(-.52,2.17,.074),Vector3(.082,2.16,.148))
	var rack: MeshInstance3D = fittings.find_child("LockerBank",true,false)
	rack.position = Vector3(HALF_WIDTH,0,-3.44)
	rack.rotation.y = -PI*.5
	rack.visibility_range_end = 25.0
	_hall._block(position + rack.position + Vector3(-.33,.949,0),Vector3(.66,1.898,1.61))
	_stock_locker(rack)


func _air_handling() -> void:
	# An accessible rectangular supply/return trunk feeds two louvred terminals.
	var x := -HALF_WIDTH + .18
	_box("Girder",Vector3(x,2.70,-4.15),Vector3(.34,.35,5.50))
	for z: float in [-1.43,-2.79,-4.15,-5.51,-6.87]:
		_box("Rail",Vector3(x,2.70,z),Vector3(.37,.38,.027))
		_box("Steel",Vector3(x,3.0625,z),Vector3(.050,.375,.05))
	for z: float in [-3.10,-5.50]:
		_box("Rail",Vector3(x+.178,2.66,z),Vector3(.054,.33,.85))
		_box("Plinth",Vector3(x+.209,2.66,z),Vector3(.016,.25,.74))
		for i in 5:
			_box("Girder",Vector3(x+.225,2.66+(i-2)*.046,z),Vector3(.052,.017,.69),Basis(Vector3.FORWARD,.34))


func _lights() -> void:
	# Glare baffles conceal the LED strips from the two normal working positions.
	for z: float in [-1.65,-5.58]:
		_box("Steel",Vector3(0,3.10,z),Vector3(3.32,.13,.33))
		_box("Lamps",Vector3(0,3.028,z),Vector3(3.16,.024,.225))
		for x: float in [-1.39,1.39]:
			_box("Girder",Vector3(x,3.207,z),Vector3(.066,.088,.10))
			_box("Rail",Vector3(x,3.24,z),Vector3(.142,.020,.141))
		for x: float in [-1.55,-.78,0.0,.78,1.55]:
			_box("Girder",Vector3(x,3.016,z),Vector3(.025,.052,.28))
		var fixture := SpotLight3D.new()
		fixture.name = "CounterLight" if z < -4.0 else "EntranceLight"
		# A broad batten lights the counter and air drop at the rear, and catches
		# the visor and locker handles from the entrance end of the room.
		fixture.position = Vector3(-.58 if z < -4.0 else .60,2.99,z)
		var aim := Vector3(-.63,1.06,BACK+.47) if z < -4.0 else Vector3(.82,.72,-2.81)
		fixture.basis = Basis.looking_at(aim-fixture.position,Vector3.UP)
		fixture.light_color = Color("#fff1d8") if z < -4.0 else Color("#eff5f3")
		fixture.light_energy = 3.4
		fixture.spot_angle = 73.0
		fixture.spot_angle_attenuation = .7
		fixture.spot_range = 6.1
		fixture.spot_attenuation = .8
		# The worktop tools need short contact shadows only when approached.
		fixture.shadow_enabled = z < -4.0
		fixture.distance_fade_enabled = true
		fixture.distance_fade_begin = 9.0
		fixture.distance_fade_length = 5.0
		fixture.distance_fade_shadow = 8.0
		add_child(fixture)


func _stock_locker(rack: MeshInstance3D) -> void:
	# Spare pieces of the wearable suit share their meshes and textures with the
	# pilot after this temporary hierarchy is freed.
	var stock := PilotGear.instantiate() as Node3D
	var glove: MeshInstance3D = stock.find_child("GloveL",true,false)
	var fabric := glove.mesh.surface_get_material(0) as StandardMaterial3D
	fabric.vertex_color_use_as_albedo = true
	_shelve(stock,rack,"Head",Vector3(.014,1.303,.399),Basis(Vector3.UP,PI+.16))
	for side: float in [-1.0,1.0]:
		var hand := "L" if side < 0.0 else "R"
		var folded := Basis(Vector3.UP,-side*1.41) * Basis(Vector3.BACK,side*PI*.5)
		_shelve(stock,rack,"Glove"+hand,Vector3(side*.085,.808,.379),folded)
		_shelve(stock,rack,"Boot"+hand,Vector3(side*.090,.197,.389),Basis(Vector3.UP,PI-.12*side))
	stock.free()


func _shelve(stock: Node3D, rack: MeshInstance3D, part: String, at: Vector3, pose: Basis) -> void:
	var original: MeshInstance3D = stock.find_child(part,true,false)
	var spare := MeshInstance3D.new()
	spare.name = part
	spare.mesh = original.mesh
	var bounds := Transform3D(pose,Vector3.ZERO) * spare.mesh.get_aabb()
	spare.transform = Transform3D(pose,at - Vector3.UP*bounds.position.y)
	spare.visibility_range_end = 13.0
	rack.add_child(spare)


func _threshold() -> void:
	_box("Rail",Vector3(0,.002,.03),Vector3(WALL_OPENING,.004,.75))
	for z: float in [-.28,-.24,.30,.34]:
		_box("Steel",Vector3(0,.0045,z),Vector3(WALL_OPENING,.001,.008))
	# The boxed track has two lower running flanges. The hanger straps pass
	# between them and the paired carriage wheels bear on the upper faces.
	_box("Steel",Vector3(0,2.475,LEAF_Z),Vector3(4.88,.025,.20))
	for cheek: float in [-1.0,1.0]:
		_box("Steel",Vector3(0,2.429,LEAF_Z+cheek*.091),Vector3(4.88,.067,.018))
		_box("Rail",Vector3(0,2.390,LEAF_Z+cheek*.0645),Vector3(4.88,.012,.071))
	_box("Girder",Vector3(0,2.555,.26),Vector3(4.92,.21,.28))
	for side: float in [-1.0,1.0]:
		# Both cheeks return into the opening but stop at the brushed pocket throat.
		_hall._block(position+Vector3(side*1.215,1.192,-.153),Vector3(.11,2.384,.431))
		_hall._block(position+Vector3(side*1.215,1.192,.328),Vector3(.11,2.384,.249))
		_box("Girder",Vector3(side*1.209,1.192,-.087),Vector3(.076,2.384,.349))
		_box("Girder",Vector3(side*1.209,1.192,.288),Vector3(.076,2.384,.19))
		_box("Plinth",Vector3(side*1.190,1.19,.076),Vector3(.038,2.36,.014))
		_box("Plinth",Vector3(side*1.190,1.19,.201),Vector3(.038,2.36,.014))
	for portal_face: float in [-.36,.43]:
		_box("Plinth",Vector3(0,2.51,portal_face),Vector3(.24,.085,.065))
		_box("Green",Vector3(.083,2.51,portal_face+signf(portal_face)*.036),Vector3(.019,.016,.008))


func _fit_doors(finishes: Dictionary) -> void:
	var mesh := _leaf_mesh(finishes)
	var shape := BoxShape3D.new()
	shape.size = Vector3(LEAF_WIDTH,LEAF_HEIGHT,.072)
	for side: float in [-1.0,1.0]:
		var leaf := AnimatableBody3D.new()
		leaf.name = "WestLeaf" if side < 0.0 else "EastLeaf"
		leaf.sync_to_physics = false
		leaf.position = Vector3(side*LEAF_WIDTH*.5,.012,LEAF_Z)
		if side > 0.0:
			leaf.rotation.y = PI
		var panel := MeshInstance3D.new()
		panel.mesh = mesh
		panel.name = "PressedSteel"
		leaf.add_child(panel)
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		collider.shape = shape
		collider.position.y = LEAF_HEIGHT*.5
		leaf.add_child(collider)
		add_child(leaf)
		_leaves.append(leaf)

	var detector := Area3D.new()
	detector.name = "Approach"
	detector.collision_layer = 0
	detector.collision_mask = 2 # Standing pilot capsule.
	detector.monitorable = false
	var zone := BoxShape3D.new()
	zone.size = Vector3(3.20,2.36,4.30)
	var trigger := CollisionShape3D.new()
	trigger.shape = zone
	trigger.position = Vector3(0,1.18,LEAF_Z)
	detector.add_child(trigger)
	detector.body_entered.connect(_approach_entered)
	detector.body_exited.connect(_approach_exited)
	add_child(detector)


func _approach_entered(_body: Node3D) -> void:
	_occupants += 1
	_dwell = 0.0
	if not _opening:
		_opening = true
		motion_started.emit(true)
	set_physics_process(true)


func _approach_exited(_body: Node3D) -> void:
	_occupants = maxi(0,_occupants-1)
	if _occupants == 0:
		_dwell = DWELL
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _occupants == 0 and _opening:
		_dwell -= delta
		if _dwell <= 0.0:
			_opening = false
			motion_started.emit(false)
	var goal := 1.0 if _opening else 0.0
	var previous := _travel
	_travel = move_toward(_travel,goal,delta/(OPEN_TIME if _opening else CLOSE_TIME))
	if _travel != previous:
		open_fraction = smoothstep(0.0,1.0,_travel)
		var offset := LEAF_WIDTH*.5 + open_fraction*SLIDE
		_leaves[0].position.x = -offset
		_leaves[1].position.x = offset
		if _travel == goal:
			motion_finished.emit(_opening)
	if _travel == goal and (_occupants > 0 or not _opening):
		set_physics_process(false)


func _rounded_profile(half_width: float, bottom: float, top: float, radius: float, center_x := 0.0) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var centers := [Vector2(half_width-radius,top-radius),Vector2(-half_width+radius,top-radius),
		Vector2(-half_width+radius,bottom+radius),Vector2(half_width-radius,bottom+radius)]
	for corner in 4:
		for step in 6:
			var angle := (corner+step/5.0)*PI*.5
			outline.append(centers[corner] + Vector2(center_x,0) + Vector2(cos(angle),sin(angle))*radius)
	return outline


func _ring(st: SurfaceTool, outer: PackedVector2Array, outer_z: float, inner: PackedVector2Array,
		inner_z: float, face: float) -> void:
	for i in outer.size():
		var j := (i+1)%outer.size()
		var a := Vector3(outer[i].x,outer[i].y,outer_z)
		var b := Vector3(outer[j].x,outer[j].y,outer_z)
		var c := Vector3(inner[j].x,inner[j].y,inner_z)
		var d := Vector3(inner[i].x,inner[i].y,inner_z)
		# The loops wind CCW around the panel. Positive face is the front (+Z).
		var normal := (b-a).cross(c-a).normalized()*face
		for pt: Vector3 in ([a,c,b,a,d,c] if face > 0 else [a,b,c,a,c,d]):
			st.set_normal(normal)
			st.set_uv(Vector2(pt.x,pt.y))
			st.add_vertex(pt)


func _cap(st: SurfaceTool, loop: PackedVector2Array, z: float, face: float) -> void:
	var center := Vector2.ZERO
	for point in loop:
		center += point
	center /= loop.size()
	for i in loop.size():
		var j := (i+1)%loop.size()
		for point: Vector2 in ([center,loop[j],loop[i]] if face > 0 else [center,loop[i],loop[j]]):
			st.set_normal(Vector3.BACK*face)
			st.set_uv(point)
			st.add_vertex(Vector3(point.x,point.y,z))


# A pressed plate seats on the panel skin and turns through a small exposed radius.
func _plate(st: SurfaceTool, center: Vector2, size: Vector2, radius: float, face: float,
		back: float, top: float, bevel: float) -> void:
	var lo := center.y-size.y*.5
	var hi := center.y+size.y*.5
	var rim := _rounded_profile(size.x*.5,lo,hi,radius,center.x)
	var surface := _rounded_profile(size.x*.5-bevel,lo+bevel,hi-bevel,radius-bevel,center.x)
	_ring(st,rim,back*face,rim,(top-bevel)*face,face)
	_ring(st,rim,(top-bevel)*face,surface,top*face,face)
	_cap(st,surface,top*face,face)


func _keyway(metal: SurfaceTool, dark: SurfaceTool, center: Vector2, radius: float, z: float,
		face: float, socket_sides: int) -> void:
	var skirt := PackedVector2Array()
	var rim := PackedVector2Array()
	var socket := PackedVector2Array()
	var step := TAU/socket_sides
	var segments := 24 if socket_sides == 3 else 12
	for i in segments:
		var theta := TAU*i/segments
		var ray := Vector2(cos(theta+PI*.5),sin(theta+PI*.5))
		skirt.append(center + radius*ray)
		rim.append(center + radius*.89*ray)
		# Sample the straight walls of the actual triangular or hex key socket.
		var flat := cos(step*.5) / cos(fposmod(theta,step)-step*.5)
		socket.append(center + radius*.54*flat*ray)
	var top := z+radius*.22
	_ring(metal,skirt,z*face,rim,top*face,face)
	_ring(metal,rim,top*face,socket,top*face,face)
	_ring(metal,socket,top*face,socket,(z+.0004)*face,face)
	_cap(dark,socket,(z+.0004)*face,face)


func _carriage(metal: SurfaceTool, x: float) -> void:
	var strap := _rounded_profile(.031,LEAF_HEIGHT-.014,LEAF_HEIGHT+.068,.008,x)
	_ring(metal,strap,-.010,strap,.010,1.0)
	_cap(metal,strap,-.010,-1.0)
	_cap(metal,strap,.010,1.0)
	var axle := PackedVector2Array()
	var wheel := PackedVector2Array()
	for i in 16:
		var ray := Vector2(cos(TAU*i/16),sin(TAU*i/16))
		var center := Vector2(x,LEAF_HEIGHT+.050)
		axle.append(center+.009*ray)
		wheel.append(center+.026*ray)
	_ring(metal,axle,-.067,axle,.067,1.0)
	for side: float in [-1.0,1.0]:
		_cap(metal,axle,.067*side,side)
		_ring(metal,wheel,.046*side,wheel,.064*side,side)
		_ring(metal,wheel,.064*side,axle,.064*side,side)
		_ring(metal,wheel,.046*side,axle,.046*side,-side)


func _leaf_mesh(finishes: Dictionary) -> ArrayMesh:
	var panel := ArrayMesh.new()
	var st := SurfaceTool.new()
	var half_skin := (LEAF_WIDTH-MEETING_SEAL)*.5
	var edge := _rounded_profile(half_skin,0,LEAF_HEIGHT,.013,-MEETING_SEAL*.5)
	var skin := _rounded_profile(half_skin-.004,.004,LEAF_HEIGHT-.004,.011,-MEETING_SEAL*.5)
	var window := _rounded_profile(.265,1.10,2.09,.064)
	var lip := _rounded_profile(.248,1.117,2.073,.054)
	var gasket := _rounded_profile(.237,1.128,2.062,.043)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(st,edge,-.031,edge,.031,1.0)
	for face: float in [-1.0,1.0]:
		_ring(st,edge,.031*face,skin,.036*face,face)
		_ring(st,skin,.036*face,window,.036*face,face)
	st.index()
	st.commit(panel)
	panel.surface_set_material(0,finishes.Enamel)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: float in [-1.0,1.0]:
		_ring(st,window,.036*face,lip,.042*face,face)
		_ring(st,lip,.042*face,gasket,.027*face,face)
	st.index()
	st.commit(panel)
	panel.surface_set_material(1,finishes.Rail)
	var rubber := SurfaceTool.new()
	rubber.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring(rubber,gasket,-.027,gasket,.027,-1.0)
	var join_x := (LEAF_WIDTH-MEETING_SEAL)*.5
	var seal := _rounded_profile(MEETING_SEAL*.5,.003,LEAF_HEIGHT-.003,.003,join_x)
	var crown := _rounded_profile(MEETING_SEAL*.5-.0015,.005,LEAF_HEIGHT-.005,.002,join_x)
	_ring(rubber,seal,-.034,seal,.034,1.0)
	var trim := SurfaceTool.new()
	trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-.38,.38]:
		_carriage(trim,x)
	for face: float in [-1.0,1.0]:
		_ring(rubber,seal,.034*face,crown,.039*face,face)
		_cap(rubber,crown,.039*face,face)
		_plate(trim,Vector2(0,.18),Vector2(LEAF_WIDTH-.058,.30),.012,face,.0358,.041,.0015)
		_plate(trim,Vector2(.482,1.03),Vector2(.084,.165),.008,face,.0358,.044,.002)
		_keyway(trim,rubber,Vector2(.482,1.03),.025,.044,face,3)
		for x: float in [-.526,.526]:
			for y: float in [.061,.299]:
				_keyway(trim,rubber,Vector2(x,y),.0075,.041,face,6)
		for y: float in [.970,1.090]:
			_keyway(trim,rubber,Vector2(.482,y),.005,.044,face,6)
	rubber.index()
	rubber.commit(panel)
	var polymer := StandardMaterial3D.new()
	polymer.albedo_color = Color("#263134")
	polymer.roughness = .76
	panel.surface_set_material(2,polymer)
	trim.index()
	trim.commit(panel)
	panel.surface_set_material(3,finishes.Rail)
	# One pane surface, viewed from either side, without two alpha-sorted skins.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in gasket.size():
		var j := (i+1)%gasket.size()
		for point: Vector2 in [Vector2(0,1.595),gasket[j],gasket[i]]:
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(point.x,point.y,0.0))
	st.index()
	st.commit(panel)
	panel.surface_set_material(4,_glazing)
	return panel
