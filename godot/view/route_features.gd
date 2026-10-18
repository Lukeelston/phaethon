## Things to fly past on the 100 miles, so the run has places in it: road overpasses every
## ten miles (fly under them; a green sign on each says how far is left), a halfway gantry, and
## a landmark roughly every ten miles out in the desert. Placement is rule-based and checked
## (tests/test_route.gd): nothing sits on a lane, a corridor, a sign or another feature, and
## the rocks and spires keep out of every footprint (blocked()).
##   route = Route.new()                          once (pure data: placements, footprints)
##   route.build_chunk(node, cx, x0, x1)          when RangeWorld builds a chunk
##   route.animate(t)                             every frame (rotors, dishes, beacons, lights)
## Visual only: the sim has no collision with any of it, like the rest of the range.
extends RefCounted

const RangeWorld := preload("res://view/range_world.gd")
const Sim := preload("res://sim/craft_sim.gd")
const Kit := preload("res://view/mesh_kit.gd")
const MILE := 1609.344

# Overpasses: a road crossing the range on a bridge over the runway, ramps down to the desert.
const OVERPASS_MILES := [8, 18, 28, 38, 58, 68, 78, 88]
const DECK_TOP := 13.0        # road surface height
const DECK_T := 1.2           # deck thickness: underside at 11.8 m (the telegraph poles are 11 m)
const DECK_HALF_Y := 160.0    # bridge from -160 to +160, ramps beyond
const RAMP_END_Y := 290.0
const ROAD_HALF := 8.0        # road width along the range direction
const PIER_Y := [-150.0, -75.0, 75.0, 150.0]
const SIGN_W := 16.0
const SIGN_H := 5.0
# [kind, mile, y]: one landmark at a time out in the desert, every ~ten miles
const LANDMARKS := [["water_tower", 4.2, 250.0], ["wind_farm", 13.0, 1350.0], ["wreck", 23.0, -1600.0],
	["dishes", 33.0, 1650.0], ["arch", 43.0, -1450.0], ["gantry", 50.3, 0.0], ["vaporators", 57.4, 230.0],
	["needle", 66.0, 2600.0], ["sandcrawler", 75.0, 1250.0], ["spaceport", 84.0, -1750.0]]

var overpass_x: Array[float] = []
var features: Array = []      # [kind, x, y]
var blockers: Array = []      # [x0, x1, y0, y1, kind]
var anim: Array = []          # [node, kind, phase]
var mats := {}


func _init() -> void:
	for m in OVERPASS_MILES:
		overpass_x.append(_place_overpass(m))
	for o in overpass_x:
		blockers.append([o - 22.0, o + 22.0, -RAMP_END_Y - 10.0, RAMP_END_Y + 10.0, "overpass"])
	for f in LANDMARKS:
		var x: float = f[1] * MILE
		features.append([f[0], x, f[2]])
		var e: Vector2 = extent(f[0])
		blockers.append([x - e.x, x + e.x, f[2] - e.y, f[2] + e.y, f[0]])
	mats.shaded = Kit.vertex_colors()
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.vertex_color_use_as_albedo = true
	glow.vertex_color_is_srgb = true
	glow.disable_fog = true
	mats.glow = glow


## An overpass goes a half mile past its mile (clear of the mile sign), nudged up to 600 m
## either way to where the twisty lane has swung well south of its ramp.
static func _place_overpass(m: int) -> float:
	var base := (m + 0.5) * MILE
	var best := base
	var best_y := INF
	for k in 25:
		var dx: float = 50.0 * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
		var x: float = base + dx
		var north := -INF
		for s in [-30.0, 0.0, 30.0]:
			north = maxf(north, RangeWorld.twist_y(x + s) + RangeWorld.TWIST_HALF)
		if north <= -RAMP_END_Y - 60.0:
			return x
		if north < best_y:
			best_y = north
			best = x
	return best


## Half-size of each landmark's footprint (x, y), metres.
static func extent(kind: String) -> Vector2:
	match kind:
		"water_tower": return Vector2(20, 20)
		"wind_farm": return Vector2(1150, 70)
		"wreck": return Vector2(200, 120)
		"dishes": return Vector2(260, 330)
		"arch": return Vector2(110, 40)
		"gantry": return Vector2(12, 100)
		"vaporators": return Vector2(230, 70)
		"needle": return Vector2(40, 40)
		"sandcrawler": return Vector2(70, 40)
		"spaceport": return Vector2(320, 200)
	return Vector2(50, 50)


## Is (x, y) inside any feature's footprint, grown by margin? (rocks, spires keep out)
func blocked(x: float, y: float, margin := 0.0) -> bool:
	for b in blockers:
		if x > b[0] - margin and x < b[1] + margin and y > b[2] - margin and y < b[3] + margin:
			return true
	return false


## Height of the overpass road at lateral position y (deck, then ramps down; 0 off the end).
static func road_height(y: float) -> float:
	var a := absf(y)
	if a <= DECK_HALF_Y:
		return DECK_TOP
	if a >= RAMP_END_Y:
		return 0.0
	return DECK_TOP * (RAMP_END_Y - a) / (RAMP_END_Y - DECK_HALF_Y)


func build_chunk(node: Node3D, cx: float, x0: float, x1: float) -> void:
	for o in overpass_x:
		if o - cx >= x0 and o - cx < x1:
			_overpass(node, o - cx, o)
	for f in features:
		var lx: float = f[1] - cx
		if lx >= x0 and lx < x1:
			call("_" + f[0], node, lx, f[2])


func animate(t: float) -> void:
	var live := []
	for a in anim:
		if not is_instance_valid(a[0]):
			continue
		live.append(a)
		var n: Node3D = a[0]
		match a[1]:
			"rotor":
				n.rotation.z = fposmod(t * 1.1 + a[2], TAU)
			"dish":
				n.rotation.y = a[2] + 0.6 * sin(t * 0.05 + a[2])
			"beacon":
				n.visible = fposmod(t + a[2], 1.4) < 0.25
			"chase":
				n.visible = int(t * 8.0) % 6 == int(a[2])
	anim = live


# ---------------------------------------------------------------- builders (chunk-local)

func _add(node: Node3D, parts: Array, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = mats.glow if glow else mats.shaded
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	return mi


func _text(node: Node3D, pos: Vector3, text: String, size: int, px: float, c: Color, face_x := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.position = pos
	if face_x:
		l.rotation.y = -PI / 2.0   # face down the range, at the approaching pilot
	else:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	node.add_child(l)
	return l


## A triangle-fan / quad face helper for hand-built solids (normal given).
static func _face(st: SurfaceTool, pts: Array, c: Color, n: Vector3) -> void:
	for i in range(1, pts.size() - 1):
		for p in [pts[0], pts[i], pts[i + 1]]:
			st.set_color(c)
			st.set_normal(n)
			st.add_vertex(p)


func _overpass(node: Node3D, lx: float, x_abs: float) -> void:
	var concrete := Color(0.66, 0.63, 0.58)
	var dark := Color(0.24, 0.23, 0.22)
	var deck_len := DECK_HALF_Y * 2.0
	var parts := [
		[Kit.box(Vector3(ROAD_HALF * 2.0, DECK_T, deck_len)), Kit.at(Vector3(lx, DECK_TOP - DECK_T / 2.0, 0)), concrete],
		[Kit.box(Vector3(ROAD_HALF * 2.0 - 1.0, 0.06, deck_len)), Kit.at(Vector3(lx, DECK_TOP + 0.03, 0)), dark],   # asphalt
	]
	for s in [-1.0, 1.0]:   # parapets
		parts.append([Kit.box(Vector3(0.35, 1.1, deck_len)), Kit.at(Vector3(lx + s * (ROAD_HALF - 0.2), DECK_TOP + 0.55, 0)), concrete])
	for py in PIER_Y:
		parts.append([Kit.box(Vector3(ROAD_HALF * 2.0 - 2.0, 1.0, 2.6)), Kit.at(Vector3(lx, DECK_TOP - DECK_T - 0.5, -py)), concrete])   # pier cap
		for s in [-1.0, 1.0]:
			parts.append([Kit.cyl(1.0, 1.25, DECK_TOP - DECK_T - 1.0, 14), Kit.at(Vector3(lx + s * 4.5, (DECK_TOP - DECK_T - 1.0) / 2.0, -py)), concrete])
	var y := -DECK_HALF_Y
	while y < DECK_HALF_Y:   # centre dashes
		parts.append([Kit.box(Vector3(0.18, 0.02, 3.0)), Kit.at(Vector3(lx, DECK_TOP + 0.07, -(y + 1.5))), Color(0.95, 0.85, 0.3)])
		y += 9.0
	_add(node, parts)
	# ramps: embankments from the bridge ends down to the desert
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sand := Color(0.70, 0.58, 0.42)
	for s in [-1.0, 1.0]:
		var ya: float = s * DECK_HALF_Y
		var yb: float = s * RAMP_END_Y
		var spread := DECK_TOP * 0.9
		var a := Vector3(lx - ROAD_HALF, DECK_TOP, -ya)
		var b := Vector3(lx + ROAD_HALF, DECK_TOP, -ya)
		var c := Vector3(lx + ROAD_HALF, 0.0, -yb)
		var d := Vector3(lx - ROAD_HALF, 0.0, -yb)
		var el := Vector3(lx - ROAD_HALF - spread, 0.0, -ya)
		var er := Vector3(lx + ROAD_HALF + spread, 0.0, -ya)
		var up := (b - a).cross(d - a).normalized()
		_face(st, [a, b, c, d], dark, up if up.y > 0.0 else -up)
		_face(st, [a, d, el], sand, Vector3(-1, 0.6, 0).normalized())
		_face(st, [b, er, c], sand, Vector3(1, 0.6, 0).normalized())
		_face(st, [el, a, b, er], concrete, Vector3(0, 0, s))
	var emb := MeshInstance3D.new()
	emb.mesh = st.commit()
	emb.material_override = mats.shaded
	emb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(emb)
	# the sign, on the face you approach: how far is left
	var green := Color(0.05, 0.36, 0.17)
	_add(node, [[Kit.box(Vector3(0.3, SIGN_H, SIGN_W)), Kit.at(Vector3(lx - ROAD_HALF - 0.4, DECK_TOP + 0.4, 0)), green],
		[Kit.box(Vector3(0.32, SIGN_H - 0.4, SIGN_W - 0.4)), Kit.at(Vector3(lx - ROAD_HALF - 0.42, DECK_TOP + 0.4, 0)), Color(0.9, 0.92, 0.9)],
		[Kit.box(Vector3(0.34, SIGN_H - 0.7, SIGN_W - 0.7)), Kit.at(Vector3(lx - ROAD_HALF - 0.44, DECK_TOP + 0.4, 0)), green]])
	var left := maxf(0.0, (Sim.BOX_X - x_abs) / MILE)
	_text(node, Vector3(lx - ROAD_HALF - 0.65, DECK_TOP + 1.3, 0), "MILE %.1f" % (x_abs / MILE), 300, 0.008, Color(0.97, 0.97, 0.95), true)
	_text(node, Vector3(lx - ROAD_HALF - 0.65, DECK_TOP - 0.7, 0), "%.1f TO GO" % left, 220, 0.008, Color(0.97, 0.97, 0.95), true)


func _water_tower(node: Node3D, lx: float, y: float) -> void:
	var steel := Color(0.78, 0.8, 0.82)
	var parts := []
	for c in [Vector2(-6, -6), Vector2(6, -6), Vector2(6, 6), Vector2(-6, 6)]:
		parts.append([Kit.cyl(0.45, 0.6, 32.0, 10), Kit.at(Vector3(lx + c.x, 16.0, -y + c.y)), steel])
	for h in [10.0, 21.0]:
		for i in 4:
			var r := Basis(Vector3.UP, i * PI / 2.0)
			parts.append([Kit.box(Vector3(12.0, 0.3, 0.3)), Transform3D(r, Vector3(lx, h, -y) + r * Vector3(0, 0, 6.0)), steel])
	parts.append([Kit.ball(1.0, 24), Kit.at(Vector3(lx, 38.0, -y), Vector3.ZERO, Vector3(11.0, 8.0, 11.0)), steel])
	parts.append([Kit.cyl(0.4, 11.5, 5.0, 24), Kit.at(Vector3(lx, 47.5, -y)), Color(0.86, 0.27, 0.09)])
	_add(node, parts)
	_text(node, Vector3(lx, 38.0, -y + signf(-y) * 11.8), "PHAETHON", 400, 0.012, Color(0.86, 0.27, 0.09))   # on the runway side of the tank


func _wind_farm(node: Node3D, lx: float, y: float) -> void:
	var white := Color(0.93, 0.94, 0.95)
	for i in 8:
		var tx := lx - 1050.0 + i * 300.0
		var ty := y + (60.0 if i % 2 == 0 else -60.0) * 0.5
		# nacelle and rotor face the runway, so you see the blades turn, not their edges
		var toward := signf(-ty)   # render z toward the runway (y = 0)
		_add(node, [[Kit.cyl(1.8, 3.6, 100.0, 16), Kit.at(Vector3(tx, 50.0, -ty)), white],
			[Kit.rounded_box(Vector3(4.0, 4.0, 10.0), 6.0), Kit.at(Vector3(tx, 101.5, -ty - toward * 1.5)), white]])
		var rotor := Node3D.new()
		rotor.position = Vector3(tx, 101.5, -ty + toward * 3.8)
		node.add_child(rotor)
		var blades := [[Kit.ball(1.6, 16), Kit.at(Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.6)), white]]
		for k in 3:
			var r := Basis(Vector3.BACK, k * TAU / 3.0)
			blades.append([Kit.rounded_box(Vector3(2.6, 44.0, 0.5), 4.0), Transform3D(r, r * Vector3(0, 23.0, 0)), white])
		_add(rotor, blades)
		anim.append([rotor, "rotor", i * 0.9])


func _wreck(node: Node3D, lx: float, y: float) -> void:
	# a starship hulk, nose-down in the sand: a long wedge, a bridge tower, panelled flanks
	var hull := Color(0.58, 0.6, 0.62)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 340.0
	var Wr := 170.0
	var H := 55.0
	var tip := Vector3(L / 2.0, 0, 0)
	var rl := Vector3(-L / 2.0, 0, -Wr / 2.0)
	var rr := Vector3(-L / 2.0, 0, Wr / 2.0)
	var top := Vector3(-L / 2.0 + 40.0, H, 0)
	var bot := Vector3(-L / 2.0 + 40.0, -H * 0.6, 0)
	_face(st, [tip, rl, top], hull, (rl - tip).cross(top - tip).normalized() * -1.0)
	_face(st, [tip, top, rr], hull, (top - tip).cross(rr - tip).normalized() * -1.0)
	_face(st, [tip, bot, rl], hull.darkened(0.25), Vector3(0, -1, 0))
	_face(st, [tip, rr, bot], hull.darkened(0.25), Vector3(0, -1, 0))
	_face(st, [rl, bot, rr, top], hull.darkened(0.35), Vector3(-1, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mats.shaded
	mi.transform = Transform3D(Basis.from_euler(Vector3(0.32, 0.5, -0.22)), Vector3(lx, 14.0, -y))   # rolled, nose buried
	node.add_child(mi)
	_add(mi, [[Kit.box(Vector3(30, 22, 60)), Kit.at(Vector3(-L / 2.0 + 55.0, H + 6.0, 0)), hull.darkened(0.1)],
		[Kit.box(Vector3(14, 8, 90)), Kit.at(Vector3(-L / 2.0 + 55.0, H + 20.0, 0)), hull],
		[Kit.ball(5.0, 16), Kit.at(Vector3(-L / 2.0 + 55.0, H + 26.0, 30.0)), hull.lightened(0.1)],
		[Kit.ball(5.0, 16), Kit.at(Vector3(-L / 2.0 + 55.0, H + 26.0, -30.0)), hull.lightened(0.1)]])
	_add(node, [[Kit.ball(1.0, 16), Kit.at(Vector3(lx + 60.0, 0, -y + 20.0), Vector3.ZERO, Vector3(140, 10, 70)), Color(0.74, 0.6, 0.43)]])   # drift


func _dishes(node: Node3D, lx: float, y: float) -> void:
	var white := Color(0.9, 0.91, 0.92)
	for i in 6:
		var dx := (i % 3) * 220.0 - 220.0
		var dy := (i / 3) * 280.0 - 140.0
		var base := Vector3(lx + dx, 0, -(y + dy))
		_add(node, [[Kit.cyl(2.2, 3.4, 16.0, 16), Kit.at(base + Vector3(0, 8.0, 0)), white]])
		var az := Node3D.new()
		az.position = base + Vector3(0, 17.0, 0)
		node.add_child(az)
		var dish := Kit.ball(1.0, 32)
		dish.is_hemisphere = true
		_add(az, [[Kit.box(Vector3(4, 4, 8)), Kit.at(Vector3(0, 0, 0)), white.darkened(0.15)],
			[dish, Kit.at(Vector3(0, 5.0, 0), Vector3(PI + 0.9, 0, 0), Vector3(16.0, 6.0, 16.0)), white],
			[Kit.cyl(0.3, 0.3, 14.0, 8), Kit.at(Vector3(0, 12.0, 6.0), Vector3(0.9, 0, 0)), white.darkened(0.2)]])
		anim.append([az, "dish", i * 0.8])


func _arch(node: Node3D, lx: float, y: float) -> void:
	var bands := [Color(0.68, 0.42, 0.27), Color(0.76, 0.52, 0.33), Color(0.62, 0.38, 0.24)]
	var parts := []
	var n := 22
	for k in n + 1:
		var a := PI * k / n
		var p := Vector3(lx + 85.0 * cos(a), 70.0 * sin(a), -y)
		parts.append([Kit.rounded_box(Vector3(24, 24, 26), 3.0, 10), Transform3D(Basis(Vector3.BACK, a), p), bands[k % 3]])
	parts.append([Kit.rounded_box(Vector3(46, 30, 50), 3.0, 10), Kit.at(Vector3(lx - 88.0, 8.0, -y)), bands[0]])
	parts.append([Kit.rounded_box(Vector3(46, 30, 50), 3.0, 10), Kit.at(Vector3(lx + 88.0, 8.0, -y)), bands[2]])
	_add(node, parts)


func _gantry(node: Node3D, lx: float, _y: float) -> void:
	var steel := Color(0.25, 0.26, 0.28)
	var parts := []
	for s in [-1.0, 1.0]:
		for dx in [-3.0, 3.0]:
			parts.append([Kit.box(Vector3(1.4, 19.0, 1.4)), Kit.at(Vector3(lx + dx, 9.5, -s * 88.0)), steel])
	parts.append([Kit.box(Vector3(8.0, 3.2, 182.0)), Kit.at(Vector3(lx, 19.6, 0)), steel])
	for k in 14:   # checker band
		parts.append([Kit.box(Vector3(0.2, 1.6, 13.0)), Kit.at(Vector3(lx - 4.1, 20.4 + (0.8 if k % 2 == 0 else -0.8), -84.5 + 13.0 * k)), Color.WHITE if k % 2 == 0 else Color.BLACK])
	_add(node, parts)
	for k in 6:   # chasing lights under the beam
		var lights := []
		var z := -75.0 + k * 5.0
		while z < 80.0:
			lights.append([Kit.ball(0.7, 10), Kit.at(Vector3(lx - 4.2, 17.6, z)), Color(1.0, 0.7, 0.2)])
			z += 30.0
		var lm := _add(node, lights, true)
		anim.append([lm, "chase", k])
	_text(node, Vector3(lx - 4.3, 24.5, 0), "HALFWAY", 400, 0.012, Color(1.0, 0.75, 0.3), true)


func _vaporators(node: Node3D, lx: float, y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5757
	var parts := []
	var metal := Color(0.7, 0.71, 0.72)
	for i in 26:
		var p := Vector3(lx + rng.randf_range(-210, 210), 0, -(y + rng.randf_range(-55, 55)))
		var h := rng.randf_range(7.0, 12.0)
		parts.append([Kit.cyl(0.35, 0.5, h, 10), Kit.at(p + Vector3(0, h / 2.0, 0)), metal])
		for r in 3:
			parts.append([Kit.cyl(0.9, 0.9, 0.35, 12), Kit.at(p + Vector3(0, h * (0.35 + 0.25 * r), 0)), metal.darkened(0.2)])
		parts.append([Kit.cyl(0.05, 0.6, 1.2, 10), Kit.at(p + Vector3(0, h + 0.6, 0)), metal.lightened(0.1)])
	_add(node, parts)


func _needle(node: Node3D, lx: float, y: float) -> void:
	_add(node, [[Kit.cyl(3.0, 20.0, 400.0, 4), Kit.at(Vector3(lx, 200.0, -y), Vector3(0, PI / 4.0, 0)), Color(0.32, 0.3, 0.3)],
		[Kit.cyl(0.0, 3.2, 14.0, 4), Kit.at(Vector3(lx, 407.0, -y), Vector3(0, PI / 4.0, 0)), Color(0.85, 0.75, 0.45)]])
	var beacon := _add(node, [[Kit.ball(3.5, 12), Kit.at(Vector3(lx, 417.0, -y)), Color(1.0, 0.1, 0.05)]], true)
	anim.append([beacon, "beacon", 0.0])


func _sandcrawler(node: Node3D, lx: float, y: float) -> void:
	var rust := Color(0.55, 0.38, 0.26)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# hull: a long box whose front slopes back, on four track blocks
	var L := 110.0
	var Wd := 50.0
	var H := 42.0
	var p := [Vector3(-L / 2, 8, -Wd / 2), Vector3(L / 2, 8, -Wd / 2), Vector3(L / 2 - 30, 8 + H, -Wd / 2.6), Vector3(-L / 2, 8 + H * 0.9, -Wd / 2.6),
		Vector3(-L / 2, 8, Wd / 2), Vector3(L / 2, 8, Wd / 2), Vector3(L / 2 - 30, 8 + H, Wd / 2.6), Vector3(-L / 2, 8 + H * 0.9, Wd / 2.6)]
	_face(st, [p[0], p[1], p[2], p[3]], rust, Vector3(0, 0, -1))
	_face(st, [p[4], p[7], p[6], p[5]], rust, Vector3(0, 0, 1))
	_face(st, [p[1], p[5], p[6], p[2]], rust.darkened(0.15), Vector3(0.8, 0.6, 0).normalized())
	_face(st, [p[3], p[2], p[6], p[7]], rust.lightened(0.1), Vector3(0, 1, 0))
	_face(st, [p[0], p[3], p[7], p[4]], rust.darkened(0.2), Vector3(-1, 0, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mats.shaded
	mi.position = Vector3(lx, 0, -y)
	node.add_child(mi)
	var parts := []
	for c in [Vector2(-30, -20), Vector2(30, -20), Vector2(-30, 20), Vector2(30, 20)]:
		parts.append([Kit.rounded_box(Vector3(34, 9, 12), 4.0), Kit.at(Vector3(lx + c.x, 4.5, -y + c.y)), Color(0.2, 0.19, 0.18)])
	_add(node, parts)


func _spaceport(node: Node3D, lx: float, y: float) -> void:
	var concrete := Color(0.72, 0.7, 0.66)
	var parts := [[Kit.cyl(5.0, 7.0, 64.0, 16), Kit.at(Vector3(lx - 260.0, 32.0, -y)), concrete],
		[Kit.cyl(11.0, 8.0, 9.0, 16), Kit.at(Vector3(lx - 260.0, 68.0, -y)), Color(0.15, 0.25, 0.32)],
		[Kit.cyl(12.0, 12.0, 1.2, 16), Kit.at(Vector3(lx - 260.0, 73.0, -y)), concrete]]
	for i in 3:
		var c := Vector3(lx - 120.0 + i * 160.0, 0, -(y + (60.0 if i == 1 else -40.0)))
		parts.append([Kit.cyl(32.0, 34.0, 1.6, 40), Kit.at(c + Vector3(0, 0.8, 0)), concrete])
		parts.append([Kit.cyl(26.0, 26.0, 0.1, 40), Kit.at(c + Vector3(0, 1.66, 0)), Color(0.9, 0.75, 0.2)])
		parts.append([Kit.cyl(24.5, 24.5, 0.12, 40), Kit.at(c + Vector3(0, 1.68, 0)), concrete])
	# a freighter parked on the middle pad: saucer, cockpit tube, mandibles
	var f := Vector3(lx + 40.0, 0, -(y + 60.0))
	var hullc := Color(0.82, 0.82, 0.8)
	parts.append([Kit.cyl(17.0, 19.0, 5.0, 32), Kit.at(f + Vector3(0, 6.5, 0)), hullc])
	parts.append([Kit.cyl(9.0, 9.0, 2.0, 24), Kit.at(f + Vector3(0, 9.6, 0)), hullc.darkened(0.1)])
	parts.append([Kit.cyl(2.2, 2.2, 14.0, 12), Kit.at(f + Vector3(12.0, 6.5, -18.0), Vector3(PI / 2.0, 0, 0)), hullc])
	for s in [-1.0, 1.0]:
		parts.append([Kit.box(Vector3(5, 3.5, 14)), Kit.at(f + Vector3(s * 4.0, 6.0, -23.0)), hullc.darkened(0.05)])
	for k in 3:
		var r := Basis(Vector3.UP, k * TAU / 3.0)
		parts.append([Kit.cyl(0.6, 0.8, 4.0, 8), Transform3D(r, f + r * Vector3(0, 2.0, 11.0)), Color(0.3, 0.3, 0.32)])
	_add(node, parts)
