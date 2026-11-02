## The path ahead, for the minimap overlays (Luke: "a minimap overlay of upcoming path"):
## vr/minimap_panel.gd in the headset, view/minimap_2d.gd on the flat view. Heading-up: the craft
## at the origin, x to its right, y ahead, in metres. It shows LOOK_S seconds of track at the
## current speed (MIN_AHEAD..MAX_AHEAD, eased so the zoom glides rather than jumps) and a little
## behind, each point tagged with its mode (0 a STARFIGHTER town, 1 the SPEEDCRAFT loop; tracks
## without modes are all 0), plus the next mode change: how far along the track, which mode, and
## where it is on the map. `layout` fits a frame onto a panel, clipped to its edges. On a job (the
## emergency run) the dawn's front too: its line across the map and the seconds until it lights the
## job's next stop (the lake town's pad on the way out, the start town's mouth on the way home).
##   var mm := MiniMap.new(); mm.setup(sim)           once
##   var f := mm.update(heading, delta)               every frame: {pts, modes, ahead, next[, dawn {a, b, eta}]}
##   var l := MiniMap.layout(f, w, h, margin, top)    {segs [[a, b, mode]], craft, zone, scale}
## On the Network (no one road ahead) the frame carries every road near the craft instead, as
## `lines` ([[points, modes], ...], from a grid of the roads built once), and the target city
## (`target`: {name, dist, at}); layout puts the target on the map, or on its rim toward it.
## By default there (`whole`; Luke: "make the minimap the whole extents") it's the whole country
## instead, north up: every road (`lines_w`, built once: panels draw them once), the jumps, the
## cities' GPs, the cities and their on-ramps (`marks_w`), the target, and the craft where it is,
## pointing its way. whole_layout fits it; layout hands a whole frame to it.
extends RefCounted

const LOOK_S := 12.0          # seconds of track ahead at the current speed
const MIN_AHEAD := 1500.0     # m from the craft to the map's top edge, slowest ...
const MAX_AHEAD := 25000.0    # ... and fastest (4,000 mph is ~21 km)
const BEHIND := 0.18          # this share of `ahead` shows behind the craft
const POINTS := 140           # path points per frame
const EASE_T := 0.8           # s: the zoom's time constant
const CRAFT_Y := 0.2          # the craft sits this far up the panel (share of its height)
const DAWN_HALF := 200000.0   # m each way along the dawn's front: its chord always spans the map
const DAWN_COL := Color(1.0, 0.78, 0.4)
const PAD_COL := Color(1.0, 0.18, 0.12)   # the medical pad's red cross
const TARGET_COL := Color(1.0, 0.86, 0.3)  # the Network's target city

var sim
var s := PackedFloat64Array()       # distance along the lap at each sample (s[N]: the lap)
var changes := PackedInt32Array()   # samples where the mode changes, ascending
var ahead := MIN_AHEAD
var target := -1                    # the Network: the target city (the view sets it), -1 none
var waypoint := {}                  # ... or a point in its place, {name, x, y} (off the roads: the nearest on-ramp)
var marks: Array = []               # the Network: [[x, y, kind], ...] traffic and the racer (the view sets them)
var _ngrid := {}                    # the Network: Vector2i(cell) -> [[road, i0, i1], ...]: runs of road in it
const NCELL := 8000.0
var whole := true                   # the Network: the whole country (else the roads near the craft, heading up)
var gp_cities: Array = []           # the cities with a GP (names; the view sets it): marked on the whole map
var _w_lines := []                  # the whole map's roads: [[points (m, from W_MID, north up), modes], ...]
var _w_marks := []                  # ... its marks: [[at, kind], ...] ("jump", "gp", "city", "ramp")
const W_MID := Vector2(300000.0, 300000.0)   # the country's middle
const W_HALF := 292000.0            # m: half the whole map's side (the roads run 25-575 km, the turnarounds a little past)
const W_STEP := 20                  # samples between the whole map's points (~480 m)
const JUMP_COL := Color(1.0, 0.55, 0.1)
const GP_COL := Color(1.0, 0.3, 0.75)
const RAMP_COL := Color(0.75, 0.35, 1.0)


func setup(sm) -> void:
	sim = sm
	ahead = MIN_AHEAD
	if sim.kind == "network":
		_net_setup()
		return
	var n: int = sim.N
	s.resize(n + 1)
	var acc := 0.0
	for i in n:
		s[i] = acc
		acc += sim.tlen[i]
	s[n] = acc
	changes.clear()
	for i in n:
		if mode_at(i) != mode_at(posmod(i - 1, n)):
			changes.append(i)
	ahead = MIN_AHEAD


static func target_ahead(v: float) -> float:
	return clampf(v * LOOK_S, MIN_AHEAD, MAX_AHEAD)


func mode_at(i: int) -> int:
	return sim.tmode[i] if i < sim.tmode.size() else 0


func _net_setup() -> void:
	_w_lines.clear()
	_w_marks.clear()
	for r in sim.roads.size():   # the whole map: every road, coarse
		var R = sim.roads[r]
		var pts := PackedVector2Array()
		var modes := PackedByteArray()
		var i := 0
		while true:
			pts.append(Vector2(R.px[i], R.py[i]) - W_MID)
			modes.append(R.mode[i])
			if i >= R.N - 1:
				break
			i = mini(i + W_STEP, R.N - 1)
		_w_lines.append([pts, modes])
	for jp in sim.jumps:   # each jump at its lip
		var L = sim.roads[int(jp[0])]
		_w_marks.append([Vector2(L.px[L.N - 1], L.py[L.N - 1]) - W_MID, "jump"])
	for op in sim.onramps:   # each on-ramp at its mouth
		var O = sim.roads[int(op[1])]
		_w_marks.append([Vector2(O.px[0], O.py[0]) - W_MID, "ramp"])
	for c in sim.cities:
		_w_marks.append([Vector2(c.cx, c.cy) - W_MID, "city"])
	_ngrid.clear()
	for r in sim.roads.size():
		var R = sim.roads[r]
		var i := 0
		while i < R.N - 1:
			var cell := Vector2i(int(floor(R.px[i] / NCELL)), int(floor(R.py[i] / NCELL)))
			var j := i
			while j < R.N - 1 and Vector2i(int(floor(R.px[j] / NCELL)), int(floor(R.py[j] / NCELL))) == cell:
				j += 4
			j = mini(j, R.N - 1)
			if not _ngrid.has(cell):
				_ngrid[cell] = []
			_ngrid[cell].append([r, i, j])
			i = j


## This frame's map. `heading` is the way the view faces (radians, the sim's convention).
func update(heading: float, delta: float) -> Dictionary:
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	ahead = lerpf(ahead, target_ahead(v), 1.0 - exp(-delta / EASE_T))
	if sim.kind == "network" and whole:
		return _whole_update(heading)
	if sim.kind == "network":
		return _net_update(heading)
	var n: int = sim.N
	var h: int = sim.pod.hint
	var fx := cos(heading)
	var fy := sin(heading)
	var per := s[n] / n   # mean sample spacing
	var step := maxi(1, roundi(ahead * (1.0 + BEHIND) / POINTS / per))
	var back := roundi(ahead * BEHIND / per)
	var fwd := roundi(ahead * 1.2 / per)   # past the top edge, so the line runs off it
	var pts := PackedVector2Array()
	var modes := PackedByteArray()
	var nxt := {}
	var i := -back
	if sim.pod.path > 0:
		# on a branch (the shade line): its own samples, the loop's before its split and after its join
		var B = sim.branches[sim.pod.path - 1]
		while i <= fwd:
			var k: int = h + i
			if k < 0:
				var m: int = posmod(B.from_i + k, n)
				pts.append(_local(m, fx, fy))
				modes.append(mode_at(m))
			elif k <= B.N - 1:
				pts.append(_local_xy(B.px[k], B.py[k], fx, fy))
				modes.append(0)   # a STARFIGHTER line
			else:
				var m: int = (B.join_i + k - (B.N - 1)) % n
				pts.append(_local(m, fx, fy))
				modes.append(mode_at(m))
			i += step
	else:
		while i <= fwd:
			var k := posmod(h + i, n)
			pts.append(_local(k, fx, fy))
			modes.append(mode_at(k))
			i += step
		var bd := INF
		for c in changes:
			var d := fposmod(s[c] - s[h], s[n])
			if d > 1.0 and d < bd:
				bd = d
				nxt = {"dist": d, "mode": mode_at(c), "at": _local(c, fx, fy)}
	var f := {"pts": pts, "modes": modes, "ahead": ahead, "next": nxt}
	var J: Dictionary = sim.job if "job" in sim else {}
	if not J.is_empty() and J.stage in ["out", "drop", "home"]:
		var t: float = 0.0 if J.t0 == null else sim.time - float(J.t0)
		var u := Vector2(cos(sim.P.dawnDir), sin(sim.P.dawnDir))
		var d: float = sim.P.dawnSpeed * (t - sim.P.dawnT0)   # the front: points with p.u < d are lit
		var off: float = sim.pod.x * u.x + sim.pod.y * u.y - d
		var cx: float = sim.pod.x - u.x * off
		var cy: float = sim.pod.y - u.y * off
		var dl: Dictionary = sim.job_deadline()   # the route's own deadline; empty under cover
		f["dawn"] = {"a": _local_xy(cx - u.y * DAWN_HALF, cy + u.x * DAWN_HALF, fx, fy),
			"b": _local_xy(cx + u.y * DAWN_HALF, cy - u.x * DAWN_HALF, fx, fy)}
		if not dl.is_empty():
			f.dawn["eta"] = sim.t_lit(dl.x, dl.y) - t
		if J.stage == "out" and sim.pod.path == 0:
			f["pad"] = _local(sim.pad, fx, fy)   # the medical pad, marked on the way out
	return f


## The Network's frame: the roads within reach of the craft, each run a polyline (a point every
## `step` samples, coarser as the map zooms out), and the target city. Only the cells that can
## reach the map: a square panel's frame (craft CRAFT_Y up it, margin and readout band under 15% of
## its side) spans at most 0.77 ahead either side and 0.31 behind, inside a circle of 1.02 ahead
## round the point 0.35 ahead; cells within VIS_R of it (a run's points stray 4 samples out of its
## cell). The 2.7-ahead square this used to walk cost ~0.5 ms at the centre crossing.
const VIS_R := 1.1
func _net_update(heading: float) -> Dictionary:
	var fx := cos(heading)
	var fy := sin(heading)
	var step := maxi(4, int(ahead / 60.0 / 24.0))
	var lines := []
	var ox: float = sim.pod.x
	var oy: float = sim.pod.y
	var cx := ox + fx * ahead * 0.35   # the map's middle
	var cy := oy + fy * ahead * 0.35
	var rad := ahead * VIS_R + 200.0
	var lo := Vector2i(int(floor((cx - rad) / NCELL)), int(floor((cy - rad) / NCELL)))
	var hi := Vector2i(int(floor((cx + rad) / NCELL)), int(floor((cy + rad) / NCELL)))
	for gx in range(lo.x, hi.x + 1):
		for gy in range(lo.y, hi.y + 1):
			# the nearest point of the cell's box to the map's middle
			var nx := clampf(cx, gx * NCELL, (gx + 1) * NCELL) - cx
			var ny := clampf(cy, gy * NCELL, (gy + 1) * NCELL) - cy
			if nx * nx + ny * ny > rad * rad:
				continue
			for run in _ngrid.get(Vector2i(gx, gy), []):
				var R = sim.roads[run[0]]
				var px: PackedFloat64Array = R.px
				var py: PackedFloat64Array = R.py
				var md: PackedByteArray = R.mode
				var pts := PackedVector2Array()
				var modes := PackedByteArray()
				var i: int = run[1]
				var i1: int = run[2]
				while true:
					var dx: float = px[i] - ox   # _local_xy, inline
					var dy: float = py[i] - oy
					pts.append(Vector2(dx * fy - dy * fx, dx * fx + dy * fy))
					modes.append(md[i])
					if i >= i1:
						break
					i = mini(i + step, i1)
				lines.append([pts, modes])
	var f := {"pts": PackedVector2Array(), "modes": PackedByteArray(), "ahead": ahead, "next": {}, "lines": lines}
	var mk := []
	for m in marks:
		mk.append([_local_xy(m[0], m[1], fx, fy), int(m[2])])
	f["marks"] = mk
	if not waypoint.is_empty():
		f["target"] = {"name": waypoint.name, "dist": Vector2(float(waypoint.x) - sim.pod.x, float(waypoint.y) - sim.pod.y).length(), "at": _local_xy(float(waypoint.x), float(waypoint.y), fx, fy)}
	elif target >= 0 and target < sim.cities.size():
		var c: Dictionary = sim.cities[target]
		f["target"] = {"name": c.name, "dist": Vector2(c.cx - sim.pod.x, c.cy - sim.pod.y).length(), "at": _local_xy(c.cx, c.cy, fx, fy)}
	return f


## The whole country's frame: the roads and marks (built once), the GP cities' marks, the craft
## where it is pointing `heading`, the target.
func _whole_update(heading: float) -> Dictionary:
	var mk: Array = _w_marks.duplicate()
	for c in sim.cities:
		if gp_cities.has(c.name):
			mk.append([Vector2(c.cx, c.cy) - W_MID, "gp"])
	var f := {"pts": PackedVector2Array(), "modes": PackedByteArray(), "ahead": ahead, "next": {}, "whole": true,
		"lines_w": _w_lines, "half": W_HALF, "marks_w": mk,
		"craft_at": Vector2(sim.pod.x, sim.pod.y) - W_MID, "craft_dir": Vector2(cos(heading), sin(heading))}
	if not waypoint.is_empty():
		f["target"] = {"name": waypoint.name, "dist": Vector2(float(waypoint.x) - sim.pod.x, float(waypoint.y) - sim.pod.y).length(), "at_w": Vector2(float(waypoint.x), float(waypoint.y)) - W_MID}
	elif target >= 0 and target < sim.cities.size():
		var tc: Dictionary = sim.cities[target]
		f["target"] = {"name": tc.name, "dist": Vector2(tc.cx - sim.pod.x, tc.cy - sim.pod.y).length(), "at_w": Vector2(tc.cx, tc.cy) - W_MID}
	return f


## A whole-country frame fitted onto a w x h panel (as layout): north up, the country square in the
## frame under the readout's band. `with_roads` false leaves the roads out (a panel that drew them
## once). -> {segs, craft, craft_dir, target, marks [[where, kind]], scale, whole}
static func whole_layout(f: Dictionary, w: float, h: float, margin: float, top: float, with_roads := true) -> Dictionary:
	var y0 := -h / 2.0 + margin
	var y1 := h / 2.0 - margin - top
	var hw := w / 2.0 - margin
	var mid := Vector2(0.0, (y0 + y1) / 2.0)
	var sc: float = minf(hw, (y1 - y0) / 2.0) / float(f.half)
	var segs := []
	if with_roads:
		for ln in f.lines_w:
			var lp: PackedVector2Array = ln[0]
			var lm: PackedByteArray = ln[1]
			for k in lp.size() - 1:
				segs.append([mid + lp[k] * sc, mid + lp[k + 1] * sc, lm[k]])
	var marks := []
	for m in f.marks_w:
		marks.append([mid + (m[0] as Vector2) * sc, m[1]])
	var tgt = null
	if f.has("target"):
		tgt = [mid + (f.target.at_w as Vector2) * sc, true]
	return {"segs": segs, "craft": mid + (f.craft_at as Vector2) * sc, "craft_dir": f.craft_dir, "target": tgt, "marks": marks,
		"scale": sc, "whole": true, "zone": null, "dawn": null, "pad": null, "dots": []}


## Sample k relative to the craft: x to its right, y ahead (64-bit until the subtraction).
func _local(k: int, fx: float, fy: float) -> Vector2:
	return _local_xy(sim.tpx[k], sim.tpy[k], fx, fy)


func _local_xy(x: float, y: float, fx: float, fy: float) -> Vector2:
	var dx: float = x - sim.pod.x
	var dy: float = y - sim.pod.y
	return Vector2(dx * fy - dy * fx, dx * fx + dy * fy)


## A frame fitted onto a w x h panel (origin at its centre, y up), `margin` in from every edge
## and `top` more off the top (room for the readout): the path cut into segments [a, b, mode]
## clipped to that frame, the craft's spot, and the next change's spot (null when off the map).
static func layout(f: Dictionary, w: float, h: float, margin: float, top: float) -> Dictionary:
	if f.has("whole"):
		return whole_layout(f, w, h, margin, top)
	var y0 := -h / 2.0 + margin
	var y1 := h / 2.0 - margin - top
	var hw := w / 2.0 - margin
	var craft := Vector2(0.0, -h / 2.0 + h * CRAFT_Y)
	var sc: float = (y1 - craft.y) / float(f.ahead)
	var segs := []
	var pts: PackedVector2Array = f.pts
	var modes: PackedByteArray = f.modes
	for k in pts.size() - 1:
		var seg := clip(craft + pts[k] * sc, craft + pts[k + 1] * sc, hw, y0, y1)
		if not seg.is_empty():
			segs.append([seg[0], seg[1], modes[k]])
	var zone = null
	if not (f.next as Dictionary).is_empty():
		var z: Vector2 = craft + (f.next.at as Vector2) * sc
		if absf(z.x) <= hw and z.y >= y0 and z.y <= y1:
			zone = z
	var dawn = null
	if f.has("dawn"):
		var cut := clip(craft + (f.dawn.a as Vector2) * sc, craft + (f.dawn.b as Vector2) * sc, hw, y0, y1)
		if not cut.is_empty():
			dawn = [cut[0], cut[1]]
	var pad = null
	if f.has("pad"):
		var q: Vector2 = craft + (f.pad as Vector2) * sc
		if absf(q.x) <= hw and q.y >= y0 and q.y <= y1:
			pad = q
	for ln in f.get("lines", []):   # the Network: every road near the craft (hundreds of segments at a
		var lp: PackedVector2Array = ln[0]   # crossing: those wholly off one side are dropped and those
		var lm: PackedByteArray = ln[1]      # wholly inside kept, unclipped)
		var pa: Vector2 = craft + lp[0] * sc
		for k in lp.size() - 1:
			var pb: Vector2 = craft + lp[k + 1] * sc
			if not ((pa.x < -hw and pb.x < -hw) or (pa.x > hw and pb.x > hw) or (pa.y < y0 and pb.y < y0) or (pa.y > y1 and pb.y > y1)):
				if absf(pa.x) <= hw and absf(pb.x) <= hw and pa.y >= y0 and pa.y <= y1 and pb.y >= y0 and pb.y <= y1:
					segs.append([pa, pb, lm[k]])
				else:
					var seg := clip(pa, pb, hw, y0, y1)
					if not seg.is_empty():
						segs.append([seg[0], seg[1], lm[k]])
			pa = pb
	var dots := []   # the Network's traffic on the map: [where, kind]
	for m in f.get("marks", []):
		var q: Vector2 = craft + (m[0] as Vector2) * sc
		if absf(q.x) <= hw and q.y >= y0 and q.y <= y1:
			dots.append([q, m[1]])
	var tgt = null   # [where, on the map]: on the map, or on its rim toward the target
	if f.has("target"):
		var q: Vector2 = craft + (f.target.at as Vector2) * sc
		if absf(q.x) <= hw and q.y >= y0 and q.y <= y1:
			tgt = [q, true]
		else:
			var d := q - craft
			var t := INF
			if d.x != 0.0:
				t = minf(t, hw * signf(d.x) / d.x)
			if d.y > 0.0:
				t = minf(t, (y1 - craft.y) / d.y)
			elif d.y < 0.0:
				t = minf(t, (y0 - craft.y) / d.y)
			tgt = [craft + d * t, false]
	return {"segs": segs, "craft": craft, "zone": zone, "scale": sc, "dawn": dawn, "pad": pad, "target": tgt, "dots": dots}


## Segment a-b cut to the box |x| <= hw, y0 <= y <= y1 (Liang-Barsky); empty if it misses.
static func clip(a: Vector2, b: Vector2, hw: float, y0: float, y1: float) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	for e in [[-d.x, a.x + hw], [d.x, hw - a.x], [-d.y, a.y - y0], [d.y, y1 - a.y]]:
		var p: float = e[0]
		var q: float = e[1]
		if p == 0.0:
			if q < 0.0:
				return PackedVector2Array()
			continue
		var r := q / p
		if p < 0.0:
			if r > t1:
				return PackedVector2Array()
			t0 = maxf(t0, r)
		else:
			if r < t0:
				return PackedVector2Array()
			t1 = minf(t1, r)
	return PackedVector2Array([a + d * t0, a + d * t1])


## The readout: where the next mode change is ("" on tracks without modes), and on a job how long
## until the dawn lights its next stop (DAWN m:ss).
static func readout(f: Dictionary) -> String:
	var out := ""
	if not (f.next as Dictionary).is_empty():
		var mi: float = f.next.dist / 1609.344
		var far := ("%.1f mi" % mi) if mi >= 0.2 else ("%d ft" % (roundi(mi * 5280.0 / 50.0) * 50))
		out = "%s  %s" % ["STARFIGHTER" if int(f.next.mode) == 0 else "SPEEDCRAFT", far]
	if f.has("target"):
		var tm: float = f.target.dist / 1609.344
		out = "%s  %s" % [f.target.name, ("%.0f mi" % tm) if tm >= 10.0 else ("%.1f mi" % tm)]
	if f.has("dawn"):
		var s := maxi(0, int(f.dawn.get("eta", 0.0)))
		out += ("
" if out != "" else "") + ("DAWN %d:%02d" % [s / 60, s % 60] if f.dawn.has("eta") else "UNDER COVER")
	return out
