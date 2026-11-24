## Orrery IX's three individually docked survey orbs. Gameplay may move orbs[i]
## after deployment. Docks remain on the cab; muzzles follow the actual lenses.
extends "res://view/arms/fleet_bay.gd"

const SEATS := [Vector3(-0.997, -0.039, -0.233), Vector3(0.997, -0.039, -0.233), Vector3(0, 0.066, 1.76)]
const UNDOCK := [Vector3(-0.28, 0.40, -0.40), Vector3(0.28, 0.40, -0.40), Vector3(0, 0.46, 0.24)]
const LEAVES := [&"PortDoor", &"StarboardDoor", &"AftDoor"]
const MINT := Color(0.23, 0.80, 0.70, 0.0)
var orbs: Array[MeshInstance3D] = []

func build(hull: Node3D) -> void:
	if is_instance_valid(shell):
		return
	fit_shell(hull as MeshInstance3D, "orrery", Color("#9cfae2"))
	var collar := turn([Vector2(.15, -.035), Vector2(.15, -.013), Vector2(.141, -.006),
		Vector2(.122, -.006), Vector2(.116, -.015), Vector2(.116, -.035)], 18, false)
	var seat_parts := []
	var sphere := Kit.ball(.101, 16)
	var waist := turn([Vector2(.108,-.009), Vector2(.119,-.008), Vector2(.119,.008),
		Vector2(.108,.009)], 18)
	var cap := turn([Vector2(.090,.043),Vector2(.090,.047),Vector2(.082,.061),Vector2(.064,.083),
		Vector2(.040,.097),Vector2(.013,.104),Vector2(.012,.100)], 16, false)
	var bezel := turn([Vector2(.054,-.005), Vector2(.057,0), Vector2(.052,.008),
		Vector2(.042,.010), Vector2(.039,.004)], 14, false)
	var lens_pose := Kit.at(Vector3(0,0,-.104), Vector3(-PI/2,0,0))
	var pieces := [[sphere, Transform3D.IDENTITY, Color("#174e51")],
		[cap, Transform3D.IDENTITY, Color("#e1ce96")],
		[cap, Kit.at(Vector3.ZERO,Vector3(PI,0,0)), Color("#819296")],
		[waist, Kit.at(Vector3.ZERO,Vector3(.29,0,-.15)), BRASS],
		[waist, Kit.at(Vector3.ZERO, Vector3(0,0,1.22), Vector3(.97,.55,.97)), STEEL],
		[bezel, lens_pose, BRASS],
		[Kit.ball(.040, 10), Kit.at(Vector3(0,0,-.111), Vector3.ZERO, Vector3(1,1,.35)), MINT]]
	var orb_mesh := Kit.compound(pieces, null, true)
	for i in SEATS.size():
		var at: Vector3 = SEATS[i]
		seat_parts.append([collar, Kit.at(at + Vector3.UP * .053), BRASS])
		seat_parts.append([Kit.cyl(.143,.113,.058,14), Kit.at(at + Vector3.DOWN * .061), DARK])
		for j in 3:
			var a := TAU * j / 3.0
			seat_parts.append([Kit.cyl(.018,.023,.036,8), Kit.at(at + Vector3(.102*cos(a),-.026,.102*sin(a))), STEEL])
		var orb := mesh_node(self, "Orb%d" % (i+1), orb_mesh)
		orbs.append(orb)
	mesh_node(self, "DockCradles", Kit.compound(seat_parts, null, true))
	set_deploy(0.0)

func set_deploy(t: float) -> void:
	var at := clampf(t, 0.0, 1.0)
	if not show_bay(at):
		return
	var open := smoothstep(0.0, 0.42, at)
	var rise := smoothstep(0.37, 0.76, at)
	var away := smoothstep(0.7, 1.0, at)
	for i in SEATS.size():
		var leaf: MeshInstance3D = doors[LEAVES[i]]
		# Fore shoulder hatches slide aft; the third pocket slides forward.
		leaf.position = Vector3(0, .018 * open, (.385 if i < 2 else -.385) * open)
		var direction: Vector3 = UNDOCK[i]
		orbs[i].basis = Basis.IDENTITY
		orbs[i].position = SEATS[i] + Vector3(0, direction.y * rise, 0) + Vector3(direction.x, 0, direction.z) * away

func docks() -> Array:
	var seats := []
	for p: Vector3 in SEATS:
		seats.append((global_transform * Transform3D(Basis.IDENTITY, p)).orthonormalized())
	return seats

func muzzles() -> Array:
	var result := []
	for orb in orbs:
		result.append((orb.global_transform * Transform3D(Basis.IDENTITY, Vector3(0,0,-.125))).orthonormalized())
	return result
