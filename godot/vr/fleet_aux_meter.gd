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


## A cast enclosure with a flat land for the card and screws. Adjacent radius
## patches share analytic normals so the highlight continues round all three sides.
func _rounded_housing(size: Vector3, radius: float, small := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * .5
	var core := half - Vector3.ONE * radius
	var grid := [-1.0, 0.0, 0.0, 1.0] if small else [-1.0, -.60, -.28, 0.0, 0.0, .28, .60, 1.0]
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for side: float in [-1, 1]:
			var points := PackedVector3Array()
			var normals := PackedVector3Array()
			for i in grid.size():
				for j in grid.size():
					var box := Vector3.ZERO
					box[axis] = side * half[axis]
					box[u] = (-core[u] if i < grid.size() / 2 else core[u]) + radius * grid[i]
					box[v] = (-core[v] if j < grid.size() / 2 else core[v]) + radius * grid[j]
					var nearest := box.clamp(-core, core)
					var normal := nearest.direction_to(box)
					points.append(nearest + normal * radius)
					normals.append(normal)
			for i in grid.size() - 1:
				for j in grid.size() - 1:
					var a := i * grid.size() + j
					var b := a + grid.size()
					var c := a + 1
					var d := b + 1
					var order := [a, c, b, b, c, d] if side > 0 else [a, b, c, b, d, c]
					for k in order:
						st.set_normal(normals[k])
						st.add_vertex(points[k])
	st.index()
	return st.commit()


## Sweep a tool profile around a circle or a rounded rectangle. Each profile point
## is (distance from the corner centre, depth toward the pilot) in metres.
func _rim_mesh(profile: PackedVector2Array, centres: Vector2, steps: int, capped := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rays := PackedVector2Array()
	var origins := PackedVector2Array()
	for corner in 4:
		var mid := Vector2.from_angle((corner + .5) * PI / 2)
		# A rectangle needs both ends of each corner to form its straight sides.
		for i in (steps if centres == Vector2.ZERO else steps + 1):
			rays.append(Vector2.from_angle((corner + float(i) / steps) * PI / 2))
			origins.append(mid.sign() * centres)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	for j in profile.size():
		var tangent := Vector2.ZERO
		if j > 0:
			tangent += profile[j-1].direction_to(profile[j])
		if j + 1 < profile.size():
			tangent += profile[j].direction_to(profile[j+1])
		var n := Vector2(tangent.y, -tangent.x).normalized()
		for i in rays.size():
			var xy := origins[i] + rays[i] * profile[j].x
			points.append(Vector3(xy.x, xy.y, profile[j].y))
			normals.append(Vector3(rays[i].x * n.x, rays[i].y * n.x, n.y))
	var count := rays.size()
	for j in profile.size() - 1:
		for i in count:
			var a := j * count + i
			var b := j * count + (i + 1) % count
			for k: int in [a, a + count, b, b, a + count, b + count]:
				st.set_normal(normals[k])
				st.add_vertex(points[k])
	if capped:
		var last := (profile.size() - 1) * count
		for i in count:
			var next := (i + 1) % count
			Finish._triangle(st, Vector3.BACK * profile[0].y, points[i], points[next], Vector3.FORWARD)
			Finish._triangle(st, Vector3.BACK * profile[-1].y, points[last+i], points[last+next], Vector3.BACK)
	st.index()
	return st.commit()


func build(deck, eye: Vector3) -> void:
	id = deck.id
	position = Vector3(.468, .535, -.105)
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
		# The case ends on the card's underside. Its rolled brass bezel holds the
		# rim of the card and has a wide flat land for the three retaining screws.
		var case_profile := PackedVector2Array([Vector2(.060, -.0435), Vector2(.0615, -.0433),
			Vector2(.0624, -.0424), Vector2(.0755, -.004), Vector2(.076, -.0025),
			Vector2(.0758, -.0016), Vector2(.0754, -.0013), Vector2(.0698, -.0013),
			Vector2(.0696, -.0009), Vector2(.0696, .0006), Vector2(.0693, .00095)])
		_piece(self, _rim_mesh(case_profile, Vector2.ZERO, 16, true), alloy).name = "Case"
		var lip := PackedVector2Array([Vector2(.0754, -.0013), Vector2(.0758, -.0011),
			Vector2(.0761, -.0006), Vector2(.0761, .0019), Vector2(.0759, .0026),
			Vector2(.0755, .00295), Vector2(.0751, .003), Vector2(.0708, .003),
			Vector2(.0703, .0033), Vector2(.0699, .0036), Vector2(.06945, .00365),
			Vector2(.0690, .00345), Vector2(.0687, .00305), Vector2(.06865, .0027),
			Vector2(.06865, .001)])
		pieces.append([_rim_mesh(lip, Vector2.ZERO, 16), Transform3D.IDENTITY, deck.accent])
		var brass_screw := Finish.socket_screw(.0022, Color("#ccaa73"))
		for i in 3:
			var angle := TAU * i / 3 + PI / 2
			var seat := Vector3(.073 * cos(angle), .073 * sin(angle), .003)
			pieces.append([brass_screw, Kit.at(seat, face_up), Color.WHITE, true])
	else:
		var screw := Finish.socket_screw(.003, Color("#b8bfc0"))
		var w := card_size.x
		var h := card_size.y
		var size := Vector3(w + .022, .045, h + .024)
		var centre_z := -.024
		_piece(self, _rounded_housing(size, .006), body, Kit.at(Vector3(0, 0, centre_z), face_up)).name = "Case"
		var face_z := centre_z + size.y * .5
		# A compressed black seal backs the card across the gap to the casting.
		var seal_profile := PackedVector2Array([Vector2(.00418, face_z), Vector2(.00425, face_z + .0002),
			Vector2(.00425, .0007), Vector2(.0041, .00095)])
		var corner_centres := card_size * .5 - Vector2.ONE * .0045
		_piece(self, _rim_mesh(seal_profile, corner_centres, 4, true),
			Finish.tinted("rubber", Color("#222425"))).name = "CardSeal"
		# A formed retaining lip runs around the print. Its inner radius ends
		# just on the card margin, leaving its markings and pointer travel clear.
		var lip := PackedVector2Array([Vector2(.00535, face_z), Vector2(.00535, .0017),
			Vector2(.0052, .0022), Vector2(.00485, .00255), Vector2(.00445, .00265),
			Vector2(.00385, .00265), Vector2(.0035, .0025), Vector2(.00325, .00212),
			Vector2(.00315, .00175), Vector2(.00315, .001)])
		var rim_color: Color = deck.paint.darkened(.38)
		pieces.append([_rim_mesh(lip, corner_centres, 5),
			Transform3D.IDENTITY, rim_color])
		for x in [-1, 1]:
			for y in [-1, 1]:
				var seat := Vector3(x * (w * .5 - .006), y * (h * .5 + .0043), face_z)
				pieces.append([screw, Kit.at(seat, face_up), Color.WHITE, true])
	_piece(self, Kit.compound(pieces), Finish.satin()).name = "RimHardware"
	# Keep the rear foot on the dashboard while raising the printed face above the coaming.
	var foot := basis.inverse() * (Vector3(.586, .372 if round_case else .391, -.173) - position)
	var back := Vector3(0, -card_size.y * .25, -.042)
	# Seat the casting past the curved dashboard skin for a finite mounting land.
	foot += back.direction_to(foot) * .004
	var strut := Kit.at((foot + back) * .5)
	strut.basis = Basis.looking_at(foot - back, Vector3.UP)
	_piece(self, _rounded_housing(Vector3(.044, .020, foot.distance_to(back)), .0032), body, strut).name = "Bracket"
	card_material = StandardMaterial3D.new()
	card_material.albedo_texture = preload("res://art/pilot_fleet/cockpit_meters.png")
	card_material.emission_enabled = true
	card_material.emission_texture = preload("res://art/pilot_fleet/cockpit_meter_lamps.png")
	card_material.emission_energy_multiplier = 0.0
	card_material.roughness = .72
	card_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_piece(self, _card_mesh(CARDS.find(id), round_case), card_material).name = "PrintedCard"
	var pointer := Finish.tinted("powder", Color("#ff7546") if id != P.VESPER else Color("#eddbff"))
	for i in 2 if id == P.KILN else 1:
		var pivot := Node3D.new()
		pivot.name = "Pointer%d" % i
		pivot.position.z = .007 if id == P.VESPER else .003
		cursors.append(pivot)
		add_child(pivot)
		match id:
			P.ORRERY:
				_piece(pivot, _kite(.004, .055, .024), pointer)
				var hub := PackedVector2Array([Vector2(.0065, .0004), Vector2(.0068, .0008),
					Vector2(.0068, .0027), Vector2(.0066, .0034), Vector2(.0058, .0044),
					Vector2(.0044, .00505), Vector2(.0028, .0053)])
				_piece(pivot, _rim_mesh(hub, Vector2.ZERO, 6, true), alloy)
			P.KILN:
				_piece(pivot, _rounded_housing(Vector3(.004, .010, .002), .00065, true), Finish.tinted("powder", Color("#fff7df")))
			P.SHRIKE:
				_piece(pivot, _kite(.005, .009, .005), pointer)
			P.VESPER:
				# Small turned ball with compact caps, avoiding duplicated triangles at the poles.
				var ball := PackedVector2Array()
				for j in 11:
					var angle := lerpf(-PI * .48, PI * .48, j / 10.0)
					ball.append(Vector2(cos(angle), sin(angle)) * .005)
				_piece(pivot, _rim_mesh(ball, Vector2.ZERO, 5, true), pointer)


func _card_mesh(index: int, round_card: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile := Vector2(index % 2, floori(index / 2.0))
	var outline := PackedVector2Array()
	var half := card_size * .5
	if round_card:
		for i in 64:
			outline.append(Vector2.from_angle(TAU * i / 64.0) * half)
	else:
		# The stock itself has die-cut corners under the retaining lip.
		const R := .0045
		for corner in 4:
			var centre := Vector2.from_angle((corner + .5) * PI / 2).sign() * (half - Vector2.ONE * R)
			for i in 6:
				outline.append(centre + Vector2.from_angle((corner + i / 5.0) * PI / 2) * R)
	for i in outline.size():
		for xy: Vector2 in [Vector2.ZERO, outline[(i+1) % outline.size()], outline[i]]:
			var p := xy / card_size
			st.set_normal(Vector3.BACK)
			st.set_uv((tile + Vector2(.5 + p.x, .5 - p.y).clamp(Vector2(.001, .001), Vector2(.999, .999))) * .5)
			st.add_vertex(Vector3(xy.x, xy.y, .001))
	st.index()
	return st.commit()


func _kite(half_width: float, tip: float, tail: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Stamped sheet pointer. The spine stiffens the pointer and its rolled return
	# gives it a readable edge when the cockpit is viewed from the side.
	var outline := PackedVector3Array([Vector3(-half_width, 0, 0), Vector3(0, tip, 0),
		Vector3(half_width, 0, 0), Vector3(0, -tail, 0)])
	var spine := Vector3.BACK * .0009
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1) % outline.size()]
		Finish._triangle(st, a, b, spine, Vector3.BACK)
		var under := Vector3.FORWARD * .00045
		Finish._quad(st, a, b, b + under, a + under, (a+b) * .5)
		Finish._triangle(st, a+under, b+under, under, Vector3.FORWARD)
	st.index()
	return st.commit()


func sync(heading: float, brakes: Array, strain: Array, side_g: float, power: float, panel_level := 1.0) -> void:
	var backlight := clampf(power, 0, 1) * panel_level
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
				.007
			)
