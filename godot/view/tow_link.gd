## The tow links: what joins each engine to the pod. (Luke, flying the sixteenth flight: "redesign the
## tether lines and bullring? I feel like it should be more mechanical than loose swinging cable".)
## They were ropes: a tube rebuilt every frame along a curve that sagged with its slack and twanged at
## 2.2 Hz when the tension jumped. Each is now a telescoping drawbar, as an aircraft tow bar or a
## railway drawbar with its draft gear is made:
##   the bullring   a forged hoop shrunk round the pod's nose cap, a crown block across its top and
##                  a swivel post either side of centre (part of the hull: craft_model.pod_hull)
##   the swivel     turns on its post (the pod's own up: it leans when the pod banks) and carries
##                  a pitch pin POD_PIN ahead of the post
##   the barrel     hangs from that pin: five metres of tube with clamp collars and light bars, then
##                  the draft gear's finned canister and the gland nut the rod runs through
##   the rod        slides in the barrel. Nothing pushes back as it closes (the sim's links pull
##                  and never push), and at full reach its piston meets the draft gear, whose
##                  stiff spring is the sim's own stretch: a fifth of a metre at the limit
##   the yoke       on the engine: a fork over the lug's pin under the engine's tail, swinging up
##                  and down on it, with a yaw pin ENGINE_PIN behind for the rod's own fork
## Two pins at each end, crossed: the link takes no bending, whatever the engines and pod do.
## Nothing here is simulated. solve() places the five rigid parts from the two fixed points the craft
## already has (the engine's lug pin, the pod's swivel post) and the two bodies' attitudes; the
## telescope's length is whatever is left between the pins.
##   var s := TowLink.solve(eye, engine_basis, post, pod_basis)
##   s.yoke, s.swivel, s.barrel, s.rod     where each part goes (the same space the points came in)
##   s.span, s.exposed                     pitch pin to yaw pin, and the rod showing outside the gland
##   s.boot                                how long the boot at the barrel's mouth stands (boot_for)
##   s.angles                              [swivel yaw, barrel pitch, yoke pitch, rod yaw], radians
##
## Their detail (Luke, having flown them: "a good first step - they could use some more detail"). All of
## it is in the same few meshes, made once and shared by both links and both craft:
##   the swivel     a bearing housing: thrust washer, base flange, a bright race, a ring of cap screws
##                  round the post's nut and its split pin, a grease nipple at the back where the pilot
##                  looks; the pitch pin is a quick-release one, red at the hand's end, on a lanyard
##   the barrel     spanner flats on its end cap; a junction box at its root and a conduit along its top,
##                  collar to collar, so the light bars are wired (each bay's three run from one collar to
##                  the next: the collars are their bus rings, each with its two set screws); the draft
##                  gear's piggyback reservoir, its charge valve and the line into the canister; painted
##                  marks (dress(): the stencils, a hazard band, the draft gear's data plate)
##   the boot       a rubber gaiter over the rod at the barrel's mouth. It is the one part that moves
##                  with the telescope alone: one end on the gland, the other on the rod, so it stands
##                  longer as its engine pulls and folds up as the link closes (boot_for)
##   the rod        a jam nut behind its coupler, a grease nipple on its fork, a split pin through its yaw pin
##   the yoke       gussets to its tongue, split pins through the lug pin's ends, a grease nipple
## What is steel keeps one material (metal()), what glows the link's own (lit()), and paint and rubber
## share one more (dress()): three for both links.
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const Finishes := preload("res://view/craft_materials.gd")

const BARREL := 5.0          # the barrel: its pitch pin to the face of its gland, m
const ROD := 12.4            # the rod of a 16 m link (Phaethon's): its yaw pin to its piston. rod_for() for another craft's
const POD_PIN := 0.13        # the swivel's pitch pin, ahead of its post
const ENGINE_PIN := 0.26     # the yoke's yaw pin, behind the lug's pin
const BARREL_R := 0.048
const ROD_R := 0.035         # (the rope was 0.035 too: no thinner at the far end, where a thin line shimmers in the headset)
const CANISTER := 1.25       # the draft gear, at the barrel's mouth
const BURIED := 0.3          # the least of the rod left in the barrel
const RING_Z := -2.07        # the bullring's hoop: its station on the pod's nose cap ...
const RING_R := 0.03         # ... and its section
const HUB := 0.03            # the swivel's hub: half its height (the washer under it is 0.012 more)
const BOOT := 0.6            # the boot at the barrel's mouth: its length as made (the gland's face to its cuff on the rod) ...
const BOOT_SEAT := 1.8       # ... where that cuff grips the rod, from the piston: taut, the piston stands 1.2 m inside the mouth,
                             # so a taut link's boot stands about as made ...
const BOOT_MIN := 0.11       # ... its folds closed solid (past that its cuff slips along the rod: a slack link closes metres) ...
const BOOT_MAX := 0.86       # ... and pulled out straight
const BOOT_FOLDS := 7
const FORGED := Color(0.17, 0.18, 0.20)
const GUNMETAL := Color(0.27, 0.28, 0.31)
const BRIGHT := Color(0.74, 0.76, 0.80)
const BRONZE := Color(0.66, 0.50, 0.24)
const ANODISED := Color(0.74, 0.07, 0.05)    # red anodising: the one thing on a link a hand is meant to pull
const RUBBER := Color(0.05, 0.05, 0.055)
const SHEATH := Color(0.09, 0.09, 0.1)       # the conduit's braid
const CLIP := Color(0.42, 0.43, 0.45)        # a worm-drive clip round a boot's cuff
const ABOUT_X := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   # a part turned about +Z, laid along +X
const ABOUT_Y := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # ... or stood up along +Y
const ON_EDGE := Vector3(0, 0, PI / 2.0)     # a plate (thin along y as made) stood on its edge, thin along x
# The painted marks (tools/art_tow_marks.py draws them into one atlas, and these are its cells in texels,
# a texel in from each edge): what a patch of the dress surface shows.
const MARKS := "res://art/tow/marks.png"
const MARKS_SIZE := Vector2(1024, 512)
const MARK_PLAIN := Vector2(32, 32)          # white: a part in one colour (its vertices')
const MARK_HAZARD := Rect2(128, 8, 64, 112)  # one repeat of the yellow and black
const MARK := {
	"id": Rect2(1, 145, 638, 78),
	"no_step": Rect2(1, 233, 638, 78),
	"pinch": Rect2(1, 321, 638, 78),
	"plate": Rect2(657, 145, 350, 126),
}

static var _meshes := {}
static var _metal: StandardMaterial3D
static var _dress: StandardMaterial3D


## What the links' steel is made of: one material for every part of both.
static func metal() -> StandardMaterial3D:
	if _metal == null:
		_metal = Finishes.machined() if Finishes.hd else Kit.polished(0.9, 0.32)
	return _metal


## What a link's lit parts are made of (the rod, the barrel's light bars): dark polished steel that
## glows with its engine's thrust and turns amber then red with strain (craft_model.sync_cables).
static func lit(base: StandardMaterial3D) -> StandardMaterial3D:
	base.metallic = 0.85
	base.roughness = 0.3
	base.emission_enabled = true
	base.emission_energy_multiplier = 0.0
	return base


## What is painted or rubber on a link: the boots, the conduits' sheaths, the stencils. One material for
## both links: satin, not metal, coloured by vertex, with the marks' atlas where a patch maps to it.
static func dress() -> StandardMaterial3D:
	if _dress == null:
		_dress = StandardMaterial3D.new()
		_dress.vertex_color_use_as_albedo = true
		_dress.vertex_color_is_srgb = true
		_dress.metallic = 0.0
		_dress.roughness = 0.62
		_dress.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if ResourceLoader.exists(MARKS):
			_dress.albedo_texture = load(MARKS)
	return _dress


## v with its part along `axis` taken out, as a direction (a fallback when there is nothing left).
static func _across(v: Vector3, axis: Vector3, otherwise: Vector3) -> Vector3:
	var flat := v - axis * v.dot(axis)
	if flat.length() < 1e-4:
		flat = otherwise - axis * otherwise.dot(axis)
	return flat.normalized()


## How long a craft's rods are, for its links' taut length (the sim's cableLen: 16 m on the Phaethon,
## 12.5 m on the Shrike): so that taut, the piston stands about 1.2 m inside the barrel's mouth,
## at the back of the draft gear, whatever the link's length. (One rod for both left the Shrike's
## 4.6 m inside a 5 m barrel, and drawn short as soon as its link closed up.)
static func rod_for(taut: float) -> float:
	return taut - BARREL + 1.4


## Where a link's parts go. `eye`: the lug pin's middle under the engine, and `engine` that engine's
## attitude (the pin lies along its x); `post`: the middle of the pod's swivel, and `pod` the pod's
## attitude (the post stands along its y); `rod`: how long this craft's rods are (rod_for).
static func solve(eye: Vector3, engine: Basis, post: Vector3, pod: Basis, rod := ROD) -> Dictionary:
	var ex := engine.x.normalized()
	var py := pod.y.normalized()
	var pitch_pin := post
	var yaw_pin := eye
	var ze := Vector3.ZERO      # the yoke's tongue: square to the lug's pin, toward the pod
	var zp := Vector3.ZERO      # the swivel's cheeks: square to the post, toward the engine
	for again in 2:
		ze = _across(pitch_pin - eye, ex, engine.z)
		yaw_pin = eye + ze * ENGINE_PIN
		zp = _across(yaw_pin - post, py, -pod.z)
		pitch_pin = post + zp * POD_PIN
	var run := yaw_pin - pitch_pin
	var span := run.length()
	var u := run / span if span > 1e-4 else zp
	var xp := py.cross(zp)                          # the pitch pin's own line
	var ye := ze.cross(ex)                          # the yaw pin's
	var ry := (ye - u * ye.dot(u)).normalized()     # (square to the rod to within a hair: the second pass leaves microns)
	# a wreck, the ends nearer than the barrel is long: it is drawn short rather than through the engine
	var barrel_len := BARREL * clampf((span - 0.45) / BARREL, 0.05, 1.0)
	var exposed := span - barrel_len
	# the rod as made while its piston is inside the barrel; past either end of that it is drawn
	# longer (pulled past its reach) or shorter (closed up further than the barrel is deep)
	var rod_len := clampf(rod, exposed + BURIED, maxf(exposed + BURIED, span - 0.2))
	return {
		"yoke": Transform3D(Basis(ex, ye, ze), eye),
		"swivel": Transform3D(Basis(xp, py, zp), post),
		"barrel": Transform3D(Basis(xp, u.cross(xp), u).scaled_local(Vector3(1.0, 1.0, barrel_len / BARREL)), pitch_pin),
		"rod": Transform3D(Basis(ry.cross(-u), ry, -u).scaled_local(Vector3(1.0, 1.0, rod_len / rod)), yaw_pin),
		"span": span,
		"exposed": exposed,
		"buried": rod_len - exposed,
		"boot": boot_for(exposed, rod),
		"pins": [yaw_pin, pitch_pin],
		"angles": [atan2(zp.dot(pod.x.normalized()), -zp.dot(pod.z.normalized())), asin(clampf(u.dot(py), -1.0, 1.0)),
			atan2(ze.dot(engine.y.normalized()), ze.dot(engine.z.normalized())), atan2(-u.dot(ex), -u.dot(ze))],
	}


## The rod showing outside the gland for a span between the pins (what solve() draws, as a number).
static func exposed_for(span: float) -> float:
	return span - BARREL * clampf((span - 0.45) / BARREL, 0.05, 1.0)


## How long the boot stands, from the gland's face to its cuff, for that much rod showing: the cuff
## grips the rod BOOT_SEAT from its piston, so the boot gives and takes with the telescope one for one,
## between its folds closed solid and pulled straight.
static func boot_for(exposed: float, rod := ROD) -> float:
	return clampf(exposed - (rod - BOOT_SEAT), BOOT_MIN, BOOT_MAX)


# ---- the parts ----

static func _tri(st: SurfaceTool, xf: Transform3D, col: Color, p: Array, n: Array, uv := []) -> void:
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var face := (b - a).cross(c - a)
	if face.length_squared() < 1e-16:
		return
	var out: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order := [0, 1, 2] if face.dot(out) < 0.0 else [0, 2, 1]      # (Godot's fronts are clockwise)
	for i in order:
		st.set_color(col)
		if not uv.is_empty():
			st.set_uv(uv[i])
		st.set_normal((xf.basis * (n[i] as Vector3)).normalized())
		st.add_vertex(xf * (p[i] as Vector3))


## A turned part about +Z: `profile` is [z, radius, colour] stations, each pair of them a band in the
## second one's colour, flat along the profile and smooth round it, so every step is a crisp edge.
## `flats`: its faces are flat round it too (a nut).
static func _turn(st: SurfaceTool, profile: Array, sides: int, xf := Transform3D.IDENTITY, flats := false) -> void:
	for i in profile.size() - 1:
		var z0: float = profile[i][0]
		var r0: float = profile[i][1]
		var z1: float = profile[i + 1][0]
		var r1: float = profile[i + 1][1]
		var col: Color = profile[i + 1][2]
		var along := Vector2(z1 - z0, r1 - r0)
		if along.length() < 1e-6:
			continue
		var n := Vector2(-along.y, along.x).normalized()      # (its part along z, its part outward)
		for k in sides:
			var a0 := TAU * k / sides
			var a1 := TAU * (k + 1) / sides
			var d0 := Vector3(cos(a0), sin(a0), 0.0)
			var d1 := Vector3(cos(a1), sin(a1), 0.0)
			var m0 := d0
			var m1 := d1
			if flats:
				m0 = Vector3(cos((a0 + a1) / 2.0), sin((a0 + a1) / 2.0), 0.0)
				m1 = m0
			var n0 := m0 * n.y + Vector3(0, 0, n.x)
			var n1 := m1 * n.y + Vector3(0, 0, n.x)
			var p00 := d0 * r0 + Vector3(0, 0, z0)
			var p01 := d0 * r1 + Vector3(0, 0, z1)
			var p11 := d1 * r1 + Vector3(0, 0, z1)
			var p10 := d1 * r0 + Vector3(0, 0, z0)
			_tri(st, xf, col, [p00, p01, p11], [n0, n0, n1])
			_tri(st, xf, col, [p00, p11, p10], [n0, n1, n1])


## A primitive or a mesh, placed (MeshKit.compound's own loop, into a surface that holds other parts).
static func _add(st: SurfaceTool, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	var arr: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	var order: Array = range(verts.size()) if idx == null or (idx as PackedInt32Array).is_empty() else Array(idx)
	for i in order:
		st.set_color(col)
		st.set_normal((xf.basis * norms[i]).normalized())
		st.add_vertex(xf * verts[i])


## A forged plate, thin along y: its corners cut and its edges broken (64 triangles; a rounded box is 256).
static func _plate(size: Vector3, bevel := 0.006) -> ArrayMesh:
	return Finishes.beveled_plate(size, bevel)


## Where a thing that stands along its own +z goes: at `p`, its z along `d`.
static func _along(d: Vector3, p: Vector3) -> Transform3D:
	var z := d.normalized()
	var x := z.cross(Vector3.UP if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
	return Transform3D(Basis(x, z.cross(x), z), p)


## A screw's, a bolt's or a pin's head standing on `xf` along its z, `h` tall (its side and its top; what
## it sits on hides its foot): a socket cap's round head, or with `flats` a hexagon.
static func _head(st: SurfaceTool, xf: Transform3D, r: float, h: float, col: Color, sides := 6, flats := false) -> void:
	_turn(st, [[0.0, r, col], [h, r, col], [h, 0.0, col]], sides, xf, flats)


## A grease nipple standing on `p` along `d`: a hexagon's worth of stem, a shoulder, the ball's cone.
static func _nipple(st: SurfaceTool, d: Vector3, p: Vector3) -> void:
	_turn(st, [[0.0, 0.0045, BRONZE], [0.009, 0.0045, BRONZE], [0.009, 0.0065, BRONZE], [0.015, 0.003, BRONZE], [0.015, 0.0, BRONZE]], 5, _along(d, p))


## A round line along a path (a conduit, a hose, a lanyard; `closed`: a ring), its frames carried along
## it so that it does not twist.
static func _pipe(st: SurfaceTool, path: Array, r: float, col: Color, sides := 5, closed := false) -> void:
	var n := path.size()
	var rings := []
	var nrm := Vector3.ZERO
	for i in n:
		var before: Vector3 = path[(i - 1 + n) % n] if closed else path[maxi(i - 1, 0)]
		var after: Vector3 = path[(i + 1) % n] if closed else path[mini(i + 1, n - 1)]
		var t := (after - before).normalized()
		if i == 0:
			nrm = t.cross(Vector3.UP)
			if nrm.length() < 0.1:
				nrm = t.cross(Vector3.RIGHT)
		nrm = (nrm - t * nrm.dot(t)).normalized()
		var bn := t.cross(nrm)
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			ring.append(nrm * cos(a) + bn * sin(a))
		rings.append(ring)
	for i in (n if closed else n - 1):
		var j := (i + 1) % n
		var p0: Vector3 = path[i]
		var p1: Vector3 = path[j]
		for k in sides:
			var k2 := (k + 1) % sides
			var n00: Vector3 = rings[i][k]
			var n01: Vector3 = rings[i][k2]
			var n10: Vector3 = rings[j][k]
			var n11: Vector3 = rings[j][k2]
			_tri(st, Transform3D.IDENTITY, col, [p0 + n00 * r, p1 + n10 * r, p1 + n11 * r], [n00, n10, n11])
			_tri(st, Transform3D.IDENTITY, col, [p0 + n00 * r, p1 + n11 * r, p0 + n01 * r], [n00, n11, n01])


## A triangular web between three points, `thick` through (a gusset).
static func _web(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, thick: float, col: Color, xf := Transform3D.IDENTITY) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var h := nrm * thick / 2.0
	_tri(st, xf, col, [a + h, b + h, c + h], [nrm, nrm, nrm])
	_tri(st, xf, col, [a - h, b - h, c - h], [-nrm, -nrm, -nrm])
	for edge in [[a, b, c], [b, c, a], [c, a, b]]:
		var p: Vector3 = edge[0]
		var q: Vector3 = edge[1]
		var out := (q - p).cross(nrm).normalized()
		if out.dot((edge[2] as Vector3) - p) > 0.0:
			out = -out
		_tri(st, xf, col, [p + h, q + h, q - h], [out, out, out])
		_tri(st, xf, col, [p + h, q - h, p - h], [out, out, out])


static func _uv(texel: Vector2) -> Vector2:
	return texel / MARKS_SIZE


## A painted mark on a tube about +Z, its lettering along the tube: from angle `foot` to angle `head`
## (its letters' feet to their tops) and from `first` to `last` along z (its first letter to its last).
## Stand on the side it is painted on with the tube lying across in front and it reads the right way up.
static func _label(st: SurfaceTool, key: String, r: float, foot: float, head: float, first: float, last: float, segs := 3) -> void:
	var cell: Rect2 = MARK[key]
	for i in segs:
		var p := []
		var n := []
		var uv := []
		for corner in [[0, 0.0], [0, 1.0], [1, 1.0], [1, 0.0]]:
			var t := float(i + int(corner[0])) / segs
			var s: float = corner[1]
			var ang := lerpf(foot, head, t)
			var d := Vector3(cos(ang), sin(ang), 0.0)
			p.append(d * r + Vector3(0, 0, lerpf(first, last, s)))
			n.append(d)
			uv.append(_uv(cell.position + Vector2(cell.size.x * s, cell.size.y * (1.0 - t))))
		_tri(st, Transform3D.IDENTITY, Color.WHITE, [p[0], p[1], p[2]], [n[0], n[1], n[2]], [uv[0], uv[1], uv[2]])
		_tri(st, Transform3D.IDENTITY, Color.WHITE, [p[0], p[2], p[3]], [n[0], n[2], n[3]], [uv[0], uv[2], uv[3]])
	st.set_uv(_uv(MARK_PLAIN))


## A hazard band round a tube about +Z from z0 to z1: yellow and black at a slant, one repeat a side.
static func _hazard(st: SurfaceTool, z0: float, z1: float, r: float, sides: int) -> void:
	var cell := MARK_HAZARD
	for k in sides:
		var d0 := Vector3(cos(TAU * k / sides), sin(TAU * k / sides), 0.0)
		var d1 := Vector3(cos(TAU * (k + 1) / sides), sin(TAU * (k + 1) / sides), 0.0)
		var p := [d0 * r + Vector3(0, 0, z0), d0 * r + Vector3(0, 0, z1), d1 * r + Vector3(0, 0, z1), d1 * r + Vector3(0, 0, z0)]
		var uv := [_uv(cell.position), _uv(cell.position + Vector2(0, cell.size.y)), _uv(cell.end), _uv(cell.position + Vector2(cell.size.x, 0))]
		_tri(st, Transform3D.IDENTITY, Color.WHITE, [p[0], p[1], p[2]], [d0, d0, d1], [uv[0], uv[1], uv[2]])
		_tri(st, Transform3D.IDENTITY, Color.WHITE, [p[0], p[2], p[3]], [d0, d1, d1], [uv[0], uv[2], uv[3]])
	st.set_uv(_uv(MARK_PLAIN))


static func _surfaces(steel: SurfaceTool, light: SurfaceTool, paint: SurfaceTool = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	steel.index()
	steel.commit(mesh)
	if light != null:
		light.index()
		light.commit(mesh)
	if paint != null:
		paint.index()
		paint.commit(mesh)
	return mesh


## A surface for what is painted or rubber (dress()): every vertex carries a place in the marks' atlas,
## the plain white patch unless a mark says otherwise.
static func _dress_surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(_uv(MARK_PLAIN))
	return st


## The pod's swivel. Its post's line is its y through its origin, its cheeks reach along +z to the
## pitch pin (along x) POD_PIN out. The pilot sees it from behind (its -z) and a little above.
static func swivel_mesh() -> ArrayMesh:
	if _meshes.has("swivel"):
		return _meshes.swivel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Transform3D(ABOUT_Y, Vector3.ZERO)
	# (a low puck: from the seat it stands in front of the engines, and the first cut's, 10 cm tall on a raised post, read as a black can)
	# A bearing housing, as turned: the bronze thrust washer it rides on, a base flange, a waist, the
	# bearing's bright outer race standing a hair proud, and a machined land round its top.
	_turn(st, [[-HUB - 0.012, 0.068, BRONZE], [-HUB, 0.068, BRONZE], [-HUB, 0.063, BRONZE], [-0.02, 0.063, GUNMETAL], [-0.015, 0.056, GUNMETAL],
		[-0.003, 0.056, FORGED], [-0.003, 0.0605, BRIGHT], [0.011, 0.0605, BRIGHT], [0.011, 0.057, BRIGHT], [0.023, 0.057, GUNMETAL],
		[HUB, 0.051, BRIGHT], [HUB, 0.0, GUNMETAL]], 16, up)
	for k in 6:      # the bearing's retaining screws, round the top: at the pilot's shallow angle they stand up as a crown
		var a := TAU * (k + 0.5) / 6.0
		_head(st, Transform3D(ABOUT_Y, Vector3(0.0405 * cos(a), HUB, 0.0405 * sin(a))), 0.0065, 0.006, BRIGHT, 5)
	_turn(st, [[HUB, 0.026, BRIGHT], [HUB + 0.012, 0.026, BRIGHT], [HUB + 0.012, 0.0, BRIGHT]], 6, up, true)                  # the post's nut
	_turn(st, [[HUB + 0.012, 0.012, BRIGHT], [HUB + 0.021, 0.012, BRIGHT], [HUB + 0.021, 0.0, BRIGHT]], 8, up)                # the post's end through it ...
	_add(st, Kit.box(Vector3(0.036, 0.0045, 0.0045)), Kit.at(Vector3(0, HUB + 0.0165, 0), Vector3(0, 0.6, 0)), FORGED)        # ... and the split pin through that
	_nipple(st, Vector3(0.0, 0.5, -0.87), Vector3(0.0, -0.009, -0.0555))                                                      # grease, at the back
	for s in [-1.0, 1.0]:
		_add(st, _plate(Vector3(0.08, 0.022, 0.19)), Kit.at(Vector3(0.052 * s, 0.0, 0.105), ON_EDGE), FORGED)   # cheeks
	# The pitch pin (its shank is inside the barrel's eye): a quick-release pin. A bronze washer under each
	# end; the hand's end anodised red, a split ring through it and a lanyard from the ring to the cheek, so
	# that drawn it is not lost; a nut and the pin's own end on the other.
	var pull := _along(Vector3.RIGHT, Vector3(0.063, 0.0, POD_PIN))
	_head(st, pull, 0.033, 0.003, BRONZE, 10)
	_head(st, pull.translated_local(Vector3(0, 0, 0.003)), 0.021, 0.012, ANODISED, 10)
	var ring := []
	for k in 8:
		ring.append(Vector3(0.0895 + 0.015 * cos(TAU * k / 8.0), -0.004 + 0.015 * sin(TAU * k / 8.0), POD_PIN))
	_pipe(st, ring, 0.0028, BRIGHT, 4, true)
	_pipe(st, [Vector3(0.094, -0.019, POD_PIN), Vector3(0.099, -0.034, 0.12), Vector3(0.1, -0.046, 0.104), Vector3(0.096, -0.053, 0.086),
		Vector3(0.088, -0.052, 0.07), Vector3(0.078, -0.043, 0.058), Vector3(0.069, -0.03, 0.052), Vector3(0.065, -0.022, 0.05)], 0.0022, BRIGHT, 3)
	_head(st, _along(Vector3.RIGHT, Vector3(0.063, -0.022, 0.05)), 0.0055, 0.004, BRIGHT, 5)
	var nut := _along(Vector3.LEFT, Vector3(-0.063, 0.0, POD_PIN))
	_head(st, nut, 0.033, 0.003, BRONZE, 10)
	_head(st, nut.translated_local(Vector3(0, 0, 0.003)), 0.026, 0.013, BRIGHT, 6, true)
	_head(st, nut.translated_local(Vector3(0, 0, 0.016)), 0.012, 0.006, BRIGHT, 6)
	_meshes.swivel = _surfaces(st, null)
	return _meshes.swivel


## The barrel: its eye on the swivel's pitch pin (x through its origin), +z toward the engine, the
## gland's face at BARREL. Surface 0 its steel, surface 1 its lights (the link's own material), surface 2
## what is painted on it and its conduit's sheath (dress()).
## Round it, 90 degrees is its top (the pod's up) and 0 and 180 its flanks. The pilot looks at each barrel
## from behind and a little above its inboard flank: so the lights are at 30, 150 and 270 degrees (one
## faces him on either link), the stencils on both flanks, and the conduit and the reservoir along the top,
## where they stand on its outline.
static func barrel_mesh() -> ArrayMesh:
	if _meshes.has("barrel"):
		return _meshes.barrel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mouth := BARREL - CANISTER
	var collars := [1.0, 1.9, 2.8]
	_turn(st, [[-0.036, 0.0, FORGED], [-0.036, 0.042, FORGED], [0.036, 0.042, FORGED], [0.036, 0.0, FORGED]], 16, Transform3D(ABOUT_X, Vector3.ZERO))   # the eye
	_turn(st, [[-0.04, 0.02, BRONZE], [-0.04, 0.028, BRONZE], [0.04, 0.028, BRONZE], [0.04, 0.02, BRONZE]], 12, Transform3D(ABOUT_X, Vector3.ZERO))     # its bush, proud of both faces
	_turn(st, [[0.03, 0.0, FORGED], [0.03, 0.03, FORGED], [0.1, 0.034, FORGED], [0.16, 0.05, FORGED],      # the neck, flaring to ...
		[0.16, 0.06, BRIGHT], [0.19, 0.06, BRIGHT], [0.19, 0.05, BRIGHT]], 16)                              # ... the end cap,
	_turn(st, [[0.19, 0.05, BRIGHT], [0.19, 0.0615, BRIGHT], [0.222, 0.0615, BRIGHT], [0.222, BARREL_R, BRIGHT]], 8, Transform3D.IDENTITY, true)   # and the flats a spanner takes it by
	var body := [[0.222, BARREL_R, BRIGHT]]
	for zc in collars:      # the tube, a clamp collar between each bay
		body.append_array([[zc - 0.022, BARREL_R, GUNMETAL], [zc - 0.022, 0.057, BRIGHT], [zc + 0.022, 0.057, BRIGHT], [zc + 0.022, BARREL_R, BRIGHT]])
	body.append_array([[mouth - 0.06, BARREL_R, GUNMETAL], [mouth, 0.062, FORGED]])                          # the shoulder of the draft gear
	for zf in [mouth + 0.22, mouth + 0.5, mouth + 0.78]:      # its canister, three cooling fins (broad: fine ones would shimmer at this range)
		body.append_array([[zf - 0.02, 0.062, FORGED], [zf - 0.02, 0.075, GUNMETAL], [zf + 0.02, 0.075, GUNMETAL], [zf + 0.02, 0.062, GUNMETAL]])
	body.append_array([[BARREL - 0.16, 0.062, FORGED], [BARREL - 0.16, 0.05, FORGED]])
	_turn(st, body, 16)
	_turn(st, [[BARREL - 0.16, 0.05, BRIGHT], [BARREL - 0.16, 0.061, BRIGHT], [BARREL - 0.045, 0.061, BRIGHT], [BARREL - 0.045, 0.044, BRIGHT]], 8, Transform3D.IDENTITY, true)   # the gland nut
	_turn(st, [[BARREL - 0.045, 0.044, FORGED], [BARREL, 0.044, FORGED], [BARREL, ROD_R + 0.0035, FORGED]], 16)   # its wiper, and the bore the rod and its light bars run in
	# The lights' wiring. A junction box on the root, a conduit along the top from it to each collar in turn
	# and on into the draft gear's shoulder, a saddle on each collar where the conduit goes through: each
	# bay's three bars run collar to collar, so the collars are their bus rings. Two set screws a collar.
	var line_y := BARREL_R + 0.0085
	_add(st, _plate(Vector3(0.036, 0.024, 0.085), 0.004), Kit.at(Vector3(0.0, BARREL_R + 0.011, 0.278)), GUNMETAL)
	for k in 4:
		_head(st, Transform3D(ABOUT_Y, Vector3(0.011 * (1 - 2 * (k % 2)), BARREL_R + 0.023, 0.278 + 0.03 * (1 - (k & 2)))), 0.0035, 0.002, BRIGHT, 4)
	for zc in collars:
		_add(st, Kit.box(Vector3(0.026, 0.017, 0.052)), Kit.at(Vector3(0.0, 0.0635, zc)), GUNMETAL)
		for side in [0.0, PI]:
			var d := Vector3(cos(side), sin(side), 0.0)
			_head(st, _along(d, d * 0.0565 + Vector3(0, 0, zc)), 0.007, 0.0055, FORGED, 5)
	_turn(st, [[mouth - 0.075, 0.0095, BRIGHT], [mouth - 0.035, 0.0095, BRIGHT]], 6, Transform3D(Basis(), Vector3(0, line_y, 0)))   # the ferrule where it enters the shoulder
	# The draft gear's reservoir, piggyback on the canister's top, sat in its first two fins: bronze end
	# caps, its charge valve at the end the pilot sees, and a hard line from its far end over the third
	# fin and down into the canister through a banjo.
	var res_y := 0.062 + 0.026
	_turn(st, [[mouth + 0.125, 0.0, BRONZE], [mouth + 0.125, 0.006, BRONZE], [mouth + 0.15, 0.006, BRONZE], [mouth + 0.15, 0.0255, BRONZE], [mouth + 0.185, 0.0255, BRONZE],
		[mouth + 0.185, 0.0235, BRIGHT], [mouth + 0.575, 0.0235, BRIGHT], [mouth + 0.575, 0.0255, BRONZE], [mouth + 0.61, 0.0255, BRONZE], [mouth + 0.61, 0.0, BRONZE]],
		8, Transform3D(Basis(), Vector3(0, res_y, 0)))
	_pipe(st, [Vector3(0, res_y, mouth + 0.61), Vector3(0, res_y + 0.002, mouth + 0.66), Vector3(0, res_y - 0.002, mouth + 0.86), Vector3(0, 0.07, mouth + 0.93)], 0.005, BRONZE, 4)
	_head(st, Transform3D(ABOUT_Y, Vector3(0, 0.061, mouth + 0.93)), 0.012, 0.013, BRIGHT, 6, true)
	var light := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	# light bars let into the tube, three round it in each bay: whichever way it is seen, one faces the eye
	# (slim: the first cut's, 20 mm wide, read as neon tubes)
	for bay in [[0.34, collars[0] - 0.022], [collars[0] + 0.022, collars[1] - 0.022], [collars[1] + 0.022, collars[2] - 0.022], [collars[2] + 0.022, mouth - 0.09]]:
		var z0: float = bay[0]
		var z1: float = bay[1]
		for third in 3:
			var about := Basis(Vector3(0, 0, 1), PI / 6.0 + TAU * third / 3.0)
			_add(light, Kit.box(Vector3(0.008, 0.013, z1 - z0)), Transform3D(about, about * Vector3(BARREL_R - 0.0015, 0.0, (z0 + z1) / 2.0)), Color.WHITE)
	_turn(light, [[BARREL - 0.03, 0.0455, Color.WHITE], [BARREL - 0.012, 0.0455, Color.WHITE]], 16)             # the rod's light at the gland
	# ... and a ring of it round the end cap at the barrel's root, facing the cockpit. Flying straight the links run
	# down and away behind the nose, and this is the one lit part of each the pilot sees: its engine's thrust, its strain
	_turn(light, [[0.159, 0.047, Color.WHITE], [0.159, 0.0615, Color.WHITE], [0.184, 0.0615, Color.WHITE], [0.184, 0.06, Color.WHITE]], 16)
	var paint := _dress_surface()
	var runs := [0.32]      # the conduit: its sheath, saddle to saddle
	for zc in collars:
		runs.append_array([zc - 0.026, zc + 0.026])
	runs.append(mouth - 0.04)
	for k in range(0, runs.size(), 2):
		_pipe(paint, [Vector3(0, line_y, runs[k]), Vector3(0, line_y, runs[k + 1])], 0.0065, SHEATH, 5)
	if dress().albedo_texture != null:
		# Stencils along both flanks, each the right way up from its own side, and the draft gear's data plate
		# between its first two fins; a hazard band where the tube ends and the telescope begins.
		var skin := BARREL_R + 0.0008
		var tall := deg_to_rad(18.0)
		for mark in [["id", 0.52, 0.771], ["no_step", 1.32, 1.571], ["pinch", mouth - 0.49, mouth - 0.239]]:
			_label(paint, mark[0], skin, -tall, tall, mark[2], mark[1])
			_label(paint, mark[0], skin, PI + tall, PI - tall, mark[1], mark[2])
		_hazard(paint, mouth - 0.2, mouth - 0.152, skin, 16)
		var plate := deg_to_rad(26.0)
		_label(paint, "plate", 0.0632, -plate, plate, mouth + 0.44, mouth + 0.28, 4)
		_label(paint, "plate", 0.0632, PI + plate, PI - plate, mouth + 0.28, mouth + 0.44, 4)
	_meshes.barrel = _surfaces(st, light, paint)
	return _meshes.barrel


## The boot: a rubber gaiter from the gland's face (its origin, +z along the rod toward the engine) to
## its cuff on the rod, BOOT long as made. It hangs on the barrel, and craft_model stretches it along z to
## boot_for() each frame: its folds open and close with the telescope. One surface, dress().
static func boot_mesh() -> ArrayMesh:
	if _meshes.has("boot"):
		return _meshes.boot
	var st := _dress_surface()
	var first := 0.032
	var pitch := (BOOT - 2.0 * first) / BOOT_FOLDS
	var profile := [[0.0, 0.05, CLIP], [0.026, 0.05, CLIP], [first, 0.046, RUBBER]]      # its cuff on the gland, under a clip
	for k in BOOT_FOLDS:
		profile.append([first + (k + 0.5) * pitch, 0.065, RUBBER])
		profile.append([first + (k + 1.0) * pitch, 0.046, RUBBER])
	profile.append_array([[BOOT - 0.026, 0.0425, RUBBER], [BOOT, 0.0425, CLIP], [BOOT, ROD_R + 0.0012, CLIP]])   # its cuff on the rod
	_turn(st, profile, 10)
	_meshes.boot = _surfaces(st, null)
	return _meshes.boot


## The rod: its fork on the yoke's yaw pin (y through its origin), +z toward the pod, its piston at
## `length` (rod_for). Surface 0 its steel (the fork, the coupler, the rod itself), surface 1 what glows: three light
## bars let into the coupler and three into the rod, its whole length. (The first cut's rod glowed
## whole, as the ropes did: a blue-white beam from close to, and nothing a machine is made of.)
static func rod_mesh(length := ROD) -> ArrayMesh:
	var key := "rod %.3f" % length
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_add(st, _plate(Vector3(0.085, 0.022, 0.14)), Kit.at(Vector3(0.0, 0.046 * s, 0.04)), FORGED)      # the fork's ears
	# the yaw pin (its shank is inside the yoke's eye): a head over the upper ear; under the lower a nut, the pin's end and its split pin
	_head(st, _along(Vector3.UP, Vector3(0, 0.057, 0)), 0.025, 0.012, BRIGHT, 10)
	_head(st, _along(Vector3.DOWN, Vector3(0, -0.057, 0)), 0.024, 0.013, BRIGHT, 6, true)
	_head(st, _along(Vector3.DOWN, Vector3(0, -0.07, 0)), 0.011, 0.009, BRIGHT, 6)
	_add(st, Kit.box(Vector3(0.034, 0.004, 0.004)), Kit.at(Vector3(0, -0.075, 0), Vector3(0, 0.5, 0)), FORGED)
	_add(st, _plate(Vector3(0.085, 0.114, 0.05), 0.008), Kit.at(Vector3(0.0, 0.0, 0.125)), FORGED)               # its root
	_nipple(st, Vector3(0.0, 0.8, 0.6), Vector3(0.0, 0.055, 0.125))
	_turn(st, [[0.14, 0.0, FORGED], [0.14, 0.04, FORGED], [0.2, 0.058, FORGED], [0.25, 0.058, BRIGHT], [0.25, 0.05, BRIGHT],            # the coupler: the widest thing at the far end
		[1.15, 0.05, GUNMETAL], [1.15, 0.058, BRIGHT], [1.2, 0.058, BRIGHT], [1.34, 0.04, FORGED]], 14)                                 # ... down to the rod,
	_turn(st, [[1.34, 0.047, BRIGHT], [1.385, 0.047, BRIGHT], [1.385, ROD_R, BRIGHT]], 6, Transform3D.IDENTITY, true)                   # and the jam nut that locks the rod in it
	_turn(st, [[1.385, ROD_R, BRIGHT], [length, ROD_R, BRIGHT], [length, 0.0, BRIGHT]], 12)                                                     # the rod: bright steel, a piston's
	var light := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	for third in 3:
		var about := Basis(Vector3(0, 0, 1), PI / 2.0 + TAU * third / 3.0)
		_add(light, Kit.box(Vector3(0.008, 0.024, 0.86)), Transform3D(about, about * Vector3(0.05 - 0.0015, 0.0, 0.7)), Color.WHITE)
		# (30 mm of light on a 70 mm rod: at the far end, 18 m from the seat, a narrower bar is a pixel wide and crawls)
		_add(light, Kit.box(Vector3(0.008, 0.03, length - 1.42)), Transform3D(about, about * Vector3(ROD_R - 0.002, 0.0, (length + 1.38) / 2.0)), Color.WHITE)
	_meshes[key] = _surfaces(st, light)
	return _meshes[key]


## The engine's yoke: its cheeks over the lug's pin (x through its origin), +z toward the pod, its
## tongue's yaw pin (along y) ENGINE_PIN out. It clears a lug boss 0.24 wide and 0.115 in radius.
static func yoke_mesh() -> ArrayMesh:
	if _meshes.has("yoke"):
		return _meshes.yoke
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var side := Transform3D(ABOUT_X, Vector3(0.135 * s, 0.0, 0.0))
		_turn(st, [[-0.013, 0.0, FORGED], [-0.013, 0.082, FORGED], [0.013, 0.082, FORGED], [0.013, 0.0, FORGED]], 16, side)          # a cheek round the pin
		_add(st, _plate(Vector3(0.092, 0.026, 0.2)), Kit.at(Vector3(0.135 * s, 0.0, 0.1), ON_EDGE), FORGED)                # and its arm
		var out := _along(Vector3(s, 0, 0), Vector3(0.148 * s, 0.0, 0.0))
		_head(st, out, 0.036, 0.022, BRIGHT, 6, true)                                                                      # the pin's nut,
		_head(st, out.translated_local(Vector3(0, 0, 0.022)), 0.015, 0.012, BRIGHT, 6)                                     # the pin's end through it
		_add(st, Kit.box(Vector3(0.0045, 0.044, 0.0045)), Kit.at(Vector3(0.176 * s, 0.0, 0.0), Vector3(0.5, 0, 0)), FORGED)   # and its split pin
		_web(st, Vector3(0.036 * s, 0.0, 0.219), Vector3(0.036 * s, 0.0, 0.264), Vector3(0.112 * s, 0.0, 0.219), 0.022, FORGED)   # a gusset from the bridge to the tongue
	_add(st, _plate(Vector3(0.296, 0.066, 0.064), 0.008), Kit.at(Vector3(0.0, 0.0, 0.187)), FORGED)                   # the bridge between them
	_nipple(st, Vector3(0.0, 1.0, -0.4), Vector3(0.0, 0.032, 0.18))
	_add(st, Kit.box(Vector3(0.072, 0.062, 0.06)), Kit.at(Vector3(0.0, 0.0, 0.235)), FORGED)                                       # the tongue
	var up := Transform3D(ABOUT_Y, Vector3(0, 0, ENGINE_PIN))
	_turn(st, [[-0.031, 0.0, FORGED], [-0.031, 0.04, FORGED], [0.031, 0.04, FORGED], [0.031, 0.0, FORGED]], 16, up)                # its eye
	for z0 in [-0.0345, 0.031]:
		_turn(st, [[z0, 0.02, BRONZE], [z0, 0.035, BRONZE], [z0 + 0.0035, 0.035, BRONZE], [z0 + 0.0035, 0.02, BRONZE]], 14, up)   # a washer either side of it
	_meshes.yoke = _surfaces(st, null)
	return _meshes.yoke
