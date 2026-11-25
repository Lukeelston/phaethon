## Six full-size tow rigs in opposed service bays. All public transforms are in
## global space. Spawn/boarding origins are on the walking floor; seat is the eye.
extends Node3D

const Pilot := preload("res://sim/pilot_craft.gd")
const Livery := preload("res://view/livery.gd")
const Settings := preload("res://release/game_settings.gd")
const Parked := preload("res://garage/parked_airframe.gd")
const Seat := preload("res://garage/garage_seat.gd")
const ServiceEntry := preload("res://garage/workshop_annex.gd")
const Inspection := preload("res://garage/inspection_station.gd")
const FloorFinish := preload("res://garage/garage_floor.gdshader")
const GlassFinish := preload("res://garage/workshop_glazing.gdshader")
const IndicatorFinish := preload("res://garage/service_indicator.gdshader")
const BlockFinish := preload("res://garage/workshop_blockwork.gdshader")
const CladdingFinish := preload("res://garage/workshop_cladding.gdshader")
const Aggregate := preload("res://art/road/pavement_detail.png")
const PowderRelief := preload("res://art/finish/powder_normal.png")
const WorkshopPanorama := preload("res://garage/workshop_reflections.hdr")
const Equipment := preload("res://garage/workshop_equipment.glb")
const BayLettering := preload("res://art/signs/RG2014D.ttf")
const FloorStencil := preload("res://garage/workshop_direction.png")
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
const MARKER_HEIGHT := 1.055
const DRAIN_X := HALF_X - 1.05
const DRAIN_HALF_WIDTH := .101
const DRAIN_HALF_LENGTH := 5.40

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
var _standing := {}      # bay -> the craft standing in it: its own, or in the Phaethon's the Phaethon or the Talon
var _gates := {}
var _marker_guides: Dictionary[String, Array] = {}
var _finishes := {}
var _instances := {}
var _equipment_meshes: Dictionary[String, Mesh] = {}
var inspection: Inspection
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
	var kit := Equipment.instantiate()
	for item: MeshInstance3D in kit.find_children("*","MeshInstance3D",true,false):
		_equipment_meshes[String(item.name)] = item.mesh
	kit.free()
	for fixture in ["MarkerPost", "MarkerWing", "ShutterFrame", "TrenchGrate",
			"HighBayLamp", "SaddleBase", "SaddleScrew", "SaddleShoe"]:
		_instances[fixture] = []
	# Curtain instances are ordered by the bay number printed on their slats.
	_instances["ShutterCurtain"] = []
	_instances["ShutterCurtain"].resize(Pilot.GARAGE_BAYS.size())
	var shutter_coating := ShaderMaterial.new()
	shutter_coating.shader = preload("res://garage/workshop_shutter.gdshader")
	shutter_coating.set_shader_parameter("numbers", preload("res://garage/workshop_shutter_numbers.png"))
	shutter_coating.set_shader_parameter("powder", PowderRelief)
	_finishes["ShutterCurtain"] = shutter_coating
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
	var gate_centers := PackedVector2Array()
	for i in Pilot.GARAGE_BAYS.size():
		var id: String = Pilot.GARAGE_BAYS[i]
		# Each craft in the paint the menus chose for it, as its flight wears it (view/livery.gd: the Phaethon's
		# "paint", each other craft's "paint_<id>"; Factory is each as designed, the Vesper's Star Command its own).
		# The Phaethon's bay holds the body last chosen there (the Phaethon, or the Talon: Settings.phaethon_body).
		var craft: String = Settings.phaethon_body() if id == Pilot.STANDARD else id
		_berth(id, i, Livery.built(craft), craft)
		var gate: Vector3 = _gates[id].origin
		gate_centers.append(Vector2(gate.x, gate.z))
	var floor_finish: ShaderMaterial = $SealedConcrete.material_override
	floor_finish.set_shader_parameter("gate_centers", gate_centers)
	_batch_structure()
	var back_wall: Transform3D = $ServiceEntry.transform.translated_local(Vector3(0, 0, ServiceEntry.BACK))
	inspection = Inspection.new()
	inspection.install(self, back_wall)


## A bay by its id, or by a craft's: the Talon's is the Phaethon's (sim/pilot_craft.gd bay_of).
func bay_node(id: String) -> Node3D:
	return _bays.get(_bay_key(id))


func _bay_key(id: String) -> String:
	return id if _bays.has(id) else Pilot.bay_of(id)


## The craft standing in a bay.
func bay_craft(id: String) -> String:
	return _standing.get(id, "")


## A bay's craft built again in place (garage.gd: its paint changed), as `craft` in `finish`: the same bay node, so the
## inspection board's and the service lamps' connections, the stands and the gate stay as they are.
func rebuild_bay(id: String, craft: String, finish: String) -> void:
	var bay := bay_node(id) as Parked
	if bay == null:
		return
	bay.rebuild(craft, finish)
	_standing[id] = craft


func seat_transform(id: String) -> Transform3D:
	var bay := bay_node(id)
	return bay.global_transform * Transform3D(Basis.IDENTITY, Seat.EYE) if bay else global_transform


func boarding_transform(id: String) -> Transform3D:
	var key := _bay_key(id)
	return global_transform * _gates[key] if _gates.has(key) else spawn_transform()


func spawn_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0,0,21.45))


func marker_guide(id: String, observer: Vector3) -> Transform3D:
	var faces := _marker_guides[id if _marker_guides.has(id) else Pilot.STANDARD]
	var local_eye := to_local(observer)
	var a: Transform3D = faces[0]
	var b: Transform3D = faces[1]
	var first := a.basis.z.dot(local_eye - a.origin)
	var second := b.basis.z.dot(local_eye - b.origin)
	return global_transform * (a if first > second else b)


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
	daylight.shadow_blur = .65 # Keep the thin window-frame shadows stable as the pilot moves.
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


func _slab() -> ArrayMesh:
	var concrete_rects: Array[Rect2] = []
	var inner := DRAIN_X - DRAIN_HALF_WIDTH
	var outer := DRAIN_X + DRAIN_HALF_WIDTH
	concrete_rects.append(Rect2(-inner,-HALF_Z,inner*2,HALF_Z*2))
	for side in [-1.0,1.0]:
		var lip_x := minf(side*outer,side*HALF_X)
		concrete_rects.append(Rect2(lip_x,-HALF_Z,HALF_X-outer,HALF_Z*2))
		var strip_x := minf(side*outer,side*inner)
		var start := -HALF_Z
		for row: float in [-ROW_SPACING,0.0,ROW_SPACING]:
			concrete_rects.append(Rect2(strip_x,start,DRAIN_HALF_WIDTH*2,row-DRAIN_HALF_LENGTH-start))
			start = row+DRAIN_HALF_LENGTH
		concrete_rects.append(Rect2(strip_x,start,DRAIN_HALF_WIDTH*2,HALF_Z-start))
	var slab := SurfaceTool.new()
	slab.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in concrete_rects:
		var a := rect.position
		var b := rect.end
		for p: Vector2 in [a,Vector2(b.x,a.y),b,a,b,Vector2(a.x,b.y)]:
			slab.set_normal(Vector3.UP)
			slab.set_tangent(Plane(Vector3.RIGHT,-1))
			slab.set_uv(Vector2(p.x/HALF_X,p.y/HALF_Z)*.5+Vector2(.5,.5))
			slab.add_vertex(Vector3(p.x,0,p.y))
	slab.index()
	return slab.commit()


func _hall() -> void:
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SealedConcrete"
	floor_node.mesh = _slab()
	var concrete := ShaderMaterial.new()
	concrete.shader = FloorFinish
	concrete.set_shader_parameter("aggregate", Aggregate)
	concrete.set_shader_parameter("direction_stencil", FloorStencil)
	concrete.set_shader_parameter("bay_pitch", ROW_SPACING)
	concrete.set_shader_parameter("contact", preload("res://garage/workshop_contact.png"))
	concrete.set_shader_parameter("floor_size", Vector2(HALF_X*2,HALF_Z*2))
	floor_node.material_override = concrete
	add_child(floor_node)
	_block(Vector3(0,-.15,0),Vector3(HALF_X*2+.5,.30,HALF_Z*2+.5))
	for side in [-1.0,1.0]:
		_wall(Vector3(side*(HALF_X+.12),EAVES*.5,0),Vector3(.24,EAVES,2*HALF_Z))
		var portal: bool = side < 0.0
		_wall(Vector3(0,EAVES*.5,side*(HALF_Z+.12)),Vector3(2*HALF_X+.48,EAVES,.24),portal)
		_box("Blockwork", Vector3(side*(HALF_X-.07),.67,0), Vector3(.14,1.34,2*HALF_Z))
		_gable_course("Blockwork", Vector3(0,.67,side*(HALF_Z-.07)), Vector3(2*HALF_X,1.34,.14),portal,ServiceEntry.FRONTAGE)
		_gable_course("Enamel", Vector3(0,2.24,side*(HALF_Z-.11)),Vector3(2*HALF_X,.30,.055),portal,ServiceEntry.FRONTAGE)
		_box("Rail", Vector3(side*(HALF_X-.22),5.72,0),Vector3(.09,.09,HALF_Z*2))
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
			var post := Vector3(x,3.8,side*(HALF_Z-.15))
			var post_size := Vector3(.18,7.6,.25)
			if side < 0.0:
				for slab in ServiceEntry.wall_pieces(post,post_size):
					_box("Girder",slab.get_center(),slab.size)
			else:
				_box("Girder",post,post_size)
			_box("Steel", Vector3(x,.38,side*(HALF_Z-.20)), Vector3(.29,.76,.29))
	# A continuous roof sits above the exposed trusses and their corrugated lining.
	_box("Roof", Vector3(0,EAVES+.15,0),Vector3(2*HALF_X+.5,.22,2*HALF_Z+.5))
	for i in range(-45,46):
		_box("RoofRibs",Vector3(i*.76,EAVES+.007,0),Vector3(.085,.085,HALF_Z*2))
	for iz in [-21.0,-14.0,-7.0,0.0,7.0,14.0,21.0]:
		for side in [-1.0,1.0]:
			var column_x: float = side*(HALF_X-.36)
			if iz == 0.0 or absf(iz) == ROW_SPACING:
				# Transfer the truss load around the rolling door. Nothing
				# crosses the curtain below its hood or blocks a racer bay.
				for jamb_offset: float in [-5.97,5.97]:
					var z: float = iz + jamb_offset
					_box("Steel",Vector3(column_x,2.62,z),Vector3(.29,5.24,.31))
					_box("Girder",Vector3(column_x,.17,z),Vector3(.43,.34,.40))
					_block(Vector3(column_x,2.62,z),Vector3(.29,5.24,.31))
					_block(Vector3(column_x,.17,z),Vector3(.43,.34,.40))
				_box("Girder",Vector3(column_x,5.25,iz),Vector3(.37,.060,12.29))
				_box("Steel",Vector3(column_x,5.435,iz),Vector3(.104,.31,12.24))
				_box("Girder",Vector3(column_x,5.62,iz),Vector3(.37,.060,12.29))
				_box("Steel",Vector3(column_x,6.3725,iz),Vector3(.29,1.445,.33))
			else:
				_box("Steel",Vector3(column_x,3.5475,iz),Vector3(.29,7.095,.33))
				_box("Girder",Vector3(column_x,.22,iz),Vector3(.53,.44,.58))
				_block(Vector3(column_x,3.5475,iz),Vector3(.29,7.095,.33))
				_block(Vector3(column_x,.22,iz),Vector3(.53,.44,.58))
			_box("Steel",Vector3(side*HALF_X*.5,7.21,iz),Vector3(HALF_X,.23,.28))
			for ix in 6:
				var panel := HALF_X/6.0
				var x0: float = side * ix * panel
				var top := Vector3(x0+side*panel*.5,7.2,iz)
				_strut("Girder",Vector3(x0,6.42,iz),top,.105)
				_strut("Girder",top,Vector3(x0+side*panel,6.42,iz),.105)
		_box("Steel",Vector3(0,6.42,iz),Vector3(HALF_X*2,.20,.24))
		for x in [-21.0,-6.0,6.0,21.0]:
			_instances["HighBayLamp"].append(Transform3D(Basis.IDENTITY,Vector3(x,6.0,iz)))
			_box("Lamps",Vector3(x,6.026,iz),Vector3(3.46,.032,.366))
	var crane := preload("res://garage/workshop_crane.glb").instantiate()
	crane.name = "BridgeCrane"
	add_child(crane)
	_service_entry()
	_bench(Vector3(-12,0,-21.5))
	_bench(Vector3(12,0,21.5))


func _service_entry() -> void:
	var wall := Vector3(0,0,-HALF_Z)
	# Two thin faces leave a proper pocket in front of the structural wall.
	# An open leaf disappears between them without passing through masonry.
	_gable_course("Wall",wall+Vector3(0,1.42,.38),Vector3(ServiceEntry.FRONTAGE,2.84,.10),true)
	_box("Wall",wall+Vector3(0,2.63,.38),Vector3(ServiceEntry.WALL_OPENING, .42,.10))
	for side: float in [-1.0,1.0]:
		var cheek := (ServiceEntry.FRONTAGE - ServiceEntry.WALL_OPENING) * .5
		# The load-bearing rear wall already collides. Match the front skin here
		# so that the powered leaf travels in a physically empty pocket.
		var jamb := wall+Vector3(side*(ServiceEntry.FRONTAGE-cheek)*.5,1.42,.38)
		for slab in ServiceEntry.wall_pieces(jamb,Vector3(cheek,2.84,.10)):
			_block(slab.get_center(),slab.size)
		_box("Girder", wall+Vector3(side*1.205,1.21,.411), Vector3(.09,2.42,.10))
		_box("Girder", wall+Vector3(side*1.205,1.21,-.21), Vector3(.09,2.42,.11))
		# Blades tilt down toward the room. The dark plenum stays visible between them.
		var vent := wall+Vector3(side*2.83,1.69,0)
		if side < 0:
			_box("Girder", vent+Vector3(0,0,.346), Vector3(2.36,1.17,.09))
			_box("Plinth", vent+Vector3(0,0,.404), Vector3(2.24,1.05,.035))
			for blade in 7:
				_box("RoofRibs", vent+Vector3(0,(blade-3)*.141,.454),
					Vector3(2.17,.054,.105), Basis(Vector3.RIGHT,.39))
			_box("Rail", vent+Vector3(0,-.582,.436), Vector3(2.40,.065,.19))
		else:
			# A low return runs beneath the observation sill.
			vent = wall+Vector3(ServiceEntry.OBSERVATION.get_center().x,.806,.44)
			_box("Steel",vent,Vector3(1.68,.35,.08))
			for blade in 4:
				_box("Girder",vent+Vector3(0,(blade-1.5)*.064,.056),Vector3(1.56,.028,.055),Basis(Vector3.RIGHT,.39))
		_box("Steel", wall+Vector3(side*4.41,1.42,.285), Vector3(.14,2.84,.46))
		_strut("Girder", wall+Vector3(side*3.89,2.53,.36), wall+Vector3(side*3.89,2.82,.89), .085)
	_box("Girder", wall+Vector3(0,2.44,.398), Vector3(2.53,.12,.17))
	_box("Plinth", wall+Vector3(0,2.87,.47), Vector3(9.02,.13,.99))
	_box("Enamel", wall+Vector3(0,3.108,.895), Vector3(9.02,.48,.14))
	_box("Rail", wall+Vector3(0,3.37,.49), Vector3(9.14,.058,1.03))
	_box("Lamps", wall+Vector3(0,2.792,.716), Vector3(1.64,.025,.12))
	_label("FLEET WORKSHOP", wall+Vector3(0,3.106,.975), Basis.IDENTITY,.0088,48)
	var entry := ServiceEntry.new()
	entry.name = "ServiceEntry"
	entry.position = wall
	add_child(entry)
	entry.build(self)


func _shutter(side: float, row: float) -> void:
	var x := side*(HALF_X-.17)
	var number := 2*roundi((ROW_SPACING-row)/ROW_SPACING)+(1 if side > 0 else 0)
	var frame := Basis.looking_at(Vector3(-side,0,0),Vector3.UP,true)
	var origin := Transform3D(frame,Vector3(x,0,row))
	_instances["ShutterFrame"].append(origin)
	_instances["ShutterCurtain"][number] = origin
	_instances["TrenchGrate"].append(Transform3D(frame,Vector3(side*DRAIN_X,0,row)))
	_block(origin * Vector3(0,2.43,.066), Vector3(11.06,4.86,.084),frame)
	for jamb: float in [-5.545,5.545]:
		_block(origin * Vector3(jamb,1.0,.157),Vector3(.19,2.0,.150),frame)
	# A light mounted to the end of the roller hood identifies the closed bay door.
	_box("Plinth",origin*Vector3(-4.85,4.98,.345),Vector3(.47,.20,.080),frame)
	_box("Green",origin*Vector3(-4.85,4.98,.390),Vector3(.32,.10,.023),frame)


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
	var piece := MeshInstance3D.new()
	piece.name = id
	piece.mesh = _equipment_meshes[id]
	piece.transform = Transform3D(face,at)
	add_child(piece,true)


## A bay (`id`, the hall's own) with `craft` standing in it (its own; at the Phaethon's, the Phaethon or the Talon).
func _berth(id: String, index: int, paint: String, craft := "") -> void:
	if craft.is_empty():
		craft = id
	var side := -1.0 if index % 2 == 0 else 1.0
	var row := ROW_SPACING * (1.0 - floori(index/2.0))
	var bay := Parked.new()
	bay.name = id
	bay.position = Vector3(side*BAY_X, Parked.SHELL_HEIGHT, row)
	bay.rotation.y = -side*PI/2
	add_child(bay)
	bay.build(craft, paint)
	_bays[id] = bay
	_standing[id] = craft
	# Keep the entire painted opening clear of a broad coaming like Vesper's.
	var shell_bounds: AABB = bay.model.pod.transform * bay.model.pod.mesh.get_aabb()
	var shell_edge := side * shell_bounds.get_center().x + shell_bounds.size.x * .5
	if craft == Pilot.TALON:      # (the bay's gate is the Phaethon's whichever body stands there: 2.45 m out, Codex's)
		shell_edge = 0.0
	var approach_offset := maxf(2.45, shell_edge + .85)
	var approach := bay.transform * Vector3(side*approach_offset,-Parked.SHELL_HEIGHT,.54)
	var seat := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,.54)
	_gates[id] = Transform3D(Basis.looking_at(seat-approach, Vector3.UP), approach)
	# The floor finish paints each gate at its actual approach point.
	if index in [0,3,4]:
		_tool_cart(Vector3(side*10.3,0,row+4.25))
	var pod_shoes := STANDARD_POD_SHOES if id in [Pilot.STANDARD,Pilot.SHRIKE] else FLEET_POD_SHOES
	var threads: Array[Transform3D] = []
	for station in 2:
		var p := bay.transform * Vector3(0,-Parked.SHELL_HEIGHT,[-.95,1.03][station])
		_stand(p,1.41,bay.basis,pod_shoes[station],threads)
	_thread_detail(threads)
	threads.clear()
	for center in bay.engine_centers:
		for station in 2:
			var p := bay.transform * (center+Vector3(0,-Parked.ENGINE_HEIGHT,[-1.38,1.45][station]))
			_stand(p,1.30,bay.basis,ENGINE_SHOES[id][station],threads)
	_thread_detail(threads)
	_bay_sign(id, index, side, row)


func _bay_sign(id: String, index: int, side: float, row: float) -> void:
	# A folded enamel sign can be read on either walk along the aisle. Each
	# face carries both identifiers in a single label, including the far side.
	# Give the entrance pair enough setback to fit in the forward walking view.
	var sign_z := minf(row + 4.90, HALF_Z - 5.80)
	var nose := Vector3(side*2.33,MARKER_HEIGHT,sign_z)
	var post := nose + Vector3(side*.50,0,0)
	var width := 1.68
	# The entrance pair sits closer to its crossing. Open the fold just enough
	# to leave a metre between the tips and the center of the marked gate.
	var gate: Transform3D = _gates[id]
	var wing_z := clampf((sign_z - gate.origin.z - 1.0) / width, 0.0, .80)
	var wing_x := sqrt(1.0 - wing_z*wing_z)
	var words := "%02d   %s" % [index+1, Pilot.NAMES[id].to_upper()]
	var base := Vector3(post.x,0,post.z)
	_instances["MarkerPost"].append(Transform3D(Basis.IDENTITY,base))
	_block(base+Vector3.UP*MARKER_HEIGHT*.5,Vector3(.14,MARKER_HEIGHT,.13))
	var foot := _block(base+Vector3.UP*.025,Vector3(.345,.05,.267))
	foot.name = "MarkerFoot%02d" % [index + 1]
	# The rail joins the backs of the two wings to the post.
	_box("Steel",post-Vector3.UP*.13,Vector3(.08,.10,maxf(.08,wing_z/wing_x)))
	_marker_guides[id] = []
	for toward: float in [-1.0,1.0]:
		var face := Basis.looking_at(Vector3(-side*wing_z,0,toward*wing_x), Vector3.UP, true)
		face = face * Basis(Vector3.RIGHT, deg_to_rad(-9.0))
		var along := Vector3(side*wing_x,0,toward*wing_z)
		var panel := nose + along * (width*.5)
		var wing := Transform3D(face,panel)
		_instances["MarkerWing"].append(wing)
		# The card sits below the outer hem on two steel stays. Facing along
		# the aisle keeps it legible from both the crossing and cockpit gate.
		var envelope: AABB = wing * _equipment_meshes["MarkerWing"].get_aabb()
		var rim_z := envelope.end.z if toward > 0.0 else envelope.position.z
		var card_face := Basis.looking_at(Vector3.BACK * toward,Vector3.UP,true) * Basis(Vector3.RIGHT,-.38)
		var mount := Transform3D(card_face,Vector3(panel.x + side*.28,panel.y-.275,rim_z+toward*.115))
		_marker_guides[id].append(mount)
		for x: float in [-.285,.285]:
			var clip := mount * Vector3(x,.10,-.014)
			var at := wing.affine_inverse() * clip
			var rivet := wing * Vector3(clampf(at.x,-.79,.79),-.142,-.012)
			_strut("Steel",rivet,clip,.026)
		_label(words,panel+face*Vector3(.020,.005,.0275),face,.0038,48,BayLettering)
		_block(panel,Vector3(1.65,.333,.061),face)
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
	_service_lenses.instance_count = Pilot.GARAGE_BAYS.size() * 2
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


func _stand(floor_point: Vector3, width: float, axes: Basis, setting: Array, threads: Array[Transform3D]) -> void:
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
		_instances["SaddleBase"].append(Transform3D(Basis.IDENTITY,foot-Vector3.UP*.028))
		_strut("Girder",lower,upper,.105)
		_strut("Crane",lower,lower.lerp(upper,.38),.135)
		var shoe := head + axes.x*(side*pickup.x) + Vector3.UP*pickup.y
		var normal := axes * Vector3(-side*slope.x,1,-slope.y).normalized()
		var forward := axes * Vector3(0,slope.y,1).normalized()
		var shoe_frame := Basis(normal.cross(forward),normal,forward)
		_instances["SaddleScrew"].append(Transform3D(axes,shoe))
		_instances["SaddleShoe"].append(Transform3D(shoe_frame,shoe))
		threads.append(Transform3D(axes,shoe))


func _thread_detail(threads: Array[Transform3D]) -> void:
	# The shafts and locknuts remain solid at every distance. Draw the actual
	# helical flanks only by the cradles close enough to resolve them in stereo.
	var center := Vector3.ZERO
	for xf in threads:
		center += xf.origin
	center /= threads.size()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = _equipment_meshes["SaddleThread"]
	batch.instance_count = threads.size()
	for i in threads.size():
		batch.set_instance_transform(i,threads[i].translated(-center))
	var hardware := MultiMeshInstance3D.new()
	hardware.multimesh = batch
	hardware.name = "JackThreads"
	hardware.position = center
	hardware.visibility_range_end = 7.0
	hardware.visibility_range_end_margin = .75
	hardware.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hardware,true)


func _label(words: String, at: Vector3, frame: Basis, pixel: float, size: int, typeface: Font = null) -> void:
	var label := Label3D.new()
	if typeface:
		label.font = typeface
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


func _block(center: Vector3, size: Vector3, frame := Basis.IDENTITY) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var collider := CollisionShape3D.new()
	collider.shape = box
	collider.transform = Transform3D(frame,center)
	_building.add_child(collider)
	return collider


## A continuous horizontal course stops at the structural reveals of the doorway.
func _gable_course(finish: String, at: Vector3, size: Vector3, portal: bool, opening := ServiceEntry.WALL_OPENING) -> void:
	if not portal:
		_box(finish,at,size)
		return
	var wing := (size.x - opening) * .5
	for side: float in [-1.0,1.0]:
		var center := at+Vector3.RIGHT*side*(size.x-wing)*.5
		for slab in ServiceEntry.wall_pieces(center,Vector3(wing,size.y,size.z)):
			_box(finish,slab.get_center(),slab.size)


func _wall(at: Vector3, size: Vector3, portal := false) -> void:
	if size.z > size.x:
		_box("Wall",at,size)
	else:
		# Keep the actual opening behind each translucent clerestory. The box
		# collider continues across the glass; only the masonry blocks the sun.
		var sill := WINDOW_Y - WINDOW_HEIGHT * .5
		var head := WINDOW_Y + WINDOW_HEIGHT * .5
		_gable_course("Wall",Vector3(at.x, sill*.5, at.z),Vector3(size.x, sill, size.z),portal)
		if portal:
			var over := sill - ServiceEntry.WALL_HEAD
			_box("Wall",Vector3(at.x,sill-over*.5,at.z),Vector3(ServiceEntry.WALL_OPENING,over,size.z))
		_box("Wall",Vector3(at.x, (head + EAVES) * .5, at.z),Vector3(size.x, EAVES - head, size.z))
		var pier_width := WINDOW_SPACING - WINDOW_WIDTH
		for ix in range(-WINDOW_HALF_COUNT, WINDOW_HALF_COUNT):
			_box("Wall",Vector3((ix+.5)*WINDOW_SPACING, WINDOW_Y, at.z),Vector3(pier_width, WINDOW_HEIGHT, size.z))
		var outer_jamb := size.x * .5 - WINDOW_HALF_COUNT * WINDOW_SPACING - WINDOW_WIDTH * .5
		for side in [-1.0, 1.0]:
			_box("Wall",Vector3(side * (size.x - outer_jamb) * .5, WINDOW_Y, at.z),Vector3(outer_jamb, WINDOW_HEIGHT, size.z))
	if portal:
		var wing := (size.x - ServiceEntry.WALL_OPENING) * .5
		for side: float in [-1.0,1.0]:
			var center := at+Vector3.RIGHT*side*(size.x-wing)*.5
			for slab in ServiceEntry.wall_pieces(center,Vector3(wing,size.y,size.z)):
				_block(slab.get_center(),slab.size)
		var over := size.y - ServiceEntry.WALL_HEAD
		_block(Vector3(at.x,ServiceEntry.WALL_HEAD+over*.5,at.z),Vector3(ServiceEntry.WALL_OPENING,over,size.z))
	else:
		_block(at,size)


func _batch_structure() -> void:
	var unit := BoxMesh.new()
	for id: String in _instances:
		var transforms: Array = _instances[id]
		if transforms.is_empty():
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = _equipment_meshes.get(id,unit)
		batch.instance_count = transforms.size()
		for i in transforms.size():
			batch.set_instance_transform(i,transforms[i])
		var piece := MultiMeshInstance3D.new()
		piece.name = id
		piece.multimesh = batch
		piece.material_override = _finishes.get(id)
		if id in ["RoofRibs","Panes","Lamps","Green","White","Safety","Blockwork"]:
			piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
	_instances.clear()
