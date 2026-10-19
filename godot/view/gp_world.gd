## The grand prix's trackside, dressed from the sim's own centreline (CraftSim tpx/tnx/tw): dark
## asphalt with white edge lines, red/white kerbs on the inside of every corner, painted concrete
## walls on both edges (where the sim's walls are), a chequered start/finish line under a gantry,
## grandstands along the main straight, braking boards (1000 / 600 / 300 m) before the slow
## corners, turn numbers, and desert mesas outside and in the infield. Corners are found from the
## centreline's curvature, so the dressing always matches the track the sim drives.
## The walls are tall so you can read where the track goes (Luke: "higher walls that indicate
## where the track is going"): concrete to 1.6 m, then panels to 5.5 m with a lit strip along
## the top (red on the left wall, green on the right, like nav lights, so the two edges draw
## lines into the distance and you always know which side is which), yellow chevrons on the
## outside wall of every corner from ~120 m before it, pointing the way it turns, and a lit mast
## every 96 m on both walls that shows the line over the inside wall.
## Every corner is banked (CraftSim tb, up to 30 deg) on its inside edge: the outside climbs up
## to 55 m, with an earth berm behind the high wall; everything trackside sits on that surface.
## Built in absolute track coordinates under one root; the view moves it with the floating origin.
##   add_child(gp); gp.build(sim, view)
##   gp.sync(org_x, org_y)
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Props := preload("res://view/props.gd")
const WALL_H := 1.6           # concrete
const FENCE_H := 5.5          # the tall panels above it
const STRIP_H := 0.4          # lit strip along the top
const MAST_H := 12.0
const MAST_EVERY := 8         # samples (96 m)
const CHEVRON_LEAD := 10      # samples (120 m) of chevrons before a corner starts
const LEFT_LIGHT := Color(1.0, 0.16, 0.12)
const RIGHT_LIGHT := Color(0.15, 1.0, 0.35)
const CHEVRON := Color(1.0, 0.82, 0.08)
const KERB_W := 3.0
const LINE_W := 0.6
const OMEGA := 1.0            # STARFIGHTER turn-rate limit used to estimate corner speeds
const A_LAT := 40.0 * 9.81
const SLOW_MPH := 820.0       # corners slower than this get braking boards

var sim
var view
var corners: Array = []       # [start i, apex i, end i, sign (+1 left), radius, est mph, number]
var chevrons := 0             # how many chevrons were built (the test reads these)
var berm_samples := 0
var masts := 0
var floodlights := 0          # floodlight towers built (the test reads these)
var plants := 0               # scattered plants and boulders


func build(s, v) -> void:
	sim = s
	view = v
	_find_corners()
	var mat := Kit.vertex_colors()
	var surf := SurfaceTool.new()
	surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var asph := SurfaceTool.new()   # the racing surface: view/asphalt.gdshader, UV (m along, m across)
	asph.begin(Mesh.PRIMITIVE_TRIANGLES)
	var along := 0.0
	var deco := SurfaceTool.new()
	deco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()   # lit: unshaded, so it reads at distance and in shadow
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = sim.N
	var kerb := _kerb_flags()
	var chev := _chevron_flags()
	for i in n:
		var j := (i + 1) % n
		var hw: float = sim.tw[i] / 2.0
		var hw2: float = sim.tw[j] / 2.0
		# asphalt: aggregate, rubber, joints every 25 m (they read at speed), cracks and patches
		_asphalt(asph, i, j, hw, hw2, along, along + sim.tlen[i])
		along += sim.tlen[i]
		# edge lines
		for sgn in [-1.0, 1.0]:
			_strip(deco, i, j, sgn * (hw - 1.5 - LINE_W), sgn * (hw - 1.5), sgn * (hw2 - 1.5 - LINE_W), sgn * (hw2 - 1.5), 0.04, Color(0.92, 0.92, 0.9))
		# kerbs on the inside of corners: red and white blocks
		if kerb[i] != 0:
			var side: float = kerb[i]
			var col := Color(0.85, 0.1, 0.08) if i % 2 == 0 else Color(0.95, 0.95, 0.93)
			_strip(deco, i, j, side * (hw - KERB_W), side * hw, side * (hw2 - KERB_W), side * hw2, 0.06, col)
		# walls: concrete with a painted band, sponsor colours alternating every ~48 m
		for sgn in [-1.0, 1.0]:
			var a := _edge(i, sgn * hw)
			var b := _edge(j, sgn * hw2)
			var band := Color(0.86, 0.27, 0.09) if (i / 4) % 2 == 0 else Color(0.95, 0.95, 0.93)
			_wall(deco, a, b, 0.0, WALL_H * 0.7, Color(0.72, 0.71, 0.68))
			_wall(deco, a, b, WALL_H * 0.7, WALL_H, band)
			# banked corners: an earth berm from the high (outside) wall back down to the desert
			if sim.tb[i] != 0.0 and signf(sim.tb[i]) == signf(sim.tb[j]) and sgn == -signf(sim.tb[i]):
				var hi: float = 2.0 * hw * absf(tan(sim.tb[i]))
				var hj: float = 2.0 * hw2 * absf(tan(sim.tb[j]))
				if hi > 0.3 or hj > 0.3:
					_strip(surf, i, j, sgn * hw, sgn * (hw + hi + 0.5), sgn * hw2, sgn * (hw2 + hj + 0.5), -0.05, Color(0.6, 0.47, 0.33))
					berm_samples += 1
			# the tall panels: slate, a shade apart every ~48 m so they stream past at speed;
			# black where the chevrons are
			var on_chev: bool = chev[i] == int(sgn)
			var slate := 0.2 + 0.035 * ((i / 4) % 2)
			_wall(deco, a, b, WALL_H, FENCE_H, Color(0.05, 0.05, 0.06) if on_chev else Color(slate, slate + 0.01, slate + 0.03))
			_wall(glow, a, b, FENCE_H, FENCE_H + STRIP_H, LEFT_LIGHT if sgn > 0.0 else RIGHT_LIGHT)
			if on_chev and i % 2 == 0:
				_chevron(glow, i, sgn * (hw - 0.08))
				chevrons += 1
			if i % MAST_EVERY == 0:
				_mast(deco, glow, _edge(i, sgn * (hw + 0.4)), LEFT_LIGHT if sgn > 0.0 else RIGHT_LIGHT)
				masts += 1
	# start / finish: chequers across the track at sample 0
	for k in 16:
		for r in 2:
			var c := Color.WHITE if (k + r) % 2 == 0 else Color(0.05, 0.05, 0.05)
			var w0: float = -sim.tw[0] / 2.0 + k * sim.tw[0] / 16.0
			_patch(deco, 0, w0, w0 + sim.tw[0] / 16.0, r * 2.0, r * 2.0 + 2.0, 0.07, c)
	var m0 := MeshInstance3D.new()
	m0.mesh = asph.commit()
	var am := ShaderMaterial.new()
	am.shader = preload("res://view/asphalt.gdshader")
	am.set_shader_parameter("period", 1.0e6)
	am.set_shader_parameter("base", Vector3(0.25, 0.245, 0.245))   # sRGB (a Color would arrive linearised)
	am.set_shader_parameter("lane_half", 34.0)
	m0.material_override = am
	m0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m0)
	var m1 := MeshInstance3D.new()
	surf.generate_normals()
	m1.mesh = surf.commit()
	m1.material_override = mat
	m1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m1)
	var m2 := MeshInstance3D.new()
	m2.mesh = deco.commit()
	m2.material_override = mat
	m2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m2)
	var m3 := MeshInstance3D.new()
	m3.mesh = glow.commit()
	m3.material_override = Kit.vertex_colors(true)
	m3.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m3)
	_gantry()
	_grandstands()
	_boards_and_numbers()
	_scenery()
	_props()


## Corners: runs of samples turning faster than a 2 km radius, merged across short gaps.
func _find_corners() -> void:
	var n: int = sim.N
	var kap := PackedFloat64Array()
	kap.resize(n)
	for i in n:
		var j := (i + 1) % n
		var d := wrapf(atan2(sim.tty[j], sim.ttx[j]) - atan2(sim.tty[i], sim.ttx[i]), -PI, PI)
		kap[i] = d / sim.tlen[i]
	var k := 0
	var num := 1
	while k < n:
		if absf(kap[k]) > 1.0 / 2000.0:
			var sgn := signf(kap[k])
			var st := k
			while k < n and absf(kap[k]) > 1.0 / 2000.0 and signf(kap[k]) == sgn:
				k += 1
			var en := k - 1
			var k_avg := 0.0
			for q in range(st, en + 1):
				k_avg += absf(kap[q])
			k_avg /= (en - st + 1)
			var r := 1.0 / k_avg
			var v := minf(OMEGA * r, sqrt(A_LAT * r)) * 2.236936
			corners.append([st, (st + en) / 2, en, sgn, r, v, num])
			num += 1
		else:
			k += 1


## Per sample: which side gets a kerb (+1 left / -1 right / 0 none): the inside of each corner,
## from a little before it starts to a little after it ends.
func _kerb_flags() -> PackedInt32Array:
	var n: int = sim.N
	var f := PackedInt32Array()
	f.resize(n)
	for c in corners:
		for q in range(c[0] - 6, c[2] + 7):
			f[posmod(q, n)] = int(c[3])
	return f


## Per sample: which wall carries chevrons (+1 left / -1 right / 0 none): the OUTSIDE of each
## corner, from CHEVRON_LEAD samples before it starts to its end.
func _chevron_flags() -> PackedInt32Array:
	var n: int = sim.N
	var f := PackedInt32Array()
	f.resize(n)
	for c in corners:
		for q in range(c[0] - CHEVRON_LEAD, c[2] + 1):
			f[posmod(q, n)] = -int(c[3])
	return f


## A ">" on the wall face at sample i (lateral offset off, just proud of the wall, facing the
## track), its tip pointing down the track: the way the corner goes.
func _chevron(st: SurfaceTool, i: int, off: float) -> void:
	var base := _edge(i, off)
	var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
	var hc := (WALL_H + FENCE_H) / 2.0
	var hh := (FENCE_H - WALL_H) / 2.0 - 0.35
	var at := func(sv: float, h: float) -> Vector3:
		return base + t * sv + Vector3.UP * h
	var arm := 1.3   # along the track, per arm
	var nrm := Vector3(-sim.tnx[i], 0.0, sim.tny[i]) * signf(off)   # toward the track
	for quad in [[at.call(-arm, hc + hh), at.call(0.0, hc + hh), at.call(arm, hc), at.call(0.0, hc)],
			[at.call(0.0, hc), at.call(arm, hc), at.call(0.0, hc - hh), at.call(-arm, hc - hh)]]:
		for p in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			st.set_color(CHEVRON)
			st.set_normal(nrm)
			st.add_vertex(p)


## A mast on the wall: a thin pole with a lit block on top, in that side's light colour.
func _mast(st: SurfaceTool, lit: SurfaceTool, p: Vector3, c: Color) -> void:
	_box(st, p + Vector3.UP * (MAST_H / 2.0), Vector3(0.35, MAST_H, 0.35), Color(0.3, 0.31, 0.33))
	_box(lit, p + Vector3.UP * (MAST_H + 0.45), Vector3(0.9, 0.9, 0.9), c)


func _box(st: SurfaceTool, ctr: Vector3, size: Vector3, c: Color) -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var hz := size.z / 2.0
	var v := [ctr + Vector3(-hx, -hy, -hz), ctr + Vector3(hx, -hy, -hz), ctr + Vector3(hx, hy, -hz), ctr + Vector3(-hx, hy, -hz),
		ctr + Vector3(-hx, -hy, hz), ctr + Vector3(hx, -hy, hz), ctr + Vector3(hx, hy, hz), ctr + Vector3(-hx, hy, hz)]
	for f in [[0, 1, 2, 3, Vector3.FORWARD], [5, 4, 7, 6, Vector3.BACK], [4, 0, 3, 7, Vector3.LEFT], [1, 5, 6, 2, Vector3.RIGHT], [3, 2, 6, 7, Vector3.UP]]:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(c)
			st.set_normal(f[4])
			st.add_vertex(v[f[k]])


## A point `off` metres left of sample i's centreline, on the (banked) surface.
func _edge(i: int, off: float) -> Vector3:
	return Vector3(sim.tpx[i] + sim.tnx[i] * off, sim.bank_height(sim.tw[i] / 2.0, off, sim.tb[i]), -(sim.tpy[i] + sim.tny[i] * off))


## A strip between lateral offsets (o0..o1 at sample i, p0..p1 at sample j).
func _strip(st: SurfaceTool, i: int, j: int, o0: float, o1: float, p0: float, p1: float, h: float, c: Color) -> void:
	var a := _edge(i, o0) + Vector3.UP * h
	var b := _edge(i, o1) + Vector3.UP * h
	var cc := _edge(j, p1) + Vector3.UP * h
	var d := _edge(j, p0) + Vector3.UP * h
	for p in [a, b, cc, a, cc, d]:
		st.set_color(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(p)


## The track surface between samples i and j, with UVs (metres along the lap, metres across).
func _asphalt(st: SurfaceTool, i: int, j: int, hw: float, hw2: float, s0: float, s1: float) -> void:
	var a := _edge(i, -hw) + Vector3.UP * 0.02
	var b := _edge(i, hw) + Vector3.UP * 0.02
	var cc := _edge(j, hw2) + Vector3.UP * 0.02
	var d := _edge(j, -hw2) + Vector3.UP * 0.02
	var nrm := (b - a).cross(d - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	for v in [[a, Vector2(s0, -hw)], [b, Vector2(s0, hw)], [cc, Vector2(s1, hw2)], [a, Vector2(s0, -hw)], [cc, Vector2(s1, hw2)], [d, Vector2(s1, -hw2)]]:
		st.set_normal(nrm)
		st.set_uv(v[1])
		st.add_vertex(v[0])


## A small patch on sample i's segment: lateral w0..w1, along s0..s1 metres from the sample.
func _patch(st: SurfaceTool, i: int, w0: float, w1: float, s0: float, s1: float, h: float, c: Color) -> void:
	var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
	var a := _edge(i, w0) + t * s0 + Vector3.UP * h
	var b := _edge(i, w1) + t * s0 + Vector3.UP * h
	var cc := _edge(i, w1) + t * s1 + Vector3.UP * h
	var d := _edge(i, w0) + t * s1 + Vector3.UP * h
	for p in [a, b, cc, a, cc, d]:
		st.set_color(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(p)


func _wall(st: SurfaceTool, a: Vector3, b: Vector3, h0: float, h1: float, c: Color) -> void:
	var nrm := (b - a).cross(Vector3.UP).normalized()
	for p in [a + Vector3.UP * h0, b + Vector3.UP * h0, b + Vector3.UP * h1, a + Vector3.UP * h0, b + Vector3.UP * h1, a + Vector3.UP * h1]:
		st.set_color(c)
		st.set_normal(nrm)
		st.add_vertex(p)


func _label(pos: Vector3, text: String, size: int, px: float, c: Color, yaw: float, billboard := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 12
	l.outline_modulate = Color(0.05, 0.05, 0.05)
	l.position = pos
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	else:
		l.rotation.y = yaw
	add_child(l)


## The start gantry over sample 0, facing the cars coming down the main straight.
func _gantry() -> void:
	var hw: float = sim.tw[0] / 2.0 + 4.0
	var steel := Color(0.22, 0.23, 0.25)
	var parts := []
	var top := maxf(_edge(0, hw).y, _edge(0, -hw).y) + 16.0   # level beam over a banked line
	for s in [-1.0, 1.0]:
		var p := _edge(0, s * hw)
		parts.append([Kit.box(Vector3(1.6, top - p.y, 1.6)), Kit.at(p + Vector3(0, (top - p.y) / 2.0, 0)), steel])
	var mid := _edge(0, 0.0)
	mid.y = top - 16.0
	var yaw := atan2(sim.tty[0], sim.ttx[0])
	parts.append([Kit.box(Vector3(3.0, 3.4, hw * 2.0 + 1.6)), Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, 16.0, 0)), steel])
	var lights := []
	for k in 5:
		lights.append([Kit.ball(0.8, 12), Kit.at(mid + Vector3(-1.6, 13.8, -6.0 + k * 3.0)), Color(1.0, 0.15, 0.1)])
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = Kit.vertex_colors()
	add_child(mi)
	var li := MeshInstance3D.new()
	li.mesh = Kit.compound(lights)
	li.material_override = Kit.vertex_colors(true)
	add_child(li)
	_label(mid + Vector3(-1.8, 19.6, 0), "PHAETHON GRAND PRIX", 260, 0.012, Color(1.0, 0.72, 0.38), -PI / 2.0 + yaw)


## Stepped grandstands outside the main straight, crowds in colour.
func _grandstands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var parts := []
	var crowd := []
	# outside of the main straight is the right-hand side (the loop runs anticlockwise)
	for g in 4:
		var i := 30 + g * 50
		if i >= sim.N:
			break
		var base := _edge(i, -(sim.tw[i] / 2.0 + 14.0))
		for step in 8:
			var p := base + Vector3(0, 0.6 + step * 1.2, step * 1.6)   # stepping back from the track
			parts.append([Kit.box(Vector3(140.0, 1.2, 1.6)), Kit.at(p), Color(0.55, 0.56, 0.58)])
			for k in 46:
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.9), rng.randf_range(0.5, 1.0))
				crowd.append([Kit.box(Vector3(1.4, 1.0, 0.7)), Kit.at(p + Vector3(-67.0 + k * 3.0 + rng.randf_range(-0.6, 0.6), 1.1, 0)), c])
		parts.append([Kit.box(Vector3(142.0, 0.6, 14.0)), Kit.at(base + Vector3(0, 11.2, 6.0)), Color(0.86, 0.27, 0.09)])   # roof
		for s in [-1.0, 1.0]:
			parts.append([Kit.box(Vector3(0.6, 11.0, 0.6)), Kit.at(base + Vector3(s * 70.0, 5.5, 12.5)), Color(0.4, 0.4, 0.42)])
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = Kit.vertex_colors()
	add_child(mi)
	var ci := MeshInstance3D.new()
	ci.mesh = Kit.compound(crowd)
	ci.material_override = Kit.vertex_colors()
	add_child(ci)


## Braking boards before slow corners (outside, just past the wall) and a turn number at
## each corner's apex, on the outside.
func _boards_and_numbers() -> void:
	var n: int = sim.N
	var parts := []
	for c in corners:
		var out: float = -c[3]   # outside of the corner
		var apex: int = c[1]
		var pa := _edge(apex, out * (sim.tw[apex] / 2.0 + 14.0))
		_label(pa + Vector3(0, 16.0, 0), "T%d" % c[6], 400, 0.025, Color(1.0, 1.0, 1.0), 0.0, true)
		if c[5] >= SLOW_MPH:
			continue
		var s_total := 0.0
		var q: int = c[0]
		var marks := [300.0, 600.0, 1000.0]
		var mi := 0
		while mi < marks.size() and s_total < 1200.0:
			q = posmod(q - 1, n)
			s_total += sim.tlen[q]
			if s_total >= marks[mi]:
				var side: float = -c[3]
				var p := _edge(q, side * (sim.tw[q] / 2.0 + 6.0))
				var yaw := atan2(sim.tty[q], sim.ttx[q])
				var bc := FENCE_H + STRIP_H + 3.6   # the board's centre: clear above the tall wall
				parts.append([Kit.box(Vector3(0.4, 6.0, 5.0)), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, bc, 0)), Color(0.08, 0.08, 0.1)])
				parts.append([Kit.box(Vector3(0.3, bc, 0.3)), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, bc / 2.0, 0)), Color(0.5, 0.5, 0.5)])
				var t := Vector3(sim.ttx[q], 0.0, -sim.tty[q])
				_label(p + Vector3(0, bc, 0) - t * 0.3, str(int(marks[mi])), 220, 0.012, Color(1.0, 0.95, 0.85), -PI / 2.0 + yaw)
				mi += 1
	var mesh := MeshInstance3D.new()
	mesh.mesh = Kit.compound(parts)
	mesh.material_override = Kit.vertex_colors()
	add_child(mesh)


## Desert mesas and spires around and inside the circuit, never within 280 m of the track.
func _scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in sim.N:
		lo = Vector2(minf(lo.x, sim.tpx[i]), minf(lo.y, sim.tpy[i]))
		hi = Vector2(maxf(hi.x, sim.tpx[i]), maxf(hi.y, sim.tpy[i]))
	var bands := [Color(0.62, 0.38, 0.24), Color(0.74, 0.52, 0.33), Color(0.68, 0.45, 0.29), Color(0.82, 0.64, 0.44)]
	var parts := []
	var placed := 0
	var tries := 0
	while placed < 70 and tries < 2000:
		tries += 1
		var x := rng.randf_range(lo.x - 3000.0, hi.x + 3000.0)
		var y := rng.randf_range(lo.y - 3000.0, hi.y + 3000.0)
		var mesa := rng.randf() < 0.35
		var r_bot := rng.randf_range(90.0, 220.0) if mesa else rng.randf_range(10.0, 24.0)
		if _track_dist(x, y) < 280.0 + r_bot:
			continue
		placed += 1
		var h := rng.randf_range(35.0, 100.0) if mesa else rng.randf_range(50.0, 200.0)
		var r_top := r_bot * (rng.randf_range(0.7, 0.85) if mesa else rng.randf_range(0.25, 0.45))
		var nb := 3 if mesa else 4
		var z0 := 0.0
		for b in nb:
			var ra := lerpf(r_bot, r_top, float(b) / nb)
			var rb := lerpf(r_bot, r_top, float(b + 1) / nb)
			parts.append([Kit.cyl(rb, ra, h / nb, 7 if mesa else 6), Kit.at(Vector3(x, z0 + h / nb / 2.0, -y), Vector3(0, rng.randf() * TAU, 0)), bands[(b + placed) % 4]])
			z0 += h / nb
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = Kit.vertex_colors()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Props round the circuit (view/props.gd): Joshua trees, scrub and boulders out in the desert,
## none within 150 m of any part of the track; floodlight towers just outside the walls every
## ~480 m, on the inside of banked corners (the outside is berm); and the pit building on the
## main straight, opposite the grandstands, its garages facing the track.
func _props() -> void:
	var near := _near_track(150.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1357
	var xs := [[], [], [], []]   # joshua0, joshua1, bush, boulder
	for k in 16000:
		# thickest just past the walls, where you see it, thinning out over ~1.5 km
		var i := rng.randi_range(0, sim.N - 1)
		var d := 150.0 + 1500.0 * pow(rng.randf(), 1.7)
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		var x: float = sim.tpx[i] + sim.tnx[i] * d * sd + rng.randf_range(-6.0, 6.0)
		var y: float = sim.tpy[i] + sim.tny[i] * d * sd + rng.randf_range(-6.0, 6.0)
		if near.has(Vector2i(floori(x / 50.0), floori(y / 50.0))):
			continue
		var r := rng.randf()
		var pos := Vector3(x, 0.0, -y)
		if r < 0.09:
			xs[0 if r < 0.045 else 1].append(Props.scatter_xf(rng, pos, 0.8, 1.35))
		elif r < 0.85:
			xs[2].append(Props.scatter_xf(rng, pos, 0.8, 2.0, 0.0))
		else:
			var sz := rng.randf_range(0.8, 4.0)
			xs[3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.5, 1.0), sz * rng.randf_range(0.7, 1.3))), pos + Vector3(0, sz * 0.15, 0)))
	plants = xs[0].size() + xs[1].size() + xs[2].size() + xs[3].size()
	Props.binned(self, "joshua0", xs[0], 1000.0, 6000.0)
	Props.binned(self, "joshua1", xs[1], 1000.0, 6000.0)
	Props.binned(self, "bush", xs[2], 1000.0, 1800.0)
	Props.binned(self, "boulder", xs[3], 1000.0, 3000.0)
	# floodlights
	var side := 1.0
	for i in range(0, sim.N, 40):
		var s2: float = signf(sim.tb[i]) if sim.tb[i] != 0.0 else side
		side = -side
		var off: float = s2 * (sim.tw[i] / 2.0 + 18.0)
		var p := _edge(i, off)
		if _other_track_near(i, p, sim.tw[i] / 2.0 + 14.0):
			continue
		var to_track := _edge(i, 0.0) - p
		to_track.y = 0.0
		Props.place(self, "floodlight", Transform3D(Basis.looking_at(to_track.normalized(), Vector3.UP), Vector3(p.x, 0.0, p.z)))
		floodlights += 1
	# the pit building, left of the main straight (the grandstands are on the right)
	for i in [22, 33]:
		var hw: float = sim.tw[i] / 2.0
		var p := _edge(i, hw + 32.0)
		var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
		var n := Vector3(sim.tnx[i], 0.0, -sim.tny[i])
		Props.place(self, "pit_building", Transform3D(Basis(-t, Vector3.UP, n), Vector3(p.x, 0.0, p.z)))


## 50 m cells (sim x, y) within r of the centreline.
func _near_track(r: float) -> Dictionary:
	var cells := {}
	var span := int(ceil(r / 50.0))
	for i in sim.N:
		var cx := floori(sim.tpx[i] / 50.0)
		var cy := floori(sim.tpy[i] / 50.0)
		for dx in range(-span, span + 1):
			for dy in range(-span, span + 1):
				cells[Vector2i(cx + dx, cy + dy)] = true
	return cells


## Whether some other part of the track (not within 30 samples of i) passes within r of p.
func _other_track_near(i: int, p: Vector3, r: float) -> bool:
	for j in range(0, sim.N, 2):
		var d := absi(j - i)
		if mini(d, sim.N - d) <= 30:
			continue
		if Vector2(p.x - sim.tpx[j], -p.z - sim.tpy[j]).length() < r:
			return true
	return false


func _track_dist(x: float, y: float) -> float:
	var best := INF
	for i in range(0, sim.N, 4):
		best = minf(best, Vector2(x - sim.tpx[i], y - sim.tpy[i]).length())
	return best


func sync(ox: float, oy: float) -> void:
	position = Vector3(-ox, 0.0, oy)
