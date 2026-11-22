## The title's lettering (Luke, 2026-11-22, with a box-cover picture: "work on a title screen using this
## as a reference"): PHAETHON in heavy italic slab capitals as solid letters, cream faces over a tan
## bevel line, orange-red sides, and the orange stroke under the word. The seven letters are drawn here
## as outlines (no font: nothing to license), in cap heights: x to the right, y up from the baseline,
## the faces toward +z and the letters' depth behind them.
##   TitleLetters.word("PHAETHON") -> ArrayMesh     one surface, vertex colours (draw it unshaded)
##   TitleLetters.width("PHAETHON") -> float        the word's width at the baseline, cap heights
extends RefCounted

const STEM := 0.335       # a stem's width, before SQUEEZE
const SLAB := 0.19        # a slab serif's height
const OVER := 0.07        # ... and how far it stands out past its stem
const SQUEEZE := 0.80     # the letters are drawn square and set this much narrower
const SLANT := 0.21       # the italic: m to the right per m up (12 degrees)
const GAP := 0.055        # between letters
const DEPTH := 0.34       # front face to back
const BEVEL := 0.024      # the tan line round each face
const PROUD := 0.012      # ... which the cream face stands this far in front of
const CREAM := Color(0.97, 0.90, 0.72)
const TAN := Color(0.86, 0.56, 0.26)
const SIDE := Color(0.93, 0.31, 0.07)        # the sides that face left and right
const UNDER := Color(0.70, 0.14, 0.05)       # ... down
const OVERHEAD := Color(0.98, 0.50, 0.14)    # ... and up
const BACK := Color(0.42, 0.10, 0.04)
const STROKE := Color(0.98, 0.52, 0.10)
const STROKE_UNDER := Color(0.72, 0.26, 0.04)


## A letter upright and unsqueezed: {w: its width, outer: its outline, holes: [each counter's outline]}.
static func glyph(letter: String) -> Dictionary:
	var s := STEM
	var t := SLAB
	var v := OVER
	var foot := s + 2.0 * v      # a stem's slab, end to end
	match letter:
		"P":
			var w := 1.00
			var yb := 0.37
			var c := 0.13
			return {"w": w, "outer": _pts([0, 0, foot, 0, foot, t, v + s, t, v + s, yb, w - c, yb, w, yb + c, w, 1.0 - c, w - c, 1,
				0, 1, 0, 1.0 - t, v, 1.0 - t, v, t, 0, t]),
				"holes": [_pts([v + s, yb + 0.20, w - 0.35, yb + 0.20, w - 0.30, yb + 0.25, w - 0.30, 0.75, w - 0.35, 0.80, v + s, 0.80])]}
		"H":
			var w := 1.12
			var b := 0.22
			return {"w": w, "outer": _pts([0, 0, foot, 0, foot, t, v + s, t, v + s, 0.5 - b / 2.0, w - v - s, 0.5 - b / 2.0, w - v - s, t, w - foot, t,
				w - foot, 0, w, 0, w, t, w - v, t, w - v, 1.0 - t, w, 1.0 - t, w, 1, w - foot, 1, w - foot, 1.0 - t, w - v - s, 1.0 - t,
				w - v - s, 0.5 + b / 2.0, v + s, 0.5 + b / 2.0, v + s, 1.0 - t, foot, 1.0 - t, foot, 1, 0, 1, 0, 1.0 - t, v, 1.0 - t, v, t, 0, t]), "holes": []}
		"A":
			var w := 1.16
			var top0 := 0.37                               # the flat top's left end
			var k := (top0 - v) / (1.0 - t)                # a leg's lean: m across per m up
			var bar0 := 0.25                               # the crossbar, bottom and top
			var bar1 := 0.45
			var in0 := v + s + k * (bar0 - t)              # the left leg's inner edge at the bar's bottom ...
			var in1 := v + s + k * (bar1 - t)              # ... and at its top
			var apex := t + (w / 2.0 - v - s) / k          # where the two inner edges meet
			return {"w": w, "outer": _pts([0, 0, foot, 0, foot, t, v + s, t, in0, bar0, w - in0, bar0, w - v - s, t, w - foot, t, w - foot, 0,
				w, 0, w, t, w - v, t, w - top0, 1, top0, 1, v, t, 0, t]),
				"holes": [_pts([in1, bar1, w - in1, bar1, w / 2.0, apex])]}
		"E":
			var w := 0.94
			var tip := 0.19
			return {"w": w, "outer": _pts([0, 0, w, 0, w, 0.36, w - tip, 0.36, w - tip, 0.20, v + s, 0.20, v + s, 0.40, 0.70, 0.40, 0.70, 0.60,
				v + s, 0.60, v + s, 0.80, w - tip, 0.80, w - tip, 0.64, w, 0.64, w, 1, 0, 1, 0, 1.0 - t, v, 1.0 - t, v, t, 0, t]), "holes": []}
		"T":
			var w := 1.00
			var x0 := (w - s) / 2.0
			var tip := 0.19
			return {"w": w, "outer": _pts([x0 - v, 0, x0 + s + v, 0, x0 + s + v, t, x0 + s, t, x0 + s, 0.79, w - tip, 0.79, w - tip, 0.62, w, 0.62,
				w, 1, 0, 1, 0, 0.62, tip, 0.62, tip, 0.79, x0, 0.79, x0, t, x0 - v, t]), "holes": []}
		"O":
			var w := 1.06
			return {"w": w, "outer": _round_box(0.0, 0.0, w, 1.0, 0.36), "holes": [_round_box(0.345, 0.215, w - 0.345, 0.785, 0.13)]}
		"N":
			var w := 1.16
			return {"w": w, "outer": _pts([0, 0, foot, 0, foot, t, v + s, t, v + s, 0.5, w - v - s, 0, w - v, 0, w - v, 1.0 - t, w, 1.0 - t, w, 1,
				w - foot, 1, w - foot, 1.0 - t, w - v - s, 1.0 - t, w - v - s, 0.5, v + s, 1, 0, 1, 0, 1.0 - t, v, 1.0 - t, v, t, 0, t]), "holes": []}
	return {}


static func _pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return out


static func _round_box(x0: float, y0: float, x1: float, y1: float, r: float, steps := 7) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in [[x1 - r, y0 + r, -PI / 2.0], [x1 - r, y1 - r, 0.0], [x0 + r, y1 - r, PI / 2.0], [x0 + r, y0 + r, PI]]:
		for i in steps + 1:
			var a: float = float(corner[2]) + PI / 2.0 * float(i) / float(steps)
			out.append(Vector2(float(corner[0]) + r * cos(a), float(corner[1]) + r * sin(a)))
	return out


static func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return sum / 2.0


## The outline turned so the letter's metal is on its left as it runs (`solid`: an outer edge; else a counter's).
static func _wound(poly: PackedVector2Array, solid: bool) -> PackedVector2Array:
	if (_area(poly) > 0.0) == solid:
		return poly
	var out := poly.duplicate()
	out.reverse()
	return out


## A letter set in its place: squeezed, leaned and moved x0 along the baseline.
static func _placed(poly: PackedVector2Array, x0: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(x0 + p.x * SQUEEZE + p.y * SLANT, p.y))
	return out


static func width(text: String) -> float:
	var x := 0.0
	for i in text.length():
		var g := glyph(text[i])
		if not g.is_empty():
			x += float(g.w) * SQUEEZE + (GAP if i < text.length() - 1 else 0.0)
	return x


## A face with its counters cut out, as polygons with no holes in them (the engine's triangulator takes
## none): each counter in turn halves the pieces it lies in along a level line through its middle.
static func _pieces(outer: PackedVector2Array, holes: Array) -> Array:
	var pieces: Array = [outer]
	for hole: PackedVector2Array in holes:
		var lo := INF
		var hi := -INF
		for p in hole:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
		var mid := (lo + hi) / 2.0
		var next: Array = []
		for piece: PackedVector2Array in pieces:
			for half in [PackedVector2Array([Vector2(-50, mid), Vector2(50, mid), Vector2(50, 50), Vector2(-50, 50)]),
					PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, mid), Vector2(-50, mid)])]:
				for part: PackedVector2Array in Geometry2D.intersect_polygons(piece, half):
					for cut: PackedVector2Array in Geometry2D.clip_polygons(part, hole):
						if absf(_area(cut)) > 1e-6:
							next.append(cut)
		pieces = next
	return pieces


static func _face(st: SurfaceTool, poly: PackedVector2Array, z: float, colour: Color, normal: Vector3) -> int:
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in tris:
		st.set_color(colour)
		st.set_normal(normal)
		st.add_vertex(Vector3(poly[i].x, poly[i].y, z))
	return tris.size() / 3


static func _walls(st: SurfaceTool, loop: PackedVector2Array, z0: float, z1: float, side: Color, under: Color, over: Color) -> void:
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var n := Vector2(b.y - a.y, a.x - b.x).normalized()      # (the metal is on the left of a to b: out is to its right)
		var colour := side
		if n.y < -0.6:
			colour = under
		elif n.y > 0.6:
			colour = over
		for p in [[a, z0], [b, z0], [b, z1], [a, z0], [b, z1], [a, z1]]:
			st.set_color(colour)
			st.set_normal(Vector3(n.x, n.y, 0.0))
			st.add_vertex(Vector3((p[0] as Vector2).x, (p[0] as Vector2).y, float(p[1])))


## The word as one mesh, its baseline's left end at the origin: each letter's back, its sides, its tan
## face and the cream face a bevel's width inside that; with `stroke`, the orange stroke under it all.
static func word(text: String, stroke := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := 0.0
	for i in text.length():
		var g := glyph(text[i])
		if g.is_empty():
			continue
		var outer := _wound(_placed(g.outer, x), true)
		var holes: Array = []
		for h: PackedVector2Array in g.holes:
			holes.append(_wound(_placed(h, x), false))
		_walls(st, outer, 0.0, -DEPTH, SIDE, UNDER, OVERHEAD)
		for h: PackedVector2Array in holes:
			_walls(st, h, 0.0, -DEPTH, SIDE, UNDER, OVERHEAD)
		for piece: PackedVector2Array in _pieces(outer, holes):
			_face(st, piece, 0.0, TAN, Vector3.BACK)
			_face(st, piece, -DEPTH, BACK, Vector3.FORWARD)
		# the cream face: the outline drawn in by the bevel, the counters let out by it
		var inner_holes: Array = []
		for h: PackedVector2Array in holes:
			for grown: PackedVector2Array in Geometry2D.offset_polygon(h, BEVEL, Geometry2D.JOIN_MITER):
				inner_holes.append(grown)
		for inner: PackedVector2Array in Geometry2D.offset_polygon(outer, -BEVEL, Geometry2D.JOIN_MITER):
			for piece: PackedVector2Array in _pieces(_wound(inner, true), inner_holes):
				_face(st, piece, PROUD, CREAM, Vector3.BACK)
		x += float(g.w) * SQUEEZE + GAP
	if stroke:
		# the stroke: a long thin bar leaning with the letters, pointed at its left end
		var x0 := -0.50
		var x1 := x - GAP + 0.34
		var y0 := -0.36
		var th := 0.115
		var bar := PackedVector2Array([Vector2(x0 + y0 * SLANT, y0 + th * 0.5), Vector2(x0 + 0.9 + y0 * SLANT, y0),
			Vector2(x1 + y0 * SLANT, y0), Vector2(x1 + (y0 + th) * SLANT, y0 + th), Vector2(x0 + 0.9 + (y0 + th) * SLANT, y0 + th)])
		bar = _wound(bar, true)
		_walls(st, bar, 0.0, -DEPTH * 0.45, STROKE_UNDER, STROKE_UNDER, OVERHEAD)
		_face(st, bar, 0.0, STROKE, Vector3.BACK)
		_face(st, bar, -DEPTH * 0.45, BACK, Vector3.FORWARD)
	return st.commit()
