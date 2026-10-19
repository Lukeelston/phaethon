## Scenery props shared by the range and the GP: desert plants and boulders, runway lights, and
## the buildings of an airfield and a race circuit. Every prop is one compound mesh (MeshKit,
## vertex-coloured, one draw call); `multi` places many of one as a single MultiMesh, faded out
## past a visibility range so far-off scatter costs nothing.
##   Props.mesh("joshua0") -> Mesh        (cached; see MESHES)
##   Props.multi(parent, "bush", xforms, 2500.0)
##   Props.place(parent, "hangar", xform)
extends RefCounted

const Kit := preload("res://view/mesh_kit.gd")
const MESHES := ["joshua0", "joshua1", "bush", "boulder", "edge_light", "hangar", "tower", "tank",
	"radar_base", "radar_dish", "windsock", "floodlight", "pit_building", "truck", "lamp_white", "lamp_green",
	"poplar", "oak", "pine", "house0", "house1", "spire"]
const BARK := Color(0.40, 0.33, 0.25)
const LEAF := Color(0.36, 0.42, 0.21)
const DEAD := Color(0.55, 0.49, 0.38)
const METAL := Color(0.74, 0.74, 0.72)
const CONCRETE := Color(0.80, 0.78, 0.73)
const LIVERY := Color(0.86, 0.27, 0.09)
const GLASS := Color(0.16, 0.26, 0.30)

static var _cache := {}
static var _mats := {}


static func mesh(name: String) -> Mesh:
	if not _cache.has(name):
		match name:
			"joshua0": _cache[name] = _joshua(0)
			"joshua1": _cache[name] = _joshua(1)
			"bush": _cache[name] = _bush()
			"boulder": _cache[name] = _boulder()
			"edge_light": _cache[name] = _edge_light()
			"hangar": _cache[name] = _hangar()
			"tower": _cache[name] = _tower()
			"tank": _cache[name] = _tank()
			"radar_base": _cache[name] = _radar_base()
			"radar_dish": _cache[name] = _radar_dish()
			"windsock": _cache[name] = _windsock()
			"floodlight": _cache[name] = _floodlight()
			"pit_building": _cache[name] = _pit_building()
			"truck": _cache[name] = _truck()
			"poplar": _cache[name] = _poplar()
			"oak": _cache[name] = _oak()
			"pine": _cache[name] = _pine()
			"house0": _cache[name] = _house(0)
			"house1": _cache[name] = _house(1)
			"spire": _cache[name] = _spire()
			"lamp_white": _cache[name] = Kit.compound([[Kit.ball(0.13, 8), Kit.at(Vector3(0, 0.58, 0)), Color(1.0, 0.93, 0.78)]])
			"lamp_green": _cache[name] = Kit.compound([[Kit.ball(0.16, 8), Kit.at(Vector3(0, 0.12, 0)), Color(0.25, 1.0, 0.4)]])
	return _cache[name]


## The shared vertex-colour material; lamps get a glowing one (blooms under the environment's glow).
static func material(lamp := false) -> Material:
	var key := "lamp" if lamp else "solid"
	if not _mats.has(key):
		if lamp:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.albedo_color = Color(2.2, 2.2, 2.2)   # HDR: over the glow threshold
			_mats[key] = m
		else:
			_mats[key] = Kit.vertex_colors()
	return _mats[key]


static func multi(parent: Node3D, name: String, xforms: Array, vis_end := 0.0, lamp := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh(name)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material(lamp)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = vis_end * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi


## Many of one prop spread over a big area: binned into `block`-metre squares, each its own
## MultiMesh under a node at the square's centre, so each square culls by its own distance.
## Returns how many squares were made.
static func binned(parent: Node3D, name: String, xforms: Array, block: float, vis_end: float) -> int:
	var bins := {}
	for t in xforms:
		var key := Vector2i(floori((t as Transform3D).origin.x / block), floori((t as Transform3D).origin.z / block))
		if not bins.has(key):
			bins[key] = []
		bins[key].append(t)
	for key in bins:
		var blk := Node3D.new()
		blk.position = Vector3((key.x + 0.5) * block, 0.0, (key.y + 0.5) * block)
		parent.add_child(blk)
		var back := Transform3D(Basis(), -blk.position)
		multi(blk, name, bins[key].map(func(t): return back * t), vis_end)
	return bins.size()


static func place(parent: Node3D, name: String, xf: Transform3D, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(name)
	mi.material_override = material()
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A random upright placement: yaw, size, and a little lean.
static func scatter_xf(rng: RandomNumberGenerator, pos: Vector3, s0: float, s1: float, lean := 0.08) -> Transform3D:
	var s := rng.randf_range(s0, s1)
	var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-lean, lean))
	return Transform3D(b.scaled(Vector3.ONE * s), pos)


# --- plants and rocks -----------------------------------------------------------------------

## Joshua tree, ~6 m: a shaggy trunk forking into arms, each ending in a spiky green tuft over a
## skirt of dead leaves.
static func _joshua(variant: int) -> ArrayMesh:
	var parts := []
	var trunk_h := 2.6 if variant == 0 else 3.4
	parts.append([Kit.cyl(0.2, 0.32, trunk_h, 7), Kit.at(Vector3(0, trunk_h / 2.0, 0)), BARK])
	var arms := [[0.0, 0.7, 1.7], [2.2, 0.9, 1.4], [4.1, 0.55, 1.9]] if variant == 0 \
		else [[0.6, 0.45, 1.3], [2.9, 0.8, 1.6], [4.4, 1.0, 1.2], [5.6, 0.35, 1.0]]
	for a in arms:
		var yaw: float = a[0]
		var tilt: float = a[1]
		var l: float = a[2]
		var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, tilt)
		var base := Vector3(0, trunk_h - 0.1, 0)
		var tip := base + dir * Vector3(0, l, 0)
		parts.append([Kit.cyl(0.12, 0.17, l, 6), Transform3D(dir, base + dir * Vector3(0, l / 2.0, 0)), BARK])
		parts.append([Kit.cyl(0.3, 0.12, 0.55, 7), Kit.at(tip + Vector3(0, -0.1, 0)), DEAD])     # skirt
		parts.append([Kit.cyl(0.0, 0.42, 0.7, 7), Kit.at(tip + Vector3(0, 0.4, 0)), LEAF])       # tuft
		parts.append([Kit.cyl(0.0, 0.3, 0.45, 5), Transform3D(Basis(Vector3.RIGHT, PI), tip + Vector3(0, 0.05, 0)), LEAF.darkened(0.2)])
	return Kit.compound(parts)


## Creosote / sage bush, ~1.5 m: three squashed blobs, olive.
static func _bush() -> ArrayMesh:
	var parts := []
	for b in [[Vector3(0, 0.45, 0), 0.75, LEAF.lightened(0.12)], [Vector3(0.5, 0.35, 0.3), 0.55, LEAF], [Vector3(-0.4, 0.3, -0.35), 0.5, Color(0.47, 0.45, 0.30)]]:
		var s := SphereMesh.new()
		s.radius = b[1]
		s.height = b[1] * 1.3
		s.radial_segments = 7
		s.rings = 3
		parts.append([s, Kit.at(b[0]), b[2]])
	return Kit.compound(parts)


## Boulder, ~1.1 m: a lumpy, flat-shaded sphere (the old rocks were boxes), weathered tan.
static func _boulder() -> ArrayMesh:
	var s := SphereMesh.new()
	s.radius = 0.55
	s.height = 1.1
	s.radial_segments = 9
	s.rings = 5
	var arr := s.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bump := func(v: Vector3) -> Vector3:
		var k := v.normalized()
		var n := sin(k.x * 7.1 + 1.3) * cos(k.z * 5.3) + 0.6 * sin(k.y * 9.7 + k.x * 3.1)
		return v * (1.0 + 0.16 * n) * Vector3(1.0, 0.8, 1.0)
	for t in range(0, idx.size(), 3):
		var p := [bump.call(verts[idx[t]]), bump.call(verts[idx[t + 1]]), bump.call(verts[idx[t + 2]])]
		var nrm: Vector3 = (p[2] - p[0]).cross(p[1] - p[0]).normalized()
		var shade := 0.85 + 0.15 * fposmod(float(t) * 0.618, 1.0)
		for q in p:
			st.set_color(Color(0.58, 0.46, 0.34) * shade)
			st.set_normal(nrm)
			st.add_vertex(q)
	return st.commit()


# --- lights -----------------------------------------------------------------------------------

## Runway edge light: a short post with a lamp (the lamp is a separate glowing MultiMesh: see
## RangeWorld; this is the post and a dark collar).
static func _edge_light() -> ArrayMesh:
	return Kit.compound([[Kit.cyl(0.05, 0.07, 0.5, 6), Kit.at(Vector3(0, 0.25, 0)), Color(0.85, 0.75, 0.2)],
		[Kit.cyl(0.11, 0.11, 0.06, 8), Kit.at(Vector3(0, 0.5, 0)), Color(0.15, 0.15, 0.16)]])


## Floodlight tower, 30 m: a lattice-look mast, a service platform, and a bank of lamps facing
## the track (-Z).
static func _floodlight() -> ArrayMesh:
	var steel := Color(0.55, 0.57, 0.6)
	var parts := [[Kit.cyl(0.35, 0.6, 30.0, 8), Kit.at(Vector3(0, 15.0, 0)), steel],
		[Kit.box(Vector3(3.2, 0.2, 2.0)), Kit.at(Vector3(0, 27.5, 0.2)), steel.darkened(0.3)],
		[Kit.box(Vector3(6.0, 3.4, 0.5)), Kit.at(Vector3(0, 31.2, -0.4), Vector3(-0.35, 0, 0)), Color(0.18, 0.19, 0.2)]]
	for r in 3:
		for c in 5:
			parts.append([Kit.box(Vector3(0.95, 0.85, 0.12)), Kit.at(Vector3(-2.2 + c * 1.1, 30.1 + r * 1.0, -0.72 + r * 0.33), Vector3(-0.35, 0, 0)), Color(0.92, 0.94, 0.96)])
	return Kit.compound(parts)


# --- airfield ---------------------------------------------------------------------------------

## Hangar, 40 x 30 m, arched roof, its big door facing -Z (toward the runway when placed so).
static func _hangar() -> ArrayMesh:
	var parts := [[Kit.box(Vector3(40.0, 11.0, 30.0)), Kit.at(Vector3(0, 5.5, 0)), METAL],
		[Kit.cyl(20.0, 20.0, 30.0, 20), Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, 0.32, 1.0)), Vector3(0, 11.0, 0)), METAL.darkened(0.12)],
		[Kit.box(Vector3(30.0, 9.5, 0.3)), Kit.at(Vector3(0, 4.75, -15.05)), Color(0.24, 0.26, 0.29)],     # door
		[Kit.box(Vector3(40.4, 1.0, 0.4)), Kit.at(Vector3(0, 10.2, -15.1)), LIVERY],                     # stripe
		[Kit.box(Vector3(0.3, 9.5, 0.4)), Kit.at(Vector3(0, 4.75, -15.2)), Color(0.4, 0.42, 0.45)]]      # door seam
	for k in 6:   # corrugation ribs down the sides
		for s in [-1.0, 1.0]:
			parts.append([Kit.box(Vector3(0.25, 11.0, 0.25)), Kit.at(Vector3(s * 20.05, 5.5, -12.5 + k * 5.0)), METAL.darkened(0.25)])
	return Kit.compound(parts)


## Control tower, 26 m: concrete shaft, a glass cab with a catwalk, antenna and beacon.
static func _tower() -> ArrayMesh:
	return Kit.compound([[Kit.box(Vector3(5.0, 20.0, 5.0)), Kit.at(Vector3(0, 10.0, 0)), CONCRETE],
		[Kit.box(Vector3(9.0, 3.0, 9.0)), Kit.at(Vector3(0, 1.5, 0)), CONCRETE.darkened(0.08)],
		[Kit.cyl(4.6, 4.6, 0.4, 8), Kit.at(Vector3(0, 20.2, 0)), Color(0.35, 0.35, 0.37)],               # catwalk
		[Kit.cyl(3.6, 3.0, 3.6, 8), Kit.at(Vector3(0, 22.2, 0)), GLASS],                                  # cab
		[Kit.cyl(4.0, 4.0, 0.5, 8), Kit.at(Vector3(0, 24.25, 0)), Color(0.9, 0.9, 0.88)],                 # roof
		[Kit.cyl(0.08, 0.12, 5.0, 5), Kit.at(Vector3(1.2, 27.0, 0)), Color(0.8, 0.8, 0.82)],              # antenna
		[Kit.ball(0.35, 8), Kit.at(Vector3(1.2, 29.6, 0)), Color(1.0, 0.15, 0.1)],
		[Kit.box(Vector3(2.0, 0.8, 0.1)), Kit.at(Vector3(0, 17.0, -2.55)), LIVERY]])


## Fuel tank, 12 m across: white with an orange band and a ladder.
static func _tank() -> ArrayMesh:
	return Kit.compound([[Kit.cyl(6.0, 6.0, 9.0, 18), Kit.at(Vector3(0, 4.5, 0)), Color(0.9, 0.9, 0.88)],
		[Kit.cyl(6.05, 6.05, 1.2, 18), Kit.at(Vector3(0, 6.2, 0)), LIVERY],
		[Kit.cyl(5.6, 6.0, 0.8, 18), Kit.at(Vector3(0, 9.4, 0)), Color(0.82, 0.82, 0.8)],
		[Kit.box(Vector3(0.6, 9.5, 0.3)), Kit.at(Vector3(0, 4.75, -6.1)), Color(0.4, 0.4, 0.42)]])


static func _radar_base() -> ArrayMesh:
	return Kit.compound([[Kit.box(Vector3(4.0, 3.0, 4.0)), Kit.at(Vector3(0, 1.5, 0)), CONCRETE],
		[Kit.cyl(0.5, 0.8, 6.0, 8), Kit.at(Vector3(0, 6.0, 0)), Color(0.6, 0.62, 0.64)]])


## The radar dish: spun about its mast by RangeWorld (origin at the top of the mast).
static func _radar_dish() -> ArrayMesh:
	var dish := SphereMesh.new()
	dish.radius = 3.5
	dish.height = 2.4
	dish.radial_segments = 14
	dish.rings = 6
	return Kit.compound([[dish, Transform3D(Basis(Vector3.RIGHT, -1.2) * Basis.from_scale(Vector3(1.0, 0.35, 1.0)), Vector3(0, 1.0, 0.6)), Color(0.92, 0.92, 0.9)],
		[Kit.box(Vector3(0.6, 1.6, 0.6)), Kit.at(Vector3(0, 0.3, 0)), Color(0.5, 0.5, 0.52)],
		[Kit.cyl(0.08, 0.08, 2.2, 5), Kit.at(Vector3(0, 1.4, -0.6), Vector3(-0.4, 0, 0)), Color(0.4, 0.4, 0.42)]])


## Windsock on an 8 m pole, streaming toward +X in orange and white bands.
static func _windsock() -> ArrayMesh:
	var parts := [[Kit.cyl(0.08, 0.12, 8.0, 6), Kit.at(Vector3(0, 4.0, 0)), Color(0.85, 0.85, 0.83)]]
	for k in 4:
		var r0 := 0.55 - k * 0.09
		parts.append([Kit.cyl(r0 - 0.09, r0, 0.8, 10), Transform3D(Basis(Vector3.FORWARD, PI / 2.0 - 0.15), Vector3(0.5 + k * 0.78, 7.6 - k * 0.1, 0)),
			LIVERY if k % 2 == 0 else Color(0.95, 0.95, 0.93)])
	return Kit.compound(parts)


## Fuel bowser: cab, tank, wheels. ~9 m long along +X.
static func _truck() -> ArrayMesh:
	var parts := [[Kit.box(Vector3(2.2, 2.4, 2.4)), Kit.at(Vector3(3.4, 1.7, 0)), Color(0.9, 0.86, 0.3)],
		[Kit.box(Vector3(1.6, 0.9, 2.3)), Kit.at(Vector3(3.6, 2.4, 0)), GLASS],
		[Kit.cyl(1.15, 1.15, 5.6, 12), Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(-0.6, 1.9, 0)), Color(0.88, 0.88, 0.86)],
		[Kit.box(Vector3(8.4, 0.4, 2.2)), Kit.at(Vector3(0.6, 0.75, 0)), Color(0.2, 0.2, 0.22)]]
	for wx in [-2.6, -1.2, 3.4]:
		for s in [-1.0, 1.0]:
			parts.append([Kit.cyl(0.5, 0.5, 0.4, 10), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(wx, 0.5, s * 1.1)), Color(0.08, 0.08, 0.09)])
	return Kit.compound(parts)


## Pit building, 120 m along +X: two storeys of garages (doors facing -Z), a glass race-control
## deck on top, sponsor band.
static func _pit_building() -> ArrayMesh:
	var parts := [[Kit.box(Vector3(120.0, 9.0, 18.0)), Kit.at(Vector3(0, 4.5, 0)), Color(0.88, 0.88, 0.86)],
		[Kit.box(Vector3(118.0, 3.0, 12.0)), Kit.at(Vector3(0, 10.5, 2.0)), GLASS],
		[Kit.box(Vector3(122.0, 0.6, 16.0)), Kit.at(Vector3(0, 12.3, 1.0)), Color(0.3, 0.31, 0.33)],
		[Kit.box(Vector3(120.4, 1.2, 0.3)), Kit.at(Vector3(0, 8.0, -9.05)), LIVERY]]
	for k in 12:
		parts.append([Kit.box(Vector3(7.5, 5.0, 0.2)), Kit.at(Vector3(-55.0 + k * 10.0, 2.5, -9.05)), Color(0.22, 0.24, 0.27)])
	return Kit.compound(parts)


# --- the verdant world (Eridanus) ----------------------------------------------------------------

## Lombardy poplar, ~22 m: a tall, narrow column of dark green on a short trunk (the Heliades: the
## sisters on the Eridanus' banks).
static func _poplar() -> ArrayMesh:
	var crown := SphereMesh.new()
	crown.radius = 2.3
	crown.height = 18.0
	crown.radial_segments = 8
	crown.rings = 6
	return Kit.compound([[Kit.cyl(0.25, 0.35, 4.0, 6), Kit.at(Vector3(0, 2.0, 0)), BARK],
		[crown, Kit.at(Vector3(0, 12.5, 0)), Color(0.20, 0.33, 0.14)]])


## Oak, ~14 m: a stout trunk under a broad crown of three blobs.
static func _oak() -> ArrayMesh:
	var parts := [[Kit.cyl(0.45, 0.65, 5.0, 7), Kit.at(Vector3(0, 2.5, 0)), BARK]]
	for b in [[Vector3(0, 9.0, 0), 5.2, Color(0.27, 0.40, 0.16)], [Vector3(3.2, 8.0, 1.0), 3.6, Color(0.24, 0.37, 0.14)], [Vector3(-2.6, 8.3, -1.6), 3.8, Color(0.30, 0.43, 0.18)]]:
		var s := SphereMesh.new()
		s.radius = b[1]
		s.height = b[1] * 1.6
		s.radial_segments = 8
		s.rings = 4
		parts.append([s, Kit.at(b[0]), b[2]])
	return Kit.compound(parts)


## Pine, ~18 m: stacked cones over a thin trunk.
static func _pine() -> ArrayMesh:
	var parts := [[Kit.cyl(0.22, 0.32, 4.0, 6), Kit.at(Vector3(0, 2.0, 0)), BARK]]
	for k in 4:
		parts.append([Kit.cyl(0.0, 3.6 - k * 0.7, 5.0, 8), Kit.at(Vector3(0, 5.0 + k * 3.2, 0)), Color(0.13, 0.26, 0.15).lightened(k * 0.03)])
	return Kit.compound(parts)


## A village house, ~9 x 7 m: whitewashed walls under a red-tiled (0) or slate (1) gabled roof.
static func _house(variant: int) -> ArrayMesh:
	var wall := Color(0.92, 0.89, 0.82) if variant == 0 else Color(0.82, 0.76, 0.66)
	var roof := Color(0.66, 0.26, 0.17) if variant == 0 else Color(0.30, 0.31, 0.34)
	var parts := [[Kit.box(Vector3(9.0, 5.0, 7.0)), Kit.at(Vector3(0, 2.5, 0)), wall],
		[Kit.box(Vector3(9.6, 0.25, 4.6)), Transform3D(Basis(Vector3.RIGHT, 0.62), Vector3(0, 6.6, -1.75)), roof],
		[Kit.box(Vector3(9.6, 0.25, 4.6)), Transform3D(Basis(Vector3.RIGHT, -0.62), Vector3(0, 6.6, 1.75)), roof],
		[Kit.box(Vector3(1.0, 2.2, 0.15)), Kit.at(Vector3(0, 1.1, 3.55)), Color(0.35, 0.22, 0.14)],
		[Kit.box(Vector3(0.9, 1.2, 1.0)), Kit.at(Vector3(2.8, 8.0, 0)), Color(0.55, 0.3, 0.22)]]
	for wx in [-2.8, 2.8]:
		parts.append([Kit.box(Vector3(1.2, 1.0, 0.12)), Kit.at(Vector3(wx, 3.0, 3.53)), Color(0.18, 0.22, 0.26)])
	return Kit.compound(parts)


## The village church: a nave with a tall spire, ~38 m.
static func _spire() -> ArrayMesh:
	var stone := Color(0.78, 0.74, 0.66)
	return Kit.compound([[Kit.box(Vector3(10.0, 9.0, 22.0)), Kit.at(Vector3(0, 4.5, 4.0)), stone],
		[Kit.box(Vector3(10.6, 0.3, 6.0)), Transform3D(Basis(Vector3.FORWARD, 0.0) * Basis(Vector3.RIGHT, 0.0), Vector3(0, 9.2, 4.0)), Color(0.3, 0.31, 0.34)],
		[Kit.box(Vector3(6.0, 20.0, 6.0)), Kit.at(Vector3(0, 10.0, -9.0)), stone],
		[Kit.cyl(0.0, 4.2, 16.0, 8), Kit.at(Vector3(0, 28.0, -9.0)), Color(0.32, 0.36, 0.38)],
		[Kit.box(Vector3(0.3, 2.4, 0.3)), Kit.at(Vector3(0, 37.2, -9.0)), Color(0.85, 0.7, 0.3)]])

