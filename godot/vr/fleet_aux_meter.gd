## The instrument on the starboard cheek of each non-standard cockpit. All moving
## parts are in the frame of the printed card, with +Z pointing toward the pilot.
extends Node3D

const P := preload("res://sim/pilot_craft.gd")
const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const CARDS := [P.SHRIKE, P.ORRERY, P.KILN, P.VESPER]
var id: String
var card_size: Vector2
var cursors: Array[Node3D] = []
var card_material: StandardMaterial3D


func _piece(parent: Node3D, mesh: Mesh, material: Material, at := Transform3D.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = at
	parent.add_child(mi)
	return mi


func build(deck, eye: Vector3) -> void:
	id = deck.id
	position = Vector3(.545, .445, -.135)
	basis = Basis.looking_at(position - eye, Vector3.UP)
	card_size = Vector2(.184, .100)
	var round_case := id == P.ORRERY
	if round_case:
		card_size = Vector2(.139, .139)
	var alloy := Finish.tinted("satin", deck.accent)
	var body := Finish.tinted("powder", deck.paint)
	var face_up := Vector3(PI / 2, 0, 0)
	var pieces := []
	if round_case:
		_piece(self, Kit.cyl(.077, .062, .043, 56), alloy, Kit.at(Vector3(0, 0, -.022), face_up))
		pieces.append([Finish.washer(.069, .076, .006, 64), Kit.at(Vector3.ZERO, face_up), deck.accent])
	else:
		var w := card_size.x
		var h := card_size.y
		_piece(
			self,
			Finish.beveled_plate(Vector3(w + .022, .045, h + .024), .007),
			body,
			Kit.at(Vector3(0, 0, -.024), face_up)
		)
		for x in [-1, 1]:
			for y in [-1, 1]:
				pieces.append(
					[
						Finish.slotted_screw(.003),
						Kit.at(Vector3(x * (w * .5 + .004), y * (h * .5 + .003), .0003), face_up),
						Color.SILVER
					]
				)
	# A fixed mounting shoe under the case runs back into the dashboard cheek.
	pieces.append(
		[
			Finish.beveled_plate(Vector3(.059, .032, .095)),
			Kit.at(Vector3(0, -card_size.y * .36, -.065)),
			deck.upholstery
		]
	)
	_piece(self, Kit.compound(pieces), Finish.satin())
	card_material = StandardMaterial3D.new()
	card_material.albedo_texture = preload("res://art/pilot_fleet/cockpit_meters.png")
	card_material.emission_enabled = true
	card_material.emission_texture = card_material.albedo_texture
	card_material.roughness = .72
	card_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_piece(self, _card_mesh(CARDS.find(id), round_case), card_material)
	var pointer := Finish.tinted("powder", Color("#ff7546") if id != P.VESPER else Color("#eddbff"))
	for i in 2 if id == P.KILN else 1:
		var pivot := Node3D.new()
		pivot.name = "Pointer%d" % i
		pivot.position.z = .003
		cursors.append(pivot)
		add_child(pivot)
		match id:
			P.ORRERY:
				_piece(pivot, _kite(.004, .055, .024), pointer)
				_piece(pivot, Kit.cyl(.006, .007, .005, 16), alloy, Kit.at(Vector3(0, 0, .003), face_up))
			P.KILN:
				_piece(pivot, Kit.box(Vector3(.004, .010, .002)), Finish.tinted("powder", Color("#fff7df")))
			P.SHRIKE:
				_piece(pivot, _kite(.005, .009, .005), pointer)
			P.VESPER:
				_piece(pivot, Kit.ball(.005, 16), pointer)


func _card_mesh(index: int, round_card: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile := Vector2(index % 2, floori(index / 2.0))
	var count := 64 if round_card else 4
	for k in count:
		var start := TAU * float(k) / count + PI * .25
		var end := TAU * float(k + 1) / count + PI * .25
		var radius := .50 if round_card else sqrt(.50)
		for p: Vector2 in [Vector2.ZERO, Vector2.from_angle(end) * radius, Vector2.from_angle(start) * radius]:
			st.set_normal(Vector3.BACK)
			st.set_uv((tile + Vector2(.5 + p.x, .5 - p.y).clamp(Vector2(.001, .001), Vector2(.999, .999))) * .5)
			st.add_vertex(Vector3(p.x * card_size.x, p.y * card_size.y, .001))
	return st.commit()


func _kite(half_width: float, tip: float, tail: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Finish._quad(
		st,
		Vector3(-half_width, 0, 0),
		Vector3(0, tip, 0),
		Vector3(half_width, 0, 0),
		Vector3(0, -tail, 0),
		Vector3.BACK
	)
	return st.commit()


func sync(heading: float, brakes: Array, strain: Array, side_g: float, power: float) -> void:
	var backlight := .38 * clampf(power, 0, 1)
	if not is_equal_approx(card_material.emission_energy_multiplier, backlight):
		card_material.emission_energy_multiplier = backlight
	var cursor := cursors[0]
	match id:
		P.ORRERY:
			# North-up map uses +X east and +Y north. The index points up at zero rotation.
			cursor.rotation.z = heading - PI / 2
		P.SHRIKE:
			cursor.position.x = card_size.x * .37 * clampf(float(brakes[1]) - float(brakes[0]), -1, 1)
			cursor.position.y = -card_size.y * .183
		P.KILN:
			for i in 2:
				var x := lerpf(99.0, 434.0, clampf(strain[i], 0, 1))
				cursors[i].position = Vector3(
					(x / 512.0 - .5) * card_size.x, (.5 - (222.0 + 129.0 * i) / 512.0) * card_size.y, .003
				)
		P.VESPER:
			# The ball moves outboard of a turn, like a physical inclinometer.
			var fraction := clampf(side_g / 20.0, -1, 1)
			cursor.position = Vector3(
				card_size.x * .37 * fraction,
				card_size.y * (.5 - (302.0 - 57.0 * fraction * fraction) / 512.0),
				.005
			)
