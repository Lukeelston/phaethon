## Kiln Six's induction lance telescopes out of its starboard nose sill. The two
## armoured jaws are real pieces of cab skin, including its original factory paint.
extends "res://view/arms/fleet_bay.gd"

const AXIS := Vector3(.595,-.189,-2.135)
const BORE := Vector3(0,0,-.508)
const CERAMIC := Color("#c6c0aa")
const EMBER := Color(.92,.34,.09,0)
var emitter: MeshInstance3D

func build(hull: Node3D) -> void:
	if is_instance_valid(shell):
		return
	fit_shell(hull as MeshInstance3D, "kiln", Color("#ffbd5d"))
	# In the machining frame +Y points out of the nose. The graphite sleeve
	# stays behind the open jaws while the armature with its ceramic shoes extends.
	var bore_basis := Basis(Vector3.RIGHT, -PI/2)
	var sleeve := turn([Vector2(.112,-.13),Vector2(.117,-.12),Vector2(.117,.016),
		Vector2(.110,.025),Vector2(.087,.025),Vector2(.085,.017),Vector2(.085,-.13)], 20)
	mesh_node(self, "RecessSleeve", Kit.compound([[sleeve, Transform3D(bore_basis,AXIS), DARK]], null, true))
	var receiver := turn([Vector2(.064,-.13),Vector2(.078,-.11),Vector2(.078,.105),
		Vector2(.068,.125),Vector2(.048,.125),Vector2(.048,-.13)], 20)
	var crown := turn([Vector2(.072,.392),Vector2(.083,.407),Vector2(.077,.475),
		Vector2(.065,.502),Vector2(.051,.502),Vector2(.045,.485),Vector2(.045,.392)], 20)
	var coils := turn([Vector2(.054,-.012),Vector2(.069,-.007),Vector2(.069,.007),
		Vector2(.054,.012),Vector2(.050,.009),Vector2(.050,-.009)], 18)
	var pieces := [[receiver,Transform3D.IDENTITY,STEEL], [crown,Transform3D.IDENTITY,CERAMIC],
		[Kit.cyl(.053,.060,.28,18),Kit.at(Vector3.UP*.262),DARK]]
	for j in 6:
		pieces.append([coils,Kit.at(Vector3.UP*(.15 + .042*j)),BRASS if j % 2 == 0 else EMBER])
	for j in 3:
		var a := TAU*j/3
		var pos := Vector3(.075*cos(a),.272,.075*sin(a))
		pieces.append([Kit.cyl(.013,.015,.32,8),Kit.at(pos),STEEL])
	pieces.append([Kit.cyl(.044,.045,.012,18),Kit.at(Vector3.UP*.478),EMBER])
	var assembly := Kit.compound(pieces,null,true)
	emitter = mesh_node(self,"InductionLance",Kit.compound([[assembly,Transform3D(bore_basis,Vector3.ZERO),Color.WHITE,true]],null,true))
	set_deploy(0.0)

func set_deploy(t: float) -> void:
	var at := clampf(t,0.0,1.0)
	if not show_bay(at):
		return
	var split := smoothstep(0, .4, at)
	doors[&"PortJaw"].position = Vector3(-.155*split,0,-.022*split)
	doors[&"StarboardJaw"].position = Vector3(.155*split,0,-.022*split)
	emitter.position = AXIS + Vector3.BACK * (.58 * (1.0-smoothstep(.32,1,at)))

func muzzles() -> Array:
	return [(emitter.global_transform * Transform3D(Basis.IDENTITY, BORE)).orthonormalized()]
