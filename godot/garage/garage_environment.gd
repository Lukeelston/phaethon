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
const GlassFinish := preload("res://garage/workshop_glazing.gdshader")
const IndicatorFinish := preload("res://garage/service_indicator.gdshader")
const BlockFinish := preload("res://garage/workshop_blockwork.gdshader")
const CladdingFinish := preload("res://garage/workshop_cladding.gdshader")
const Aggregate := preload("res://art/road/pavement_detail.png")
const PowderRelief := preload("res://art/finish/powder_normal.png")
const WorkshopPanorama := preload("res://garage/workshop_reflections.hdr")
const HALF_X := 35.0
const HALF_Z := 23.5
const EAVES := 7.6
const WINDOW_SPACING := 7.5
const WINDOW_WIDTH := 6.9
const WINDOW_HEIGHT := 1.85
const WINDOW_Y := 5.80
const WINDOW_HALF_COUNT := 4
const BAY_X := 5.2
const ROW_SPACING := 14.0

# Fore and aft rubber shoe settings, measured on the underside of the parked
# meshes. Each pair records the shoe centre (outboard, above floor, fore/aft)
# in metres and the local skin slope (outboard, fore/aft). Mirror for the left shoe.
const STANDARD_POD_SHOES := [
	[Vector3(.30,.690,-.15), Vector2(.038,-.056)], [Vector3(.32,.785,0), Vector2(.037,.107)]]
const FLEET_POD_SHOES := [
	[Vector3(.32,.708,0), Vector2(.003,-.075)], [Vector3(.32,.818,0), Vector2(.001,.194)]]
const ENGINE_SHOES := {
	Pilot.STANDARD: [[Vector3(.30,1.084,0),Vector2(.003,.009)], [Vector3(.32,1.143,0),Vector2(.003,.050)]],
	Pilot.SHRIKE: [[Vector3(.30,1.045,0),Vector2(.040,-.025)], [Vector3(.30,1.103,0),Vector2(.038,.032)]],
	Pilot.ORRERY: [[Vector3(.30,.473,.08),Vector2(.157,0)], [Vector3(.22,1.167,0),Vector2(.183,-.098)]],
	Pilot.KILN: [[Vector3(.32,1.022,0),Vector2(.006,-.008)], [Vector3(.32,.929,0),Vector2(.006,-.518)]],
	Pilot.VESPER: [[Vector3(.56,1.525,0),Vector2(-.096,-.065)], [Vector3(.28,1.257,0),Vector2(-.016,-.091)]],
	Pilot.BASILISK: [[Vector3(.32,.990,0),Vector2(.008,.017)], [Vector3(.30,1.008,0),Vector2(.007,.022)]],
}

var _bays := {}
var _gates := {}
var _finishes := {}
var _instances := {}
var _building: StaticBody3D
var _service_lenses := MultiMesh.new()
var _lamp_states := PackedByteArray()


func _ready() -> void:
	build()


func build() -> void:
	if is_instance_valid(_building):
		return
	_building = StaticBody3D.new()
	_building.name = "WorkshopStructure"
	add_child(_building)
	var cladding := ShaderMaterial.new()
	cladding.shader = CladdingFinish
	_finishes["Wall"] = cladding
	_instances["Wall"] = []
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
	var glass := ShaderMaterial.new()
	glass.shader = GlassFinish
	_finishes["Panes"] = glass
	_instances["Panes"] = []
	var masonry := ShaderMaterial.new()
	masonry.shader = BlockFinish
	masonry.set_shader_parameter("aggregate", Aggregate)
	_finishes["Blockwork"] = masonry
	_instances["Blockwork"] = []
	_material("Lamps", "#ffebcc", .08, .35, 2.6)
	_material("Green", "#88e1c6", .12, .45, .85)
	_lighting()
	_hall()
	_build_service_lenses()
	var selected := Settings.selected_craft()
	var paint := Settings.choice("paint", Livery.ids())
	if Route.arrival_craft in Pilot.ORDER:
		selected = Route.arrival_craft
		if Livery.TABLE.has(Route.arrival_paint):
			paint = Route.arrival_paint
	var gate_centers := PackedVector2Array()
	for i in Pilot.ORDER.size():
		var id: String = Pilot.ORDER[i]
		_berth(id, i, Route.bay_paint(id, paint if id == selected else Livery.FACTORY))
		var gate: Vector3 = _gates[id].origin
		gate_centers.append(Vector2(gate.x, gate.z))
	var floor_finish: ShaderMaterial = $SealedConcrete.material_override
	floor_finish.set_shader_parameter("gate_centers", gate_centers)
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
	env.ambient_light_color = Color("#d6e4eb")
	env.ambient_light_energy = .65
	env.ambient_light_sky_contribution = .20
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.10
	world.environment = env
	add_child(world)
	var daylight := DirectionalLight3D.new()
	daylight.name = "ClerestoryDaylight"
	# Low daylight crosses the hall from the entrance windows. The opaque roof
	# and window piers cut the beam; their shadow is shared by every bay.
	daylight.rotation_degrees = Vector3(-21.0, -22.0, 0.0)
	daylight.light_color = Color("#ffedd4")
	daylight.light_energy = 1.55
	daylight.shadow_enabled = true
	daylight.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	daylight.directional_shadow_max_distance = 55.0
	add_child(daylight)
	# The six central work lamps sit over the pods, with bounded, overlapping
	# pools. Their light comes from the diffuser, 6 m above the shop floor.
	for row in [-ROW_SPACING,0.0,ROW_SPACING]:
		for x in [-6.0, 6.0]:
			var pool := SpotLight3D.new()
			pool.position = Vector3(x, 5.96, row)
			pool.rotation_degrees.x = -90.0
			pool.light_color = Color("#fff0df")
			pool.light_energy = 4.6
			pool.spot_range = 10.0
			pool.spot_angle = 56.0
			pool.spot_attenuation = 0.95
			pool.spot_angle_attenuation = 0.65
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
	concrete.set_shader_parameter("contact", preload("res://garage/workshop_contact.png"))
	concrete.set_shader_parameter("floor_size", floor_mesh.size)
	floor_node.material_override = concrete
	add_child(floor_node)
	_block(Vector3(0,-.15,0),Vector3(HALF_X*2+.5,.30,HALF_Z*2+.5))
	for side in [-1.0,1.0]:
		_wall(Vector3(side*(HALF_X+.12),EAVES*.5,0),Vector3(.24,EAVES,2*HALF_Z))
		_wall(Vector3(0,EAVES*.5,side*(HALF_Z+.12)),Vector3(2*HALF_X+.48,EAVES,.24))
		_box("Blockwork", Vector3(side*(HALF_X-.07),.67,0), Vector3(.14,1.34,2*HALF_Z))
		_box("Blockwork", Vector3(0,.67,side*(HALF_Z-.07)), Vector3(2*HALF_X,1.34,.14))
		_box("Enamel", Vector3(0,2.24,side*(HALF_Z-.11)),Vector3(2*HALF_X,.30,.055))
		_box("Rail", Vector3(side*(HALF_X-.22),3.80,0),Vector3(.09,.09,HALF_Z*2))
		for row in [-ROW_SPACING,0.0,ROW_SPACING]:
			_shutter(side,row)
	for ix in range(-WINDOW_HALF_COUNT, WINDOW_HALF_COUNT + 1):
		var x := WINDOW_SPACING * ix
		for side in [-1.0,1.0]:
			_box("Panes", Vector3(x,WINDOW_Y,side*(HALF_Z-.17)), Vector3(WINDOW_WIDTH,WINDOW_HEIGHT,.11))
			for dx in [-3.5,-1.75,0.0,1.75,3.5]:
				_box("Steel",Vector3(x+dx,5.80,side*(HALF_Z-.25)),Vector3(.09,2.0,.065))
			_box("Steel",Vector3(x,5.78,side*(HALF_Z-.25)),Vector3(7.1,.07,.07))
			_box("Girder",Vector3(x,4.82,side*(HALF_Z-.25)),Vector3(7.1,.10,.19))
			_box("Steel", Vector3(x,6.77,side*(HALF_Z-.24)), Vector3(7.12,.12,.18))
	# Each run of glazing bears on the same columns as the insulated wall below it.
	for col in range(-WINDOW_HALF_COUNT, WINDOW_HALF_COUNT + 2):
		var x := (col - .5) * WINDOW_SPACING
		for side: float in [-1.0, 1.0]:
			_box("Girder", Vector3(x,3.8,side*(HALF_Z-.15)), Vector3(.18,7.6,.25))
			_box("Steel", Vector3(x,.38,side*(HALF_Z-.20)), Vector3(.29,.76,.29))
	# A continuous roof sits above the exposed trusses and their corrugated lining.
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
	_service_entry()
	_bench(Vector3(-12,0,-21.5))
	_bench(Vector3(12,0,21.5))


## A closed pair of service doors terminates the walking aisle. The side returns,
## lintel and intake louvres give the flat end wall depth from the approach.
func _service_entry() -> void:
	var wall := Vector3(0,0,-HALF_Z)
	_box("Wall", wall+Vector3(0,1.42,.16), Vector3(8.9,2.84,.32))
	_block(wall+Vector3(0,1.40,.21), Vector3(8.9,2.80,.42))
	_box("Steel", wall+Vector3(0,1.24,.34), Vector3(2.40,2.48,.13))
	# The jamb stands proud of the two leaves, including their upper sight panes.
	for side: float in [-1.0,1.0]:
		var door := wall+Vector3(side*.551,0,0)
		_box("Enamel", door+Vector3(0,1.16,.423), Vector3(1.08,2.29,.055))
		_box("Rail", door+Vector3(0,.195,.459), Vector3(1.03,.30,.010))
		_box("Plinth", door+Vector3(-side*.18,1.68,.460), Vector3(.245,.61,.026))
		_box("Panes", door+Vector3(-side*.18,1.68,.474), Vector3(.198,.56,.008))
		_box("Steel", door+Vector3(0,1.00,.468), Vector3(.77,.10,.043))
		_box("Rail", door+Vector3(0,1.00,.510), Vector3(.65,.059,.046))
		_box("Girder", wall+Vector3(side*1.173,1.25,.396), Vector3(.11,2.50,.16))
		# Blades tilt down toward the room. The dark plenum stays visible between them.
		var vent := wall+Vector3(side*2.83,1.69,0)
		_box("Girder", vent+Vector3(0,0,.346), Vector3(2.36,1.17,.09))
		_box("Plinth", vent+Vector3(0,0,.404), Vector3(2.24,1.05,.035))
		for blade in 7:
			_box("RoofRibs", vent+Vector3(0,(blade-3)*.141,.454),
				Vector3(2.17,.054,.105), Basis(Vector3.RIGHT,.39))
		_box("Rail", vent+Vector3(0,-.582,.436), Vector3(2.40,.065,.19))
		_box("Steel", wall+Vector3(side*4.41,1.42,.285), Vector3(.14,2.84,.46))
		_strut("Girder", wall+Vector3(side*3.89,2.53,.36), wall+Vector3(side*3.89,2.82,.89), .085)
	_box("Girder", wall+Vector3(0,2.444,.398), Vector3(2.45,.12,.17))
	_box("Plinth", wall+Vector3(0,2.87,.47), Vector3(9.02,.13,.99))
	_box("Enamel", wall+Vector3(0,3.108,.895), Vector3(9.02,.48,.14))
	_box("Rail", wall+Vector3(0,3.37,.49), Vector3(9.14,.058,1.03))
	_box("Lamps", wall+Vector3(0,2.792,.716), Vector3(1.64,.025,.12))
	_label("FLEET WORKSHOP", wall+Vector3(0,3.106,.975), Basis.IDENTITY,.0088,48)


func _shutter(side: float, row: float) -> void:
	var x := side*(HALF_X-.17)
	_box("Steel",Vector3(x,2.46,row),Vector3(.18,4.92,11.45))
	for i in 13:
		_box("Girder",Vector3(x-side*.125,.22+i*.35,row),Vector3(.075,.31,10.87))
	for dz in [-5.57,5.57]:
		_box("Steel", Vector3(x-side*.12,2.43,row+dz), Vector3(.19,4.86,.27))
		_box("Crane",Vector3(x-side*.237,1.50,row+dz),Vector3(.082,3.00,.13))
	_box("Steel", Vector3(x-side*.182,.065,row), Vector3(.15,.10,10.93))
	_box("Girder", Vector3(x-side*.204,4.95,row), Vector3(.33,.29,11.6))
	_box("Steel", Vector3(x-side*.37,4.85,row), Vector3(.085,.080,11.62))
	# A light mounted to the end of the roller hood identifies the closed bay door.
	_box("Plinth", Vector3(x-side*.382,4.98,row-4.85), Vector3(.085,.24,.47))
	_box("Green",Vector3(x-side*.435,4.98,row-4.85),Vector3(.047,.12,.32))
	var bay_number := 1+2*roundi((ROW_SPACING-row)/ROW_SPACING)+(1 if side > 0 else 0)
	var face := Basis.looking_at(Vector3(-side,0,0), Vector3.UP, true)
	_label("%02d" % bay_number,Vector3(x-side*.171,2.68,row),face,.015,78)


func _bench(at: Vector3) -> void:
	var face := Basis(Vector3.UP, PI) if at.z > 0.0 else Basis.IDENTITY
	_workshop_fixture("MachineBench",at,face)
	_block(at+Vector3.UP*.494,Vector3(3.18,.988,.89),face)
	# The uprights rise off the rear lip. The diffuser sits in front of the tool
	# board to light its faces and throw the vise shadow across the worktop.
	for x: float in [-1.30,1.30]:
		_box("Steel", at+face*Vector3(x,1.56,-.40),Vector3(.045,1.15,.045),face)
		_box("Girder",at+face*Vector3(x,2.12,-.14),Vector3(.046,.045,.56),face)
	_box("Steel",at+face*Vector3(0,2.12,.14),Vector3(2.74,.085,.19),face)
	_box("Lamps",at+face*Vector3(0,2.072,.14),Vector3(2.63,.016,.14),face)
	var task_light := SpotLight3D.new()
	task_light.transform = Transform3D(
		face * Basis(Vector3.RIGHT, deg_to_rad(-75.0)), at + face * Vector3(0,2.05,.15))
	task_light.light_color = Color("#fff1d9")
	task_light.light_energy = 3.5
	task_light.spot_angle = 69.0
	task_light.spot_range = 3.1
	task_light.spot_attenuation = .70
	task_light.shadow_enabled = true
	task_light.shadow_bias = .035
	task_light.distance_fade_enabled = true
	task_light.distance_fade_begin = 12.0
	task_light.distance_fade_shadow = 8.0
	task_light.distance_fade_length = 5.0
	add_child(task_light)


func _tool_cart(at: Vector3) -> void:
	var face := Basis(Vector3.UP, -signf(at.x)*PI*.5)
	_workshop_fixture("RollCabinet",at,face)
	_block(at+face*Vector3(.038,.45,.017),Vector3(1.216,.90,.638),face)


func _workshop_fixture(id: String, at: Vector3, face: Basis) -> void:
	# Both fixtures share the imported finish atlas. Keep only the requested mesh.
	var kit := preload("res://garage/workshop_equipment.glb").instantiate()
	var piece := kit.find_child(id,true,false) as MeshInstance3D
	piece.get_parent().remove_child(piece)
	kit.free()
	piece.transform = Transform3D(face,at)
	add_child(piece,true)


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
	# Keep the entire painted opening clear of a broad coaming like Vesper's.
	var shell_bounds: AABB = bay.model.pod.transform * bay.model.pod.mesh.get_aabb()
	var shell_edge := side * shell_bounds.get_center().x + shell_bounds.size.x * .5
	var approach_offset := maxf(2.45, shell_edge + .85)
	var approach := bay.transform * Vector3(side*approach_offset,-Parked.SHELL_HEIGHT,.54)
	var seat := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,.54)
	_gates[id] = Transform3D(Basis.looking_at(seat-approach, Vector3.UP), approach)
	# Wide gates at the aisle, and low removable stands under real service points.
	for dz in [-5.60,5.60]:
		_box("White", Vector3(side*17.6,.006,row+dz),Vector3(25.3,.012,.067))
	if index in [0,3,4]:
		_tool_cart(Vector3(side*10.3,0,row+4.25))
	var pod_shoes := STANDARD_POD_SHOES if id in [Pilot.STANDARD,Pilot.SHRIKE] else FLEET_POD_SHOES
	for station in 2:
		var p := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,[-.95,1.03][station])
		_stand(p,1.41,bay.basis,pod_shoes[station])
	for center in bay.engine_centers:
		for station in 2:
			var p := bay.transform * (center+Vector3(0,-Parked.ENGINE_HEIGHT,[-1.38,1.45][station]))
			_stand(p,1.30,bay.basis,ENGINE_SHOES[id][station])
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
	# The entrance pair sits closer to its crossing. Open the fold just enough
	# to leave a metre between the tips and the center of the marked gate.
	var gate: Transform3D = _gates[id]
	var wing_z := clampf((sign_z - gate.origin.z - 1.0) / width, 0.0, .80)
	var wing_x := sqrt(1.0 - wing_z*wing_z)
	var words := "%02d   %s" % [index+1, Pilot.NAMES[id].to_upper()]
	_box("Steel",post-Vector3.UP*.73,Vector3(.095,1.46,.095))
	_box("Plinth",post-Vector3.UP*1.40,Vector3(.40,.12,.33))
	_block(post-Vector3.UP*.73,Vector3(.15,1.46,.15))
	# The rail joins the backs of the two wings to the post.
	_box("Steel",post-Vector3.UP*.13,Vector3(.08,.10,maxf(.08,wing_z/wing_x)))
	for toward: float in [-1.0,1.0]:
		var face := Basis.looking_at(Vector3(-side*wing_z,0,toward*wing_x), Vector3.UP, true)
		var along := Vector3(side*wing_x,0,toward*wing_z)
		var panel := nose + along * (width*.5)
		_box("Enamel",panel,Vector3(width,.43,.056),face)
		_box("Safety",panel+face*Vector3(-.775,0,.031),Vector3(.035,.33,.006),face)
		_label(words,panel+face*Vector3(.022,.006,.035),face,.0039,48)
		_block(panel,Vector3(width,.43,.056),face)
	_service_indicators(post, side, index)
	_bays[id].engine_stage_changed.connect(_set_service_indicator.bind(index))


func _build_service_lenses() -> void:
	var glass := CylinderMesh.new()
	glass.top_radius = .048
	glass.bottom_radius = .052
	glass.height = .066
	glass.radial_segments = 12
	glass.rings = 0
	glass.cap_top = false
	glass.cap_bottom = false
	var finish := ShaderMaterial.new()
	finish.shader = IndicatorFinish
	glass.material = finish
	_service_lenses.transform_format = MultiMesh.TRANSFORM_3D
	_service_lenses.use_custom_data = true
	_service_lenses.mesh = glass
	_service_lenses.instance_count = Pilot.ORDER.size() * 2
	_lamp_states.resize(_service_lenses.instance_count)
	var fixture := MultiMeshInstance3D.new()
	fixture.name = "BayEngineIndicators"
	fixture.multimesh = _service_lenses
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fixture)


func _service_indicators(post: Vector3, side: float, index: int) -> void:
	# The port and starboard windows sit above both sign wings. Their slight
	# diagonal preserves engine order across opposed bays and separates them on approach.
	var frame := Basis(Vector3.UP, -side * .23)
	_box("Steel", post + Vector3.UP * .112, Vector3(.094,.224,.094))
	_box("Girder", post + Vector3.UP * .244, Vector3(.39,.040,.131), frame)
	for engine in 2:
		var socket := post + frame * Vector3((engine - .5) * .246,.264,0)
		_box("Plinth", socket + Vector3.UP * .014, Vector3(.118,.028,.118), frame)
		_box("Steel", socket + Vector3.UP * .101, Vector3(.112,.014,.112), frame)
		var lens := index * 2 + engine
		_service_lenses.set_instance_transform(lens, Transform3D(frame, socket + Vector3.UP * .061))
		_service_lenses.set_instance_custom_data(lens, Color(0,0,0,1))


func _set_service_indicator(engine: int, stage: String, bay: int) -> void:
	var state := 0
	if stage == "run":
		state = 2
	elif stage == "crank" or stage == "catch":
		state = 1
	var lens := bay * 2 + engine
	if _lamp_states[lens] != state:
		_lamp_states[lens] = state
		_service_lenses.set_instance_custom_data(lens, Color(state * .5,0,0,1))


func _stand(floor_point: Vector3, width: float, axes: Basis, setting: Array) -> void:
	var pickup: Vector3 = setting[0]
	var slope: Vector2 = setting[1]
	var head := floor_point + axes.z * pickup.z
	# Leave space for the keel between the screw jacks. Vesper's forward shoes
	# are spread wide enough to land on the two runners.
	var rail_top := pickup.y - .23
	var rail_width := maxf(width*.79, 2.0*(pickup.x+.075))
	_box("Steel",floor_point+Vector3.UP*.074,Vector3(.15,.080,width+.040))
	_box("Crane",head+Vector3.UP*(rail_top-.061),Vector3(.29,.10,rail_width-.02))
	_box("Steel",head+Vector3.UP*(rail_top-.008),Vector3(.30,.016,rail_width))
	for side: float in [-1.0,1.0]:
		var foot := floor_point + Vector3.UP*.028 + axes.x*(side*width*.43)
		var lower := foot+Vector3.UP*.043
		var upper := head + Vector3.UP*(rail_top-.07) + axes.x*(side*width*.28)
		_box("Steel",foot,Vector3(.54,.056,.20))
		_strut("Girder",lower,upper,.105)
		_strut("Crane",lower,lower.lerp(upper,.38),.135)
		var shoe := head + axes.x*(side*pickup.x) + Vector3.UP*pickup.y
		var normal := axes * Vector3(-side*slope.x,1,-slope.y).normalized()
		var forward := axes * Vector3(0,slope.y,1).normalized()
		var shoe_frame := Basis(normal.cross(forward),normal,forward)
		_box("Steel",shoe-Vector3.UP*.182,Vector3(.11,.096,.11))
		_box("Rail",shoe-Vector3.UP*.093,Vector3(.073,.138,.073))
		_box("Plinth",shoe-normal*.022,Vector3(.12,.044,.16),shoe_frame)


func _label(words: String, at: Vector3, frame: Basis, pixel: float, size: int) -> void:
	var label := Label3D.new()
	label.text = words
	label.transform = Transform3D(frame,at)
	label.font_size = size * 2
	label.pixel_size = pixel * .5
	label.outline_size = 0
	label.double_sided = false
	label.modulate = Color("#f0efdf")
	label.shaded = true
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	add_child(label)


func _material(id: String, hex: String, metal: float, roughness: float, energy := 0.0) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.metallic = metal
	material.roughness = roughness
	if id == "Enamel":
		material.normal_enabled = true
		material.normal_texture = PowderRelief
		material.normal_scale = .22
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3.ONE / .14
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
	if size.z > size.x:
		_box("Wall",at,size)
	else:
		# Keep the actual opening behind each translucent clerestory. The box
		# collider continues across the glass; only the masonry blocks the sun.
		var sill := WINDOW_Y - WINDOW_HEIGHT * .5
		var head := WINDOW_Y + WINDOW_HEIGHT * .5
		_box("Wall",Vector3(at.x, sill * .5, at.z),Vector3(size.x, sill, size.z))
		_box("Wall",Vector3(at.x, (head + EAVES) * .5, at.z),Vector3(size.x, EAVES - head, size.z))
		var pier_width := WINDOW_SPACING - WINDOW_WIDTH
		for ix in range(-WINDOW_HALF_COUNT, WINDOW_HALF_COUNT):
			_box("Wall",Vector3((ix+.5)*WINDOW_SPACING, WINDOW_Y, at.z),Vector3(pier_width, WINDOW_HEIGHT, size.z))
		var outer_jamb := size.x * .5 - WINDOW_HALF_COUNT * WINDOW_SPACING - WINDOW_WIDTH * .5
		for side in [-1.0, 1.0]:
			_box("Wall",Vector3(side * (size.x - outer_jamb) * .5, WINDOW_Y, at.z),Vector3(outer_jamb, WINDOW_HEIGHT, size.z))
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
		if id in ["RoofRibs","Panes","Lamps","Green","White","Safety","Blockwork"]:
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
	_instances.clear()
