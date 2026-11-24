## Twin flush cheek panels carry two pearl-bodied darts each. Forward is -Z.
extends "res://view/arms/hull_hatches.gd"

const HATCHES := "res://art/arms/shrike_hatches.glb"
const BAY_Z := -0.39
const PEARL := Color("#eae7d8")
static var _missile: ArrayMesh
var _trays: Array[Node3D] = []
var _rounds: Array[MeshInstance3D] = []


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
	_missile = Kit.compound(parts, null, true)
	_missile.surface_set_material(0, Finish.powder_coat())
	return _missile


func build(hull: Node3D) -> void:
	if is_instance_valid(_skin):
		return
	var pivots: Array[Vector3] = [Vector3(-1.13,-0.346,BAY_Z), Vector3(1.13,-0.346,BAY_Z)]
	install(hull, hull.get_node("ShrikeStrakes"), load(HATCHES), pivots)
	var hot := luminous(Color("#397f78"), Color("#ff9e4a"))
	var tray_parts := [[Finish.beveled_plate(Vector3(0.33,0.035,0.68),0.012), Transform3D.IDENTITY, GRAPHITE]]
	for x in [-0.080,0.080]:
		tray_parts.append([Finish.beveled_plate(Vector3(0.045,0.038,0.54),0.008), Kit.at(Vector3(x,0.031,0)), SILVER])
	for z in [-0.20,0.18]:
		tray_parts.append([Finish.beveled_plate(Vector3(0.29,0.036,0.042),0.006), Kit.at(Vector3(0,0.030,z)), BRONZE])
	var windows := Kit.compound([
		[Finish.beveled_plate(Vector3(.114,.009,.023),.003), Kit.at(Vector3(0,.027,.263)), Color.WHITE],
		[Finish.beveled_plate(Vector3(.114,.009,.015),.002), Kit.at(Vector3(0,.027,.294)), Color.WHITE]], null, true)
	for side: float in [-1.0, 1.0]:
		var handed_parts := tray_parts.duplicate()
		for z in [-.19,.18]:
			var arm := Finish.beveled_plate(Vector3(.40,.040,.077),.011)
			handed_parts.append([arm,Kit.at(Vector3(-side * .235,-.019,z)),SILVER])
		var tray := piece(self, &"PortCassette" if side < 0 else &"StarboardCassette",
				Kit.compound(handed_parts,null,true), Finish.machined())
		_trays.append(tray)
		piece(tray, &"ChargeWindows", windows, hot)
		for j in 2:
			var at := Vector3(side * (j - .5) * .16, .088, -.027)
			var dart := piece(tray, &"Round%d" % (j+1), missile_mesh(), null, at)
			_rounds.append(dart)
			muzzle(tray, &"Mouth%d" % (j+1), at + Vector3.FORWARD * .322)
	set_deploy(0.0)


## Optional presentation hook for the flight code when a seat is empty or reloaded.
func set_loaded(slot: int, loaded: bool) -> void:
	if slot >= 0 and slot < _rounds.size():
		_rounds[slot].visible = loaded


func set_deploy(t: float) -> void:
	if not pose(t):
		return
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		hinges[i].rotation.z = -side * deg_to_rad(77) * smoothstep(0.0,.55,_deployed)
		var travel := smoothstep(.22,1.0,_deployed)
		_trays[i].position = Vector3(side * lerpf(.93,1.48,travel), -.262, BAY_Z - travel * .16)
		_trays[i].visible = _deployed > .22
