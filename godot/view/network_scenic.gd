## The land beside the Network's scenic roads (Luke, 2026-11-19: "a track that drives along the side
## of a mountain, with the beach on one side. Then maybe another with a massive vertical drop into
## the valley below ... Pacific Northwest coastal highway but at speed").
## CraftSim.NET_SCENIC (tools/design_network.py's SCENIC) gives, at stations along each road, the
## height the land reaches on its left and its right and over how far, and how far the land's edge
## lies under the deck (a viaduct's air). From that:
##   land(vertex, p)   what the terrain's grid stands at there: Vector2(how much of it is this road's
##                     doing 0..1, its height). Everything within UNDER of a deck is held under it.
##   row(road, i, left) the same land across one side at a sample, finely: the road's own mesh out to
##                     FLANK (view/network_world.gd builds it), because a 512 m grid can't hold a cliff.
##   open(road, i, left) the land falls away on that side: the road's edge there is see-through.
##   is_sea(p)         west of the coast road's waterline, the whole length of the map.
## A side whose land is lower than the road falls from the deck's edge to it (a cliff, then a floor);
## higher, it rises over the road (a rock cut, then the mountainside); the coast road's sea side is
## a cliff down to a beach and the water, behind a shelf of low ground where the road is inland.
extends RefCounted

const SEA := -2.0            # sea level (where the wetlands' water stands too)
const FLOOR := -4.0          # the seabed, and the open ground everywhere else
const BERM := 3.5            # the top of the beach
const CELL := 2048.0
const REACH := 5             # cells either side of the road that know of it (~10 km)
const FLOOR_W := 2200.0      # a fall's floor runs this far before the country comes back
const BLEND := 4500.0        # ... which it does over this
const UNDER := 840.0         # the terrain's 512 m triangles within this of a deck's edge could cross it
const SINK := 14.0           # the terrain lies this far under the road's own land, so only one of them shows
const FLANK := 1600.0        # the road's own land reaches this far from its edge
const END := 120.0           # samples at each end over which the road's doing fades in
const OFFS := [0.0, 14.0, 40.0, 110.0, 260.0, 520.0, 900.0, 1300.0, 1600.0, 1900.0]
const SAND := Color(0.74, 0.68, 0.52, 0.0)
const STEP := 512.0          # the terrain's grid (NetworkLandscape.STEP)
const Helios := preload("res://view/helios.gd")
const MOUNTAIN := "SHelios"  # this road's land is the mountain's own surface (view/helios.gd), with the road a bench in it
const EASE := 220.0          # m from the deck's edge over which that bench's cut and fill meet the slope
const SPAN := 512            # samples in each stretch a hint is looked for in (a multiple of 32, the samples a hint looks at)
const LAP_SURE := 2800.0     # m: nearer the mountain's road than this, the lap found is the nearest there is (its laps lie 6 km apart)

var sim
var roads := {}              # road -> {first, last, sea, hw, e, h, tl, rl, tr, rr, gap} (arrays from `first`)
var hints := {}              # cell -> [road, sample, its distance squared], the scenic sample nearest that cell ([] for none in reach): found when first asked (_hint)
var boxes: Array[Rect2i] = []   # the cells each road's hints cover: nothing outside them is asked anything more
var coast_hi := -INF         # the easternmost the waterline gets: nothing east of it is the sea
var coast := PackedFloat32Array()   # the waterline's x at each COAST_STEP of y, from coast_y0
var coast_y0 := 0.0
const COAST_STEP := 256.0
var _cache := {}             # terrain vertex -> Vector2(weight, height)
var _noise := FastNoiseLite.new()


func setup(s, heights := []) -> void:   # heights: the world's own per-sample heights, road by road (worked out again without them)
	sim = s
	_noise.seed = 9917
	_noise.frequency = 1.0 / 900.0
	_noise.fractal_octaves = 3
	for entry in s.NET_SCENIC:
		var r := int(entry[0])
		if r >= s.roads.size():
			continue   # (a test's cut-down network: no such road)
		var R = s.roads[r]
		var st: Array = entry[2]
		var first := int(st[0][0])
		var last := int(st[st.size() - 1][0])
		var n := last - first + 1
		var D := {"first": first, "last": last, "sea": int(entry[1]), "hw": float(R.w[first]) / 2.0, "e": s.net_edge_span(float(R.w[first]))}
		if String(R.name) == MOUNTAIN:
			D["mountain"] = true
		for key in ["h", "tl", "rl", "tr", "rr", "gap"]:
			var a := PackedFloat32Array()
			a.resize(n)
			D[key] = a
		var k := 0
		for i in range(first, last + 1):
			while k < st.size() - 2 and i >= int(st[k + 1][0]):
				k += 1
			var a: Array = st[k]
			var b: Array = st[k + 1]
			var u := smoothstep(0.0, 1.0, clampf(float(i - int(a[0])) / float(int(b[0]) - int(a[0])), 0.0, 1.0))
			D.h[i - first] = heights[r][i] if r < heights.size() else s.net_height(r, float(i))
			D.tl[i - first] = lerpf(a[1], b[1], u)
			D.rl[i - first] = lerpf(a[2], b[2], u)
			D.tr[i - first] = lerpf(a[3], b[3], u)
			D.rr[i - first] = lerpf(a[4], b[4], u)
			D.gap[i - first] = lerpf(a[5], b[5], u)
		roads[r] = D
		var box := Rect2i(int(floor(R.px[first] / CELL)), int(floor(R.py[first] / CELL)), 1, 1)
		for i in range(first, last + 1, 32):
			var cx := int(floor(R.px[i] / CELL))
			var cy := int(floor(R.py[i] / CELL))
			box = box.expand(Vector2i(cx - REACH, cy - REACH)).expand(Vector2i(cx + REACH + 1, cy + REACH + 1))
		boxes.append(box)
		D["box"] = box
		# its samples in stretches of SPAN, each with the ground a hint could be asked for from (_hint looks only at
		# the stretches near a cell: the mountain's road is 15,500 samples, and every new cell walked all of them)
		var reach := (REACH + 0.75) * CELL
		var spans := []
		for i0 in range(first, last + 1, SPAN):
			var i1 := mini(i0 + SPAN - 32, last)
			var ground := Rect2(R.px[i0], R.py[i0], 0.0, 0.0)
			for i in range(i0, i1 + 1, 32):
				ground = ground.expand(Vector2(R.px[i], R.py[i]))
			spans.append([i0, i1, ground.grow(reach)])
		D["spans"] = spans
		if int(D.sea) != 0:
			_trace_coast(r)
			for x in coast:
				coast_hi = maxf(coast_hi, x)


## The waterline's x by y: along the sea stretch the shore the road's own land comes down to,
## and north and south of it straight on, so the sea runs the length of the map.
func _trace_coast(r: int) -> void:
	var D: Dictionary = roads[r]
	var R = sim.roads[r]
	var pts := []
	for i in range(int(D.first), int(D.last) + 1, 4):
		var q := i - int(D.first)
		var shelf: float = (D.rl if int(D.sea) > 0 else D.rr)[q]
		if not _sea_at(D, q, int(D.sea) > 0):
			continue   # (the flat ends: no sea side yet)
		var top := _shore_top(D.h[q], shelf)
		var off: float = float(D.hw) - float(D.e) + shelf + _cliff_run(top) + 0.95 * _beach(top)
		var sgn := float(int(D.sea))
		pts.append(Vector2(R.px[i] + R.nx[i] * sgn * off, R.py[i] + R.ny[i] * sgn * off))
	if pts.size() < 2:
		return
	coast_y0 = pts[0].y
	var n := int(ceil((pts[pts.size() - 1].y - coast_y0) / COAST_STEP)) + 1
	coast.resize(n)
	var k := 0
	for m in n:
		var y := coast_y0 + m * COAST_STEP
		while k < pts.size() - 2 and (pts[k + 1] as Vector2).y < y:
			k += 1
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		coast[m] = lerpf(a.x, b.x, clampf((y - a.y) / maxf(1.0, b.y - a.y), 0.0, 1.0))


func coast_x(y: float) -> float:
	var f := clampf((y - coast_y0) / COAST_STEP, 0.0, float(coast.size() - 1))
	var m := mini(int(f), coast.size() - 2)
	return lerpf(coast[m], coast[m + 1], f - float(m))


func is_sea(p: Vector2) -> bool:
	return p.x < coast_hi and p.x < coast_x(p.y)


func on(r: int, i: int) -> bool:
	return roads.has(r) and i >= int(roads[r].first) and i <= int(roads[r].last)


## Does the land fall away on that side of road r's sample i (its edge there is open: see-through)?
func open(r: int, i: int, left: bool) -> bool:
	if not on(r, i):
		return false
	var D: Dictionary = roads[r]
	var q := i - int(D.first)
	return _sea_at(D, q, left) or (D.tl if left else D.tr)[q] < D.h[q] - 12.0


## Is that side of the road the sea's at its q-th scenic sample? (The table's height there is under
## the open ground's: -5 at a sea station, easing from a flat end's -4.)
func _sea_at(D: Dictionary, q: int, left: bool) -> bool:
	return int(D.sea) == (1 if left else -1) and (D.tl if left else D.tr)[q] < FLOOR - 0.5


## The scenic sample nearest a cell ([road, sample, distance squared]), or [] with none within reach
## of it: found the first time the cell is asked about, and kept (stamping every cell round every
## road at the start was 79,000 writes and a tenth of a second of the world's set-up).
func _hint(cell: Vector2i) -> Array:
	var had = hints.get(cell)
	if had != null:
		return had
	var best := []
	var centre := Vector2((cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL)
	var limit := (REACH + 0.75) * CELL
	for r in roads:
		var D: Dictionary = roads[r]
		if not (D.box as Rect2i).has_point(cell):
			continue
		var R = sim.roads[r]
		var bd := limit * limit
		var bi := -1
		for span in D.spans:
			if not (span[2] as Rect2).has_point(centre):
				continue
			for i in range(int(span[0]), int(span[1]) + 1, 32):
				var d := Vector2(R.px[i] - centre.x, R.py[i] - centre.y).length_squared()
				if d < bd:
					bd = d
					bi = i
		if bi >= 0 and (best.is_empty() or bd < float(best[2])):
			best = [r, bi, bd]
	hints[cell] = best
	return best


## Is p on the road's own land (within FLANK of a scenic road's edge)? The terrain is sunk under
## it there, so nothing may be stood on the terrain.
func covered(p: Vector2) -> bool:
	var hint := _hint(Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))))
	if hint.is_empty():
		return false
	var r := int(hint[0])
	var D: Dictionary = roads[r]
	var R = sim.roads[r]
	var i := _nearest(R, D, p, int(hint[1]))
	if D.has("mountain"):
		i = _nearest_lap(r, p, Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL))), i)
	return absf((p.x - R.px[i]) * R.nx[i] + (p.y - R.py[i]) * R.ny[i]) < float(D.hw) + FLANK + 120.0 and Vector2(R.px[i] - p.x, R.py[i] - p.y).length() < float(D.hw) + FLANK + 200.0


func sea_side(r: int, i: int, left: bool) -> bool:
	return on(r, i) and _sea_at(roads[r], i - int(roads[r].first), left)


## A viaduct there: nothing but air under the deck (it gets its piers back).
func bridged(r: int, i: int) -> bool:
	return on(r, i) and roads[r].gap[i - int(roads[r].first)] > 60.0


static func _shore_top(h: float, shelf: float) -> float:
	return lerpf(h - 1.0, minf(h - 1.0, 9.0), smoothstep(0.0, 300.0, shelf))


static func _cliff_run(top: float) -> float:
	return 30.0 + 0.75 * maxf(0.0, top - BERM)


static func _beach(top: float) -> float:
	return clampf(260.0 - top, 60.0, 260.0)


## The land `d` m out from the deck's edge on one side, where the road is `h` up and that side's land
## reaches `target` over `run`: Vector2(how much of this is the road's doing, the height).
func _side(h: float, target: float, run: float, gap: float, sea: bool, d: float) -> Vector2:
	d = maxf(d, 0.0)
	if sea:
		var shelf := run
		var top := _shore_top(h, shelf)
		if d < shelf:
			return Vector2(1.0, lerpf(h - 1.0, top, smoothstep(0.0, minf(shelf, 300.0), d)))
		d -= shelf
		var rc := _cliff_run(top)
		if d < rc:
			return Vector2(1.0, top + (BERM - top) * (1.0 - pow(1.0 - d / rc, 2.2)))
		d -= rc
		var bw := _beach(top)
		if d < bw:
			return Vector2(1.0, lerpf(BERM, SEA - 0.3, d / bw))
		return Vector2(1.0, lerpf(SEA - 0.3, FLOOR, clampf((d - bw) / 60.0, 0.0, 1.0)))
	var rising := target > h
	var e0 := h - 1.0 if rising else maxf(h - gap, minf(target, h - 1.0))
	var delta := target - e0
	var u := clampf(d / run, 0.0, 1.0)
	if absf(delta) < 15.0:   # level ground: a valley's floor, the open country at the road's ends
		return Vector2(1.0 - smoothstep(run, run + BLEND, d), e0 + delta * smoothstep(0.0, 1.0, u))
	if rising:               # a rock cut, then the mountainside (no steeper than trees stand on: steeper, and it was one dark wall of rock)
		var cut := minf(delta * 0.2, 30.0)
		return Vector2(1.0 - smoothstep(run, run + BLEND, d), e0 + cut * smoothstep(0.0, 40.0, d) + (delta - cut) * (1.0 - pow(1.0 - u, 1.6)))
	return Vector2(1.0 - smoothstep(run + FLOOR_W, run + FLOOR_W + BLEND, d), e0 + delta * (1.0 - pow(1.0 - u, 2.6)))


## What the terrain's grid stands at `d` m out from the deck's edge on one side: the land the road's
## own mesh shows there, sunk under it. Where that land falls away (a sea cliff, a valley's wall) the
## grid lies at its foot all the way in: a cliff is steeper than 512 m triangles can follow, and
## between their corners they stood out through it as a great slab.
func _ground(D: Dictionary, q: int, left: bool, d: float) -> Vector2:
	if _sea_at(D, q, left):
		return Vector2(1.0, FLOOR)
	var h: float = D.h[q]
	var target: float = (D.tl if left else D.tr)[q]
	if target < h - 15.0 and d < FLANK:
		return Vector2(1.0, minf(target, h - 1.0) - SINK)
	var v := _side(h, target, (D.rl if left else D.rr)[q], D.gap[q], false, d)
	v.y -= SINK * (1.0 - smoothstep(FLANK - 300.0, FLANK, d))
	return v


## The scenic sample nearest p, from the one its cell knows: downhill in ever smaller steps.
func _nearest(R, D: Dictionary, p: Vector2, start: int) -> int:
	var best := start
	var bd := Vector2(R.px[best] - p.x, R.py[best] - p.y).length_squared()
	for step in [64, 16, 4, 1]:
		var moved := true
		while moved:
			moved = false
			for dir in [-1, 1]:
				var j := clampi(best + dir * step, int(D.first), int(D.last))
				var d := Vector2(R.px[j] - p.x, R.py[j] - p.y).length_squared()
				if d < bd:
					bd = d
					best = j
					moved = true
	return best


## The mountain's road passes near the same place more than once (a spiral's laps, 6 km apart), and
## the sample nearest p may be on another lap than the one p's own cell knows of: the cells round it
## are asked too, and the nearest of what they find is p's.
func _nearest_lap(r: int, p: Vector2, cell: Vector2i, best: int) -> int:
	var D: Dictionary = roads[r]
	var R = sim.roads[r]
	var bd := Vector2(R.px[best] - p.x, R.py[best] - p.y).length_squared()
	if bd < LAP_SURE * LAP_SURE:
		return best      # (no other lap can be nearer: they are 6 km apart)
	var tried := [best]
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var other := _hint(cell + Vector2i(dx, dy))
			if other.is_empty() or int(other[0]) != r:
				continue
			var fresh := true
			for t in tried:
				fresh = fresh and absi(int(other[1]) - int(t)) >= 160
			if not fresh:
				continue
			var j := _nearest(R, D, p, int(other[1]))
			tried.append(int(other[1]))
			tried.append(j)
			var d := Vector2(R.px[j] - p.x, R.py[j] - p.y).length_squared()
			if d < bd:
				bd = d
				best = j
	return best


## The terrain's grid beside and under the mountain's road. The road is a bench in the slope: cut into
## it on the uphill side, on fill on the downhill. The grid lies under the deck and under the road's
## own land (row): at the hill's own height where that is the lower (under the fill), held under the
## deck for as far as one of its triangles could reach across it, and the mountain itself past FLANK.
func _mountain_ground(h: float, hw: float, lat: float, d: float, p: Vector2) -> Vector2:
	var hill := Helios.land(p)
	if d < 0.0:
		return Vector2(1.0, minf(h - 1.0, hill) - SINK)
	var y := minf(lerpf(h - 1.0, hill, smoothstep(0.0, EASE, d)), hill) - SINK * (1.0 - smoothstep(FLANK - 300.0, FLANK, d))
	if absf(lat) < hw + UNDER:
		y = minf(y, h - 1.0 - SINK)
	return Vector2(1.0 - smoothstep(FLANK, FLANK + BLEND, d), y)      # (its ridges come back as slowly as the country does elsewhere)


## The height a point beside road r is known to stand at without asking the terrain (the mountain's
## road: the mountain's), or NAN.
func known_height(r: int, p: Vector2) -> float:
	return Helios.land(p) if roads.has(r) and roads[r].has("mountain") else NAN


## What the terrain's vertex c (at p) stands at: Vector2(weight, height); weight 0 where no scenic
## road has a say. The terrain lies SINK under the road's own land out to FLANK, and under the deck
## itself wherever one of its triangles could reach it.
func land(c: Vector2i, _p: Vector2) -> Vector2:
	# (at the grid's own vertex, whatever point near it was asked about: the answer is kept by vertex)
	var p := Vector2(c) * STEP
	if is_sea(p):
		return Vector2(1.0, FLOOR)
	var cell := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
	var near := false
	for box in boxes:
		near = near or box.has_point(cell)
	if not near:
		return Vector2.ZERO
	var hint := _hint(cell)
	if hint.is_empty():
		return Vector2.ZERO
	if _cache.has(c):
		return _cache[c]
	var r := int(hint[0])
	var D: Dictionary = roads[r]
	var R = sim.roads[r]
	var i := _nearest(R, D, p, int(hint[1]))
	if D.has("mountain"):
		i = _nearest_lap(r, p, cell, i)
	var along: float = ((p.x - R.px[i]) * R.tx[i] + (p.y - R.py[i]) * R.ty[i]) / R.len[i]
	var out := Vector2.ZERO
	if not ((i == int(D.first) and along < 0.0) or (i == int(D.last) and along > 0.0)):
		var lat: float = (p.x - R.px[i]) * R.nx[i] + (p.y - R.py[i]) * R.ny[i]
		var left := lat > 0.0
		var q := i - int(D.first)
		var is_open := open(r, i, left)
		var edge: float = float(D.hw) - (float(D.e) if is_open else -3.2)
		var d := absf(lat) - edge
		if D.has("mountain"):
			out = _mountain_ground(D.h[q], float(D.hw), lat, d, p)
		elif d < 0.0:   # under the deck: as low as the lower of its two sides, so no triangle from here stands out through a cliff
			out = Vector2(1.0, minf(D.h[q] - 10.0, minf(_ground(D, q, true, 0.0).y, _ground(D, q, false, 0.0).y)))
		else:
			out = _ground(D, q, left, d)
			if absf(lat) < float(D.hw) + UNDER:
				# (a triangle from here can reach across the deck to the other side: no higher than that side's land at its edge,
				# or it stood out through a sea cliff from the mountain's side of the road)
				out.y = minf(out.y, minf(D.h[q] - 10.0, _ground(D, q, not left, 0.0).y))
		if not D.has("mountain"):   # (the mountain's road begins and ends on level ground already: nothing to ease in)
			out.x *= smoothstep(0.0, END, float(i - int(D.first))) * smoothstep(0.0, END, float(int(D.last) - i))
	_cache[c] = out
	return out


## The land across one side of road r at its sample i, for the road's own mesh: OFFS.size() pairs
## [m out from the centreline, height], the last one buried. Roughened a little away from the deck
## (never downward by more than the terrain is sunk), so a mountainside isn't a ruled surface.
func row(r: int, i: int, left: bool) -> PackedFloat32Array:
	var D: Dictionary = roads[r]
	var R = sim.roads[r]
	var q := i - int(D.first)
	var sea := _sea_at(D, q, left)
	var is_open := open(r, i, left)
	var edge: float = float(D.hw) - (float(D.e) if is_open else -3.2)
	var h: float = D.h[q]
	var target: float = (D.tl if left else D.tr)[q]
	var run: float = (D.rl if left else D.rr)[q]
	var sgn := 1.0 if left else -1.0
	var out := PackedFloat32Array()
	if D.has("mountain"):
		# the mountain itself, from the deck's edge: a cut over the road on the uphill side, a bank under it on the
		# downhill, each meeting the slope within EASE; roughened a little (upward only: the terrain lies SINK under it)
		for m in OFFS.size():
			var out_m: float = OFFS[m]
			var at := Vector2(R.px[i] + R.nx[i] * sgn * (edge + out_m), R.py[i] + R.ny[i] * sgn * (edge + out_m))
			var hill := lerpf(h - 1.0, Helios.land(at), smoothstep(0.0, EASE, out_m))
			if m == OFFS.size() - 1:
				hill -= 45.0
			elif m > 1:
				hill += 26.0 * smoothstep(14.0, 260.0, out_m) * (1.0 - smoothstep(1100.0, FLANK, out_m)) * (0.5 + 0.5 * _noise.get_noise_2d(at.x, at.y))
			out.append(edge + out_m)
			out.append(hill)
		if not is_open and target > h:
			out[1] = h + sim.net_edge(float(R.w[i]), float(D.hw)).x + 0.5
		return out
	var ds := OFFS
	if sea:
		var top := _shore_top(h, run)
		var rc := _cliff_run(top)
		var bw := _beach(top)
		ds = [0.0, minf(150.0, run * 0.5), minf(300.0, run), run, run + rc * 0.45, run + rc, run + rc + bw * 0.5, run + rc + bw, run + rc + bw + 60.0, run + rc + bw + 300.0]
	for m in ds.size():
		var d: float = ds[m]
		var v := _side(h, target, run, D.gap[q], sea, minf(d, FLANK) if not sea else d)
		var y := v.y
		if m == ds.size() - 1:
			y -= 45.0 if not sea else 6.0
		elif m > 1 and not sea:
			var off: float = edge + d
			var amp := minf(0.05 * absf(target - h), 40.0) * smoothstep(14.0, 260.0, d) * (1.0 - smoothstep(1100.0, FLANK, d))
			y += amp * (0.375 + 0.625 * _noise.get_noise_2d(R.px[i] + R.nx[i] * sgn * off, R.py[i] + R.ny[i] * sgn * off))
		out.append(edge + d)
		out.append(y)
	if not is_open and target > h:
		out[1] = h + sim.net_edge(float(R.w[i]), float(D.hw)).x + 0.5   # behind the wall, just over its foot
	return out
