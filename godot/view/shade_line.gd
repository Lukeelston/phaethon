## The shade line (a private covered STARFIGHTER line off Eridanus' loop into the start town,
## tools/design_eridanus.py; the sim's branch 0), drawn as you ride it: twisted over by its
## corkscrews (sim.roll_at) and raised to its canopy (sim.branch_height), ridden upside down on
## the canopy's underside. The sim is flat: every point lat metres left of the centreline and up
## metres off the road sits along the rolled road's left and up (CraftModel.road_xf does the same
## for the craft). Built in chunks like view/course_world.gd, each chunk's meshes in its own
## local coordinates; the junction zones are chunks of their own.
##   the road     asphalt 120 m wide, lit bars across it every 48 m (under the canopy, the speed
##                cue overhead); where it shares the loop's road at a junction, the loop's draws
##   walls        concrete, a dark band and a lit strip (white, like the towns'), standing off the
##                road whichever way up it is; open where the roads meet
##   the canopy   over the covered samples: where the road is turned over, the road's own back, a
##                slab with eaves past the walls, on pillars outside them; once it's turned back
##                upright, a roof over the road on posts at the walls
##   the gate     a gantry over the line once its road has fully left the loop's: PRIVATE LINE (red)
##                unless the job opens it (the SPEED AUTHORIZED look), and shut for a pass the sim's
##                gate shut (into its zone over 1,250 mph); shut, a red-and-white barrier stands
##                along the loop's wall line across the gap (course_world builds it: `barrier`), just
##                where the sim's wall holds
##   add_child(sl); sl.build(sim, view)   once (view/course_world.gd)
##   sl.sync(org_x, org_y)                 every frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const CHUNK := 128                # branch samples per chunk (~1.5 km)
const VIS := 16000.0              # chunks further than this (m, centre to pod) are hidden
const WALL_H := 1.4               # concrete ...
const BAND_H := 3.2               # ... a dark band to here ...
const STRIP_H := 0.4              # ... and a lit strip on top
const LAMP_EVERY := 4             # samples (48 m): a lit bar across the road
const SLAB := 3.0                 # the canopy's thickness behind the road
const EAVE := 10.0                # its reach past each wall
const PILLAR_EVERY := 8           # samples (~96 m)
const PILLAR_OFF := 7.0           # m outside the walls
const ROOF_UP := 16.0             # upright again, the canopy is a roof this far over the road
const GATE_CLEAR := 22.0          # the gate's beam over the road
const GATE_H := 16.0              # its face
const STRIP_LIGHT := Color(0.9, 0.94, 1.0)
const CONCRETE := Color(0.62, 0.61, 0.58)
const BAND := Color(0.14, 0.15, 0.17)
const SLAB_COL := Color(0.42, 0.42, 0.41)

var sim
var view
var B                              # the branch (sim.branches[0])
var chunks := []                   # [node, centre x, centre y, first sample, end sample]
var normals := PackedVector3Array()   # the road's up at each sample, as built (tests read it)
var canopy_range := Vector2i(-1, -1)  # the first and last samples under the canopy, as built
var gate_i := -1                   # the gate's branch sample
var gate_open := false
var shut_sign: Node3D
var open_sign: Node3D
var barrier: Node3D                # course_world's barrier across the loop's gap (shown while shut)
var _s := PackedFloat64Array()     # distance along the line at each sample


func build(s, v) -> void:
	sim = s
	view = v
	B = sim.branches[0]
	var n: int = B.N
	_s.resize(n)
	var acc := 0.0
	for i in n:
		_s[i] = acc
		acc += B.len[i]
	normals.resize(n)
	for i in n:
		normals[i] = _frame(i)[2]
	var asph := ShaderMaterial.new()
	asph.shader = preload("res://view/asphalt.gdshader")
	asph.set_shader_parameter("period", 64000.0)
	asph.set_shader_parameter("base", Vector3(0.23, 0.225, 0.225))
	asph.set_shader_parameter("lane_half", 20.0)
	var mat := Kit.vertex_colors()
	var glow := Kit.vertex_colors(true)
	glow.albedo_color = Color(2.2, 2.2, 2.2)   # HDR: the strips and bars bloom
	# chunks: the junction zones on their own, CHUNK samples between
	var cuts := [0, B.jz]
	var k: int = B.jz + CHUNK
	while k < n - 1 - B.jz:
		cuts.append(k)
		k += CHUNK
	cuts.append_array([n - 1 - B.jz, n - 1])
	for c in cuts.size() - 1:
		_chunk(cuts[c], cuts[c + 1], asph, mat, glow)
	canopy_range = Vector2i(B.covered.x, mini(B.covered.y, n - 2))
	_gate()


func sync(ox: float, oy: float) -> void:
	for c in chunks:
		var dx: float = c[1] - ox
		var dy: float = c[2] - oy
		(c[0] as Node3D).position = Vector3(dx, 0.0, -dy)
		(c[0] as Node3D).visible = dx * dx + dy * dy < VIS * VIS
	gate_open = B.open and sim.gate[0] != false
	if shut_sign:
		shut_sign.visible = not gate_open
		open_sign.visible = gate_open
	if barrier:
		barrier.visible = not gate_open


# --- geometry ------------------------------------------------------------------------------------

## Sample i's road: [centre height, left, up] (render axes; left and up rolled by the corkscrews).
func _frame(i: int) -> Array:
	var r: float = sim.roll_at(1, i)
	var nl := Vector3(B.nx[i], 0.0, -B.ny[i])
	return [sim.branch_height(1, i), nl * cos(r) - Vector3.UP * sin(r), nl * sin(r) + Vector3.UP * cos(r)]


## A point lat m left of sample i's centreline and up m off its road, relative to (cx, cy).
func _q(cx: float, cy: float, i: int, lat: float, up: float) -> Vector3:
	var f := _frame(i)
	return Vector3(B.px[i] - cx, f[0], -(B.py[i] - cy)) + (f[1] as Vector3) * lat + (f[2] as Vector3) * up


## True where sim (x, y) lies on the loop's own road (a junction: the loop draws it there).
func _on_main(i: int, x: float, y: float) -> bool:
	if i >= B.jz and i <= B.N - 1 - B.jz:
		return false
	var hint: int = (B.from_i + i) % sim.N if i < B.jz else posmod(B.join_i - (B.N - 1 - i), sim.N)
	sim._nearest(x, y, hint, 40)
	return absf(sim._n_lat) < sim._n_w / 2.0 - 0.5


func _quad(st: SurfaceTool, q: Array, nrm: Vector3, c: Color) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(c)
		st.set_normal(nrm)
		st.add_vertex(q[k])


func _chunk(i0: int, i1: int, asph: Material, mat: Material, glow: Material) -> void:
	var node := Node3D.new()
	add_child(node)
	var cx := 0.0
	var cy := 0.0
	for i in range(i0, i1):
		cx += B.px[i]
		cy += B.py[i]
	cx /= (i1 - i0)
	cy /= (i1 - i0)
	chunks.append([node, cx, cy, i0, i1])
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deco := SurfaceTool.new()
	deco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lit := SurfaceTool.new()
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(i0, i1):
		var j := i + 1
		var hw: float = B.w[i] / 2.0
		var hj: float = B.w[j] / 2.0
		var fi := _frame(i)
		var fj := _frame(j)
		var shared := _on_main(i, B.px[i], B.py[i]) and _on_main(j, B.px[j], B.py[j])
		# the road (where the loop's isn't already)
		if not shared:
			var u0 := fposmod(_s[i], 64000.0)
			var u1: float = u0 + B.len[i]
			var a := _q(cx, cy, i, -hw, 0.02)
			var b := _q(cx, cy, i, hw, 0.02)
			var c := _q(cx, cy, j, hj, 0.02)
			var d := _q(cx, cy, j, -hj, 0.02)
			for vv in [[a, Vector2(u0, -hw), fi[2]], [b, Vector2(u0, hw), fi[2]], [c, Vector2(u1, hj), fj[2]],
					[a, Vector2(u0, -hw), fi[2]], [c, Vector2(u1, hj), fj[2]], [d, Vector2(u1, -hj), fj[2]]]:
				road.set_normal(vv[2])
				road.set_uv(vv[1])
				road.add_vertex(vv[0])
			if i % LAMP_EVERY == 0:   # a lit bar across: the speed cue, overhead under the canopy
				var jb := mini(i + 1, B.N - 1)
				_quad(lit, [_q(cx, cy, i, -hw * 0.85, 0.06), _q(cx, cy, i, hw * 0.85, 0.06), _q(cx, cy, jb, hj * 0.85, 0.06).lerp(_q(cx, cy, i, hw * 0.85, 0.06), 0.9),
					_q(cx, cy, jb, -hj * 0.85, 0.06).lerp(_q(cx, cy, i, -hw * 0.85, 0.06), 0.9)], fi[2], STRIP_LIGHT)
		# walls, off the road along its up, open where they'd stand on the loop's road
		for sgn in [-1.0, 1.0]:
			var ex: float = B.px[i] + B.nx[i] * sgn * hw
			var ey: float = B.py[i] + B.ny[i] * sgn * hw
			if _on_main(i, ex, ey):
				continue
			var e0 := _q(cx, cy, i, sgn * hw, 0.0)
			var e1 := _q(cx, cy, j, sgn * hj, 0.0)
			var nrm: Vector3 = -(fi[1] as Vector3) * sgn
			_quad(deco, [e0, e1, e1 + (fj[2] as Vector3) * WALL_H, e0 + (fi[2] as Vector3) * WALL_H], nrm, CONCRETE)
			_quad(deco, [e0 + (fi[2] as Vector3) * WALL_H, e1 + (fj[2] as Vector3) * WALL_H, e1 + (fj[2] as Vector3) * BAND_H, e0 + (fi[2] as Vector3) * BAND_H], nrm, BAND)
			_quad(lit, [e0 + (fi[2] as Vector3) * BAND_H, e1 + (fj[2] as Vector3) * BAND_H, e1 + (fj[2] as Vector3) * (BAND_H + STRIP_H), e0 + (fi[2] as Vector3) * (BAND_H + STRIP_H)], nrm, STRIP_LIGHT)
		# the canopy
		if i >= B.covered.x and i <= B.covered.y and j < B.N:
			_canopy(deco, cx, cy, i, j, hw, hj, fi, fj)
	for pair in [[road, asph], [deco, mat], [lit, glow]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)


## How far left (sgn 1) or right (-1) of sample i's centreline, up m off its road, the canopy can
## reach (to hw + EAVE) and still stay half a metre clear of the ground (on edge mid-corkscrew the
## road's low side is only just up: the eaves there shrink to the wall).
func _reach(i: int, sgn: float, hw: float, up: float) -> float:
	var f := _frame(i)
	var lo: float = -(f[1] as Vector3).y * sgn   # height lost per metre out
	var h: float = f[0] + (f[2] as Vector3).y * up - 0.5
	if lo <= 1e-6 or h >= lo * (hw + EAVE):
		return hw + EAVE
	return clampf(h / lo, hw, hw + EAVE)


## One sample's run of canopy. Turned over (the road faces down), it's the road's back: a slab
## SLAB thick reaching EAVE past the walls, on pillars outside them from the ground. Upright, a roof
## ROOF_UP over the road on posts at the walls.
func _canopy(st: SurfaceTool, cx: float, cy: float, i: int, j: int, hw: float, hj: float, fi: Array, fj: Array) -> void:
	var over: bool = sim.roll_at(1, i) >= PI / 2.0
	var up := -SLAB if over else ROOF_UP
	var ow := minf(_reach(i, 1.0, hw, up), _reach(i, 1.0, hw, 0.0)) if over else _reach(i, 1.0, hw, up)
	var oj := minf(_reach(j, 1.0, hj, up), _reach(j, 1.0, hj, 0.0)) if over else _reach(j, 1.0, hj, up)
	var ow_r := minf(_reach(i, -1.0, hw, up), _reach(i, -1.0, hw, 0.0)) if over else _reach(i, -1.0, hw, up)
	var oj_r := minf(_reach(j, -1.0, hj, up), _reach(j, -1.0, hj, 0.0)) if over else _reach(j, -1.0, hj, up)
	if over:
		# the back, the eaves' undersides, the outer edges
		_quad(st, [_q(cx, cy, i, -ow_r, -SLAB), _q(cx, cy, i, ow, -SLAB), _q(cx, cy, j, oj, -SLAB), _q(cx, cy, j, -oj_r, -SLAB)], -(fi[2] as Vector3), SLAB_COL)
		for sgn in [-1.0, 1.0]:
			var a: float = ow if sgn > 0.0 else ow_r
			var b: float = oj if sgn > 0.0 else oj_r
			_quad(st, [_q(cx, cy, i, sgn * hw, 0.0), _q(cx, cy, i, sgn * a, 0.0), _q(cx, cy, j, sgn * b, 0.0), _q(cx, cy, j, sgn * hj, 0.0)], fi[2], SLAB_COL)
			_quad(st, [_q(cx, cy, i, sgn * a, 0.0), _q(cx, cy, j, sgn * b, 0.0), _q(cx, cy, j, sgn * b, -SLAB), _q(cx, cy, i, sgn * a, -SLAB)], (fi[1] as Vector3) * sgn, SLAB_COL)
		# pillars from the ground to the eaves, where the slab is (near enough) flat over the road
		if i % PILLAR_EVERY == 0 and sim.roll_at(1, i) >= deg_to_rad(150.0):
			for sgn in [-1.0, 1.0]:
				var top := _q(cx, cy, i, sgn * (hw + PILLAR_OFF), -SLAB)
				var x: float = B.px[i] + B.nx[i] * sgn * (hw + PILLAR_OFF)
				var y: float = B.py[i] + B.ny[i] * sgn * (hw + PILLAR_OFF)
				if not _on_main(i, x, y) and top.y > 1.0:
					_pillar(st, Vector3(top.x, 0.0, top.z), top.y)
	else:
		_quad(st, [_q(cx, cy, i, -ow_r, ROOF_UP), _q(cx, cy, i, ow, ROOF_UP), _q(cx, cy, j, oj, ROOF_UP), _q(cx, cy, j, -oj_r, ROOF_UP)], -(fi[2] as Vector3), SLAB_COL)
		_quad(st, [_q(cx, cy, i, -ow_r, ROOF_UP + 1.5), _q(cx, cy, i, ow, ROOF_UP + 1.5), _q(cx, cy, j, oj, ROOF_UP + 1.5), _q(cx, cy, j, -oj_r, ROOF_UP + 1.5)], fi[2], SLAB_COL)
		if i % PILLAR_EVERY == 0 and sim.roll_at(1, i) < deg_to_rad(5.0):   # upright: posts at the walls
			for sgn in [-1.0, 1.0]:
				var x: float = B.px[i] + B.nx[i] * sgn * (hw + 2.0)
				var y: float = B.py[i] + B.ny[i] * sgn * (hw + 2.0)
				if _on_main(i, x, y):
					continue
				var head := _q(cx, cy, i, sgn * (hw + 2.0), ROOF_UP)
				_pillar(st, Vector3(head.x, 0.0, head.z), head.y)


func _pillar(st: SurfaceTool, foot: Vector3, h: float) -> void:
	_post(st, foot, foot + Vector3.UP * h)


## A square post 3 m across from a to b.
func _post(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var ax := (b - a).normalized()
	var s1 := ax.cross(Vector3.FORWARD if absf(ax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized() * 1.5
	var s2 := ax.cross(s1).normalized() * 1.5
	var cs := [s1 + s2, -s1 + s2, -s1 - s2, s1 - s2]
	for k in 4:
		var p: Vector3 = cs[k]
		var q: Vector3 = cs[(k + 1) % 4]
		_quad(st, [a + p, a + q, b + q, b + p], (p + q).normalized(), SLAB_COL)


## The gate: an overhead across the line where its centreline leaves the loop's road, legs at
## both walls, a face toward the oncoming craft: shut (red, PRIVATE LINE, a red-and-white boom
## across the road) or open (the SPEED AUTHORIZED look).
func _gate() -> void:
	gate_i = B.jz - 1
	for i in B.jz:   # the first sample where both legs stand 2 m clear of the loop's road
		var clear := true
		for lat in [-(B.w[i] / 2.0 + 5.0), B.w[i] / 2.0 + 5.0]:
			if _on_main(i, B.px[i] + B.nx[i] * lat, B.py[i] + B.ny[i] * lat):
				clear = false
		if clear:
			gate_i = i
			break
	var i := gate_i
	var ch: Array = chunks[0]
	var hw: float = B.w[i] / 2.0 + 3.0
	var t := Vector3(B.tx[i], 0.0, -B.ty[i])
	var b := Basis(Vector3.UP, atan2(B.ty[i], B.tx[i]))   # thin along the line
	var mid := _q(ch[1], ch[2], i, 0.0, 0.0)
	var steel := Color(0.22, 0.23, 0.25)
	var parts := []
	for sd in [-1.0, 1.0]:
		var q := _q(ch[1], ch[2], i, sd * hw, 0.0)
		parts.append([Kit.box(Vector3(2.4, GATE_CLEAR + GATE_H + 4.0, 2.4)), Kit.at(q + Vector3(0, (GATE_CLEAR + GATE_H + 4.0) / 2.0, 0)), steel])
	var sc := mid + Vector3.UP * (GATE_CLEAR + GATE_H / 2.0 + 2.0)
	parts.append([Kit.box(Vector3(2.0, GATE_H + 4.0, hw * 2.0)), Transform3D(b, sc), Color(0.1, 0.1, 0.12)])
	var frame := MeshInstance3D.new()
	frame.mesh = Kit.compound(parts)
	frame.material_override = Kit.vertex_colors()
	(ch[0] as Node3D).add_child(frame)
	var facing := Basis(Vector3.UP, atan2(-B.tx[i], B.ty[i]))   # +Z toward the oncoming craft
	shut_sign = Node3D.new()
	open_sign = Node3D.new()
	for pair in [[shut_sign, "PRIVATE LINE", "NO ENTRY  /  AUTHORIZED JOBS ONLY"], [open_sign, "SPEED AUTHORIZED", "SHADE LINE OPEN  /  UNDER 1,250 MPH"]]:
		var sign: Node3D = pair[0]
		(ch[0] as Node3D).add_child(sign)
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(hw * 2.0 - 4.0, GATE_H)
		face.mesh = quad
		face.transform = Transform3D(facing, sc - t * 1.1)
		var m := ShaderMaterial.new()
		if sign == shut_sign:
			m.shader = preload("res://view/shade_gate.gdshader")
		else:
			m.shader = preload("res://view/authorized.gdshader")
			m.set_shader_parameter("col", Vector3(0.25, 0.65, 1.0))
		face.material_override = m
		sign.add_child(face)
		for line in [[pair[1], 150, 2.0], [pair[2], 60, -4.5]]:
			var l := Label3D.new()
			l.text = line[0]
			l.font_size = line[1]
			l.pixel_size = 0.05
			l.outline_size = 0
			l.modulate = Color(0.03, 0.03, 0.04)
			l.double_sided = false
			l.transform = Transform3D(facing, sc + Vector3.UP * float(line[2]) - t * 1.4)
			sign.add_child(l)
	gate_open = B.open
	shut_sign.visible = not gate_open
	open_sign.visible = gate_open
