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

var sim
var s := PackedFloat64Array()       # distance along the lap at each sample (s[N]: the lap)
var changes := PackedInt32Array()   # samples where the mode changes, ascending
var ahead := MIN_AHEAD


func setup(sm) -> void:
	sim = sm
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


static func target(v: float) -> float:
	return clampf(v * LOOK_S, MIN_AHEAD, MAX_AHEAD)


func mode_at(i: int) -> int:
	return sim.tmode[i] if i < sim.tmode.size() else 0


## This frame's map. `heading` is the way the view faces (radians, the sim's convention).
func update(heading: float, delta: float) -> Dictionary:
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	ahead = lerpf(ahead, target(v), 1.0 - exp(-delta / EASE_T))
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
	return f


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
	return {"segs": segs, "craft": craft, "zone": zone, "scale": sc, "dawn": dawn}


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
	if f.has("dawn"):
		var s := maxi(0, int(f.dawn.get("eta", 0.0)))
		out += ("
" if out != "" else "") + ("DAWN %d:%02d" % [s / 60, s % 60] if f.dawn.has("eta") else "UNDER COVER")
	return out
