## A big course's trackside (Eridanus: 193 km), dressed from the sim's own centreline and built
## in chunks: CHUNK samples each, every chunk's meshes in its own local coordinates (worked out
## in 64-bit and centred on the chunk), the chunk node placed against the floating origin every
## frame and hidden beyond VIS. One mesh at the origin would lose millimetres at 50 km out and
## couldn't cull.
##   towns ("sf", STARFIGHTER)   asphalt; red/white kerbs on corner insides; concrete walls with
##                               tall panels and a lit strip on top (red left, green right);
##                               yellow chevrons on corner outsides; a lit mast every 96 m; earth
##                               berms behind banked corners
##   speed loop ("sp")           400 m of asphalt with the lane rubber, its sweepers banked 3 deg
##                               (earth berms behind the raised outside wall); 3.2 m walls,
##                               concrete under a band of SPEEDCRAFT-blue and white panels (48 m
##                               blocks), a bright strip on top; a 24 m mast every 240 m, a beacon
##                               on each, and a 200 m light column on every other one
##                               (view/pylon.gdshader: Luke, "make ... the markers more vertically
##                               visible from further away")
##   beacons                     a glow on every loop mast and every other town mast (red left,
##                               green right) that never shrinks below a few pixels and ignores the
##                               fog (view/beacon.gdshader): at 4,000 mph the walls' lines of lights
##                               show the way 10-40 km ahead (Luke: "make the walls of speedcraft
##                               much more visible from further away"). Shown to BEACON_VIS.
##   zones                       braking boards before each town, 8 / 6 / 4 / 2 / 1 miles out
##                               (brake from ~4,000 mph, flip to STARFIGHTER): lit signs 80 m wide
##                               over the middle of the track on gantries (the engines hide the
##                               walls' part of the view), amber then magenta, black numbers on the
##                               side facing you, beacons on top (Luke: "make those light up as
##                               well. Currently their numbers are hidden": they sat inside their
##                               own board); a STARFIGHTER gantry at each town's mouth, a
##                               SPEEDCRAFT gantry where the loop begins
##   the start                   the gantry over the line, grandstands and pits on the river
##                               straight, floodlights round the towns
## The world round it (trees, the river and lake, bridges, houses) is view/verdant_world.gd.
##   add_child(cw); cw.build(sim, view)      once
##   cw.sync(org_x, org_y)                   every frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Props := preload("res://view/props.gd")
const CHUNK := 256                # samples per chunk (~3 km)
const VIS := 16000.0              # chunks further than this (m, centre to pod) are hidden
const WALL_H := 1.6
const FENCE_H := 5.5              # towns: the tall panels above the concrete
const STRIP_H := 0.4
const MAST_H := 12.0
const LOOP_WALL_H := 3.2          # the speed loop: concrete to 1.4 m, the panel band above
const LOOP_STRIP_H := 0.7
const LOOP_MAST_H := 24.0
const LOOP_MAST_EVERY := 20       # samples (240 m); towns: every 8 (96 m)
const BEACON_VIS := 40000.0       # beacons show this far (m, chunk centre to pod)
const LOOP_BAND := [Color(0.16, 0.45, 0.95), Color(0.95, 0.95, 0.93)]
const LEFT_LIGHT := Color(1.0, 0.16, 0.12)
const RIGHT_LIGHT := Color(0.15, 1.0, 0.35)
const CHEVRON := Color(1.0, 0.82, 0.08)
const SF_COL := Color(1.0, 0.3, 0.75)     # the zone signs in each mode's colour (ModeSwitch)
const SP_COL := Color(0.25, 0.65, 1.0)
const KERB_W := 3.0
const LINE_W := 0.6
const ASPHALT_PERIOD := 64000.0
const BOARDS_MI := [8, 6, 4, 2, 1]   # braking boards, miles before each town (imperial: Luke)
const MILE := 1609.344
const PYLON_H := 200.0            # the loop's light columns, m above their masts
const BOARD_AMBER := Color(1.0, 0.62, 0.12)
const BOARD_W := 80.0             # the overhead braking boards' lit faces, m
const BOARD_H := 40.0
const BOARD_CLEAR := 28.0         # their gantry beam this far over the track's higher edge

var sim
var view
var chunks := []                  # [node, centre x, centre y]
var corners := []                 # towns: [start i, end i, sign]
var zones := []                   # [sample i, "sf" entering a town / "sp" leaving one]
var boards := 0                   # tests read these
var chevrons := 0
var masts := 0
var beacons := 0
var lights := []                  # [node, centre x, centre y]: each chunk's beacons and columns, shown to BEACON_VIS
var pylons := 0
var _bright: StandardMaterial3D   # lit faces and strips: HDR, so they bloom
var _beam: ShaderMaterial         # beacons (view/beacon.gdshader)
var _board_mat: StandardMaterial3D   # the boards' lit faces: bright, but keeping their colour
var _s := PackedFloat64Array()    # distance along the lap at each sample


func build(s, v) -> void:
	sim = s
	view = v
	var n: int = sim.N
	_s.resize(n + 1)
	var acc := 0.0
	for i in n:
		_s[i] = acc
		acc += sim.tlen[i]
	_s[n] = acc
	_find_corners()
	_find_zones()
	var kerb := _flags(true)
	var chev := _flags(false)
	var mat := Kit.vertex_colors()
	var lit := Kit.vertex_colors(true)
	var bright := Kit.vertex_colors(true)   # the loop's strips: HDR, so they bloom
	bright.albedo_color = Color(2.4, 2.4, 2.4)
	_bright = bright
	var beam := ShaderMaterial.new()
	beam.shader = preload("res://view/beacon.gdshader")
	_beam = beam
	_board_mat = Kit.vertex_colors(true)
	_board_mat.albedo_color = Color(1.35, 1.35, 1.35)
	_board_mat.disable_fog = true   # lit: it cuts through the haze from miles out, like the beacons
	var column := ShaderMaterial.new()
	column.shader = preload("res://view/pylon.gdshader")
	var asph := ShaderMaterial.new()
	asph.shader = preload("res://view/asphalt.gdshader")
	asph.set_shader_parameter("period", ASPHALT_PERIOD)
	asph.set_shader_parameter("base", Vector3(0.25, 0.245, 0.245))
	asph.set_shader_parameter("lane_half", 40.0)
	var c0 := 0
	while c0 < n:
		var c1 := mini(c0 + CHUNK, n)
		var node := Node3D.new()
		add_child(node)
		var cx := 0.0
		var cy := 0.0
		for i in range(c0, c1):
			cx += sim.tpx[i]
			cy += sim.tpy[i]
		cx /= (c1 - c0)
		cy /= (c1 - c0)
		chunks.append([node, cx, cy])
		var surf := SurfaceTool.new()
		surf.begin(Mesh.PRIMITIVE_TRIANGLES)
		var deco := SurfaceTool.new()
		deco.begin(Mesh.PRIMITIVE_TRIANGLES)
		var glow := SurfaceTool.new()
		glow.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lglow := SurfaceTool.new()
		lglow.begin(Mesh.PRIMITIVE_TRIANGLES)
		var lamps := SurfaceTool.new()
		lamps.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n_lamps := 0
		var cols := SurfaceTool.new()
		cols.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n_cols := 0
		var n_lglow := 0
		for i in range(c0, c1):
			var j := (i + 1) % n
			var town: bool = sim.tmode[i] == 0
			var hw: float = sim.tw[i] / 2.0
			var hw2: float = sim.tw[j] / 2.0
			_asphalt(surf, cx, cy, i, j, hw, hw2)
			for sgn in [-1.0, 1.0]:
				_strip(deco, cx, cy, i, j, sgn * (hw - 1.5 - LINE_W), sgn * (hw - 1.5), sgn * (hw2 - 1.5 - LINE_W), sgn * (hw2 - 1.5), 0.04, Color(0.92, 0.92, 0.9))
			if kerb[i] != 0:
				var side: float = kerb[i]
				_strip(deco, cx, cy, i, j, side * (hw - KERB_W), side * hw, side * (hw2 - KERB_W), side * hw2, 0.06,
					Color(0.85, 0.1, 0.08) if i % 2 == 0 else Color(0.95, 0.95, 0.93))
			for sgn in [-1.0, 1.0]:
				var a := _p(cx, cy, i, sgn * hw)
				var b := _p(cx, cy, j, sgn * hw2)
				var band := Color(0.86, 0.27, 0.09) if (i / 4) % 2 == 0 else Color(0.95, 0.95, 0.93)
				var top := WALL_H
				if town:
					_wall(deco, a, b, 0.0, WALL_H * 0.7, Color(0.72, 0.71, 0.68))
					_wall(deco, a, b, WALL_H * 0.7, WALL_H, band)
				else:
					_wall(deco, a, b, 0.0, 1.4, Color(0.72, 0.71, 0.68))
					_wall(deco, a, b, 1.4, LOOP_WALL_H, LOOP_BAND[(i / 4) % 2])
					top = LOOP_WALL_H
				if town:
					var on_chev: bool = chev[i] == int(sgn)
					var slate := 0.2 + 0.035 * ((i / 4) % 2)
					_wall(deco, a, b, WALL_H, FENCE_H, Color(0.05, 0.05, 0.06) if on_chev else Color(slate, slate + 0.01, slate + 0.03))
					top = FENCE_H
					if on_chev and i % 2 == 0:
						_chevron(glow, cx, cy, i, sgn * (hw - 0.08))
						chevrons += 1
				# banked: an earth berm from the high wall back down to the ground
				if sim.tb[i] != 0.0 and sgn == -signf(sim.tb[i]):
					var hi: float = 2.0 * hw * absf(tan(sim.tb[i]))
					var hj: float = 2.0 * hw2 * absf(tan(sim.tb[j]))
					if hi > 0.3 or hj > 0.3:
						_strip(deco, cx, cy, i, j, sgn * hw, sgn * (hw + hi + 0.5), sgn * hw2, sgn * (hw2 + hj + 0.5), -0.05, Color(0.33, 0.42, 0.2))
				var nav := LEFT_LIGHT if sgn > 0.0 else RIGHT_LIGHT
				if town:
					_wall(glow, a, b, top, top + STRIP_H, nav)
				else:
					_wall(lglow, a, b, top, top + LOOP_STRIP_H, nav)
					n_lglow += 1
				if i % (8 if town else LOOP_MAST_EVERY) == 0:
					var mh := MAST_H if town else LOOP_MAST_H
					var foot := _p(cx, cy, i, sgn * (hw + 0.4))
					_mast(deco, glow, foot, nav, mh)
					masts += 1
					if not town or i % 16 == 0:
						_beacon(lamps, foot + Vector3.UP * (mh + 0.45), nav)
						n_lamps += 1
					if not town and i % (2 * LOOP_MAST_EVERY) == 0:
						_column(cols, foot + Vector3.UP * (mh + 1.0), PYLON_H, nav)
						n_cols += 1
		var meshes := [[surf, asph], [deco, mat], [glow, lit]]
		if n_lglow > 0:
			meshes.append([lglow, bright])
		for pair in meshes:
			var mi := MeshInstance3D.new()
			mi.mesh = (pair[0] as SurfaceTool).commit()
			mi.material_override = pair[1]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if n_lamps > 0:
			var ln := Node3D.new()
			ln.name = "lights"
			add_child(ln)
			lights.append([ln, cx, cy])
			for pair in [[lamps, beam, "beacons"], [cols, column, "columns"]] if n_cols > 0 else [[lamps, beam, "beacons"]]:
				var bm := MeshInstance3D.new()
				bm.name = pair[2]
				bm.mesh = (pair[0] as SurfaceTool).commit()
				bm.material_override = pair[1]
				bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				bm.extra_cull_margin = 400.0   # the quads grow with distance, past the mesh's own bounds
				ln.add_child(bm)
			beacons += n_lamps
			pylons += n_cols
		c0 = c1
	_start_line()
	_zone_signs()
	_grandstands()
	_floodlights()


## Chunks follow the floating origin; far ones hide.
func sync(ox: float, oy: float) -> void:
	for c in chunks:
		var dx: float = c[1] - ox
		var dy: float = c[2] - oy
		(c[0] as Node3D).position = Vector3(dx, 0.0, -dy)
		(c[0] as Node3D).visible = dx * dx + dy * dy < VIS * VIS
	for c in lights:
		var dx: float = c[1] - ox
		var dy: float = c[2] - oy
		(c[0] as Node3D).position = Vector3(dx, 0.0, -dy)
		(c[0] as Node3D).visible = dx * dx + dy * dy < BEACON_VIS * BEACON_VIS


## The chunk node that holds sample i.
func chunk_of(i: int) -> Array:
	return chunks[mini(i / CHUNK, chunks.size() - 1)]


# --- geometry, chunk-local (64-bit until the subtraction) -------------------------------------

## A point `off` metres left of sample i's centreline, on the banked surface, relative to (cx, cy).
func _p(cx: float, cy: float, i: int, off: float) -> Vector3:
	var x: float = sim.tpx[i] + sim.tnx[i] * off - cx
	var y: float = sim.tpy[i] + sim.tny[i] * off - cy
	return Vector3(x, sim.bank_height(sim.tw[i] / 2.0, off, sim.tb[i]), -y)


func _strip(st: SurfaceTool, cx: float, cy: float, i: int, j: int, o0: float, o1: float, p0: float, p1: float, h: float, c: Color) -> void:
	var a := _p(cx, cy, i, o0) + Vector3.UP * h
	var b := _p(cx, cy, i, o1) + Vector3.UP * h
	var cc := _p(cx, cy, j, p1) + Vector3.UP * h
	var d := _p(cx, cy, j, p0) + Vector3.UP * h
	for q in [a, b, cc, a, cc, d]:
		st.set_color(c)
		st.set_normal(Vector3.UP)
		st.add_vertex(q)


func _asphalt(st: SurfaceTool, cx: float, cy: float, i: int, j: int, hw: float, hw2: float) -> void:
	var a := _p(cx, cy, i, -hw) + Vector3.UP * 0.02
	var b := _p(cx, cy, i, hw) + Vector3.UP * 0.02
	var cc := _p(cx, cy, j, hw2) + Vector3.UP * 0.02
	var d := _p(cx, cy, j, -hw2) + Vector3.UP * 0.02
	var nrm := (b - a).cross(d - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var u0 := fposmod(_s[i], ASPHALT_PERIOD)   # periodic: every lattice in the shader divides it
	var u1: float = u0 + sim.tlen[i]
	for v in [[a, Vector2(u0, -hw)], [b, Vector2(u0, hw)], [cc, Vector2(u1, hw2)], [a, Vector2(u0, -hw)], [cc, Vector2(u1, hw2)], [d, Vector2(u1, -hw2)]]:
		st.set_normal(nrm)
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _wall(st: SurfaceTool, a: Vector3, b: Vector3, h0: float, h1: float, c: Color) -> void:
	var nrm := (b - a).cross(Vector3.UP).normalized()
	for q in [a + Vector3.UP * h0, b + Vector3.UP * h0, b + Vector3.UP * h1, a + Vector3.UP * h0, b + Vector3.UP * h1, a + Vector3.UP * h1]:
		st.set_color(c)
		st.set_normal(nrm)
		st.add_vertex(q)


func _chevron(st: SurfaceTool, cx: float, cy: float, i: int, off: float) -> void:
	var base := _p(cx, cy, i, off)
	var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
	var hc := (WALL_H + FENCE_H) / 2.0
	var hh := (FENCE_H - WALL_H) / 2.0 - 0.35
	var at := func(sv: float, h: float) -> Vector3:
		return base + t * sv + Vector3.UP * h
	var arm := 1.3
	var nrm := Vector3(-sim.tnx[i], 0.0, sim.tny[i]) * signf(off)
	for quad in [[at.call(-arm, hc + hh), at.call(0.0, hc + hh), at.call(arm, hc), at.call(0.0, hc)],
			[at.call(0.0, hc), at.call(arm, hc), at.call(0.0, hc - hh), at.call(-arm, hc - hh)]]:
		for q in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			st.set_color(CHEVRON)
			st.set_normal(nrm)
			st.add_vertex(q)


func _mast(st: SurfaceTool, lit: SurfaceTool, p: Vector3, c: Color, h := MAST_H) -> void:
	var w := 0.35 if h <= MAST_H else 0.6
	_box(st, p + Vector3.UP * (h / 2.0), Vector3(w, h, w), Color(0.3, 0.31, 0.33))
	_box(lit, p + Vector3.UP * (h + 0.45), Vector3(0.9, 0.9, 0.9), c)


## A light column standing on `foot`, `h` tall: one quad, its foot and head on the axis (the
## shader turns it to the camera and keeps it a few pixels wide; UV: x the side, y up it).
func _column(st: SurfaceTool, foot: Vector3, h: float, c: Color) -> void:
	var top := foot + Vector3.UP * h
	for v in [[foot, Vector2(-1, 0)], [foot, Vector2(1, 0)], [top, Vector2(1, 1)], [foot, Vector2(-1, 0)], [top, Vector2(1, 1)], [top, Vector2(-1, 1)]]:
		st.set_color(c)
		st.set_uv(v[1])
		st.set_normal(Vector3.UP)
		st.add_vertex(v[0])


## A beacon: one quad with all four corners at `p` (the shader spreads them; UV is the corner).
func _beacon(st: SurfaceTool, p: Vector3, c: Color) -> void:
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_color(c)
		st.set_uv(uv)
		st.set_normal(Vector3.UP)
		st.add_vertex(p)


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


# --- corners and zones ---------------------------------------------------------------------------

## Town corners: runs of town samples turning faster than a 2 km radius.
func _find_corners() -> void:
	var n: int = sim.N
	var k := 0
	while k < n:
		var kap := _kap(k)
		if sim.tmode[k] == 0 and absf(kap) > 1.0 / 2000.0:
			var sgn := signf(kap)
			var st := k
			while k < n and sim.tmode[k] == 0 and absf(_kap(k)) > 1.0 / 2000.0 and signf(_kap(k)) == sgn:
				k += 1
			corners.append([st, k - 1, sgn])
		else:
			k += 1


func _kap(i: int) -> float:
	var j: int = (i + 1) % sim.N
	return wrapf(atan2(sim.tty[j], sim.ttx[j]) - atan2(sim.tty[i], sim.ttx[i]), -PI, PI) / sim.tlen[i]


## Per sample: kerbs (the inside of each corner) or chevrons (the outside, from 120 m before).
func _flags(kerbs: bool) -> PackedInt32Array:
	var n: int = sim.N
	var f := PackedInt32Array()
	f.resize(n)
	for c in corners:
		for q in range(c[0] - (6 if kerbs else 10), c[1] + (7 if kerbs else 1)):
			f[posmod(q, n)] = int(c[2]) if kerbs else -int(c[2])
	return f


## Where the modes meet: [i, "sf"] where a town begins, [i, "sp"] where the speed loop does.
func _find_zones() -> void:
	var n: int = sim.N
	for i in n:
		var prev: int = sim.tmode[posmod(i - 1, n)]
		if sim.tmode[i] != prev:
			zones.append([i, "sf" if sim.tmode[i] == 0 else "sp"])


## Before each town: braking boards on both walls (12 / 9 / 6 / 3 / 1 km) and a STARFIGHTER
## gantry at its mouth. At the loop's start: a SPEEDCRAFT gantry.
func _zone_signs() -> void:
	var n: int = sim.N
	for z in zones:
		var i: int = z[0]
		if z[1] == "sf":
			for mi in BOARDS_MI:
				var k := _back(i, mi * MILE)
				_board(k, mi, SF_COL if mi <= 2 else BOARD_AMBER)
			_gantry(i, "STARFIGHTER ZONE   1,250 MPH", SF_COL)
		else:
			_gantry(i, "SPEEDCRAFT", SP_COL)


## The sample `metres` back along the track from sample i.
func _back(i: int, metres: float) -> int:
	var n: int = sim.N
	var k := i
	var d := 0.0
	while d < metres:
		k = posmod(k - 1, n)
		d += sim.tlen[k]
	return k


## A braking board: a lit sign over the middle of the track on a gantry, its face toward the
## oncoming craft with the miles on it in black, beacons on its top corners. Over the middle,
## because from the cockpit the engines hide the band 3-10 deg either side of dead ahead, where
## boards on the walls of a 400 m track sit from 1 to 2.5 km out; the gap between the engines is
## open. (The first boards, on the walls, also hid their numbers inside themselves.)
func _board(i: int, miles: int, c: Color) -> void:
	var ch: Array = chunk_of(i)
	var hw: float = sim.tw[i] / 2.0 + 4.0
	var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
	var b := Basis(Vector3.UP, atan2(sim.tty[i], sim.ttx[i]))   # thin along the track
	var across := b * Vector3(0, 0, 1)
	var mid := _p(ch[1], ch[2], i, 0.0)
	var foot := maxf(_p(ch[1], ch[2], i, hw).y, _p(ch[1], ch[2], i, -hw).y) + BOARD_CLEAR   # over the higher edge (banked)
	var steel := Color(0.22, 0.23, 0.25)
	var parts := []
	for sd in [-1.0, 1.0]:
		var q := _p(ch[1], ch[2], i, sd * hw)
		parts.append([Kit.box(Vector3(2.4, foot + 4.0 - q.y, 2.4)), Kit.at(q + Vector3(0, (foot + 4.0 - q.y) / 2.0, 0)), steel])
	parts.append([Kit.box(Vector3(3.0, 4.0, hw * 2.0 + 2.4)), Transform3D(b, Vector3(mid.x, foot + 2.0, mid.z)), steel])
	var sc := Vector3(mid.x, foot + 4.0 + BOARD_H / 2.0, mid.z)   # the sign's centre
	parts.append([Kit.box(Vector3(2.0, BOARD_H + 4.0, BOARD_W + 4.0)), Transform3D(b, sc), Color(0.1, 0.1, 0.12)])
	var frame := MeshInstance3D.new()
	frame.mesh = Kit.compound(parts)
	frame.material_override = Kit.vertex_colors()
	(ch[0] as Node3D).add_child(frame)
	var face := MeshInstance3D.new()
	face.add_to_group("board_face")   # tests count them
	face.mesh = Kit.compound([[Kit.box(Vector3(0.3, BOARD_H, BOARD_W)), Transform3D(b, sc - t * 1.15), c]])
	face.material_override = _board_mat
	(ch[0] as Node3D).add_child(face)
	var facing := Basis(Vector3.UP, atan2(-sim.ttx[i], sim.tty[i]))   # a label's +Z toward the oncoming craft
	for ln in [[str(miles), 640, 3.0], ["1 MILE   STARFIGHTER" if miles == 1 else "MILES", 170, -14.5]]:
		var l := Label3D.new()
		l.text = ln[0]
		l.font_size = ln[1]
		l.pixel_size = 0.05
		l.outline_size = 0
		l.modulate = Color(0.03, 0.03, 0.04)
		l.double_sided = false
		l.transform = Transform3D(facing, sc + Vector3.UP * float(ln[2]) - t * 1.4)
		(ch[0] as Node3D).add_child(l)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s2 in [-1.0, 1.0]:
		_beacon(st, sc + Vector3.UP * (BOARD_H / 2.0 + 3.5) + across * s2 * (BOARD_W / 2.0 + 2.0), c)
	var bm := MeshInstance3D.new()
	bm.mesh = st.commit()
	bm.material_override = _beam
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bm.extra_cull_margin = 400.0
	(ch[0] as Node3D).add_child(bm)
	boards += 1


## A gantry spanning the track at sample i, its banner facing the oncoming craft.
func _gantry(i: int, text: String, c: Color) -> void:
	var ch: Array = chunk_of(i)
	var hw: float = sim.tw[i] / 2.0 + 4.0
	var steel := Color(0.22, 0.23, 0.25)
	var top := maxf(_p(ch[1], ch[2], i, hw).y, _p(ch[1], ch[2], i, -hw).y) + 18.0
	var parts := []
	for s in [-1.0, 1.0]:
		var p := _p(ch[1], ch[2], i, s * hw)
		parts.append([Kit.box(Vector3(1.8, top - p.y, 1.8)), Kit.at(p + Vector3(0, (top - p.y) / 2.0, 0)), steel])
	var mid := _p(ch[1], ch[2], i, 0.0)
	mid.y = top
	var yaw := atan2(sim.tty[i], sim.ttx[i])
	parts.append([Kit.box(Vector3(3.0, 4.0, hw * 2.0 + 1.8)), Transform3D(Basis(Vector3.UP, yaw), mid), steel])
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = Kit.vertex_colors()
	(ch[0] as Node3D).add_child(mi)
	var banner := MeshInstance3D.new()
	banner.mesh = Kit.compound([[Kit.box(Vector3(0.3, 2.6, hw * 2.0 - 4.0)), Transform3D(Basis(Vector3.UP, yaw), mid + Vector3(0, -0.2, 0) - Vector3(sim.ttx[i], 0.0, -sim.tty[i]) * 1.7), c]])
	banner.material_override = Kit.vertex_colors(true)
	(ch[0] as Node3D).add_child(banner)
	var l := Label3D.new()
	l.text = text
	l.font_size = 300
	l.pixel_size = 0.02
	l.outline_size = 16
	l.modulate = Color(0.06, 0.06, 0.08)
	l.outline_modulate = Color(1, 1, 1, 0.6)
	l.position = mid + Vector3(0, -0.2, 0) - Vector3(sim.ttx[i], 0.0, -sim.tty[i]) * 1.9
	l.rotation.y = -PI / 2.0 + yaw
	(ch[0] as Node3D).add_child(l)


## The start: a gantry over the line, chequers across the track.
func _start_line() -> void:
	_gantry(0, "ERIDANUS", Color(1.0, 0.72, 0.38))
	var ch: Array = chunk_of(0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = sim.tw[0]
	var t := Vector3(sim.ttx[0], 0.0, -sim.tty[0])
	for k in 20:
		for r in 2:
			var w0 := -w / 2.0 + k * w / 20.0
			var a := _p(ch[1], ch[2], 0, w0) + t * (r * 2.5) + Vector3.UP * 0.07
			var b := _p(ch[1], ch[2], 0, w0 + w / 20.0) + t * (r * 2.5) + Vector3.UP * 0.07
			var cc := b + t * 2.5
			var d := a + t * 2.5
			for q in [a, b, cc, a, cc, d]:
				st.set_color(Color.WHITE if (k + r) % 2 == 0 else Color(0.05, 0.05, 0.05))
				st.set_normal(Vector3.UP)
				st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Kit.vertex_colors()
	(ch[0] as Node3D).add_child(mi)


## Grandstands and the pit buildings on the river straight (the start town's main straight):
## stands on the right, pits on the left.
func _grandstands() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	for g in 4:
		var i := 40 + g * 50
		var ch: Array = chunk_of(i)
		var hw: float = sim.tw[i] / 2.0
		var base := _p(ch[1], ch[2], i, -(hw + 14.0))
		var yaw := atan2(sim.tty[i], sim.ttx[i])
		var b := Basis(Vector3.UP, yaw - PI / 2.0)
		var parts := []
		for step in 8:
			parts.append([Kit.box(Vector3(1.6, 1.2, 140.0)), Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, 0.6 + step * 1.2, 0) + Vector3(sim.tnx[i], 0, -sim.tny[i]) * (-step * 1.6)), Color(0.55, 0.56, 0.58)])
			for k in 40:
				var c := Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.9), rng.randf_range(0.5, 1.0))
				var along := -66.0 + k * 3.3 + rng.randf_range(-0.6, 0.6)
				parts.append([Kit.box(Vector3(0.7, 1.0, 1.4)), Transform3D(Basis(Vector3.UP, yaw),
					base + Vector3(0, 1.7 + step * 1.2, 0) + Vector3(sim.tnx[i], 0, -sim.tny[i]) * (-step * 1.6) + Vector3(sim.ttx[i], 0, -sim.tty[i]) * along), c])
		parts.append([Kit.box(Vector3(14.0, 0.6, 142.0)), Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, 11.2, 0) + Vector3(sim.tnx[i], 0, -sim.tny[i]) * -6.0), Color(0.86, 0.27, 0.09)])
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.compound(parts)
		mi.material_override = Kit.vertex_colors()
		(ch[0] as Node3D).add_child(mi)
	for i in [30, 41]:
		var ch: Array = chunk_of(i)
		var hw: float = sim.tw[i] / 2.0
		var p := _p(ch[1], ch[2], i, hw + 32.0)
		var t := Vector3(sim.ttx[i], 0.0, -sim.tty[i])
		var nn := Vector3(sim.tnx[i], 0.0, -sim.tny[i])
		Props.place(ch[0], "pit_building", Transform3D(Basis(-t, Vector3.UP, nn), Vector3(p.x, 0.0, p.z)))


## Floodlight towers round the towns, every ~480 m, on the inside of banked corners.
func _floodlights() -> void:
	var side := 1.0
	for i in range(0, sim.N, 40):
		if sim.tmode[i] != 0:
			continue
		var s2: float = signf(sim.tb[i]) if sim.tb[i] != 0.0 else side
		side = -side
		var ch: Array = chunk_of(i)
		var p := _p(ch[1], ch[2], i, s2 * (sim.tw[i] / 2.0 + 18.0))
		var to_track := _p(ch[1], ch[2], i, 0.0) - p
		to_track.y = 0.0
		Props.place(ch[0], "floodlight", Transform3D(Basis.looking_at(to_track.normalized(), Vector3.UP), Vector3(p.x, 0.0, p.z)))
