## Kiln Six's articulated foredeck lance. The painted leaves are cut from the
## starboard shoulder; a parallel lift keeps the induction barrel pointing ahead
## as it rises across the pilot's windscreen and slides into firing position.
extends "res://view/arms/fleet_bay.gd"

const Finish := preload("res://view/craft_materials.gd")
const DECK_X := .70
const REAR_PIN := Vector3(DECK_X, -.19, -1.84)
const PIN_SPACING := .20
const ARM_LENGTH := .55
const BORE := Vector3(0, 0, -.508)
const CERAMIC := Color("#c6c0aa")
const EMBER := Color(.92, .34, .09, 0)
const OXIDE := Color("#b84e34")

var emitter: MeshInstance3D
var saddle: MeshInstance3D
var links: Array[MeshInstance3D] = []

func build(hull: Node3D) -> void:
	if is_instance_valid(shell):
		return
	fit_shell(hull as MeshInstance3D, "kiln", Color("#ffbd5d"))
	var trough := [
		[Finish.beveled_plate(Vector3(.33, .032, .88), .009), Kit.at(Vector3(DECK_X, -.242, -1.625)), DARK],
	]
	for side: float in [-1.0, 1.0]:
		trough.append([Kit.box(Vector3(.012, .30, .88)), Kit.at(Vector3(DECK_X + side*.164, -.075, -1.625)), DARK])
	for z: float in [-1.19, -2.065]:
		trough.append([Kit.box(Vector3(.33, .30, .012)), Kit.at(Vector3(DECK_X, -.075, z)), DARK])
	mesh_node(self, "LanceWell", Kit.compound(trough, null, true))

	# The forward fork nests inside the aft fork as both fold into the well.
	for i in 2:
		var link := mesh_node(self, "ElevatorFork%d" % i, _lift_fork(.121 if i == 0 else .087))
		link.position = REAR_PIN + Vector3.FORWARD * PIN_SPACING * i
		links.append(link)
	var bearing := turn([Vector2(.106, -.060), Vector2(.114, -.052), Vector2(.114, .052),
		Vector2(.106, .060), Vector2(.102, .060), Vector2(.102, -.060)], 24)
	var cradle := [
		[Finish.beveled_plate(Vector3(.203, .051, .355), .012), Kit.at(Vector3(0, .029, -.09)), DARK],
		[bearing, Kit.at(Vector3(0, .109, -.12), Vector3(-PI/2, 0, 0)), STEEL]
	]
	for i in 2:
		cradle.append([Kit.cyl(.032, .032, .252, 12), Kit.at(Vector3(0, 0, -PIN_SPACING*i), Vector3(0, 0, PI/2)), BRASS])
	saddle = mesh_node(self, "LanceSaddle", Kit.compound(cradle, null, true))
	emitter = mesh_node(saddle, "InductionLance", _lance())
	set_deploy(0.0)

func _lift_fork(half_span: float) -> ArrayMesh:
	var side_link := Finish.beveled_plate(Vector3(.018, .048, ARM_LENGTH), .007)
	var pin_cheek := Kit.cyl(.038,.038,.026,12)
	var parts := []
	for side: float in [-1.0,1.0]:
		var x := half_span * side
		parts.append([side_link, Kit.at(Vector3(x,0,ARM_LENGTH/2)), OXIDE])
		for z: float in [0.0, ARM_LENGTH]:
			parts.append([pin_cheek, Kit.at(Vector3(x,0,z),Vector3(0,0,PI/2)),STEEL])
	return Kit.compound(parts,null,true)

func _lance() -> ArrayMesh:
	# Machine the concentric parts about +Y, then mount the assembly on its -Z bore.
	var bore_basis := Basis(Vector3.RIGHT, -PI/2)
	var receiver := turn([Vector2(.079,-.094),Vector2(.099,-.078),Vector2(.099,.107),
		Vector2(.084,.127),Vector2(.051,.127),Vector2(.051,-.094)], 20)
	var crown := turn([Vector2(.078,.365),Vector2(.095,.387),Vector2(.091,.472),
		Vector2(.073,.502),Vector2(.051,.502),Vector2(.044,.484),Vector2(.044,.365)], 20)
	var coils := turn([Vector2(.054,-.012),Vector2(.073,-.007),Vector2(.073,.007),
		Vector2(.054,.012),Vector2(.050,.009),Vector2(.050,-.009)], 18)
	var pieces := [[receiver,Transform3D.IDENTITY,STEEL],[crown,Transform3D.IDENTITY,CERAMIC],
		[Kit.cyl(.060,.060,.255,18), Kit.at(Vector3.UP*.244),DARK],
		[Kit.cyl(.080,.068,.025,16), Kit.at(Vector3.DOWN*.095),OXIDE],
		[Kit.cyl(.051,.044,.019,16), Kit.at(Vector3.DOWN*.115),DARK],
		[Kit.cyl(.024,.022,.009,12), Kit.at(Vector3.DOWN*.126),BRASS]]
	for j in 5:
		pieces.append([coils,Kit.at(Vector3.UP*(.145+.045*j)),BRASS if j%2==0 else EMBER])
	for j in 3:
		var a := TAU*j/3
		var pos := Vector3(.086*cos(a),.249,.086*sin(a))
		pieces.append([Kit.cyl(.017,.017,.27,8),Kit.at(pos),STEEL])
	pieces.append([Kit.cyl(.043,.044,.012,18),Kit.at(Vector3.UP*.478),EMBER])
	return Kit.compound([[Kit.compound(pieces,null,true),Transform3D(bore_basis,Vector3.ZERO),Color.WHITE,true]],null,true)

func set_deploy(t: float) -> void:
	var at := clampf(t,0,1)
	if not show_bay(at):
		return
	var hatch_angle := deg_to_rad(145) * smoothstep(0,.50,at)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hinge := Vector3(DECK_X + side*.17,.103,-1.63)
		var rotation_basis := Basis(Vector3.BACK,-side*hatch_angle)
		var leaf: MeshInstance3D = doors[&"PortJaw" if i == 0 else &"StarboardJaw"]
		leaf.transform = Transform3D(rotation_basis, hinge - rotation_basis * hinge)
	# Both pins of the carriage describe equal arcs; its barrel stays level.
	var lift := smoothstep(.08,.88,at)
	var fork_basis := Basis(Vector3.RIGHT,-deg_to_rad(83)*lift)
	for link in links:
		link.basis = fork_basis
	saddle.position = REAR_PIN + fork_basis * Vector3.BACK * ARM_LENGTH
	emitter.position = Vector3(0,.109,-.18*smoothstep(.55,1,at))

func muzzles() -> Array:
	return [(emitter.global_transform * Transform3D(Basis.IDENTITY, BORE)).orthonormalized()]
