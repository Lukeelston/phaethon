## Hyperion (Luke, 2026-11-21, of Helios: "its still not what i was talking about. Keep it as it is, and
## add another one, twice as tall. Maybe 3 times - it should be inconceivable. Then it should have a
## steadily steepening ramp until it's basically straight up, then a braking section to crest over the
## top, enjoy the view from the top, then creep over a cliff and scream down the other side. It should
## be wide and imposing. The hill climb road to end all roads. Olympus mons, but bigger."): the second
## mountain, 48 km high, in the middle of the north-west cell, and the road SHyperion: one straight
## line from E2 to E3 that goes up its ramp, over its summit and down its cliff.
## tools/design_network.py's HYPERION_*, hyperion_shape, hyperion_out and hyperion_z are the mountain;
## this mirrors them, and the road's heights are that surface (tests/test_hyperion.gd holds the two
## together). The road is where the designer laid it, so the mountain's place is read from the road.
##   Hyperion.setup(sim)       find the road and work the mountain out (false: this sim has no such road)
##   Hyperion.height(p)        the designer's surface at p (map metres): the road lies on this
##   Hyperion.land(p)          what the country stands at there: the surface, let down to the plain's floor at the foot
##   Hyperion.ground(p)        what the terrain's 512 m grid stands at there: under the surface everywhere (the mesh is what shows)
##   Hyperion.body_mesh(landscape)   the whole mountain as one mesh: at 88 degrees a 512 m grid is four stretched triangles
extends RefCounted

const ROAD := "SHyperion"
const HEIGHT := 48000.0                      # m: the summit (HYPERION_H)
const UP := [2880, 70, 192]                  # samples of deck: the ramp, the wall, the crest (HYPERION_UP)
const TOP := 200                             # ... the summit (HYPERION_TOP)
const DOWN := [19, 1345, 1024]               # ... the lip, the wall down, the run-out (HYPERION_DOWN)
const HALF_WIDTH := 3000.0                   # m: half the plateau's width across the road (HYPERION_PLATEAU)
const CORNER := 1200.0                       # m: its corners' radius
const SKIRT := Vector2(10000.0, 8000.0)      # the flanks: this much more run at the foot than the ramp's own, gone by this height (HYPERION_SKIRT)
const STEP := 24.0                           # m of deck a sample (CraftSim.NET_STEP)
const FLOOR := -4.0                          # the open ground everywhere else (NetworkScenic.FLOOR)
const GRID := 512.0                          # the terrain's grid (NetworkLandscape.STEP)
const LEVELS := 4096                         # the heights the three profiles are kept at (closer together toward the foot and the summit)
const UNDER := 14.0                          # m: the terrain's grid lies this far under the lowest of the surface round each of its corners
const FACE := 2400.0                         # m either side of the road's line: the road's own land shows here (NetworkScenic.FLANK), and the mesh lies under it
const FACE_SINK := 18.0                      # ... by this much
const RING_EVERY := 16                       # the mesh: a ring every so many levels
const ROUND_STRAIGHT := 300.0                # ... a column every so many metres along the plateau's straight edges
const ROUND_CORNER := 20                     # ... and so many round each of its corners
const RIDGE := 1500.0                        # m: the tallest of its buttresses, half way up, away from the road
const CLEARING := 0.56                       # how much of the cloud deck's cover is gone round it (Helios.CLEARING is 0.47; view/network_clouds.gdshader)
const ROCK := Color(0.35, 0.33, 0.31)
const SNOW := Color(0.90, 0.93, 0.95)
const HIGH_ROCK := Color(0.33, 0.29, 0.27)   # over the snow: too high and too dry for any to lie
const WALL_ROCK := Color(0.16, 0.155, 0.165)
const SUMMIT_ROCK := Color(0.46, 0.43, 0.42)
const MAST := 420.0                          # m: the summit's two masts
const STOP_SHORT := 12                       # samples short of the lip: the summit's stop line (and its start point, 4 behind that)
const BRINK := 5                             # samples onto the lip: the brink's mark, 24 degrees nose down, where the country comes into view under the nose

static var ready := false
static var road := -1
static var centre := Vector2.ZERO            # the summit's middle (map metres)
static var axis := Vector2.RIGHT             # the road's way over it
static var at := {}                          # the road's samples: ramp (its foot), wall, crest, summit, centre, lip, drop, runout, end (the run-out's)
static var shape := {}                       # the designer's hyperion_shape(): tm, td (rad), R1, Lw, Rc, Rl, Ld, R2, zc, zw, zl, zo, front, back
static var reach := 0.0                      # m: no part of the mountain is further than this from its centre
static var _front := PackedFloat64Array()    # at each level: how far out from the plateau's edge the mountain stands that high, on the ramp's side
static var _back := PackedFloat64Array()     # ... on the cliff's
static var _side := PackedFloat64Array()     # ... on either flank
static var _sim_id := 0
static var _cx := 0.0                        # the centre and the axis again, as doubles (a Vector2 keeps a place on the map to 3 cm: a metre of an 88 degree wall)
static var _cy := 0.0
static var _ux := 1.0
static var _uy := 0.0
static var _noise: FastNoiseLite


static func _solve(n_arc: int, n_wall: int) -> float:
	var lo := 1.3
	var hi := 1.57
	for k in 200:
		var mid := (lo + hi) / 2.0
		if STEP * n_arc * (1.0 - cos(mid)) / mid + STEP * n_wall * sin(mid) - HEIGHT > 0.0:
			hi = mid
		else:
			lo = mid
	return (lo + hi) / 2.0


## Find the road in `sim` and work the mountain out from it. False when the sim has no such road (a
## test's cut-down network), and then no place is on the mountain.
static func setup(sim) -> bool:
	if ready and _sim_id == sim.get_instance_id():
		return true
	ready = false
	road = -1
	if sim.get("roads") == null:
		return false
	for k in sim.roads.size():
		if String(sim.roads[k].name) == ROAD:
			road = k
	if road < 0:
		return false
	var tm := _solve(int(UP[0]) + int(UP[2]), int(UP[1]))
	var td := _solve(int(DOWN[0]) + int(DOWN[2]), int(DOWN[1]))
	var S := {"tm": tm, "td": td, "R1": STEP * int(UP[0]) / tm, "Lw": STEP * int(UP[1]), "Rc": STEP * int(UP[2]) / tm,
		"Rl": STEP * int(DOWN[0]) / td, "Ld": STEP * int(DOWN[1]), "R2": STEP * int(DOWN[2]) / td, "top": STEP * TOP}
	S["zc"] = HEIGHT - float(S.Rc) * (1.0 - cos(tm))
	S["zw"] = float(S.zc) - float(S.Lw) * sin(tm)
	S["zl"] = HEIGHT - float(S.Rl) * (1.0 - cos(td))
	S["zo"] = float(S.zl) - float(S.Ld) * sin(td)
	S["front"] = float(S.Rc) * sin(tm) + float(S.Lw) * cos(tm) + float(S.R1) * sin(tm)
	S["back"] = float(S.Rl) * sin(td) + float(S.Ld) * cos(td) + float(S.R2) * sin(td)
	shape = S
	# the road's samples: the summit is where it is highest; the rest by the designer's counts
	var R = sim.roads[road]
	var first := -1
	var last := -1
	for i in R.N:
		if sim.net_height(road, float(i)) > HEIGHT - 0.001:
			if first < 0:
				first = i
			last = i
	if first < 0 or last - first != TOP:
		push_error("Hyperion: the road's summit is samples %d to %d (it should be %d long)" % [first, last, TOP])
		return false
	at = {"summit": first, "lip": last, "centre": (first + last) / 2, "crest": first - int(UP[2]), "wall": first - int(UP[2]) - int(UP[1]),
		"ramp": first - int(UP[2]) - int(UP[1]) - int(UP[0]), "drop": last + int(DOWN[0]), "runout": last + int(DOWN[0]) + int(DOWN[1]),
		"end": last + int(DOWN[0]) + int(DOWN[1]) + int(DOWN[2])}
	var c: int = at.centre
	centre = Vector2(R.px[c], R.py[c])
	axis = Vector2(R.tx[c], R.ty[c]).normalized()
	_cx = R.px[c]
	_cy = R.py[c]
	_ux = R.tx[c]
	_uy = R.ty[c]
	_front.resize(LEVELS + 1)
	_back.resize(LEVELS + 1)
	_side.resize(LEVELS + 1)
	for k in LEVELS + 1:
		var z := _level_height(float(k))
		_front[k] = _out_front(z)
		_back[k] = _out_back(z)
		_side[k] = _front[k] + (SKIRT.x * pow(1.0 - z / SKIRT.y, 2.0) if z < SKIRT.y else 0.0)
	reach = Vector2(float(S.top) / 2.0, HALF_WIDTH).length() + maxf(_side[0], maxf(_front[0], _back[0])) + 2000.0
	_sim_id = sim.get_instance_id()
	ready = true
	return true


## The height of level k (0 the foot, LEVELS the summit): close-set at both ends, where each profile turns
## fastest against its height (a circle's foot, a circle's top).
static func _level_height(k: float) -> float:
	return HEIGHT * (1.0 - cos(PI * k / LEVELS)) / 2.0


## The height at a fractional level: a straight line from the level below to the one above, as the distance
## out is between them (_level). So a wall, which is straight, is exact, and a curve is its chord between
## heights a few metres apart.
static func _height_at_level(lvl: float) -> float:
	var a := clampi(int(lvl), 0, LEVELS - 1)
	return lerpf(_level_height(float(a)), _level_height(float(a + 1)), lvl - float(a))


## The designer's hyperion_out on the ramp's side: how far out from the plateau's edge the mountain is z high.
static func _out_front(z: float) -> float:
	var tm: float = shape.tm
	if z >= float(shape.zc):
		return float(shape.Rc) * sin(acos(clampf(1.0 - (HEIGHT - z) / float(shape.Rc), -1.0, 1.0)))
	if z >= float(shape.zw):
		return float(shape.Rc) * sin(tm) + (float(shape.zc) - z) / tan(tm)
	return float(shape.Rc) * sin(tm) + float(shape.Lw) * cos(tm) + float(shape.R1) * (sin(tm) - sin(acos(clampf(1.0 - z / float(shape.R1), -1.0, 1.0))))


## ... and on the cliff's.
static func _out_back(z: float) -> float:
	var td: float = shape.td
	if z >= float(shape.zl):
		return float(shape.Rl) * sin(acos(clampf(1.0 - (HEIGHT - z) / float(shape.Rl), -1.0, 1.0)))
	if z >= float(shape.zo):
		return float(shape.Rl) * sin(td) + (float(shape.zl) - z) / tan(td)
	return float(shape.Rl) * sin(td) + float(shape.Ld) * cos(td) + float(shape.R2) * (sin(td) - sin(acos(clampf(1.0 - z / float(shape.R2), -1.0, 1.0))))


## p against the plateau: Vector3(m along the road from the summit's middle, m to its left, 0), then
## Vector2(m out from the plateau's edge (under 0: on it), the cosine of the way out against the way the
## road came: 1 the ramp's side, -1 the cliff's, 0 a flank).
static func across(p: Vector2) -> Vector2:
	return across_xy(p.x, p.y)


static func across_xy(x: float, y: float) -> Vector2:
	var dx := x - _cx
	var dy := y - _cy
	return Vector2(dx * _ux + dy * _uy, -dx * _uy + dy * _ux)


static func outward(p: Vector2) -> Vector2:
	return _outward(across_xy(p.x, p.y))


static func _outward(uv: Vector2) -> Vector2:
	var qu := absf(uv.x) - (STEP * TOP / 2.0 - CORNER)
	var qv := absf(uv.y) - (HALF_WIDTH - CORNER)
	var mu := maxf(qu, 0.0)
	var mv := maxf(qv, 0.0)
	var m := sqrt(mu * mu + mv * mv)
	return Vector2(m + minf(maxf(qu, qv), 0.0) - CORNER, (-signf(uv.x) * mu / m) if m > 0.0 else 0.0)


## How far out the mountain's level k is, the way whose cosine is c.
static func _out_at(k: int, c: float) -> float:
	var c2 := c * c
	return (c2 * _front[k] if c > 0.0 else c2 * _back[k]) + (1.0 - c2) * _side[k]


## The level (0..LEVELS, fractional) that stands `out` from the plateau's edge the way whose cosine is c:
## the designer's bisection, between the heights kept. (Straight out from the plateau's ends, where the
## road and its land are, one profile is searched, not three.)
static func _level(out: float, c: float) -> float:
	if out <= 0.0:
		return float(LEVELS)
	var lo := 0
	var hi := LEVELS
	if absf(c) >= 1.0:
		var one := _front if c > 0.0 else _back
		if out >= one[0]:
			return 0.0
		while hi - lo > 1:
			var mid := (lo + hi) >> 1
			if one[mid] > out:
				lo = mid
			else:
				hi = mid
		return float(lo) + ((one[lo] - out) / (one[lo] - one[hi]) if one[lo] > one[hi] else 0.0)
	if out >= _out_at(0, c):
		return 0.0
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if _out_at(mid, c) > out:
			lo = mid
		else:
			hi = mid
	var a := _out_at(lo, c)
	var b := _out_at(hi, c)
	return float(lo) + ((a - out) / (a - b) if a > b else 0.0)


## Is p on the mountain (inside its foot)?
static func on(p: Vector2) -> bool:
	if not ready or p.distance_squared_to(centre) > reach * reach:
		return false
	var o := outward(p)
	return o.x < _out_at(0, o.y)


## The designer's hyperion_z: the summit's height on the plateau, and round it the height at which the
## mountain stands as far out as p is from the plateau's edge (between the 4,096 heights kept).
static func height(p: Vector2) -> float:
	if not ready or p.distance_squared_to(centre) > reach * reach:
		return 0.0
	var o := outward(p)
	return _height_at_level(_level(o.x, o.y))


## ... at a place given in doubles (the sims' own: the road's samples).
static func height_xy(x: float, y: float) -> float:
	if not ready:
		return 0.0
	var o := _outward(across_xy(x, y))
	return _height_at_level(_level(o.x, o.y))


## How much of the way out to the foot p is: 0 on the plateau, 1 at the foot and beyond.
static func outness(p: Vector2) -> float:
	if not ready:
		return 1.0
	var o := outward(p)
	return clampf(o.x / _out_at(0, o.y), 0.0, 1.0)


static func land(p: Vector2) -> float:
	if not ready or p.distance_squared_to(centre) > reach * reach:
		return FLOOR
	var o := outward(p)
	var u := clampf(o.x / _out_at(0, o.y), 0.0, 1.0)
	return _height_at_level(_level(o.x, o.y)) + FLOOR * u * u


## How much of the regions' own relief is left at p: none on the mountain or at its foot, all of it a
## third of the way to its foot again beyond that foot.
static func country(p: Vector2) -> float:
	if not ready or p.distance_squared_to(centre) > reach * reach * 1.8:
		return 1.0
	var o := outward(p)
	return smoothstep(1.02, 1.33, o.x / _out_at(0, o.y))


## What the terrain's grid stands at on the mountain: under the lowest the surface gets within a square of
## the grid of p, less UNDER. A square of the grid is flat between its corners and the mountain is not (at 88
## degrees a square is 15 km of wall), so the grid is kept under the surface everywhere, and the mountain
## that shows is its own mesh (body_mesh) and, beside the road, the road's own land.
## (The surface falls with the distance out, and with the way out turning from a flank toward either end of
## the plateau, toward the cliff's fastest: so the lowest within a square is no lower than the surface a
## square's diagonal further out, the way out turned by what that diagonal subtends, toward the cliff if it
## could be.)
static func ground(p: Vector2) -> float:
	if not ready or p.distance_squared_to(centre) > reach * reach:
		return FLOOR - UNDER
	var o := outward(p)
	var out := maxf(o.x, 0.0) + GRID * 1.5
	var c := -1.0      # (on the plateau or within a square of its edge: any way out may be a square away, the cliff's among them)
	if o.x > GRID * 1.5:
		var turn := GRID * 1.5 / (o.x + CORNER - GRID * 1.5)      # (what a square's diagonal subtends from the corner the way out turns about, at the least)
		c = clampf((o.y + turn) if o.y > turn else (-absf(o.y) - turn), -1.0, 1.0)
	return _height_at_level(_level(out, c)) + FLOOR - UNDER


## How far under the surface the terrain's grid lies at p (NetworkScenic lets its own corners down by this,
## on top of its own SINK).
static func sag(p: Vector2) -> float:
	return maxf(0.0, land(p) - ground(p) - UNDER)


## Is the road's land to be built at every sample there (not every fourth)? Over the lip: a quarter turn
## in 460 m of deck.
static func fine(i: int) -> bool:
	return ready and i >= int(at.lip) - 4 and i <= int(at.drop) + 4


## The surface's pitch at p, radians: how steeply it climbs straight toward the plateau.
static func pitch(p: Vector2) -> float:
	if not ready or p.distance_squared_to(centre) > reach * reach:
		return 0.0
	var o := outward(p)
	return _pitch_at(_level(o.x, o.y), o.y)


## ... at level `lvl`, the way whose cosine is c: its height's change against its distance out's, over a level either side.
static func _pitch_at(lvl: float, c: float) -> float:
	if lvl <= 0.0 or lvl >= float(LEVELS):
		return 0.0
	var a := clampi(int(lvl) - 1, 0, LEVELS - 2)
	var b := a + 2
	var run := _out_at(a, c) - _out_at(b, c)
	return atan((_level_height(float(b)) - _level_height(float(a))) / maxf(run, 0.001))


## Buttresses and gullies down the mountain's flanks, for the mesh: none within FACE of the road's line, at
## the foot or near the summit, tallest between. Never below the surface.
static func rough(p: Vector2) -> float:
	if not ready:
		return 0.0
	return _rough_at(p, across(p).y, outness(p))


## ... where p is `lateral` m off the road's line and `u` of the way out to the foot.
static func _rough_at(p: Vector2, lateral: float, u: float) -> float:
	var clear := smoothstep(FACE + 600.0, FACE + 9000.0, absf(lateral))
	if clear <= 0.0 or u <= 0.0 or u >= 1.0:
		return 0.0
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 9041
		_noise.frequency = 1.0 / 14000.0
		_noise.fractal_octaves = 3
	var ridge := 1.0 - absf(_noise.get_noise_2dv(p))
	return RIDGE * clear * smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.5, 1.0, u)) * ridge * ridge * ridge


## The mountain's own colours over the country's: bare rock above the trees, snow above that, and above
## the snow (too high and too dry for any to lie) dark rock to a paler summit; its walls darker still.
## (n: the land's detail noise there, -1..1; wall: 0 where snow lies to 1 on a face too steep for it.)
static func colour(base: Color, h: float, n: float, wall := 0.0) -> Color:
	var col := base.lerp(Color(ROCK.r, ROCK.g, ROCK.b, base.a), smoothstep(1500.0, 3300.0, h + n * 500.0))
	col = col.lerp(Color(SNOW.r, SNOW.g, SNOW.b, base.a), smoothstep(4700.0, 6100.0, h + n * 700.0))
	col = col.lerp(Color(HIGH_ROCK.r, HIGH_ROCK.g, HIGH_ROCK.b, base.a), smoothstep(10500.0, 14500.0, h + n * 1500.0))
	col = col.lerp(Color(SUMMIT_ROCK.r, SUMMIT_ROCK.g, SUMMIT_ROCK.b, base.a), smoothstep(36000.0, 47000.0, h + n * 1200.0))
	col = col.lerp(Color(WALL_ROCK.r, WALL_ROCK.g, WALL_ROCK.b, base.a), wall * (0.80 + 0.14 * n))
	col.a = base.a * (1.0 - smoothstep(700.0, 1900.0, h))      # (no field patterns up a mountain)
	return col


## 0 where snow would lie, 1 where the surface is a wall (over 62 degrees); between from 40.
static func steep(p: Vector2) -> float:
	return smoothstep(deg_to_rad(40.0), deg_to_rad(62.0), pitch(p))


## The plateau's edge, counter-clockwise from the middle of its cliff end: [point (m along, m left), the way out there].
static func _rim() -> Array:
	var half_len := STEP * TOP / 2.0
	var a := half_len - CORNER
	var b := HALF_WIDTH - CORNER
	var out := []
	var straight := func(from: Vector2, to: Vector2, n: Vector2) -> void:
		var count := maxi(1, int(ceil(from.distance_to(to) / ROUND_STRAIGHT)))
		for k in count:      # (its far end is the next corner's first point)
			out.append([from.lerp(to, float(k) / count), n])
	var corner := func(mid: Vector2, from: float) -> void:
		for k in ROUND_CORNER:
			var ang := from + (PI / 2.0) * float(k) / ROUND_CORNER
			var n := Vector2(cos(ang), sin(ang))
			out.append([mid + n * CORNER, n])
	straight.call(Vector2(half_len, -b), Vector2(half_len, b), Vector2(1.0, 0.0))      # the cliff end, right to left
	corner.call(Vector2(a, b), 0.0)
	straight.call(Vector2(a, HALF_WIDTH), Vector2(-a, HALF_WIDTH), Vector2(0.0, 1.0))      # the left flank, back toward the ramp
	corner.call(Vector2(-a, b), PI / 2.0)
	straight.call(Vector2(-half_len, b), Vector2(-half_len, -b), Vector2(-1.0, 0.0))      # the ramp end
	corner.call(Vector2(-a, -b), PI)
	straight.call(Vector2(-a, -HALF_WIDTH), Vector2(a, -HALF_WIDTH), Vector2(0.0, -1.0))      # the right flank
	corner.call(Vector2(a, -b), PI * 1.5)
	return out


## The whole mountain as one mesh about its centre (x east, y up, z south): a ring every RING_EVERY
## levels from the plateau's edge down to the foot, a column out from each point of the plateau's edge.
## Within FACE of the road's line it lies FACE_SINK under the surface (the road's own land shows there);
## beyond, on the surface, with its buttresses. Its colours are the land's own (landscape.color_at).
static func body_mesh(landscape) -> ArrayMesh:
	var rim := _rim()
	var n_round := rim.size()
	var levels := []
	for k in range(LEVELS, -1, -RING_EVERY):
		levels.append(k)
	if int(levels[levels.size() - 1]) != 0:
		levels.append(0)
	var left := Vector2(-axis.y, axis.x)
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := levels.size() + 1      # (one more beyond the foot, under the ground)
	# each column's own country: the land's colour just beyond its foot (the mountain's colours go over it)
	var country_col := []
	for q in n_round:
		var n0: Vector2 = rim[q][1]
		var beyond: Vector2 = (rim[q][0] as Vector2) + n0 * (_out_at(0, -n0.x) + 600.0)
		country_col.append(landscape.color_at(centre + axis * beyond.x + left * beyond.y, 0.0))
	var detail: FastNoiseLite = landscape.detail
	for ring in rings:
		var k := int(levels[mini(ring, levels.size() - 1)])
		var z := _level_height(float(k))
		for q in n_round:
			var edge: Vector2 = rim[q][0]
			var n: Vector2 = rim[q][1]
			var c := -n.x      # the cosine of the way out against the way the road came
			var foot := _out_at(0, c)
			var out := _out_at(k, c) if ring < levels.size() else foot + 420.0
			var local := edge + n * out
			var p := centre + axis * local.x + left * local.y
			var u := clampf(out / foot, 0.0, 1.0)
			var h := z + FLOOR * u * u + _rough_at(p, local.y, u)
			if ring >= levels.size():
				h = FLOOR - 60.0
			else:
				h -= FACE_SINK * (1.0 - smoothstep(FACE - 350.0, FACE, absf(local.y)))
			verts.append(Vector3(p.x - centre.x, h, -(p.y - centre.y)))
			var wall := smoothstep(deg_to_rad(40.0), deg_to_rad(62.0), _pitch_at(float(k), c))
			colours.append(colour(country_col[q], maxf(h, 0.0), detail.get_noise_2dv(p), wall))
			uvs.append(Vector2(p.x, -p.y) / 256.0)
	for ring in rings - 1:
		for q in n_round:
			var a := ring * n_round + q
			var b := ring * n_round + (q + 1) % n_round
			var c2 := a + n_round
			var d := b + n_round
			indices.append_array(PackedInt32Array([a, b, c2, b, d, c2]))      # (clockwise from outside: the face that shows)
	# the plateau: a fan from its middle
	var mid := verts.size()
	verts.append(Vector3(0.0, HEIGHT + FLOOR * 0.0 - FACE_SINK, 0.0))
	colours.append(landscape.color_at(centre, HEIGHT))
	uvs.append(Vector2(centre.x, -centre.y) / 256.0)
	for q in n_round:
		indices.append_array(PackedInt32Array([mid, (q + 1) % n_round, q]))
	# normals: each corner's from the faces round it
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for k in range(0, indices.size(), 3):
		var face := (verts[indices[k + 1]] - verts[indices[k]]).cross(verts[indices[k + 2]] - verts[indices[k]])
		for m in 3:
			normals[indices[k + m]] += face
	for k in normals.size():
		normals[k] = normals[k].normalized() if normals[k].length_squared() > 0.0 else Vector3.UP
		if normals[k].y < 0.0:
			normals[k] = -normals[k]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# (never out of sight: it is drawn from as far as the eye is, pulled inside the camera's reach by its shader)
	mesh.custom_aabb = AABB(Vector3(-2000000.0, -100.0, -2000000.0), Vector3(4000000.0, HEIGHT + 4000.0, 4000000.0))
	return mesh


## What stands on the summit and along the road, built about the mountain's middle at the summit's height (x
## east, y up, z south): the stop line across the road at the summit's middle and the box a craft stops in; a
## mast either side of it and a shorter one at each of the plateau's four corners; and lights: one at each
## mast's head, and one on each edge of the road every LIGHT_EVERY samples from the ramp's foot to the
## run-out's end, so the road shows as two lines of light up the mountain and down it. -> a node with
## children "line", "masts" and "lights" (each one mesh; the lights are the roads' own beacons, which stay a
## few pixels across from any distance: view/beacon.gdshader).
const LIGHT_EVERY := 32

static func summit(sim) -> Node3D:
	var root := Node3D.new()
	root.name = "hyperion_summit"
	var R = sim.roads[road]
	var c: int = int(at.lip) - STOP_SHORT
	var half_road: float = float(R.w[c]) / 2.0
	var along := Vector3(axis.x, 0.0, -axis.y)
	var across3 := Vector3.UP.cross(along).normalized()
	var frame := Basis(across3, Vector3.UP, along)
	var at_line := along * (float(c - int(at.centre)) * STEP)      # the stop line's place, from the summit's middle
	# the stop line: a bright bar across the deck, a thin one before it, and the box behind it
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(1.25, 1.2, 1.05)
	var marks := SurfaceTool.new()
	marks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bar in [[Vector3(0.0, 0.0, 0.0), Vector3(2.0 * half_road - 150.0, 0.06, 4.0)], [Vector3(0.0, 0.0, 14.0), Vector3(2.0 * half_road - 150.0, 0.06, 1.2)],
			[Vector3(-70.0, 0.0, -40.0), Vector3(1.2, 0.06, 80.0)], [Vector3(70.0, 0.0, -40.0), Vector3(1.2, 0.06, 80.0)], [Vector3(0.0, 0.0, -80.0), Vector3(141.2, 0.06, 1.2)]]:
		var slab := BoxMesh.new()
		slab.size = bar[1]
		marks.append_from(slab, 0, Transform3D(frame, at_line + frame * (bar[0] as Vector3) + Vector3.UP * 0.12))
	# the brink: a bar across the lip where it is BRINK samples old, square to the deck there
	var bi := int(at.lip) + BRINK
	var brink_pitch := asin(clampf(float(sim.net_slope(road, float(bi))) / STEP, -1.0, 1.0))
	var brink_at := Vector3(R.px[bi] - _cx, sim.net_height(road, float(bi)) - HEIGHT, -(R.py[bi] - _cy))
	var brink_frame := Basis(across3, Vector3.UP.rotated(across3, -brink_pitch), along.rotated(across3, -brink_pitch))
	for bar in [[0.0, 3.0], [9.0, 1.0]]:
		var slab := BoxMesh.new()
		slab.size = Vector3(2.0 * half_road - 150.0, 0.06, float(bar[1]))
		marks.append_from(slab, 0, Transform3D(brink_frame, brink_at + brink_frame * Vector3(0.0, 0.14, float(bar[0]))))
	var line := MeshInstance3D.new()
	line.name = "line"
	line.mesh = marks.commit()
	line.material_override = paint
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(line)
	# the masts
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.36, 0.38, 0.41)
	steel.metallic = 0.3
	steel.roughness = 0.6
	var posts := SurfaceTool.new()
	posts.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamps := SurfaceTool.new()
	lamps.begin(Mesh.PRIMITIVE_TRIANGLES)
	var places := []
	for side in [-1.0, 1.0]:
		places.append([at_line + across3 * side * (half_road + 60.0), MAST, 9.0])
	var half_len := STEP * TOP / 2.0
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			places.append([along * su * (half_len - CORNER) + across3 * sv * (HALF_WIDTH - CORNER), 90.0, 4.0])
	for place in places:
		var foot: Vector3 = place[0]
		var tall: float = place[1]
		var box := BoxMesh.new()
		box.size = Vector3(float(place[2]), tall + FACE_SINK, float(place[2]))
		posts.append_from(box, 0, Transform3D(frame, foot + Vector3.UP * ((tall - FACE_SINK) / 2.0)))
		_beacon(lamps, foot + Vector3.UP * (tall + 2.0), Color(1.0, 0.96, 0.9))
	var masts := MeshInstance3D.new()
	masts.name = "masts"
	masts.mesh = posts.commit()
	masts.material_override = steel
	masts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(masts)
	# the road's lights, each edge
	for i in range(int(at.ramp), int(at.end) + 1, LIGHT_EVERY):
		var h: float = sim.net_height(road, float(i)) - HEIGHT
		for side in [-1.0, 1.0]:
			var off: float = side * (float(R.w[i]) / 2.0 + 6.0)
			_beacon(lamps, Vector3(R.px[i] + R.nx[i] * off - _cx, h + 30.0, -(R.py[i] + R.ny[i] * off - _cy)), Color(0.62, 0.80, 1.0))
	var lights := MeshInstance3D.new()
	lights.name = "lights"
	lights.mesh = lamps.commit()
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://view/beacon.gdshader")
	glow.set_shader_parameter("size", 16.0)
	glow.set_shader_parameter("min_ang", 0.0030)
	glow.set_shader_parameter("energy", 3.4)
	glow.set_shader_parameter("far_dim", 0.9)
	lights.material_override = glow
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lights.custom_aabb = AABB(Vector3(-80000.0, -HEIGHT - 200.0, -80000.0), Vector3(160000.0, HEIGHT + 1000.0, 160000.0))
	root.add_child(lights)
	return root


## One of the roads' beacons (NetworkWorld._beacon): a quad whose four corners all sit at its centre, spread by its shader.
static func _beacon(st: SurfaceTool, p: Vector3, c: Color) -> void:
	st.set_color(c)
	st.set_uv2(Vector2(0.0, 1e6))
	st.set_normal(Vector3.UP)
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_uv(uv)
		st.add_vertex(p)


## The boards along the road, for NetworkWorld's signs: [sample, the way they face traffic going (+1 up
## the samples), kind ("stunt": a wide warning board; "brake": a small one), two lines].
static func boards() -> Array:
	if not ready:
		return []
	var mile := 1609.344 / STEP
	var out := []
	var foot: int = at.ramp
	var summit_at: int = at.summit
	var lip: int = at.lip
	out.append([foot - 80, 1, "stunt", ["MOUNT HYPERION", "CLIMB 47 MI  SUMMIT 48 KM"]])
	# the ramp, by its pitch: 30, 45, 60 and 75 degrees
	for deg in [30, 45, 60, 75]:
		var i := foot + roundi(float(shape.R1) * deg_to_rad(float(deg)) / STEP)
		out.append([i, 1, "brake", ["%d DEG" % deg, "ALT %d KM" % roundi(float(shape.R1) * (1.0 - cos(deg_to_rad(float(deg)))) / 1000.0)]])
	out.append([int(at.wall), 1, "stunt", ["BRAKING SECTION", "SUMMIT 4 MI  BRAKE NOW"]])
	for mi in [3, 2, 1]:
		out.append([summit_at - roundi(mi * mile), 1, "brake", ["%d MI" % mi, "SUMMIT  BRAKE"]])
	out.append([summit_at, 1, "stunt", ["HYPERION SUMMIT", "48 KM  STOP LINE 3 MI"]])
	out.append([lip - roundi(mile), 1, "stunt", ["CLIFF 1 MI", "STOP AT THE LINE"]])
	out.append([lip - 2, 1, "stunt", ["THE BRINK", "CREEP  88 DEG DROP"]])
	out.append([int(at.runout), 1, "brake", ["RUN OUT", "PULL OUT 15 KM"]])
	# ... and for a craft that takes the road the other way: up the cliff, down the ramp
	var end: int = at.end
	out.append([end + 80, -1, "stunt", ["MOUNT HYPERION", "WALL 20 MI  SUMMIT 48 KM"]])
	out.append([int(at.drop) + roundi(3.0 * mile), -1, "brake", ["3 MI", "SUMMIT  BRAKE"]])
	out.append([int(at.drop) + roundi(mile), -1, "brake", ["1 MI", "SUMMIT  BRAKE"]])
	out.append([lip, -1, "stunt", ["HYPERION SUMMIT", "48 KM  STOP AT THE LINE"]])
	out.append([summit_at + roundi(mile), -1, "stunt", ["RAMP 1 MI", "88 DEG DESCENT"]])
	return out
