## Six full-size tow rigs in opposed service bays. All public transforms are in
## global space. Spawn/boarding origins are on the walking floor; seat is the eye.
extends Node3D

const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Settings := preload("res://release/game_settings.gd")
const Route := preload("res://release/garage_route.gd")
const Parked := preload("res://garage/parked_airframe.gd")
const Seat := preload("res://garage/garage_seat.gd")
const FloorFinish := preload("res://garage/garage_floor.gdshader")
const Aggregate := preload("res://art/road/pavement_detail.png")
const WorkshopPanorama := preload("res://garage/workshop_reflections.hdr")
const HALF_X := 35.0
const HALF_Z := 23.5
const EAVES := 7.6
const BAY_X := 5.2
const ROW_SPACING := 14.0

var _bays := {}
var _gates := {}
var _finishes := {}
var _instances := {}
var _building: StaticBody3D


func _ready() -> void:
	build()


func build() -> void:
	if is_instance_valid(_building):
		return
	_building = StaticBody3D.new()
	_building.name = "WorkshopStructure"
	add_child(_building)
	_material("Wall", "#899697", .20, .68)
	_material("Roof", "#657777", .30, .60)
	_material("RoofRibs", "#758383", .39, .51)
	_material("Steel", "#394e55", .62, .40)
	_material("Girder", "#738486", .65, .38)
	_material("Rail", "#9aafa9", .70, .32)
	_material("Plinth", "#344248", .32, .70)
	_material("Enamel", "#2e605f", .46, .36)
	_material("Crane", "#cd8c43", .49, .38)
	_material("Safety", "#e5b66b", .22, .63)
	_material("White", "#d0d7ce", .18, .56)
	_material("Panes", "#bcd8d7", .10, .37, .43)
	_material("Lamps", "#ffebcc", .08, .35, 2.6)
	_material("Green", "#88e1c6", .12, .45, .85)
	_lighting()
	_hall()
	var selected := Settings.selected_craft()
	var paint := Settings.choice("paint", Livery.ids())
	if Route.arrival_craft in Pilot.ORDER:
		selected = Route.arrival_craft
		if Livery.TABLE.has(Route.arrival_paint):
			paint = Route.arrival_paint
	for i in Pilot.ORDER.size():
		var id: String = Pilot.ORDER[i]
		_berth(id, i, Route.bay_paint(id, paint if id == selected else Livery.FACTORY))
	_batch_structure()


func bay_node(id: String) -> Node3D:
	return _bays.get(id)


func seat_transform(id: String) -> Transform3D:
	var bay := bay_node(id)
	return bay.global_transform * Transform3D(Basis.IDENTITY, Seat.EYE) if bay else global_transform


func boarding_transform(id: String) -> Transform3D:
	return global_transform * _gates[id] if _gates.has(id) else spawn_transform()


func spawn_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0,0,21.45))


func nearest_bay(at: Vector3, radius := 2.4) -> String:
	var local := to_local(at)
	var here := Vector2(local.x,local.z)
	var nearest := ""
	var best_sq := radius * radius
	for id: String in _gates:
		var p: Vector3 = _gates[id].origin
		var d := here.distance_squared_to(Vector2(p.x,p.z))
		if d <= best_sq:
			nearest = id
			best_sq = d
	return nearest


func set_cockpit_visible(id: String, shown: bool) -> void:
	var bay := bay_node(id) as Parked
	if bay:
		bay.model.pod.visible = shown


func _lighting() -> void:
	var world := WorldEnvironment.new()
	world.name = "ShopLight"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# The HDR panorama was captured in this hall, at (0, 3.55, 0). Its strips
	# and clerestory light the metal without allocating a live reflection atlas.
	var sky_paint := PanoramaSkyMaterial.new()
	sky_paint.panorama = WorkshopPanorama
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.sky_material = sky_paint
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d8e3e5")
	env.ambient_light_energy = .75
	env.ambient_light_sky_contribution = .20
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.10
	world.environment = env
	add_child(world)
	var daylight := DirectionalLight3D.new()
	daylight.name = "ClerestoryDaylight"
	daylight.rotation = Vector3(deg_to_rad(-53),deg_to_rad(29),0)
	daylight.light_color = Color("#fff0d8")
	daylight.light_energy = 1.34
	daylight.shadow_enabled = true
	daylight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	daylight.directional_shadow_max_distance = 55.0
	add_child(daylight)
	# Local lamps never cast an additional shadow map. Each covers one pod bench.
	for row in [-ROW_SPACING,0.0,ROW_SPACING]:
		var pool := OmniLight3D.new()
		pool.position = Vector3(0,4.6,row)
		pool.light_color = Color("#ffe4c9")
		pool.light_energy = 1.10
		pool.omni_range = 10.0
		pool.omni_attenuation = 1.4
		add_child(pool)


func _hall() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(HALF_X*2,HALF_Z*2)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SealedConcrete"
	floor_node.mesh = floor_mesh
	var concrete := ShaderMaterial.new()
	concrete.shader = FloorFinish
	concrete.set_shader_parameter("aggregate", Aggregate)
	floor_node.material_override = concrete
	add_child(floor_node)
	_block(Vector3(0,-.15,0),Vector3(HALF_X*2+.5,.30,HALF_Z*2+.5))
	for side in [-1.0,1.0]:
		_wall(Vector3(side*(HALF_X+.12),EAVES*.5,0),Vector3(.24,EAVES,2*HALF_Z))
		_wall(Vector3(0,EAVES*.5,side*(HALF_Z+.12)),Vector3(2*HALF_X+.48,EAVES,.24))
		_box("Plinth", Vector3(side*(HALF_X-.07),.67,0), Vector3(.14,1.34,2*HALF_Z))
		_box("Plinth", Vector3(0,.67,side*(HALF_Z-.07)), Vector3(2*HALF_X,1.34,.14))
		_box("Enamel", Vector3(0,2.24,side*(HALF_Z-.11)),Vector3(2*HALF_X,.30,.055))
		_box("Rail", Vector3(side*(HALF_X-.22),3.80,0),Vector3(.09,.09,HALF_Z*2))
		for row in [-ROW_SPACING,0.0,ROW_SPACING]:
			_shutter(side,row)
	for ix in range(-4,5):
		var x := 7.5 * ix
		for side in [-1.0,1.0]:
			_box("Panes", Vector3(x,5.80,side*(HALF_Z-.17)), Vector3(6.9,1.85,.11))
			for dx in [-3.5,-1.75,0.0,1.75,3.5]:
				_box("Steel",Vector3(x+dx,5.80,side*(HALF_Z-.25)),Vector3(.09,2.0,.065))
			_box("Steel",Vector3(x,5.78,side*(HALF_Z-.25)),Vector3(7.1,.07,.07))
			_box("Girder",Vector3(x,4.82,side*(HALF_Z-.25)),Vector3(7.1,.10,.19))
	# The roof skins lie outside the light's shadow pass, like the luminous
	# glazing. The roof trusses, vehicles and service stands still cast shadows.
	_box("Roof", Vector3(0,EAVES+.15,0),Vector3(2*HALF_X+.5,.22,2*HALF_Z+.5))
	for i in range(-45,46):
		_box("RoofRibs",Vector3(i*.76,EAVES+.007,0),Vector3(.085,.085,HALF_Z*2))
	for iz in [-21.0,-14.0,-7.0,0.0,7.0,14.0,21.0]:
		for side in [-1.0,1.0]:
			_box("Steel",Vector3(side*(HALF_X-.36),3.50,iz),Vector3(.29,7,.33))
			_box("Girder",Vector3(side*(HALF_X-.36),.22,iz),Vector3(.53,.44,.58))
			_box("Steel",Vector3(side*HALF_X*.5,7.21,iz),Vector3(HALF_X,.23,.28))
			for ix in 6:
				var panel := HALF_X/6.0
				var x0: float = side * ix * panel
				var top := Vector3(x0+side*panel*.5,7.2,iz)
				_strut("Girder",Vector3(x0,6.42,iz),top,.105)
				_strut("Girder",top,Vector3(x0+side*panel,6.42,iz),.105)
		_box("Steel",Vector3(0,6.42,iz),Vector3(HALF_X*2,.20,.24))
		for x in [-21.0,-6.0,6.0,21.0]:
			_box("Steel",Vector3(x,6.13,iz),Vector3(3.55,.18,.48))
			_box("Lamps",Vector3(x,6.02,iz),Vector3(3.31,.064,.31))
	for side in [-1.0,1.0]:
		_box("Steel",Vector3(side*30.4,5.70,0),Vector3(.23,.42,2*HALF_Z))
		_box("Rail",Vector3(side*30.4,5.94,0),Vector3(.22,.07,2*HALF_Z))
	# A bridge crane runs along the side rails; its hoist is parked off the aisle.
	for z in [-4.2,-3.2]:
		_box("Crane",Vector3(0,5.91,z),Vector3(61.4,.66,.23))
		_box("Steel",Vector3(0,5.56,z),Vector3(61.4,.065,.33))
	_box("Plinth",Vector3(-17,5.50,-3.7),Vector3(1.7,.47,1.65))
	for x in [-17.24,-16.76]:
		_strut("Steel",Vector3(x,5.36,-3.7),Vector3(x,3.87,-3.7),.027)
	_box("Crane",Vector3(-17,3.80,-3.7),Vector3(.64,.21,.25))
	_box("Enamel",Vector3(0,2.97,-HALF_Z+.20),Vector3(11.0,1.35,.12))
	_label("FLEET WORKSHOP",Vector3(0,2.97,-HALF_Z+.28),Basis.IDENTITY,.010,48)
	_bench(Vector3(-12,0,-21.5))
	_bench(Vector3(12,0,21.5))


func _shutter(side: float, row: float) -> void:
	var x := side*(HALF_X-.17)
	_box("Steel",Vector3(x,2.46,row),Vector3(.18,4.92,11.45))
	for i in 13:
		_box("Girder",Vector3(x-side*.125,.22+i*.35,row),Vector3(.075,.31,10.87))
	for dz in [-5.57,5.57]:
		_box("Crane",Vector3(x-side*.20,1.50,row+dz),Vector3(.12,3.00,.13))
	_box("Green",Vector3(x-side*.22,4.63,row-4.85),Vector3(.09,.16,.36))
	var bay_number := 1+2*roundi((ROW_SPACING-row)/ROW_SPACING)+(1 if side > 0 else 0)
	var face := Basis.looking_at(Vector3(-side,0,0), Vector3.UP, true)
	_label("%02d" % bay_number,Vector3(x-side*.171,2.68,row),face,.015,78)


func _bench(at: Vector3) -> void:
	_box("Enamel",at+Vector3.UP*.49,Vector3(3.05,.88,.77))
	_box("Rail",at+Vector3.UP*.96,Vector3(3.18,.085,.89))
	for x in [-.97,0.0,.97]:
		for y in [.36,.63,.815]:
			_box("Steel",at+Vector3(x,y,.40),Vector3(.85,.035,.026))
	_block(at+Vector3.UP*.48,Vector3(3.18,.96,.89))


func _tool_cart(at: Vector3) -> void:
	_box("Enamel",at+Vector3.UP*.52,Vector3(1.08,.66,.56))
	_box("Steel",at+Vector3.UP*.875,Vector3(1.16,.073,.62))
	_box("Rail",at+Vector3(.61,.80,0),Vector3(.085,.07,.38))
	for y in [.38,.51,.64,.76]:
		_box("Steel",at+Vector3(0,y,.286),Vector3(.97,.018,.018))
		_box("Rail",at+Vector3(0,y+.021,.309),Vector3(.47,.026,.038))
	for x in [-.40,.40]:
		for z in [-.18,.18]:
			_box("Plinth",at+Vector3(x,.105,z),Vector3(.095,.21,.165))
	_block(at+Vector3.UP*.45,Vector3(1.18,.9,.62))


func _berth(id: String, index: int, paint: String) -> void:
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := ROW_SPACING * (1.0 - floori(index/2.0))
	var bay := Parked.new()
	bay.name = id
	bay.position = Vector3(side*BAY_X, Parked.SHELL_HEIGHT, row)
	bay.rotation.y = -side*PI/2
	add_child(bay)
	bay.build(id, paint)
	_bays[id] = bay
	var approach := bay.transform * Vector3(side*2.45,-Parked.SHELL_HEIGHT,.54)
	var seat := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,.54)
	_gates[id] = Transform3D(Basis.looking_at(seat-approach, Vector3.UP), approach)
	# Wide gates at the aisle, and low removable stands under real service points.
	for dz in [-5.60,5.60]:
		_box("White", Vector3(side*17.6,.006,row+dz),Vector3(25.3,.012,.067))
	if index in [0,3,4]:
		_tool_cart(Vector3(side*10.3,0,row+4.25))
	for z in [-.95,1.03]:
		var p := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,z)
		_stand(p, .91,1.41)
	for center in bay.engine_centers:
		for z in [-1.38,1.45]:
			var p := bay.transform * (center+Vector3(0,-Parked.ENGINE_HEIGHT,z))
			_stand(p,.70,1.30)
	for i in 4:
		var p := approach + Vector3((i-1.5)*.26, .008, .23)
		_box("Safety",p,Vector3(.095,.012,.40),Basis(Vector3.UP,-.42))
	_aisle_gate(side, row, approach.z)
	_bay_sign(id, index, side, row)


func _aisle_gate(side: float, row: float, gate_z: float) -> void:
	# Turn the aisle paint out toward the boarding marks. The clear opening
	# lands on the physical approach point, whichever side the pod occupies.
	var edge := side * 2.26
	var row_start := -HALF_Z + .2 if row < 0 else row - ROW_SPACING * .5
	var row_end := HALF_Z - .2 if row > 0 else row + ROW_SPACING * .5
	var near_end := gate_z - .83
	var far_end := gate_z + .83
	for segment: Vector2 in [Vector2(row_start, near_end), Vector2(far_end, row_end)]:
		var middle := (segment.x + segment.y) * .5
		_box("Safety", Vector3(edge,.004,middle), Vector3(.085,.008,segment.y-segment.x))
	for end in [near_end, far_end]:
		_box("Safety", Vector3(edge+side*(.32+.0425),.004,end), Vector3(.64,.008,.085))


func _bay_sign(id: String, index: int, side: float, row: float) -> void:
	# A folded enamel sign can be read on either walk along the aisle. Each
	# face carries both identifiers in a single label, including the far side.
	# Give the entrance pair enough setback to fit in the forward walking view.
	var sign_z := minf(row + 4.90, HALF_Z - 5.80)
	var nose := Vector3(side*2.33,1.46,sign_z)
	var post := nose + Vector3(side*.50,0,0)
	var width := 1.68
	var words := "%02d   %s" % [index+1, Pilot.NAMES[id].to_upper()]
	_box("Steel",post-Vector3.UP*.73,Vector3(.095,1.46,.095))
	_box("Plinth",post-Vector3.UP*1.40,Vector3(.40,.12,.33))
	_block(post-Vector3.UP*.73,Vector3(.15,1.46,.15))
	# The rail joins the backs of the two wings to the post.
	_box("Steel",post-Vector3.UP*.13,Vector3(.08,.10,1.33))
	for toward: float in [-1.0,1.0]:
		var face := Basis.looking_at(Vector3(-side*.80,0,toward*.60), Vector3.UP, true)
		var along := Vector3(side*.60,0,toward*.80)
		var panel := nose + along * (width*.5)
		_box("Enamel",panel,Vector3(width,.43,.056),face)
		_box("Safety",panel+face*Vector3(-.775,0,.031),Vector3(.035,.33,.006),face)
		_label(words,panel+face*Vector3(.022,.006,.035),face,.0039,48)
		_block(panel,Vector3(width,.43,.056),face)


func _stand(floor_point: Vector3, height: float, width: float) -> void:
	_box("Steel",floor_point+Vector3.UP*.060,Vector3(.54,.12,width+.14))
	for sign_x in [-1.0,1.0]:
		_strut("Girder", floor_point+Vector3(.01,.11,sign_x*width*.43),
				floor_point+Vector3(.01,height-.10,sign_x*width*.28),.105)
	_box("Crane",floor_point+Vector3.UP*(height-.13),Vector3(.29,.11,width*.77))
	_box("Plinth",floor_point+Vector3.UP*(height-.047),Vector3(.27,.094,width*.65))


func _label(words: String, at: Vector3, frame: Basis, pixel: float, size: int) -> void:
	var label := Label3D.new()
	label.text = words
	label.transform = Transform3D(frame,at)
	label.font_size = size
	label.pixel_size = pixel
	label.outline_size = 0
	label.double_sided = false
	label.modulate = Color("#f0efdf")
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	add_child(label)


func _material(id: String, hex: String, metal: float, roughness: float, energy := 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.metallic = metal
	material.roughness = roughness
	if energy > 0:
		material.emission_enabled = true
		material.emission = Color(hex)
		material.emission_energy_multiplier = energy
	_finishes[id] = material
	_instances[id] = []


func _box(finish: String, at: Vector3, size: Vector3, frame := Basis.IDENTITY) -> void:
	_instances[finish].append(Transform3D(frame.scaled_local(size),at))


func _strut(finish: String, a: Vector3, b: Vector3, width: float) -> void:
	var delta := b-a
	_box(finish,(a+b)*.5,Vector3(width,delta.length(),width),Basis(Quaternion(Vector3.UP,delta.normalized())))


func _block(center: Vector3, size: Vector3, frame := Basis.IDENTITY) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.transform = Transform3D(frame,center)
	_building.add_child(collider)


func _wall(at: Vector3, size: Vector3) -> void:
	_box("Wall",at,size)
	_block(at,size)


func _batch_structure() -> void:
	var unit := BoxMesh.new()
	for id: String in _instances:
		var transforms: Array = _instances[id]
		if transforms.is_empty():
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = unit
		batch.instance_count = transforms.size()
		for i in transforms.size():
			batch.set_instance_transform(i,transforms[i])
		var piece := MultiMeshInstance3D.new()
		piece.name = id
		piece.multimesh = batch
		piece.material_override = _finishes[id]
		if id in ["Roof","RoofRibs","Wall","Panes","Lamps","Green","White","Safety"]:
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
	_instances.clear()
