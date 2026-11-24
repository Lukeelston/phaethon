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
	# The Basilisk builds the Kiln's deck (sim/pilot_craft.gd deck_of) in its own hull's colours: gunmetal, amber, tan.
	P.BASILISK: [Color("#474e49"), Color("#e59a2c"), Color("#8c7353")],
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
	id = P.deck_of(vehicle)      # (the layout: a craft drawn from another builds that one's deck)
	var finish := finishes_for(vehicle)
	paint = finish[0]
	accent = finish[1]
	upholstery = finish[2]


## Is there a fleet deck for this craft (its own, or the one it was drawn from)?
static func has_deck(vehicle: Variant) -> bool:
	return STATIONS.has(P.deck_of(vehicle))


## Dash panels, exposed structure, upholstery: the craft's own finishes, else those of the deck it builds.
static func finishes_for(vehicle: Variant) -> Array:
	return FINISHES.get(P.known(vehicle), FINISHES.get(P.deck_of(vehicle), []))


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
			Kit.compound(pieces, mesh, true)
			mesh.surface_set_material(mesh.get_surface_count() - 1, group[1])
			pieces.clear()
	return mesh


func _flush(parent: Node3D, label: String) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = _batched_mesh()
	parent.add_child(node)


## A continuous bent tube with a rolled end on each exposed cut. Ring frames
## follow the spine, so a bent grab handle has no capped-cylinder joints.
func _tube(parts: Array, path: Array, radius: float, colour: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 16 if radius > .008 else 12
	var lip := minf(radius * .22, path[0].distance_to(path[1]) * .25)
	lip = minf(lip, path.back().distance_to(path[-2]) * .25)
	var previous := []
	var previous_normals := []
	var across := Vector3.ZERO
	for i in path.size():
		var centre: Vector3 = path[i]
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		if i == 0:
			across = tangent.cross(Vector3.UP if absf(tangent.y) < .9 else Vector3.RIGHT)
		across = across.slide(tangent).normalized()
		var around := tangent.cross(across)
		var end_sign := -1 if i == 0 else (1 if i == path.size() - 1 else 0)
		var count := (3 if radius > .008 else 2) if end_sign != 0 else 1
		for step in count:
			var angle := 0.0
			if end_sign != 0:
				angle = PI * .5 * float(count - 1 - step if end_sign < 0 else step) / (count - 1)
			var ring_centre := centre - end_sign * tangent * lip * (1 - sin(angle))
			var ring := []
			var normals := []
			for j in sides:
				var theta := TAU * j / sides
				var radial := across * cos(theta) + around * sin(theta)
				ring.append(ring_centre + radial * (radius - lip + lip * cos(angle)))
				normals.append(radial * cos(angle) + end_sign * tangent * sin(angle))
			for j in sides:
				var k := (j + 1) % sides
				if not previous.is_empty():
					_smooth_quad(st, [previous[j], ring[j], ring[k], previous[k]],
						[previous_normals[j], normals[j], normals[k], previous_normals[k]])
				if angle > 1.56:
					Finish._triangle(st, ring_centre, ring[j], ring[k], end_sign * tangent)
			previous = ring
			previous_normals = normals
	parts.append([st.commit(), Transform3D.IDENTITY, colour])


func _bar(parts: Array, a: Vector3, b: Vector3, radius: float, colour: Color) -> void:
	_tube(parts, [a, b], radius, colour)


## Quadratic tangent returns retain the designed silhouette through each bend.
## Subdivide long spans in the flat pattern before wrapping it onto the dash.
func _rounded_path(stations: Array, setback: float, spacing := .045) -> Array:
	var bends := [stations[0]]
	for i in range(1, stations.size() - 1):
		var at: Vector3 = stations[i]
		var incoming: Vector3 = stations[i - 1] - at
		var outgoing: Vector3 = stations[i + 1] - at
		if incoming.normalized().dot(outgoing.normalized()) < -.997:
			bends.append(at)
			continue
		var cut := minf(setback, minf(incoming.length(), outgoing.length()) * .36)
		var a := at + incoming.normalized() * cut
		var b := at + outgoing.normalized() * cut
		for j in 5:
			var t := j * .25
			bends.append(a.lerp(at, t).lerp(at.lerp(b, t), t))
	bends.append(stations.back())
	var path := [bends[0]]
	for i in range(1, bends.size()):
		var a: Vector3 = bends[i - 1]
		var b: Vector3 = bends[i]
		var count := maxi(1, ceili(a.distance_to(b) / spacing))
		for j in range(1,count + 1):
			path.append(a.lerp(b, float(j) / count))
	return path


func _arc(x: float, y: float, z: float) -> Vector3:
	return Kit.on_arc(x, y, z, Layout.R).origin


## Clockwise triangles with a separate lighting normal at each corner. This keeps a
## highlight continuous across the little segments of a rolled lip.
func _smooth_quad(st: SurfaceTool, points: Array, normals: Array) -> void:
	var order := [0, 2, 1, 0, 3, 2]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(normals[0]) < 0:
		order = [0, 1, 2, 0, 2, 3]
	for i in order:
		st.set_normal(normals[i])
		st.add_vertex(points[i])


func _profile(stations: Array, depth: float, colour: Color, thickness := .032) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The port sprint rack is authored from inboard out, in the opposite direction.
	var ordered := stations.duplicate()
	if ordered.front().x > ordered.back().x:
		ordered.reverse()
	ordered = _rounded_path(ordered, .012)
	# Roll the cut ends as well as the long upper and lower edges. Closely
	# spaced slices fit a quarter circle tangent to both the cap and the face.
	var end_radius := minf(.003, minf(ordered[1].x - ordered[0].x, ordered[-1].x - ordered[-2].x) * .75)
	var first: Vector3 = ordered.front()
	var last: Vector3 = ordered.back()
	var first_slope: Vector3 = (ordered[1] - first) / (ordered[1].x - first.x)
	var last_slope: Vector3 = (last - ordered[-2]) / (last.x - ordered[-2].x)
	for step in range(1,5):
		var offset := end_radius * (1.0 - cos(PI * .125 * step))
		ordered.insert(step, first + first_slope * offset)
		ordered.insert(ordered.size() - step, last - last_slope * offset)
	var previous: Array[Vector3] = []
	var previous_normals: Array[Vector3] = []
	for k in ordered.size():
		var station: Vector3 = ordered[k]
		var tangent: Vector3 = ordered[mini(k + 1, ordered.size() - 1)] - ordered[maxi(k - 1, 0)]
		var frame := Kit.on_arc(station.x, 0, depth, Layout.R)
		var ring: Array[Vector3] = []
		var normals: Array[Vector3] = []
		var end_weight := 1.0 - clampf(minf(station.x - first.x, last.x - station.x) / end_radius, 0, 1)
		var face_weight := sqrt(maxf(0.0, 1.0 - end_weight * end_weight))
		var inset := end_radius * (1.0 - face_weight)
		var end_normal := Vector3.LEFT if station.x < (first.x + last.x) * .5 else Vector3.RIGHT
		var radius := minf(.004, (station.z - station.y) * .24)
		# Start on the lower back edge and travel round the face to the upper back.
		for side: float in [-1.0, 1.0]:
			var height := station.y if side < 0 else station.z
			var slope := (tangent.y if side < 0 else tangent.z) / tangent.x
			var edge := (Vector3(-slope, 1, 0) * side).normalized()
			for step in 5:
				var index := step if side < 0 else 4 - step
				var angle := PI * .5 * maxf(index - 1, 0) / 3
				var y := height - side * (inset + radius * (1 - cos(angle)))
				var z := depth - thickness + inset if index == 0 else depth - inset - radius + radius * sin(angle)
				ring.append(_arc(station.x, y, z))
				var across := (edge * cos(angle) + FRONT * sin(angle)).normalized()
				normals.append((frame.basis * (across * face_weight + end_normal * end_weight)).normalized())
		if not previous.is_empty():
			for i in ring.size() - 1:
				var j := i + 1
				_smooth_quad(st, [previous[i], ring[i], ring[j], previous[j]],
					[previous_normals[i], normals[i], normals[j], previous_normals[j]])
			Finish._quad(st, previous.back(), ring.back(), ring.front(), previous.front(), -frame.basis.z)
		if k == 0 or k == ordered.size() - 1:
			for i in range(1, ring.size() - 1):
				Finish._triangle(st, ring[0], ring[i], ring[i + 1], frame.basis.x * (-1 if k == 0 else 1))
		previous = ring
		previous_normals = normals
	var parts := panels if id == P.ORRERY else facing
	parts.append([st.commit(), Transform3D.IDENTITY, colour])


func _line(stations: Array, z: float, radius: float, colour: Color) -> void:
	var flat := []
	for point: Vector2 in stations:
		flat.append(Vector3(point.x, point.y, z))
	var path := []
	for point: Vector3 in _rounded_path(flat, .014):
		path.append(_arc(point.x, point.y, z))
	_tube(trim, path, radius, colour)


func _dial(g: Dictionary) -> void:
	var frame := Kit.on_arc(g.x, g.y, 0, Layout.R)
	# Revolve the actual open instrument cup from the bottom of the face to the glass seat.
	var section := [
		Vector2(g.rf * .985, g.face - .001),
		Vector2(g.rf * 1.01, g.face + .002),
		Vector2(g.rg - .001, g.mouth - Layout.SEAT),
		Vector2(g.rg, g.mouth - .0024),
		Vector2(g.rg + .0006, g.mouth - .0008),
		Vector2(g.rg + .0020, g.mouth),
		Vector2(g.ro - .0020, g.mouth),
		Vector2(g.ro - .0006, g.mouth - .0007),
		Vector2(g.ro, g.mouth - .0021),
		Vector2(g.ro, -.014)
	]
	var dark := SurfaceTool.new()
	var metal := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	metal.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 56
	var circle := PackedVector3Array()
	for j in SEGMENTS:
		var angle := TAU * j / SEGMENTS
		circle.append(Vector3(cos(angle), sin(angle), 0))
	circle.append(circle[0])
	for i in section.size() - 1:
		var a: Vector2 = section[i]
		var b: Vector2 = section[i + 1]
		# Adjacent bands share a tangent at each ring, including across the metal/paint seam.
		var before: Vector2 = section[maxi(0, i - 1)]
		var after: Vector2 = section[mini(section.size() - 1, i + 2)]
		var along := a.direction_to(b)
		var start_tangent := (before.direction_to(a) + along).normalized()
		var end_tangent := (along + b.direction_to(after)).normalized()
		var surface := metal if i >= 3 and i < section.size() - 2 else dark
		for j in SEGMENTS:
			var left := circle[j]
			var right := circle[j + 1]
			_smooth_quad(surface,
				[left * a.x + FRONT * a.y, right * a.x + FRONT * a.y,
				 right * b.x + FRONT * b.y, left * b.x + FRONT * b.y],
				[FRONT * start_tangent.x - left * start_tangent.y,
				 FRONT * start_tangent.x - right * start_tangent.y,
				 FRONT * end_tangent.x - right * end_tangent.y,
				 FRONT * end_tangent.x - left * end_tangent.y])

	panels.append([dark.commit(), frame, INK])
	trim.append([metal.commit(), frame, accent if id in [P.ORRERY, P.VESPER] else STEEL])
	# Hub over the two needle roots.
	_bar(trim, frame * Vector3(0, 0, g.face + .006), frame * Vector3(0, 0, g.face + .012), g.rf * .071, DARK)


## A formed LCD tray. The glass overlaps the inner ledge and sits below the
## rolled lip. All section dimensions are measured from the edge of the glass.
func _lcd_tray(half_size: Vector2, glass_z: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner_centres := half_size - Vector2.ONE * .0035
	var outline := PackedVector2Array()
	var radial := PackedVector2Array()
	for corner in 4:
		var start := corner * PI * .5
		var centre := Vector2.from_angle(start + PI * .25).sign() * corner_centres
		for step in 5:
			var direction := Vector2.from_angle(start + step * PI / 8)
			outline.append(centre + direction * .0035)
			radial.append(direction)
	# Cross section (distance outside glass, height relative to glass). The lower
	# rim lands on the carrier. Millimetre-scale rolls soften both edges of the lip.
	var profile := PackedVector2Array([
		Vector2(-.0016,-.00015), Vector2(-.0006,-.00015), Vector2(.0001,.00025),
		Vector2(.0010,.00175), Vector2(.0016,.00235), Vector2(.0025,.0026),
		Vector2(.0054,.0026), Vector2(.0064,.00235), Vector2(.0071,.00165),
		Vector2(.0074,.0006), Vector2(.0074,-.0225), Vector2(.0070,-.0236),
		Vector2(.0060,-.0240)])
	var rings := []
	var normals := []
	for row in profile.size():
		var tangent := Vector2.ZERO
		if row > 0:
			tangent += profile[row - 1].direction_to(profile[row])
		if row + 1 < profile.size():
			tangent += profile[row].direction_to(profile[row + 1])
		var normal := tangent.normalized().orthogonal() * -1
		var points := PackedVector3Array()
		var directions := PackedVector3Array()
		for index in outline.size():
			var xy := outline[index] + radial[index] * profile[row].x
			points.append(Vector3(xy.x, xy.y, glass_z + profile[row].y))
			directions.append(Vector3(radial[index].x * normal.x, radial[index].y * normal.x, normal.y))
		rings.append(points)
		normals.append(directions)
		if row == 0:
			continue
		for index in outline.size():
			var next := (index + 1) % outline.size()
			_smooth_quad(st, [rings[row-1][index], rings[row-1][next], points[next], points[index]],
					[normals[row-1][index], normals[row-1][next], directions[next], directions[index]])
	# Close the rear of the tray. The front aperture stays open around the display.
	var back: PackedVector3Array = rings.back()
	for i in back.size():
		Finish._triangle(st, Vector3(0,0,back[i].z), back[i], back[(i+1) % back.size()], -FRONT)
	st.index()
	return st.commit()


func fit_cluster(parent: Node3D, gauges: Array) -> void:
	for w in Layout.WINDOWS:
		var mount := Kit.on_arc(w[1], w[2], 0, Layout.R)
		panels.append([_lcd_tray(Vector2(w[3], w[4]), w[5] + .0006), mount, DARK])
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
			var screw := Finish.socket_screw(.005, STEEL)
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
								screw,
								Kit.on_arc(x, y, .001, Layout.R) * Kit.at(Vector3.ZERO, FACE_UP),
								Color.WHITE, true
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
					Vector3(-.189, -.024, .080)
				],
				[
					Vector3(-.186, -.084, .025),
					Vector3(-.14, -.072, .080),
					Vector3(.146, -.039, .119),
					Vector3(.186, -.013, .082)
				],
				[
					Vector3(.191, -.067, -.008),
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
	var previous := []
	var previous_normals := []
	for j in 25:
		var direction := Vector2.from_angle(TAU * (j % 24) / 24.0 + PI * .25)
		var edge := direction / maxf(absf(direction.x), absf(direction.y))
		var radial := Vector3(direction.x, 0, direction.y)
		var ring := [Vector3(edge.x * .074, .008, edge.y * .087)]
		var normals := [Vector3.UP]
		for k in 4:
			var angle := PI * k / 6.0
			ring.append(radial * (.035 - .005 * sin(angle)) + Vector3.UP * (.003 + .005 * cos(angle)))
			normals.append(Vector3.UP * cos(angle) - radial * sin(angle))
		ring.append(radial * .030 + Vector3.UP * .001)
		normals.append(-radial)
		if j > 0:
			for k in ring.size() - 1:
				_smooth_quad(st, [previous[k], ring[k], ring[k + 1], previous[k + 1]],
					[previous_normals[k], normals[k], normals[k + 1], previous_normals[k + 1]])
		previous = ring
		previous_normals = normals
	return st.commit()


## Replace the two pressed tread panels and the narrow brightwork at the throttle slots
## as a unit. The continuous walking deck and open quadrant gates below them stay in place.
func _floor() -> ArrayMesh:
	var screw := Finish.socket_screw(.004, STEEL)
	for side: float in [-1.0, 1.0]:
		var cx := side * .201
		var plate := Finish.rounded_slab(Vector3(.378, .008, 1.035))
		panels.append([plate, Kit.at(Vector3(cx, .141, 0)), upholstery])
		match id:
			P.SHRIKE:
				var bay := _punched_bay()
				for j in 5:
					var z := -.348 + j * .174
					for dx in [-.074, .074]:
						trim.append([bay, Kit.at(Vector3(cx + dx, .145, z)), Color("#596169")])
					panels.append([Finish.rounded_slab(Vector3(.277, .003, .008)), Kit.at(Vector3(cx, .154, z + .064)), DARK])
				trim.append(
					[Finish.rounded_slab(Vector3(.007, .005, .84)), Kit.at(Vector3(cx + .158 * side, .147, 0)), accent]
				)
			P.ORRERY:
				# Oiled slats with a black seam between boards and brass end straps.
				for j in 5:
					var x := cx + (j - 2) * .067
					var colour := Color("#805a3d").lerp(Color("#af8154"), float((j * 3) % 5) * .14)
					facing.append(
						[Finish.rounded_slab(Vector3(.063, .008, .954)), Kit.at(Vector3(x, .148, 0)), colour]
					)
				for z in [-.449, .449]:
					trim.append([Finish.rounded_slab(Vector3(.343, .003, .020)), Kit.at(Vector3(cx, .1535, z)), accent])
			P.KILN:
				# Bar grating over the dark drain pan. The backing remains visible through every slot.
				for j in 5:
					trim.append(
						[Finish.rounded_slab(Vector3(.008, .007, .915)), Kit.at(Vector3(cx + (j - 2) * .072, .147, 0)), STEEL]
					)
				for j in 15:
					trim.append(
						[
							Finish.rounded_slab(Vector3(.337, .008, .023)),
							Kit.at(Vector3(cx, .152, -.441 + .063 * j)),
							Color("#69706b")
						]
					)
				for z in [-.477, .477]:
					panels.append([Finish.rounded_slab(Vector3(.336, .004, .029)), Kit.at(Vector3(cx, .147, z)), accent])
			P.VESPER:
				# Three flush longitudinal runners taper toward the toe.
				for j in 3:
					var x := cx + (j - 1) * .092
					var a := Vector3(x - side * .036, .149, -.438 + .050 * j)
					var b := Vector3(x + side * .029, .149, .414 - .045 * j)
					_bar(trim, a, b, .007, accent if j == 1 else paint)
		for z in [-.482, .482]:
			for dx in [-.179, .179]:
				trim.append([screw, Kit.at(Vector3(cx + dx, .145, z)), Color.WHITE, true])
		for edge in [-1, 1]:
			trim.append(
				[
					Finish.rounded_slab(Vector3(.014, .003, .267)),
					Kit.at(Vector3(side * .46 + edge * .034, .1415, .2035)),
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


const WELT_STEPS := 6

## Contact and normal for one point on the rolled leather section. The same
## section revolves through a half circle at each end, like the toe of a cushion.
func _welt_band(shell: TriangleMesh, frame: Transform3D, radial: Vector3, step: int, groove: float) -> Array:
	var angle := PI * .5 * step / WELT_STEPS
	var width := .013 * sin(angle)
	var dent := (width - groove) / .0015
	var depression := .00055 * exp(-dent * dent)
	var crown := .0058 * cos(angle) - .0008 - depression
	var at := frame.origin + radial * width
	var sample := shell.intersect_ray(at + frame.basis.z * .025, -frame.basis.z)
	var base: Vector3 = sample.get("position", at)
	var normal: Vector3 = sample.get("normal", frame.basis.z)
	# A raised coaming strap can present a near-vertical wall to the sampler.
	# Use the cheek's outward axis for padding thickness, including over straps.
	var dw := .013 * cos(angle)
	var dh := -.0058 * sin(angle) + 2.0 * dent * depression * dw / .0015
	var surface_normal := (normal * dw - radial * dh).normalized()
	return [base + frame.basis.z * crown, surface_normal]


func _welt_cap(skin: SurfaceTool, shell: TriangleMesh, frame: Transform3D, direction: float, groove: float) -> void:
	var previous := []
	for i in 13:
		var angle := PI * i / 12
		var radial := frame.basis.y * cos(angle) + frame.basis.x * direction * sin(angle)
		var ring := []
		for j in WELT_STEPS + 1:
			ring.append(_welt_band(shell, frame, radial, j, groove))
		if i > 0:
			# The centre is one vertex, so the innermost band is a fan.
			_soft_triangle(skin, previous[0], previous[1], ring[1])
			for j in range(1, WELT_STEPS):
				_soft_quad(skin, previous[j], ring[j], ring[j + 1], previous[j + 1])
		previous = ring


func _soft_triangle(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	var normal: Vector3 = a[1] + b[1] + c[1]
	var edge: Vector3 = b[0] - a[0]
	var order := [a, c, b] if edge.cross(c[0] - a[0]).dot(normal) >= 0 else [a, b, c]
	for vertex: Array in order:
		st.set_normal(vertex[1])
		st.add_vertex(vertex[0])


func _soft_quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_soft_triangle(st, a, b, c)
	_soft_triangle(st, a, c, d)


## Welt on the pilot-facing side of the actual fitted coaming. Both long sides
## turn into the shell under the stitches and the leather rolls around the ends.
func fit_stitched_rim(rim: MeshInstance3D) -> void:
	var shell := rim.mesh.generate_triangle_mesh()
	if shell == null:
		return
	var skin := SurfaceTool.new()
	skin.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stitches := []
	var thread := _stitch_mesh()
	var yarn := accent.lerp(Color("#c6b397"), .54)
	var double_row := id in [P.ORRERY, P.VESPER]
	var groove := .0065 if double_row else 0.0
	# Shrike's segmented coaming has a 12 mm joint here. Turn both pieces
	# back onto their own cushion before the moulded shell drops away.
	var spans := [Vector2(.293, .320), Vector2(.370, .498)] if id == P.SHRIKE else [Vector2(.293, .498)]
	for side: float in [-1, 1]:
		for span: Vector2 in spans:
			var previous := []
			var tracks := [Curve3D.new(), Curve3D.new()]
			var intervals := ceili((span.y - span.x) / .008)
			for i in intervals + 1:
				var x := side * lerpf(span.x, span.y, float(i) / intervals)
				var t := (absf(x) - .293) / .205
				var y := (.597 - .010 * t) if id == P.SHRIKE else (.593 + .005 * t)
				var hit := shell.intersect_ray(Vector3(x, y, 0), Vector3.FORWARD)
				if hit.is_empty():
					continue
				var normal: Vector3 = hit.normal
				var up := Vector3.UP.slide(normal).normalized()
				var frame := Transform3D(Basis(up.cross(normal), up, normal), hit.position)
				var row := []
				for j in range(-WELT_STEPS, WELT_STEPS + 1):
					row.append(_welt_band(shell, frame, -up if j < 0 else up, absi(j), groove))
				if not previous.is_empty():
					for j in row.size() - 1:
						_soft_quad(skin, previous[j], row[j], row[j + 1], previous[j + 1])
				if i == 0 or i == intervals:
					_welt_cap(skin, shell, frame, -side if i == 0 else side, groove)
				tracks[0].add_point(row[WELT_STEPS - 2 if double_row else WELT_STEPS][0])
				tracks[1].add_point(row[WELT_STEPS + 2][0])
				previous = row
			for row_index in (2 if double_row else 1):
				var path: Curve3D = tracks[row_index]
				path.bake_interval = .002
				var length := path.get_baked_length()
				var count := floori(length / .0072)
				for i in count:
					var distance := (i + .5) * length / count
					var start := path.sample_baked(distance - .0025)
					var end := path.sample_baked(distance + .0025)
					var along := start.direction_to(end)
					var middle := (start + end) * .5
					var hit := shell.intersect_ray(Vector3(middle.x, middle.y, 0), Vector3.FORWARD)
					var support: Vector3 = hit.get("normal", along.cross(Vector3.UP) * side)
					var out := support.slide(along).normalized()
					var up := out.cross(along).normalized()
					stitches.append([thread, Transform3D(Basis(along, up, out), middle), yarn])
	if stitches.is_empty():
		return
	skin.index()
	var mesh := skin.commit()
	mesh.surface_set_material(0, Finish.tinted("leather", upholstery))
	Kit.compound(stitches, mesh, true)
	mesh.surface_set_material(1, Finish.webbing())
	var pad := MeshInstance3D.new()
	pad.name = "StitchedWelt"
	pad.mesh = mesh
	rim.add_child(pad)


func _stitch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := []
	var previous_normals := []
	# Each curved strand narrows into the punctures. Smooth normals carry the
	# highlight along its crown even when the light grazes the leather.
	for i in 6:
		var t := i / 5.0
		var arch := sin(PI * t)
		var centre := Vector3(lerpf(-.0025,.0025,t), lerpf(-.00028,.00028,t), -.00065 + .0014 * arch)
		var axis := Vector3(.005, .00056, .0014 * PI * cos(PI * t)).normalized()
		var across := Vector3.UP.slide(axis).normalized()
		var outward := axis.cross(across)
		var row := []
		var normals := []
		for j in 5:
			var angle := TAU * j / 5
			var normal := across * cos(angle) + outward * sin(angle)
			normals.append(normal)
			row.append(centre + normal * lerpf(.00032, .00059, arch))
		if not previous.is_empty():
			for j in 5:
				var k := (j + 1) % 5
				_smooth_quad(st, [previous[j], row[j], row[k], previous[k]],
					[previous_normals[j], normals[j], normals[k], previous_normals[k]])
		previous = row
		previous_normals = normals
	return st.commit()


## A four-point harness laid on this craft's own seat (geometry pass, 2026-11-23). The Phaethon's
## straps are flat boards placed for its own seat; on these seats they stood off the back and through
## the cushion. Here each strap is found on the seat by casting onto it: the shoulder straps come
## through slots in the back at shoulder height, run down its face and over the cushion to a cam-lock
## buckle, and the lap belts come over the cushion from the hips to the same buckle. Webbing has a
## rolled edge; the slots, the adjusters and the buckle are radiused castings.
const STRAP_RED := Color(0.6, 0.08, 0.06)


func fit_harness(shell: Node3D, interior: Node3D) -> void:
	var seats := []
	for label in ["FleetSeat", "seat_back", "seat_cushion"]:
		var piece := shell.find_child(label, true, false) as MeshInstance3D
		if piece and piece.mesh:
			seats.append([piece.mesh.generate_triangle_mesh(), _relative(piece, interior)])
	if seats.is_empty():
		return
	var webbing := SurfaceTool.new()
	webbing.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hardware := []
	# Where the buckle sits: on the cushion, a hand's width ahead of the back.
	var lap := _drop(seats, Vector3(0, .75, .80), Vector3.DOWN)
	if lap.is_empty():
		return
	var buckle: Vector3 = lap.position + lap.normal * .006
	for side: float in [-1.0, 1.0]:
		# Shoulder strap: down the back's face from its slot, then over the cushion to the buckle.
		var down := []
		for i in 15:
			var t := i / 14.0
			var y := lerpf(.86, .32, t)
			var hit := _drop(seats, Vector3(side * lerpf(.10, .125, t), y, .45), Vector3.BACK)
			if not hit.is_empty() and hit.normal.dot(Vector3.FORWARD) > .35:
				down.append([hit.position + hit.normal * .0035, hit.normal])
		if down.size() < 4:
			continue
		var run := down.duplicate()
		var heel: Vector3 = down.back()[0]
		for i in range(1, 9):
			var t := i / 8.0
			var guide := heel.lerp(buckle + Vector3(side * .028, 0, 0), t)
			var hit := _drop(seats, Vector3(guide.x, .75, guide.z), Vector3.DOWN)
			if not hit.is_empty() and hit.position.y > heel.y - .2:
				var lift := .0035 + .02 * sin(PI * t) * (1.0 - t)
				run.append([hit.position + hit.normal * lift, hit.normal])
		_strap(webbing, run, .046, .0032)
		var slot: Vector3 = down[0][0]
		var slot_n: Vector3 = down[0][1]
		hardware.append([Finish.rounded_slab(Vector3(.062, .006, .022), .006, .0025), _facing(slot - slot_n * .002, slot_n, Vector3.UP), DARK])
		# The length adjuster, at the chest.
		var mid: Array = down[down.size() / 3]
		hardware.append([Finish.rounded_slab(Vector3(.056, .005, .034), .007, .0022), _facing(mid[0] + mid[1] * .003, mid[1], Vector3.UP), STEEL])
		# Lap belt: from the hip, where the cushion meets the bolster, across to the buckle.
		var belt := []
		for i in 11:
			var t := i / 10.0
			var guide := Vector3(side * lerpf(.27, .035, t), .75, lerpf(.95, buckle.z + .012, t))
			var hit := _drop(seats, guide, Vector3.DOWN)
			if not hit.is_empty() and hit.position.y > buckle.y - .25:
				belt.append([hit.position + hit.normal * .004, hit.normal])
		if belt.size() > 3:
			_strap(webbing, belt, .05, .0034)
	var mesh := webbing.commit()
	mesh.surface_set_material(0, Finish.tinted("webbing", STRAP_RED))
	hardware.append([Finish.rounded_slab(Vector3(.078, .012, .066), .014, .004), _facing(buckle + lap.normal * .004, lap.normal, Vector3.FORWARD), STEEL])
	hardware.append([Finish.rounded_slab(Vector3(.052, .006, .028), .008, .0025), _facing(buckle + lap.normal * .0115 + Vector3(0, 0, -.012), lap.normal, Vector3.FORWARD), Color("#c9ccd0")])
	Kit.compound(hardware, mesh, true)
	mesh.surface_set_material(1, Finish.satin())
	var node := MeshInstance3D.new()
	node.name = "Harness"
	node.mesh = mesh
	interior.add_child(node)


## The transform taking `node`'s local frame into `frame`'s, without the scene tree (the cockpit
## can be assembled outside it, as test_cockpit_assembly does).
static func _relative(node: Node3D, frame: Node3D) -> Transform3D:
	var up := func(n: Node) -> Transform3D:
		var xf := Transform3D.IDENTITY
		while n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		return xf
	return (up.call(frame) as Transform3D).affine_inverse() * (up.call(node) as Transform3D)


## The nearest point on any seat along a ray, with its surface normal facing back along the ray.
static func _drop(seats: Array, from: Vector3, direction: Vector3) -> Dictionary:
	var best := {}
	var nearest := INF
	for seat: Array in seats:
		var xf: Transform3D = seat[1]
		var local := xf.affine_inverse()
		var hit: Dictionary = (seat[0] as TriangleMesh).intersect_ray(local * from, (local.basis * direction).normalized())
		if hit.is_empty():
			continue
		var at: Vector3 = xf * (hit.position as Vector3)
		var d := from.distance_to(at)
		if d < nearest:
			nearest = d
			var n: Vector3 = (xf.basis * (hit.normal as Vector3)).normalized()
			best = {position = at, normal = n if n.dot(direction) < 0.0 else -n}
	return best


## A basis whose +Y is `normal`, its +Z as near `along` as the normal allows.
static func _facing(origin: Vector3, normal: Vector3, along: Vector3) -> Transform3D:
	var z := along.slide(normal).normalized()
	return Transform3D(Basis(normal.cross(z), normal, z), origin)


## A strap along `run` ([point, surface normal] pairs): woven webbing with a rolled edge.
func _strap(st: SurfaceTool, run: Array, width: float, thick: float) -> void:
	var profile: Array[Vector2] = []
	for k in 7:
		var a := -PI * .5 + PI * k / 6.0
		profile.append(Vector2(width * .5 - thick * .5 + cos(a) * thick * .5, sin(a) * thick * .5))
	for k in 7:
		var a := PI * .5 + PI * k / 6.0
		profile.append(Vector2(-width * .5 + thick * .5 + cos(a) * thick * .5, sin(a) * thick * .5))
	var previous := []
	for i in run.size():
		var at: Vector3 = run[i][0]
		var up: Vector3 = run[i][1]
		var tangent: Vector3 = ((run[mini(i + 1, run.size() - 1)][0] as Vector3) - (run[maxi(i - 1, 0)][0] as Vector3)).normalized()
		var across := tangent.cross(up).normalized()
		up = across.cross(tangent).normalized()
		var ring := []
		for k in profile.size():
			var p: Vector2 = profile[k]
			var bulge := Vector2(p.x - signf(p.x) * (width * .5 - thick * .5), p.y)
			var n := (across * bulge.x + up * bulge.y).normalized() if absf(p.x) > width * .5 - thick * .5 - .0001 else up * signf(p.y)
			ring.append([at + across * p.x + up * p.y, n])
		if not previous.is_empty():
			for k in ring.size():
				var j := (k + 1) % ring.size()
				_soft_quad(st, previous[k], ring[k], ring[j], previous[j])
		if i == 0 or i == run.size() - 1:
			# A cut, heat-sealed end.
			var out := -tangent if i == 0 else tangent
			for k in range(1, ring.size() - 1):
				_soft_triangle(st, [ring[0][0], out], [ring[k][0], out], [ring[k + 1][0], out])
		previous = ring


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
					_tube(trim, _rounded_path(rail, .030, .30), .016, accent)
					_bar(panels, rail[1].lerp(rail[2], .15), rail[1].lerp(rail[2], .85), .020, DARK)
			P.VESPER:
				for k in 3:
					var z := -.15 + k * .24
					panels.append(
						[
							Finish.rounded_slab(Vector3(.044, .066, .224), .012, .009),
							Kit.at(Vector3(s * .736, .449, z + .13), Vector3(-.15, 0, s * .18)),
							paint
						]
					)
					_bar(trim, Vector3(s * .711, .438, z + .032), Vector3(s * .711, .463, z + .228), .0035, accent)
	_flush(interior, "SillFittings")
