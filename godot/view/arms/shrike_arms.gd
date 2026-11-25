## Twin flush cheek panels carry two pearl-bodied darts each. Forward is -Z.
extends "res://view/arms/hull_hatches.gd"

const HATCHES := "res://art/arms/shrike_hatches.glb"
const BAY_Z := -0.39
const PIVOT_Z := -.725
const PIVOT_Y := -.195
const WRIST_ARC_Z := -.80
const STOW_LENGTH := .417
const ARMED_LENGTH := .97
const CASSETTE_SIZE := Vector3(.70,.72,.95)
const PEARL := Color("#eae7d8")
static var _missile: ArrayMesh
static var _pod_pockets: Dictionary = {}
var _pod: MeshInstance3D
var _pod_closed: ArrayMesh
var _trays: Array[Node3D] = []
var _rounds: Array[MeshInstance3D] = []
var _rockers: Array[MeshInstance3D] = []
var _sleeves: Array[MeshInstance3D] = []
var _slides: Array[MeshInstance3D] = []


static func cassette_mesh(parts: Array) -> ArrayMesh:
	var frame := Transform3D(Basis.from_scale(CASSETTE_SIZE),Vector3.ZERO)
	for p in parts:
		p[1] = frame * p[1]
	return Kit.compound(parts,null,true)


## The curved donor paint is one-sided. Close its cut perimeter and expose a
## pressed-metal backing when the hatch rolls down.
static func hatch_backing(skin: Mesh) -> ArrayMesh:
	var data := skin.surface_get_arrays(0)
	var points: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
	var boundary := {}
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,indices.size(),3):
		for k in [0,2,1]:
			var v := indices[i+k]
			back.set_color(GRAPHITE)
			back.set_normal(-normals[v])
			back.add_vertex(points[v] - normals[v] * .002)
		for k in 3:
			var a := indices[i+k]
			var b := indices[i+(k+1)%3]
			var key := [points[a],points[b]] if points[a]<points[b] else [points[b],points[a]]
			if boundary.has(key): boundary.erase(key)
			else: boundary[key] = Vector2i(a,b)
	for edge: Vector2i in boundary.values():
		var a := points[edge.x]
		var b := points[edge.y]
		var c := a - normals[edge.x]*.002
		var d := b - normals[edge.y]*.002
		var outward := (b-a).cross(c-a).normalized()
		for v in [b,a,c,b,c,d]:
			back.set_color(BRONZE)
			back.set_normal(outward)
			back.add_vertex(v)
	back.index()
	return back.commit()


## One reusable, single-surface mesh. The origin is the flight centre, -Z is the tip.
static func missile_mesh() -> ArrayMesh:
	if _missile:
		return _missile
	var parts := []
	var axis := Vector3(-PI / 2, 0, 0)
	var bands := [
			[-0.262, 0.12, 0.006, 0.043, Color("#506d73")],
			[-0.168, 0.068, 0.043, 0.057, PEARL],
			[-0.118, 0.032, 0.057, 0.057, BRONZE],
			[0.032, 0.268, 0.057, 0.049, PEARL],
			[0.195, 0.058, 0.049, 0.047, GRAPHITE],
			[0.246, 0.044, 0.047, 0.032, BRONZE]]
	for i in bands.size():
		var band: Array = bands[i]
		var skin := Kit.cyl(band[2],band[3],band[1],12)
		skin.rings = 0
		skin.cap_top = i == 0
		skin.cap_bottom = i == bands.size()-1
		parts.append([skin, Kit.at(Vector3(0,0,band[0]),axis), band[4]])
	# A swept, clipped stabilizer with an actual bevel; its long edge trails the body.
	for i in 3:
		var clock := Transform3D(Basis(Vector3.BACK, i * TAU / 3.0), Vector3.ZERO)
		parts.append([Finish.beveled_plate(Vector3(0.068, 0.012, 0.148), 0.004),
				clock * Kit.at(Vector3(0.063, 0, 0.174), Vector3(0, -0.34, 0)), PEARL])
	_missile = cassette_mesh(parts)
	_missile.surface_set_material(0, Finish.powder_coat())
	return _missile


func build(hull: Node3D) -> void:
	if is_instance_valid(_skin):
		return
	var pivots: Array[Vector3] = [Vector3(-1.13,-0.346,BAY_Z), Vector3(1.13,-0.346,BAY_Z)]
	_pod = hull as MeshInstance3D
	_pod_closed = _pod.mesh
	install(hull, hull.get_node("ShrikeStrakes"), load(HATCHES), pivots)
	for hinge in hinges:
		var skin: MeshInstance3D = hinge.get_node("Skin")
		piece(hinge,&"Backing",hatch_backing(skin.mesh),Finish.machined(),skin.position)
	var hot := luminous(Color("#397f78"), Color("#ff9e4a"))
	var tray_parts := [[Finish.beveled_plate(Vector3(0.33,0.035,0.68),0.012), Transform3D.IDENTITY, GRAPHITE]]
	for x in [-0.080,0.080]:
		tray_parts.append([Finish.beveled_plate(Vector3(0.045,0.038,0.54),0.008), Kit.at(Vector3(x,0.031,0)), SILVER])
	for z in [-0.20,0.18]:
		tray_parts.append([Finish.beveled_plate(Vector3(0.29,0.036,0.042),0.006), Kit.at(Vector3(0,0.030,z)), BRONZE])
	var axle := Vector3(0,0,PI/2)
	tray_parts.append([Kit.cyl(.046,.046,.14,16), Kit.at(Vector3(0,-.043,0),axle), BRONZE])
	for x: float in [-.065,.065]:
		tray_parts.append([Finish.beveled_plate(Vector3(.018,.062,.094),.007), Kit.at(Vector3(x,-.038,0)), GRAPHITE])
	var tray_mesh := cassette_mesh(tray_parts)
	var windows := cassette_mesh([
		[Finish.beveled_plate(Vector3(.114,.009,.023),.003), Kit.at(Vector3(0,.027,.263)), Color.WHITE],
		[Finish.beveled_plate(Vector3(.114,.009,.015),.002), Kit.at(Vector3(0,.027,.294)), Color.WHITE]])
	# Three nested members fit inside the cheek. The cross shaft stays captured
	# in the hull while the level cassette rolls about its wrist at the far end.
	var rocker_parts := [
		[Finish.beveled_plate(Vector3(.12,.021,.37),.006), Kit.at(Vector3(0,-.026,.185)), GRAPHITE],
		[Kit.cyl(.052,.052,.102,16), Kit.at(Vector3.ZERO,axle), GRAPHITE]]
	var sleeve_parts := [
		[Finish.beveled_plate(Vector3(.088,.012,.35),.004), Kit.at(Vector3(0,-.009,-.175)), GRAPHITE]]
	for side: float in [-1.0,1.0]:
		rocker_parts.append([Finish.beveled_plate(Vector3(.015,.062,.37),.005), Kit.at(Vector3(side*.054,.002,.185)), BRONZE])
		sleeve_parts.append([Finish.beveled_plate(Vector3(.010,.043,.35),.003), Kit.at(Vector3(side*.039,.008,-.175)), SILVER])
	var sleeve_mesh := Kit.compound(sleeve_parts,null,true)
	var slide_mesh := Kit.compound([
		[Finish.beveled_plate(Vector3(.058,.032,.35),.005), Kit.at(Vector3(0,.015,-.175)), SILVER]],null,true)
	var bearing := TorusMesh.new()
	bearing.inner_radius = .042
	bearing.outer_radius = .060
	bearing.rings = 16
	bearing.ring_segments = 6
	var bearings := []
	for side: float in [-1.0, 1.0]:
		for x: float in [.804,.880]:
			bearings.append([bearing,Kit.at(Vector3(side*x,PIVOT_Y,PIVOT_Z),axle),BRONZE])
		bearings.append([Finish.beveled_plate(Vector3(.105,.014,.061),.003),
				Kit.at(Vector3(side*.842,PIVOT_Y-.058,PIVOT_Z)),GRAPHITE])
		var parts := rocker_parts.duplicate()
		parts.append([Kit.cyl(.038,.038,.48,16), Kit.at(Vector3(-side*.24,0,0),axle), SILVER])
		parts.append([Kit.cyl(.042,.042,.010,16), Kit.at(Vector3(side*.055,0,0),axle), BRONZE])
		var rocker := piece(self, &"PortHoist" if side < 0 else &"StarboardHoist", Kit.compound(parts,null,true), Finish.machined())
		_rockers.append(rocker)
		_sleeves.append(piece(rocker, &"SlidingSleeve", sleeve_mesh, Finish.machined()))
		_slides.append(piece(rocker, &"WristLink", slide_mesh, Finish.machined()))
		var tray := piece(self, &"PortCassette" if side < 0 else &"StarboardCassette",
				tray_mesh, Finish.machined())
		_trays.append(tray)
		piece(tray, &"ChargeWindows", windows, hot)
		for j in 2:
			var at := Vector3(side * (j - .5) * .16, .088, -.027) * CASSETTE_SIZE
			var dart := piece(tray, &"Round%d" % (j+1), missile_mesh(), null, at)
			_rounds.append(dart)
			muzzle(tray, &"Mouth%d" % (j+1), at + Vector3.FORWARD * (.322 * CASSETTE_SIZE.z))
	piece(self,&"CrossShaftBearings",Kit.compound(bearings,null,true),Finish.machined())
	set_deploy(0.0)


## Keep the unarmed cab exact, including after switching between the two nose styles.
func fit_pod(closed: ArrayMesh) -> void:
	_pod_closed = closed
	if _deployed <= 0.0:
		_pod.mesh = closed
		return
	if not _pod_pockets.has(closed):
		var cut := preload("res://view/shrike_airframe.gd").recess_pod(closed)
		for key in closed.get_meta_list():
			cut.set_meta(key,closed.get_meta(key))
		_pod_pockets[closed] = cut
	_pod.mesh = _pod_pockets[closed]


func _exit_tree() -> void:
	if is_instance_valid(_pod):
		_pod.mesh = _pod_closed
	super()


## Optional presentation hook for the flight code when a seat is empty or reloaded.
func set_loaded(slot: int, loaded: bool) -> void:
	if slot >= 0 and slot < _rounds.size():
		_rounds[slot].visible = loaded


func set_deploy(t: float) -> void:
	if not pose(t):
		return
	if _deployed <= 0.0 or _pod.mesh == _pod_closed:
		fit_pod(_pod_closed)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		hinges[i].rotation.z = -side * deg_to_rad(88) * smoothstep(0.0,.048,_deployed)
		# Draw the cassette through the open cheek before rolling the hoist up.
		var lift := clampf((_deployed - .06) / .94,0.0,1.0)
		var swing := .82 * (1.0 - pow(1.0 - lift,3.4)) + .18 * smoothstep(.44,1.0,lift)
		var angle := deg_to_rad(lerpf(-11.0,130.0,swing))
		var radius := lerpf(STOW_LENGTH,ARMED_LENGTH,smoothstep(.08,.84,_deployed))
		var reach := Vector2(WRIST_ARC_Z - PIVOT_Z + radius*cos(angle),
				radius*sin(angle) - .020*smoothstep(.10,.32,_deployed))
		var rocker := _rockers[i]
		var x := lerpf(1.027,1.335,smoothstep(.029,.098,_deployed)) - .025 * smoothstep(.18,.55,_deployed)
		rocker.position = Vector3(side*x,PIVOT_Y,PIVOT_Z)
		rocker.rotation.x = -reach.angle()
		var length := reach.length()
		_sleeves[i].position.z = length * .5 + .185
		_slides[i].position.z = length
		_trays[i].position = rocker.position + rocker.basis.z * length + Vector3.UP * (.043 * CASSETTE_SIZE.y)
		_trays[i].rotation.y = side * .075 * (1.0 - smoothstep(.12,.45,_deployed))
