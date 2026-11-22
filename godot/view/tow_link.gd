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
##   s.angles                              [swivel yaw, barrel pitch, yoke pitch, rod yaw], radians
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
const FORGED := Color(0.17, 0.18, 0.20)
const GUNMETAL := Color(0.27, 0.28, 0.31)
const BRIGHT := Color(0.74, 0.76, 0.80)
const BRONZE := Color(0.66, 0.50, 0.24)
const ABOUT_X := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))   # a part turned about +Z, laid along +X
const ABOUT_Y := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # ... or stood up along +Y
const ON_EDGE := Vector3(0, 0, PI / 2.0)     # a plate (thin along y as made) stood on its edge, thin along x

static var _meshes := {}
static var _metal: StandardMaterial3D


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
		"pins": [yaw_pin, pitch_pin],
		"angles": [atan2(zp.dot(pod.x.normalized()), -zp.dot(pod.z.normalized())), asin(clampf(u.dot(py), -1.0, 1.0)),
			atan2(ze.dot(engine.y.normalized()), ze.dot(engine.z.normalized())), atan2(-u.dot(ex), -u.dot(ze))],
	}


## The rod showing outside the gland for a span between the pins (what solve() draws, as a number).
static func exposed_for(span: float) -> float:
	return span - BARREL * clampf((span - 0.45) / BARREL, 0.05, 1.0)


# ---- the parts ----

static func _tri(st: SurfaceTool, xf: Transform3D, col: Color, p: Array, n: Array) -> void:
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


## A pin across a fork: a shank between two heads, about +Z, `half` from its middle to a head's inner face.
static func _pin(half: float, shank: float, head: float, thick: float) -> Array:
	return [[-half - thick, 0.0, BRIGHT], [-half - thick, head, BRIGHT], [-half, head, BRIGHT], [-half, shank, BRIGHT],
		[half, shank, BRIGHT], [half, head, BRIGHT], [half + thick, head, BRIGHT], [half + thick, 0.0, BRIGHT]]


static func _surfaces(steel: SurfaceTool, light: SurfaceTool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	steel.index()
	steel.commit(mesh)
	if light != null:
		light.index()
		light.commit(mesh)
	return mesh


## The pod's swivel. Its post's line is its y through its origin, its cheeks reach along +z to the
## pitch pin (along x) POD_PIN out.
static func swivel_mesh() -> ArrayMesh:
	if _meshes.has("swivel"):
		return _meshes.swivel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Transform3D(ABOUT_Y, Vector3.ZERO)
	# (a low puck: from the seat it stands in front of the engines, and the first cut's, 10 cm tall on a raised post, read as a black can)
	_turn(st, [[-HUB - 0.012, 0.0, BRONZE], [-HUB - 0.012, 0.068, BRONZE], [-HUB, 0.068, BRONZE], [-HUB, 0.056, BRONZE],      # the thrust washer it turns on
		[-HUB + 0.005, 0.06, GUNMETAL], [HUB - 0.012, 0.06, GUNMETAL], [HUB - 0.012, 0.06, BRIGHT], [HUB - 0.004, 0.06, BRIGHT],   # the hub, a machined land round its top
		[HUB, 0.056, BRIGHT], [HUB, 0.0, GUNMETAL]], 20, up)
	_turn(st, [[HUB, 0.028, BRIGHT], [HUB + 0.012, 0.028, BRIGHT], [HUB + 0.012, 0.0, BRIGHT]], 6, up, true)                  # the post's nut
	_turn(st, [[HUB + 0.012, 0.013, BRIGHT], [HUB + 0.02, 0.013, BRIGHT], [HUB + 0.02, 0.0, BRIGHT]], 10, up)                  # and the post's end through it
	for s in [-1.0, 1.0]:
		_add(st, _plate(Vector3(0.08, 0.022, 0.19)), Kit.at(Vector3(0.052 * s, 0.0, 0.105), ON_EDGE), FORGED)   # cheeks
	_turn(st, _pin(0.064, 0.017, 0.027, 0.014), 12, Transform3D(ABOUT_X, Vector3(0, 0, POD_PIN)))
	_meshes.swivel = _surfaces(st, null)
	return _meshes.swivel


## The barrel: its eye on the swivel's pitch pin (x through its origin), +z toward the engine, the
## gland's face at BARREL. Surface 0 its steel, surface 1 its lights (the link's own material).
static func barrel_mesh() -> ArrayMesh:
	if _meshes.has("barrel"):
		return _meshes.barrel
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mouth := BARREL - CANISTER
	_turn(st, [[-0.036, 0.0, FORGED], [-0.036, 0.042, FORGED], [0.036, 0.042, FORGED], [0.036, 0.0, FORGED]], 16, Transform3D(ABOUT_X, Vector3.ZERO))   # the eye
	_turn(st, [[-0.04, 0.02, BRONZE], [-0.04, 0.028, BRONZE], [0.04, 0.028, BRONZE], [0.04, 0.02, BRONZE]], 12, Transform3D(ABOUT_X, Vector3.ZERO))     # its bush, proud of both faces
	var body := [[0.03, 0.0, FORGED], [0.03, 0.03, FORGED], [0.1, 0.034, FORGED], [0.16, 0.05, FORGED],      # the neck, flaring to ...
		[0.16, 0.06, BRIGHT], [0.22, 0.06, BRIGHT], [0.22, BARREL_R, BRIGHT]]                                 # ... the end cap
	for zc in [1.0, 1.9, 2.8]:      # the tube, a clamp collar between each bay
		body.append_array([[zc - 0.022, BARREL_R, GUNMETAL], [zc - 0.022, 0.057, BRIGHT], [zc + 0.022, 0.057, BRIGHT], [zc + 0.022, BARREL_R, BRIGHT]])
	body.append_array([[mouth - 0.06, BARREL_R, GUNMETAL], [mouth, 0.062, FORGED]])                          # the shoulder of the draft gear
	for zf in [mouth + 0.22, mouth + 0.5, mouth + 0.78]:      # its canister, three cooling fins (broad: fine ones would shimmer at this range)
		body.append_array([[zf - 0.02, 0.062, FORGED], [zf - 0.02, 0.075, GUNMETAL], [zf + 0.02, 0.075, GUNMETAL], [zf + 0.02, 0.062, GUNMETAL]])
	body.append_array([[BARREL - 0.16, 0.062, FORGED], [BARREL - 0.16, 0.05, FORGED]])
	_turn(st, body, 16)
	_turn(st, [[BARREL - 0.16, 0.05, BRIGHT], [BARREL - 0.16, 0.061, BRIGHT], [BARREL - 0.045, 0.061, BRIGHT], [BARREL - 0.045, 0.044, BRIGHT]], 8, Transform3D.IDENTITY, true)   # the gland nut
	_turn(st, [[BARREL - 0.045, 0.044, FORGED], [BARREL, 0.044, FORGED], [BARREL, ROD_R + 0.0035, FORGED]], 16)   # its wiper, and the bore the rod and its light bars run in
	var light := SurfaceTool.new()
	light.begin(Mesh.PRIMITIVE_TRIANGLES)
	# light bars let into the tube, three round it in each bay: whichever way it is seen, one faces the eye
	# (slim: the first cut's, 20 mm wide, read as neon tubes)
	for bay in [[0.27, 0.95], [1.05, 1.85], [1.95, 2.75], [2.85, mouth - 0.09]]:
		var z0: float = bay[0]
		var z1: float = bay[1]
		for third in 3:
			var about := Basis(Vector3(0, 0, 1), PI / 2.0 + TAU * third / 3.0)
			_add(light, Kit.box(Vector3(0.008, 0.013, z1 - z0)), Transform3D(about, about * Vector3(BARREL_R - 0.0015, 0.0, (z0 + z1) / 2.0)), Color.WHITE)
	_turn(light, [[BARREL - 0.03, 0.0455, Color.WHITE], [BARREL - 0.012, 0.0455, Color.WHITE]], 16)             # the rod's light at the gland
	# ... and a ring of it round the end cap at the barrel's root, facing the cockpit. Flying straight the links run
	# down and away behind the nose, and this is the one lit part of each the pilot sees: its engine's thrust, its strain
	_turn(light, [[0.159, 0.047, Color.WHITE], [0.159, 0.0615, Color.WHITE], [0.184, 0.0615, Color.WHITE], [0.184, 0.06, Color.WHITE]], 16)
	_meshes.barrel = _surfaces(st, light)
	return _meshes.barrel


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
	_turn(st, _pin(0.058, 0.016, 0.025, 0.012), 12, Transform3D(ABOUT_Y, Vector3.ZERO))
	_add(st, _plate(Vector3(0.085, 0.114, 0.05), 0.008), Kit.at(Vector3(0.0, 0.0, 0.125)), FORGED)               # its root
	_turn(st, [[0.14, 0.0, FORGED], [0.14, 0.04, FORGED], [0.2, 0.058, FORGED], [0.25, 0.058, BRIGHT], [0.25, 0.05, BRIGHT],            # the coupler: the widest thing at the far end
		[1.15, 0.05, GUNMETAL], [1.15, 0.058, BRIGHT], [1.2, 0.058, BRIGHT], [1.34, 0.04, FORGED], [1.34, ROD_R, FORGED]], 14)            # ... down to the rod
	_turn(st, [[1.34, ROD_R, BRIGHT], [length, ROD_R, BRIGHT], [length, 0.0, BRIGHT]], 12)                                                      # the rod: bright steel, a piston's
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
		_turn(st, [[-0.013, 0.0, FORGED], [-0.013, 0.082, FORGED], [0.013, 0.082, FORGED], [0.013, 0.0, FORGED]], 18, side)          # a cheek round the pin
		_add(st, _plate(Vector3(0.092, 0.026, 0.2)), Kit.at(Vector3(0.135 * s, 0.0, 0.1), ON_EDGE), FORGED)                # and its arm
		_turn(st, [[-0.011, 0.0, BRIGHT], [-0.011, 0.036, BRIGHT], [0.011, 0.036, BRIGHT], [0.011, 0.0, BRIGHT]], 6, Transform3D(ABOUT_X, Vector3(0.159 * s, 0.0, 0.0)), true)   # the pin's nut
	_add(st, _plate(Vector3(0.296, 0.066, 0.064), 0.008), Kit.at(Vector3(0.0, 0.0, 0.187)), FORGED)                   # the bridge between them
	_add(st, Kit.box(Vector3(0.072, 0.062, 0.06)), Kit.at(Vector3(0.0, 0.0, 0.235)), FORGED)                                       # the tongue
	var up := Transform3D(ABOUT_Y, Vector3(0, 0, ENGINE_PIN))
	_turn(st, [[-0.031, 0.0, FORGED], [-0.031, 0.04, FORGED], [0.031, 0.04, FORGED], [0.031, 0.0, FORGED]], 16, up)                # its eye
	for z0 in [-0.0345, 0.031]:
		_turn(st, [[z0, 0.02, BRONZE], [z0, 0.035, BRONZE], [z0 + 0.0035, 0.035, BRONZE], [z0 + 0.0035, 0.02, BRONZE]], 14, up)   # a washer either side of it
	_meshes.yoke = _surfaces(st, null)
	return _meshes.yoke
