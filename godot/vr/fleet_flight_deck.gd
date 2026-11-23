## Fixed cockpit fittings. Dimensions are metres; dial positions are measured along the
## same curved panel as the working glass, needles and LCD windows in gauge_cluster.gd.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Finish := preload("res://view/craft_materials.gd")
const Layout := preload("res://vr/gauge_layout.gd")
const P := preload("res://sim/pilot_craft.gd")

# Mach, port thrust, starboard thrust, port systems, starboard systems: arc position, height, scale.
const STATIONS := {
	P.SHRIKE:
	[
		Vector3(0, .046, .98),
		Vector3(-.231, .053, .82),
		Vector3(.231, .053, .82),
		Vector3(-.395, -.004, .72),
		Vector3(.395, -.004, .72)
	],
	P.ORRERY:
	[
		Vector3(0, .037, .94),
		Vector3(-.374, .033, .78),
		Vector3(.374, .033, .78),
		Vector3(-.200, .018, .86),
		Vector3(.200, .018, .86)
	],
	P.KILN:
	[
		Vector3(0, .025, .82),
		Vector3(-.210, .030, .80),
		Vector3(.210, .030, .80),
		Vector3(-.386, .023, .78),
		Vector3(.386, .023, .78)
	],
	P.VESPER:
	[
		Vector3(-.310, .036, .88),
		Vector3(-.086, .016, .78),
		Vector3(.094, .031, .78),
		Vector3(.260, .024, .68),
		Vector3(.397, .060, .66)
	],
}
# Dash panels, exposed structure and upholstery.
const FINISHES := {
	P.SHRIKE: [Color("#242d33"), Color("#ee573b"), Color("#28282e")],
	P.ORRERY: [Color("#266665"), Color("#c69d5e"), Color("#664433")],
	P.KILN: [Color("#ad492d"), Color("#e8b454"), Color("#3f4847")],
	P.VESPER: [Color("#cecdda"), Color("#9079d1"), Color("#302a48")],
}
const DARK := Color("#22292c")
const INK := Color("#10171d")
const STEEL := Color("#929c9f")
const FRONT := Vector3(0, 0, 1)
const FACE_UP := Vector3(PI / 2, 0, 0)
var id: String
var paint: Color
var accent: Color
var upholstery: Color
const DECK_MATERIAL := {P.SHRIKE: "carbon", P.ORRERY: "walnut", P.KILN: "casting", P.VESPER: "porcelain"}
var facing := []
var panels := []
var trim := []


func _init(vehicle: String) -> void:
	id = vehicle
	paint = FINISHES[id][0]
	accent = FINISHES[id][1]
	upholstery = FINISHES[id][2]


func dial_layout() -> Array:
	var gauges := Layout.GAUGES.duplicate(true)
	for i in gauges.size():
		var at: Vector3 = STATIONS[id][i]
		var gauge: Dictionary = gauges[i]
		gauge.x = at.x
		gauge.y = at.y
		for key in ["rf", "ro", "rg", "face", "mouth"]:
			gauge[key] *= at.z
	return gauges


func _batched_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for group in [[panels, Finish.powder_coat()], [trim, Finish.satin()], [facing, Finish.deck_finish(DECK_MATERIAL[id])]]:
		var pieces: Array = group[0]
		if not pieces.is_empty():
			Kit.compound(pieces, mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, group[1])
			pieces.clear()
	return mesh


func _flush(parent: Node3D, label: String) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = _batched_mesh()
	parent.add_child(node)


func _bar(parts: Array, a: Vector3, b: Vector3, radius: float, colour: Color, sides := 12) -> void:
	var axis := b - a
	var across := axis.cross(Vector3.FORWARD if absf(axis.normalized().z) < .9 else Vector3.RIGHT).normalized()
	var basis := Basis(across, axis.normalized(), across.cross(axis.normalized()))
	parts.append([Kit.cyl(radius, radius, axis.length(), sides), Transform3D(basis, (a + b) * .5), colour])


func _arc(x: float, y: float, z: float) -> Vector3:
	return Kit.on_arc(x, y, z, Layout.R).origin


## Sweep a solid panel through vertical sections (arc x, bottom, top). The two narrow
## edge bands turn back into the face, so the edges catch light when seen from the seat.
func _profile(stations: Array, depth: float, colour: Color, thickness := .032) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous: Array[Vector3] = []
	for s: Vector3 in stations:
		var ring: Array[Vector3] = []
		for yz in [
			Vector2(s.y, depth - .003),
			Vector2(s.y + .004, depth),
			Vector2(s.z - .004, depth),
			Vector2(s.z, depth - .003),
			Vector2(s.z, depth - thickness),
			Vector2(s.y, depth - thickness)
		]:
			ring.append(_arc(s.x, yz.x, yz.y))
		if not previous.is_empty():
			var normals := [Vector3(0, -1, 1), FRONT, Vector3(0, 1, 1), Vector3.UP, -FRONT, Vector3.DOWN]
			for i in ring.size():
				var j := (i + 1) % ring.size()
				Finish._quad(st, previous[i], ring[i], ring[j], previous[j], normals[i])
		if s == stations.front() or s == stations.back():
			for i in range(1, ring.size() - 1):
				Finish._triangle(
					st, ring[0], ring[i], ring[i + 1], Vector3.LEFT if previous.is_empty() else Vector3.RIGHT
				)
		previous = ring
	if id == P.ORRERY:
		panels.append([st.commit(), Transform3D.IDENTITY, colour])
	else:
		facing.append([st.commit(), Transform3D.IDENTITY, colour])


func _line(stations: Array, z: float, radius: float, colour: Color) -> void:
	for i in range(1, stations.size()):
		var a: Vector2 = stations[i - 1]
		var b: Vector2 = stations[i]
		_bar(trim, _arc(a.x, a.y, z), _arc(b.x, b.y, z), radius, colour)


func _dial(g: Dictionary) -> void:
	var frame := Kit.on_arc(g.x, g.y, 0, Layout.R)
	# Revolve the actual open instrument cup from the bottom of the face to the glass seat.
	var section := [
		Vector2(g.rf * .985, g.face - .001),
		Vector2(g.rf * 1.01, g.face + .002),
		Vector2(g.rg - .001, g.mouth - Layout.SEAT),
		Vector2(g.rg, g.mouth - .003),
		Vector2(g.ro - .001, g.mouth),
		Vector2(g.ro, g.mouth - .0035),
		Vector2(g.ro, -.014)
	]
	var dark := SurfaceTool.new()
	var metal := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in section.size() - 1:
		var a: Vector2 = section[i]
		var b: Vector2 = section[i + 1]
		for j in 56:
			var t := TAU * j / 56.0
			var u := TAU * (j + 1) / 56.0
			var va := Vector3(cos(t), sin(t), 0)
			var vb := Vector3(cos(u), sin(u), 0)
			var normal := (va + vb).normalized() * (a.y - b.y) + FRONT * (b.x - a.x)
			Finish._quad(
				metal if i in [3, 4] else dark,
				va * a.x + FRONT * a.y,
				vb * a.x + FRONT * a.y,
				vb * b.x + FRONT * b.y,
				va * b.x + FRONT * b.y,
				normal
			)
	panels.append([dark.commit(), frame, INK])
	trim.append([metal.commit(), frame, accent if id in [P.ORRERY, P.VESPER] else STEEL])
	# Hub over the two needle roots.
	trim.append(
		[Kit.cyl(g.rf * .065, g.rf * .075, .006, 16), frame * Kit.at(Vector3(0, 0, g.face + .009), FACE_UP), DARK]
	)


func fit_cluster(parent: Node3D, gauges: Array) -> void:
	# Independent lower trays carry the unchanged LCDs. Keep their frames outside the active glass.
	for w in Layout.WINDOWS:
		var mount := Kit.on_arc(w[1], w[2], 0, Layout.R)
		panels.append(
			[
				Finish.beveled_plate(Vector3(w[3] * 2 + .015, .022, w[4] * 2 + .014), .002),
				mount * Kit.at(Vector3(0, 0, .003), FACE_UP),
				DARK
			]
		)
	match id:
		P.SHRIKE:
			# A light sprint rack: individual pods on a triangulated vermilion frame.
			for side in [-1.0, 1.0]:
				for run in [
					[Vector2(.025, -.087), Vector2(.42, .049)],
					[Vector2(.04, .103), Vector2(.418, -.065)],
					[Vector2(.026, -.079), Vector2(.438, -.066)]
				]:
					_line([run[0] * Vector2(side, 1), run[1] * Vector2(side, 1)], -.001, .009, accent)
				_profile(
					[
						Vector3(side * .14, -.077, .015),
						Vector3(side * .27, -.077, .088),
						Vector3(side * .44, -.067, .037)
					],
					-.013,
					paint
				)
		P.ORRERY:
			# A lacquered, scalloped instrument desk with a continuous brass gallery rail.
			var top := []
			var brass := []
			for j in 41:
				var x := (j - 20) * .023
				var crest := (
					.117 + .055 * exp(-pow(x / .135, 2.0)) - .039 * exp(-pow((absf(x) - .205) / .060, 2.0))
				)
				top.append(Vector3(x, -.088, crest))
				brass.append(Vector2(x, crest - .006))
			_profile(top, 0, paint)
			_line(brass, .002, .0035, accent)
			_line(
				[
					Vector2(-.44, -.079),
					Vector2(-.22, -.079),
					Vector2(0, -.079),
					Vector2(.22, -.079),
					Vector2(.44, -.079)
				],
				.003,
				.0025,
				accent
			)
		P.KILN:
			# Three replaceable castings. Each side cartridge contains one bank's two gauges.
			for span: Vector2 in [Vector2(-.466, -.115), Vector2(-.108, .108), Vector2(.115, .466)]:
				var left := span.x
				var right := span.y
				_profile(
					[
						Vector3(left, -.067, .096),
						Vector3(left + .015, -.084, .117),
						Vector3(right - .015, -.084, .117),
						Vector3(right, -.067, .096)
					],
					.001,
					paint,
					.046
				)
				for x in [left + .014, right - .014]:
					for y in [-.059, .094]:
						trim.append(
							[
								Finish.slotted_screw(.005),
								Kit.on_arc(x, y, .004, Layout.R) * Kit.at(Vector3.ZERO, FACE_UP),
								STEEL
							]
						)
			for side in [-1.0, 1.0]:
				for k in 7:
					var x: float = side * (.15 + .042 * k)
					_line([Vector2(x, -.078), Vector2(x + .012, -.061)], .004, .0036, accent)
		P.VESPER:
			# Separate swept blades carry the offset speed head, twin drives and starboard systems.
			for wing in [
				[
					Vector3(-.466, -.062, .041),
					Vector3(-.39, -.078, .132),
					Vector3(-.246, -.052, .143),
					Vector3(-.183, -.024, .080)
				],
				[
					Vector3(-.186, -.084, .025),
					Vector3(-.14, -.072, .080),
					Vector3(.146, -.039, .119),
					Vector3(.203, -.013, .082)
				],
				[
					Vector3(.186, -.067, -.008),
					Vector3(.233, -.055, .062),
					Vector3(.396, -.012, .122),
					Vector3(.462, .032, .127)
				]
			]:
				_profile(wing, .001, paint)
				var edge := []
				for p: Vector3 in wing:
					edge.append(Vector2(p.x, p.y + .004))
				_line(edge, .004, .003, accent)
	for g: Dictionary in gauges:
		_dial(g)
	_flush(parent, "binnacle")


## One punched bay of a sprint heel tray. Its top sheet turns down into the hole,
## leaving the backing pan visible 8 mm below it. Adjacent bay edges meet exactly.
func _punched_bay() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 32:
		var rings := []
		for k in [j, j + 1]:
			var d := Vector2.from_angle(TAU * k / 32.0 + PI * .25)
			var edge := d / maxf(absf(d.x), absf(d.y))
			rings.append(
				[
					Vector3(edge.x * .074, .008, edge.y * .087),
					Vector3(d.x * .035, .008, d.y * .035),
					Vector3(d.x * .030, .005, d.y * .030),
					Vector3(d.x * .030, .001, d.y * .030)
				]
			)
		var inward: Vector3 = -rings[0][1]
		inward.y = 0
		for i in 3:
			var normal := Vector3.UP if i == 0 else (inward.normalized() + Vector3.UP if i == 1 else inward)
			Finish._quad(st, rings[0][i], rings[1][i], rings[1][i + 1], rings[0][i + 1], normal)
	return st.commit()


## Replace the two pressed tread panels and the narrow brightwork at the throttle slots
## as a unit. The continuous walking deck and open quadrant gates below them stay in place.
func _floor() -> ArrayMesh:
	for side: float in [-1.0, 1.0]:
		var cx := side * .201
		var plate := Finish.beveled_plate(Vector3(.378, .008, 1.035), .003)
		panels.append([plate, Kit.at(Vector3(cx, .141, 0)), upholstery])
		match id:
			P.SHRIKE:
				var bay := _punched_bay()
				for j in 5:
					var z := -.348 + j * .174
					for dx in [-.074, .074]:
						trim.append([bay, Kit.at(Vector3(cx + dx, .145, z)), Color("#596169")])
					panels.append([Kit.box(Vector3(.277, .003, .008)), Kit.at(Vector3(cx, .154, z + .064)), DARK])
				trim.append(
					[Kit.box(Vector3(.007, .005, .84)), Kit.at(Vector3(cx + .158 * side, .147, 0)), accent]
				)
			P.ORRERY:
				# Oiled slats with a black seam between boards and brass end straps.
				for j in 5:
					var x := cx + (j - 2) * .067
					var colour := Color("#805a3d").lerp(Color("#af8154"), float((j * 3) % 5) * .14)
					facing.append(
						[Finish.beveled_plate(Vector3(.063, .008, .954)), Kit.at(Vector3(x, .148, 0)), colour]
					)
				for z in [-.449, .449]:
					trim.append([Kit.box(Vector3(.343, .003, .020)), Kit.at(Vector3(cx, .154, z)), accent])
			P.KILN:
				# Bar grating over the dark drain pan. The backing remains visible through every slot.
				for j in 5:
					trim.append(
						[Kit.box(Vector3(.008, .007, .915)), Kit.at(Vector3(cx + (j - 2) * .072, .147, 0)), STEEL]
					)
				for j in 15:
					trim.append(
						[
							Finish.beveled_plate(Vector3(.337, .008, .023)),
							Kit.at(Vector3(cx, .152, -.441 + .063 * j)),
							Color("#69706b")
						]
					)
				for z in [-.477, .477]:
					panels.append([Kit.box(Vector3(.336, .004, .029)), Kit.at(Vector3(cx, .147, z)), accent])
			P.VESPER:
				# Three flush longitudinal runners taper toward the toe.
				for j in 3:
					var x := cx + (j - 1) * .092
					var a := Vector3(x - side * .036, .149, -.438 + .050 * j)
					var b := Vector3(x + side * .029, .149, .414 - .045 * j)
					_bar(trim, a, b, .007, accent if j == 1 else paint)
		for z in [-.482, .482]:
			for dx in [-.159, .159]:
				trim.append([Finish.slotted_screw(.004), Kit.at(Vector3(cx + dx, .150, z)), STEEL])
		for edge in [-1, 1]:
			trim.append(
				[
					Kit.box(Vector3(.014, .003, .267)),
					Kit.at(Vector3(side * .46 + edge * .034, .1435, .2035)),
					STEEL
				]
			)
	return _batched_mesh()


## The three fleet cabs have wider bespoke glare shields. Return their underside to
## the dashboard's existing upper edge so daylight cannot appear through the fascia.
func _glare_shield_return(interior: Node3D) -> void:
	var sweep: float = {P.ORRERY: .43, P.KILN: .31, P.VESPER: .54}[id]
	var width: float = {P.ORRERY: .74, P.KILN: .79, P.VESPER: .73}[id]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := PackedVector3Array()
	for i in 65:
		var x := lerpf(-.705, .705, i / 64.0)
		var t := absf(x) / width
		var top := Vector3(x, .536 + .014 * t, -.525 + sweep * pow(t, 1.45 if id == P.KILN else 2.3))
		var z: float = (
			interior.CM.OPEN_ZC - interior.CM.OPEN_AZ_FRONT * sqrt(1.0 - pow(x / interior.CM.OPEN_AX, 2.0))
		)
		var bottom := Vector3(x, interior.CM.hull_top(x, z) + interior.CM.POD_FRAME_UP - .088, z + .009)
		var fold := Vector3(x, top.y - .012, top.z - .012)
		var row := PackedVector3Array([bottom, fold, top])
		if not previous.is_empty():
			for j in 2:
				Finish._quad(st, previous[j], row[j], row[j + 1], previous[j + 1], Vector3(0, .35, 1))
		previous = row
	panels.append([st.commit(), Transform3D.IDENTITY, upholstery])


func fit_cabin(interior: Node3D) -> void:
	# The hip liners and dashboard retain their original clearances. The outer sill carries
	# the craft-specific fittings, outboard of the switches and the entire lever sweep.
	var bezel: MeshInstance3D = interior.get_node("InstrumentBezel")
	bezel.set_surface_override_material(0, null)
	bezel.mesh = _floor()
	if id != P.SHRIKE:
		_glare_shield_return(interior)
	for part in ["SeatTub", "Dashboard"]:
		var panel := interior.get_node_or_null(part) as MeshInstance3D
		if panel:
			panel.material_override = Finish.tinted(
				("webbing" if id == P.SHRIKE else "leather") if part == "SeatTub" else DECK_MATERIAL[id],
				upholstery if part == "SeatTub" else (Color("#966743") if id == P.ORRERY else paint.darkened(.26))
			)
	for s in [-1.0, 1.0]:
		match id:
			P.SHRIKE:
				for k in 4:
					var z := -.10 + .23 * k
					_bar(trim, Vector3(s * .71, .425, z), Vector3(s * .725, .50, z + .18), .011, accent)
				_bar(trim, Vector3(s * .725, .50, -.10), Vector3(s * .725, .50, .80), .014, paint)
			P.ORRERY:
				for y in [.453, .49]:
					_bar(trim, Vector3(s * .721, y, -.12), Vector3(s * .736, y, .84), .007, accent)
				for k in 4:
					var z := -.1 + .30 * k
					_bar(trim, Vector3(s * .737, .413, z), Vector3(s * .727, .495, z), .012, accent)
			P.KILN:
				for z in [.05, .47]:
					var rail := [
						Vector3(s * .706, .408, z),
						Vector3(s * .72, .476, z + .026),
						Vector3(s * .72, .476, z + .215),
						Vector3(s * .706, .408, z + .241)
					]
					for k in 3:
						_bar(trim, rail[k], rail[k + 1], .016, accent)
					_bar(panels, rail[1].lerp(rail[2], .15), rail[1].lerp(rail[2], .85), .020, DARK)
			P.VESPER:
				for k in 3:
					var z := -.15 + k * .24
					panels.append(
						[
							Kit.rounded_box(Vector3(.044, .066, .224), 4.0, 8),
							Kit.at(Vector3(s * .724, .449, z + .13), Vector3(-.15, 0, s * .18)),
							paint
						]
					)
					_bar(trim, Vector3(s * .699, .438, z + .032), Vector3(s * .699, .463, z + .228), .0035, accent)
	_flush(interior, "SillFittings")
