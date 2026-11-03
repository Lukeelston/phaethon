## The Network's world (track "network", docs/superpowers/specs/2026-10-19-network-design.md): a
## country of highways too big to build at once, so it's streamed round the pod. The roads come in
## chunks of CH samples, found through a CELL grid: each frame the chunks within VIS of the pod that
## aren't built yet are built (nearest first, at most BUDGET_MS of work a frame), and chunks past DROP
## are freed. A chunk is the road (asphalt, edge lines), its walls as the Eridanus speed loop's
## (concrete, a blue and white band, the lit strip on top; a city's STARFIGHTER zone in the towns'
## pink with tall panels), masts with beacons, and on a flyover (the sim's NET_HEIGHTS) the deck's
## edges, its underside and pillars. Walls stay open where another road joins (inside its corridor).
## Its signs come with it: a board before every junction naming where that exit goes (road miles,
## from the junction table), END OF THE ROAD before each shaft, braking boards before each
## city's STARFIGHTER zone, the city's name over its terminal (a lit line across the road), a jump's
## boards with a big lit arrow (view/arrow_board.gdshader) on the highway before its exit and over the
## fork where its spur runs straight on off the ramp, a speed and a gear before each side road's corner.
## A shaft's stretch is built on the shape it is in the world (view/network_shaft.gd): every point
## through _p, "up" the road's own (_up), hoops round it in place of masts.
## The cities' skylines are built once at the start: towers in each city's colours, hazed by their
## own shader so they stand out of the fog from far off.
##   var w := NetworkWorld.new(); add_child(w); w.build(sim, view)
##   w.sync(org_x, org_y)   every frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const ShaftScript := preload("res://view/network_shaft.gd")
const CH := 64                    # samples a chunk (~1.5 km): one builds well inside a 72 Hz frame
const CELL := 8000.0              # the grid's cells, m
const VIS := 20000.0              # build chunks this close (m, to the nearest point of their circle)
const DROP := 28000.0             # free them past this
const SLICE_MS := 1.0             # build work a frame (a chunk takes a few frames: ~2.3 ms of work, a board
                                  # ~1.4 ms; whole in one frame they were the 120 Hz headset's dropped frames)
const BUDGET_MS := 6.0            # ... when it's behind (a respawn, a jump): a chunk wanted within CATCH_UP,
const CATCH_UP := 12000.0         # m (in flight new chunks come in at VIS, ~3 s out at 5,000 mph), or more
const BACKLOG := 8                # than this many wanted (in flight at 5,000 mph never more than 3)
const WALL_H := 1.4
const BAND_H := 3.2
const FENCE_H := 6.0              # a city's zone: tall panels over the band
const STRIP_H := 0.45             # the walls' lit strip (thinner and dimmer than the speed loop's: from the
                                  # cockpit both walls' strips run flat across the view at the horizon)
const MAST_H := 24.0
const MAST_EVERY := 40            # samples (~1 km); a city's zone every 8. (Every 240 m, their beacons
                                  # piled into a white band along the horizon: Luke, "the light poles being
                                  # so dense just washes the horizon out in light")
const PILLAR_EVERY := 6           # samples under a deck
const HALL_HALF := 84             # samples (~2 km) either side of a city's terminal: its hall (the Network's tunnels)
const HALL_H := 110.0             # the hall's roof over the road (the terminal's gantry tops out at 76 m)
const HALL_COL := Color(0.19, 0.20, 0.23)
const HALL_LIGHT_EVERY := 4       # samples: a lit bar across the roof (overhead, the speed cue)
const HALL_RIB_EVERY := 8         # samples: a steel rib across the roof and down both walls
const HALL_STRIP_H := 18.0        # the lit strip down each wall
const DECK := 5.0                 # a deck's thickness, m
const LINE_W := 0.6
const EDGE_SEGS := 4              # facets across each edge's ramp (CraftSim.net_edge: the sims' quarter-pipe)
const EDGE_FOOT := Color(0.5, 0.52, 0.56)   # a dim line where each ramp starts up
const STRIP_LIGHT := Color(0.9, 0.94, 1.0)
const WALL_STRIP := Color(0.42, 0.68, 1.0)    # the walls' lit strips: sky blue (white ones lay along the horizon as a white line)
const WALL_STRIP_SF := Color(1.0, 0.42, 0.78)   # ... pink through a city's STARFIGHTER zone
const BAND := [Color(0.16, 0.45, 0.95), Color(0.95, 0.95, 0.93)]
const BAND_SF := [Color(1.0, 0.3, 0.75), Color(0.95, 0.95, 0.93)]
const ASPHALT_PERIOD := 64000.0
const BOARD_W := 80.0
const BOARD_H := 40.0
const BOARD_CLEAR := 28.0
const SIGN_BEFORE := 250          # samples (6 km) before a junction: its board
const BRAKE_MI := [4, 2, 1]       # braking boards, miles before a city's STARFIGHTER zone
const MILE := 1609.344
# the signs' glyphs: rendered at these sizes (px) and scaled up (SIGN_PX m a pixel), so a streamed
# board's first letters cost little to rasterise; all of them warmed at the start (_warm_fonts).
# (At 200 px each new glyph cost ~200 ms in the middle of a run.)
const FONT := [72, 43, 36, 79, 25]   # a board's title, its lines, three lines' lines; a braking board's miles, its words
const SIGN_PX := 0.139
const SIGN_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789/:+-.,"
const JUMP_W := 170.0             # a jump's board: wider, its arrow on a panel at the right
const JUMP_H := 56.0
const ARROW_PANEL := 0.36
const SIGN_FAR := 290             # samples (~7 km) before a jump's exit: its first board (clear of the ramp's own, at SIGN_BEFORE)
const SIGN_NEAR := 90             # samples (~2 km) before a jump's exit: its second board
const ARROW_WORDS := 1.8          # a jump's board's words, this much bigger (the same glyphs, scaled)
const FORK_BEFORE := 22           # samples before the fork: the board over it, the arrow straight on
const CHEV_EVERY := 14            # samples between the lit chevrons on a launch spur
const HOOP_EVERY := 8             # samples between a shaft's hoops (~190 m); every second one lit
const HOOP_H := 80.0              # the hoops' clearance over the road
const CORNER_MIN_K := 1.0 / 17000.0   # side roads: a bend this tight gets a board (speed, gear)
const CORNER_BEFORE := 100        # samples (~2.4 km) before it
const CORNER_G := 11.0            # g: the speed on its board
const TOWER_VIS := 140000.0       # skylines show this far
# a city's colours: [tower body a, tower body b, crown light]
const PALETTE := {
	"verdant": [Color(0.78, 0.82, 0.80), Color(0.42, 0.55, 0.50), Color(0.55, 1.0, 0.7)],
	"desert": [Color(0.86, 0.74, 0.56), Color(0.62, 0.48, 0.34), Color(1.0, 0.75, 0.35)],
	"ice": [Color(0.30, 0.42, 0.56), Color(0.58, 0.70, 0.82), Color(0.5, 0.9, 1.0)],   # blue glass against the snow
	"basalt": [Color(0.16, 0.16, 0.18), Color(0.30, 0.28, 0.28), Color(1.0, 0.38, 0.08)],
	"mesa": [Color(0.78, 0.45, 0.30), Color(0.52, 0.28, 0.18), Color(1.0, 0.55, 0.3)],
}

var sim
var view
var shaft                 # the shafts' shapes (view/network_shaft.gd)
var _up := Vector3.UP     # the road's up at the sample being built (a shaft's goes round with it)
var _smap := {}           # TrackPath -> road index, the shafts'
var chunks := {}          # Vector2i(road, chunk) -> [node, ox, oy]
var grid := {}            # Vector2i cell -> Array of [road, chunk, cx, cy, radius]
var built := 0            # tests read these
var dropped := 0
var build_ms_max := 0.0   # the most work a chunk took (all its slices)
var wanted := 0           # chunks wanted but not started, this frame
var sync_ms := 0.0        # this frame's sync (streaming and placing), ms
var setup_ms := 0
var walls_open := 0
var boards := 0
var cities_built := 0
var towers := 0
var skylines := []        # [node, cx, cy]
var far_shafts := []      # [node, ox, oy]: each shaft's shape from far off, before its chunks stream in
var _signs := {}
var halls := {}            # road -> [first, last sample] of its hall (the cities' terminals; CourseAudio reads it)
var hall_samples := 0      # samples built under a hall's roof (tests)          # Vector2i(road, chunk) -> Array of sign specs
var _s := []              # per road: distance along it at each sample (PackedFloat64Array)
var _asph: ShaderMaterial
var _mat: StandardMaterial3D
var _lit: StandardMaterial3D
var _bright: StandardMaterial3D
var _strip_mat: StandardMaterial3D   # the walls' strips: lit, but not HDR-bright
var _sec_cache := {}               # road widths -> their sections (_section)
var _idx_cache := {}               # Vector2i(rows, cols) -> the road grid's triangles (_grid_index)
var _beam: ShaderMaterial
var _board_mat: ShaderMaterial
var _end_mat: ShaderMaterial
var _city_mat: ShaderMaterial
var _arrow_mat: ShaderMaterial
var _fork_mat: ShaderMaterial
var _job := {}            # the chunk being built, a slice a frame (_start_chunk, _work)


func build(s, v) -> void:
	var t0 := Time.get_ticks_msec()
	sim = s
	view = v
	shaft = ShaftScript.new()
	shaft.setup(sim)
	for sh in sim.shafts:
		_smap[sim.roads[int(sh[0])]] = int(sh[0])
	_mat = Kit.vertex_colors()
	_lit = Kit.vertex_colors(true)
	_bright = Kit.vertex_colors(true)
	_bright.albedo_color = Color(2.4, 2.4, 2.4)
	_strip_mat = Kit.vertex_colors(true)
	_strip_mat.albedo_color = Color(1.0, 1.0, 1.0)
	_beam = ShaderMaterial.new()
	_beam.shader = preload("res://view/beacon.gdshader")
	# smaller and dimmer far off than the courses' (a ~0.1 deg floor, a seventh as bright by 30 km):
	# with 20 km of roads in view, the courses' 0.37 deg glows overlapped into a band of light
	_beam.set_shader_parameter("size", 1.2)
	_beam.set_shader_parameter("min_ang", 0.0018)
	_beam.set_shader_parameter("energy", 2.2)
	_beam.set_shader_parameter("far_dim", 0.15)
	_board_mat = ShaderMaterial.new()
	_board_mat.shader = preload("res://view/board.gdshader")
	_end_mat = ShaderMaterial.new()
	_end_mat.shader = preload("res://view/authorized.gdshader")
	_end_mat.set_shader_parameter("col", Vector3(1.0, 0.55, 0.1))
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = preload("res://view/authorized.gdshader")
	_city_mat.set_shader_parameter("col", Vector3(0.25, 0.65, 1.0))
	_arrow_mat = ShaderMaterial.new()   # a jump's board on the highway: the arrow up and to the right, to the exit
	_arrow_mat.shader = preload("res://view/arrow_board.gdshader")
	_arrow_mat.set_shader_parameter("aspect", JUMP_W / JUMP_H)
	_arrow_mat.set_shader_parameter("panel", ARROW_PANEL)
	_arrow_mat.set_shader_parameter("angle", deg_to_rad(52.0))
	_fork_mat = _arrow_mat.duplicate()  # ... over the fork: straight on
	_fork_mat.set_shader_parameter("angle", PI / 2.0)
	_asph = ShaderMaterial.new()
	_asph.shader = preload("res://view/asphalt.gdshader")
	_asph.set_shader_parameter("period", ASPHALT_PERIOD)
	_asph.set_shader_parameter("base", Vector3(0.21, 0.205, 0.205))
	_asph.set_shader_parameter("spec", 0.2)
	_asph.set_shader_parameter("lane_half", 60.0)
	for r in sim.roads.size():
		var R = sim.roads[r]
		var acc := PackedFloat64Array()
		acc.resize(R.N)
		var d := 0.0
		for i in R.N:
			acc[i] = d
			d += R.len[i]
		_s.append(acc)
		var k := 0
		while k * CH < R.N - 1:
			var c0 := k * CH
			var c1 := mini((k + 1) * CH, R.N - 1)
			var m0 := _wxy(r, c0)
			var m1 := _wxy(r, c1)
			var cx: float = (m0.x + m1.x) / 2.0
			var cy: float = (m0.y + m1.y) / 2.0
			var rad := 0.0
			for i in range(c0, c1 + 1, 8):
				rad = maxf(rad, (_wxy(r, i) - Vector2(cx, cy)).length())
			rad += R.w[c0]
			var lo := Vector2i(int(floor((cx - rad) / CELL)), int(floor((cy - rad) / CELL)))
			var hi := Vector2i(int(floor((cx + rad) / CELL)), int(floor((cy + rad) / CELL)))
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					var key := Vector2i(gx, gy)
					if not grid.has(key):
						grid[key] = []
					grid[key].append([r, k, cx, cy, rad])
			k += 1
	_plan_signs()
	for c in sim.cities:   # a hall over each city's terminal: the Network's tunnels
		halls[int(c.road)] = [int(c.i) - HALL_HALF, int(c.i) + HALL_HALF]
	_build_skylines()
	_build_far_shafts()
	_warm_fonts()
	setup_ms = Time.get_ticks_msec() - t0


## Every frame: build what's near, free what's far, place the rest against the floating origin.
func sync(org_x: float, org_y: float) -> void:
	var t_in := Time.get_ticks_usec()
	var want := []
	var gc := Vector2i(int(floor(org_x / CELL)), int(floor(org_y / CELL)))
	var reach := int(ceil(VIS / CELL)) + 1
	var seen := {}
	for gx in range(gc.x - reach, gc.x + reach + 1):
		for gy in range(gc.y - reach, gc.y + reach + 1):
			for e in grid.get(Vector2i(gx, gy), []):
				var key := Vector2i(e[0], e[1])
				if seen.has(key) or chunks.has(key):
					continue
				seen[key] = true
				var d: float = Vector2(e[2] - org_x, e[3] - org_y).length() - e[4]
				if d < VIS:
					want.append([d, key])
	want.sort_custom(func(a, b): return a[0] < b[0])
	wanted = want.size()
	# the chunk in hand, then the nearest wanted, a slice at a time until the frame's budget is spent
	var behind: bool = want.size() > BACKLOG or (not want.is_empty() and float(want[0][0]) < CATCH_UP) or (not _job.is_empty() and float(_job.d) < CATCH_UP)
	var end := Time.get_ticks_usec() + int((BUDGET_MS if behind else SLICE_MS) * 1000.0)
	var wi := 0
	while true:
		if _job.is_empty():
			if wi >= want.size():
				break
			_start_chunk(want[wi][1].x, want[wi][1].y)
			_job.d = want[wi][0]
			wi += 1
		if not _work(end):
			break
	for key in chunks.keys():
		var c: Array = chunks[key]
		var R = sim.roads[key.x]
		var c0: int = key.y * CH
		var c1: int = mini(c0 + CH, R.N - 1)
		var cm := (_wxy(key.x, c0) + _wxy(key.x, c1)) / 2.0
		if Vector2(cm.x - org_x, cm.y - org_y).length() > DROP + CH * 24.0:
			(c[0] as Node3D).queue_free()
			chunks.erase(key)
			dropped += 1
			if not _job.is_empty() and _job.key == key:   # gone before it was finished
				_job = {}
			continue
		(c[0] as Node3D).position = Vector3(c[1] - org_x, 0.0, -(c[2] - org_y))
	for sk in skylines:
		(sk[0] as Node3D).position = Vector3(sk[1] - org_x, 0.0, -(sk[2] - org_y))
	for sk in far_shafts:
		(sk[0] as Node3D).position = Vector3(sk[1] - org_x, 0.0, -(sk[2] - org_y))
	sync_ms = (Time.get_ticks_usec() - t_in) / 1000.0


## The deck's height at sample i of road r (0 but on a flyover).
func _h(r: int, i: int) -> float:
	return sim.net_height(r, float(i))


## A point `off` m left of road r's sample i, `h` up, against the chunk origin (ox, oy).
func _p(R, ox: float, oy: float, i: int, off: float, h: float) -> Vector3:
	if R.shaft and shaft.on(_smap[R], float(i)):   # on a shaft's stretch: its own point and frame
		var A: Array = shaft.at(_smap[R], float(i))
		return Vector3(float(A[0]) - ox, A[2], -(float(A[1]) - oy)) + (A[4] as Vector3) * off + (A[5] as Vector3) * (h - float(A[2]))
	return Vector3(R.px[i] + R.nx[i] * off - ox, h, -(R.py[i] + R.ny[i] * off - oy))


## Road r's sample i in the world's plan (a shaft's stretch isn't where the sims' plan has it).
func _wxy(r: int, i: int) -> Vector2:
	var R = sim.roads[r]
	if R.shaft and shaft.on(r, float(i)):
		var A: Array = shaft.at(r, float(i))
		return Vector2(A[0], A[1])
	return Vector2(R.px[i], R.py[i])


## Is the wall on side sgn of road r's sample i open (another road joins there: the edge point is
## inside its corridor)?
func _open(r: int, i: int, sgn: float) -> bool:
	var R = sim.roads[r]
	for k in R.jx:
		var J: Array = sim.junctions[k]
		var on_a: bool = int(J[0]) == r
		var z0: int = int(J[1]) if on_a else int(J[4])
		var z1: int = int(J[2]) if on_a else int(J[5])
		if i < z0 - 4 or i > z1 + 4:
			continue
		var q: int = int(J[3]) if on_a else int(J[0])
		var t0: int = int(J[4]) if on_a else int(J[1])
		var t1: int = int(J[5]) if on_a else int(J[2])
		var u := clampf(float(i - z0) / maxf(1.0, float(z1 - z0)), 0.0, 1.0)
		var m := roundi(t0 + u * (t1 - t0) if int(J[6]) > 0 else t1 - u * (t1 - t0))
		var hw: float = R.w[i] / 2.0
		sim._nearest_on(q, R.px[i] + R.nx[i] * sgn * hw, R.py[i] + R.ny[i] * sgn * hw, m, 16)
		if not sim._n_off and absf(sim._n_lat) < sim._n_w / 2.0 - 1.0:
			return true
	return false


## A whole chunk now (tests; the stream builds them a slice at a time, _start_chunk and _work).
func _build_chunk(r: int, k: int) -> void:
	_start_chunk(r, k)
	_work(Time.get_ticks_usec() + 60000000)


## The chunk's node, in place (empty) and in `chunks`, and its build in hand.
func _start_chunk(r: int, k: int) -> void:
	var R = sim.roads[r]
	var c0 := k * CH
	var c1 := mini((k + 1) * CH, R.N - 1)
	var w0 := _wxy(r, c0)
	var ox: float = w0.x
	var oy: float = w0.y
	var node := Node3D.new()
	node.name = "%s_%d" % [R.name, k]
	add_child(node)
	var key := Vector2i(r, k)
	chunks[key] = [node, ox, oy]
	built += 1
	var st := []
	for q in 5:   # the road, deco, glow, lit strips, beacons
		var t := SurfaceTool.new()
		t.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append(t)
	_job = {"key": key, "r": r, "c0": c0, "c1": c1, "i": c0, "ox": ox, "oy": oy, "node": node, "st": st,
		"n_lamps": 0, "made": false, "signs": _signs.get(key, []), "si": 0, "us": 0, "d": 0.0,
		"rv": PackedVector3Array(), "rn": PackedVector3Array(), "ru": PackedVector2Array(), "rows": 0, "cols": 0,
		"u0": fposmod(_s[r][c0], ASPHALT_PERIOD) - _s[r][c0]}   # (the asphalt's u, continuous along the chunk)


## Build on the chunk in hand until `end` (usec): its samples, then its meshes, then its boards one at
## a time. True when it's finished (and _job is empty again).
func _work(end: int) -> bool:
	var J := _job
	var t0 := Time.get_ticks_usec()
	var R = sim.roads[J.r]
	var done := false
	while true:
		if J.i < J.c1:
			_sample(J, R, J.i)
			J.i += 1
		elif not J.made:
			_finish(J, R)
			J.made = true
		elif J.si < (J.signs as Array).size():
			_sign(J.node, R, J.r, J.ox, J.oy, J.signs[J.si])
			J.si += 1
		else:
			done = true
			break
		if Time.get_ticks_usec() >= end:
			break
	J.us += Time.get_ticks_usec() - t0
	if done:
		build_ms_max = maxf(build_ms_max, J.us / 1000.0)
		_job = {}
	return done


## Sample i of the chunk in hand: its stretch of road, lines, deck, walls, masts.
func _sample(J: Dictionary, R, i: int) -> void:
	var r: int = J.r
	var ox: float = J.ox
	var oy: float = J.oy
	var deco: SurfaceTool = J.st[1]
	var glow: SurfaceTool = J.st[2]
	var lglow: SurfaceTool = J.st[3]
	var lamps: SurfaceTool = J.st[4]
	var j := i + 1
	var hw: float = R.w[i] / 2.0
	var hi := _h(r, i)
	var hj := _h(r, j)
	var city: bool = R.mode[i] == 0
	var sec := _section(R.w[i])
	var te: float = sec.te   # the edges' ramps' top: the walls stand on it
	var on_shaft: bool = R.shaft and shaft.on(r, float(i))
	_up = (shaft.at(r, float(i))[5] as Vector3) if on_shaft else Vector3.UP
	# the road: a flat middle and a ramp up each side (the sims' net_edge), a row of the chunk's grid
	# a sample (its normals banked with the ramps)
	if i == int(J.c0):
		_road_row(J, R, sec, i, hi)
	_road_row(J, R, sec, j, hj)
	for ln in sec.lines:   # the edge lines on the ramps' tops, a dim one at each ramp's foot
		_strip(deco, R, ox, oy, i, ln[0], ln[1], hi + 0.04, hj + 0.04, ln[4], ln[2], ln[3])
	# a flyover's deck: its edges, its underside, its pillars
	if hi > 4.0 or hj > 4.0:
		for sgn in [-1.0, 1.0]:
			var ea := _p(R, ox, oy, i, sgn * hw, hi)
			var eb := _p(R, ox, oy, j, sgn * hw, hj)
			_quad(deco, [ea - _up * DECK, eb - _up * DECK, eb + _up * te, ea + _up * te], Color(0.55, 0.55, 0.53))
			_quad(lglow, [ea - _up * DECK, eb - _up * DECK, eb - _up * (DECK - 0.8), ea - _up * (DECK - 0.8)], STRIP_LIGHT)   # a lit line along its foot
		_quad(deco, [_p(R, ox, oy, i, hw, hi - DECK), _p(R, ox, oy, i, -hw, hi - DECK), _p(R, ox, oy, j, -hw, hj - DECK), _p(R, ox, oy, j, hw, hj - DECK)], Color(0.32, 0.32, 0.31))
		var high := hi > 150.0   # a jump's kick or deck: pylons, fewer and thicker
		if not on_shaft and i % (40 if high else PILLAR_EVERY) == 0 and hi > DECK + 2.0:
			for sgn in [-1.0, 1.0]:
				var foot := _p(R, ox, oy, i, sgn * (hw - 30.0), 0.0)
				var thick := 14.0 if not high else 20.0 + hi * 0.02
				_box(deco, foot + Vector3.UP * (hi - DECK) / 2.0, Vector3(thick, hi - DECK, thick), Color(0.6, 0.6, 0.58))
	if halls.has(r) and i >= int(halls[r][0]) and i < int(halls[r][1]):
		_hall(J, R, i, hw, hi + te, hj + te)
	if on_shaft and i % HOOP_EVERY == 0:
		_hoop(J, R, i, hw, hi + te, i % (HOOP_EVERY * 2) == 0)
	if R.role == "launch" and i % CHEV_EVERY == 0 and i < R.N - 4:
		_chevron(lglow, R, ox, oy, i, hi, 1.0)
	# the walls, the strip on top, the masts
	for sgn in [-1.0, 1.0]:
		if _open(r, i, sgn):
			walls_open += 1
			continue
		var wa := _p(R, ox, oy, i, sgn * hw, hi + te)   # (on the ramp's top)
		var wb := _p(R, ox, oy, j, sgn * hw, hj + te)
		var top := BAND_H
		_wall(deco, wa, wb, 0.0, WALL_H, Color(0.72, 0.71, 0.68))
		_wall(deco, wa, wb, WALL_H, BAND_H, (BAND_SF if city else BAND)[(i / 4) % 2])
		if city:
			var slate := 0.2 + 0.035 * ((i / 4) % 2)
			_wall(deco, wa, wb, BAND_H, FENCE_H, Color(slate, slate + 0.01, slate + 0.03))
			top = FENCE_H
		_wall(lglow, wa, wb, top, top + STRIP_H, WALL_STRIP_SF if city else WALL_STRIP)
		if i % (8 if city else MAST_EVERY) == 0 and not on_shaft:
			var foot := _p(R, ox, oy, i, sgn * (hw + 0.4), hi + te)
			_box(deco, foot + Vector3.UP * (MAST_H / 2.0), Vector3(0.6, MAST_H, 0.6), Color(0.3, 0.31, 0.33))
			_box(glow, foot + Vector3.UP * (MAST_H + 0.45), Vector3(0.9, 0.9, 0.9), STRIP_LIGHT)
			_beacon(lamps, foot + Vector3.UP * (MAST_H + 0.45), BAND_SF[0] if city else STRIP_LIGHT)
			J.n_lamps += 1


## A city's hall over sample i (the Network's tunnels, as Eridanus' covered ramps): its walls on up
## from the fence to a roof HALL_H over the road, the roof, a lit strip down each wall, a steel rib
## every HALL_RIB_EVERY samples, a lit bar across the roof every HALL_LIGHT_EVERY (the speed cue
## overhead), a lit band round each portal.
func _hall(J: Dictionary, R, i: int, hw: float, hi: float, hj: float) -> void:
	hall_samples += 1
	var r: int = J.r
	var ox: float = J.ox
	var oy: float = J.oy
	var deco: SurfaceTool = J.st[1]
	var lglow: SurfaceTool = J.st[3]
	var j := i + 1
	var a0 := _p(R, ox, oy, i, -hw, hi)
	var b0 := _p(R, ox, oy, j, -hw, hj)
	var a1 := _p(R, ox, oy, i, hw, hi)
	var b1 := _p(R, ox, oy, j, hw, hj)
	_wall(deco, b0, a0, FENCE_H, HALL_H, HALL_COL)   # (both faced in: -hw is the right, so its run is reversed)
	_wall(deco, a1, b1, FENCE_H, HALL_H, HALL_COL)
	var up := Vector3.UP * HALL_H
	_quad(deco, [a1 + up, b1 + up, b0 + up, a0 + up], HALL_COL.darkened(0.15))   # the roof's underside
	_quad(deco, [a0 + up + Vector3.UP * 4.0, b0 + up + Vector3.UP * 4.0, b1 + up + Vector3.UP * 4.0, a1 + up + Vector3.UP * 4.0], Color(0.36, 0.37, 0.39))   # its top
	for e in [[a0, b0, 1.0], [a1, b1, -1.0]]:   # a lit strip down each wall, just off it
		var ea: Vector3 = e[0]
		var eb: Vector3 = e[1]
		var inward := (_p(R, ox, oy, i, 0.0, hi) - ea).normalized() * 0.3
		_wall(lglow, ea + inward, eb + inward, HALL_STRIP_H, HALL_STRIP_H + 2.4, STRIP_LIGHT)
	if i % HALL_RIB_EVERY == 0:   # a steel rib: a beam under the roof and a pilaster down each wall
		var steel := Color(0.12, 0.13, 0.15)
		var along := (b0 - a0).normalized() * 3.0
		_quad(deco, [a0 + up + Vector3.DOWN * 5.0, a1 + up + Vector3.DOWN * 5.0, a1 + up + Vector3.DOWN * 5.0 + along, a0 + up + Vector3.DOWN * 5.0 + along], steel)
		for e in [[a0, 1.0], [a1, -1.0]]:
			var p: Vector3 = e[0]
			var inward := (_p(R, ox, oy, i, 0.0, hi) - p).normalized() * 1.5
			_wall(deco, p + inward, p + inward + along, FENCE_H, HALL_H, steel)
	if i % HALL_LIGHT_EVERY == 0:   # a bar across, 92% of the span, a third of the sample long
		var y := Vector3.UP * (HALL_H - 0.6)
		var p0 := a0.lerp(a1, 0.04) + y
		var p1 := a1.lerp(a0, 0.04) + y
		var p2 := p1.lerp(b1.lerp(b0, 0.04) + y, 0.3)
		var p3 := p0.lerp(b0.lerp(b1, 0.04) + y, 0.3)
		_quad(lglow, [p0, p1, p2, p3], STRIP_LIGHT)
	var span: Array = halls[r]
	if i == int(span[0]) or i == int(span[1]) - 1:   # a portal: a lit band across the roof's edge and down both walls
		var q0 := a0 if i == int(span[0]) else b0
		var q1 := a1 if i == int(span[0]) else b1
		_wall(lglow, q0, q1, HALL_H - 3.0, HALL_H, WALL_STRIP_SF)
		for q in [q0, q1]:
			_box(lglow, q + Vector3.UP * (HALL_H / 2.0), Vector3(3.0, HALL_H - FENCE_H, 3.0), WALL_STRIP_SF)


## A shaft's hoop round sample i: two legs and a beam over the road, HOOP_H clear, faced both ways so
## it reads from outside too; every second one lit. Going up through them is the speed cue.
func _hoop(J: Dictionary, R, i: int, hw: float, h: float, lit: bool) -> void:
	var ox: float = J.ox
	var oy: float = J.oy
	var st: SurfaceTool = J.st[3] if lit else J.st[1]
	var c := WALL_STRIP if lit else Color(0.16, 0.17, 0.2)
	var j := mini(i + 1, R.N - 1)
	var a0 := _p(R, ox, oy, i, -hw, h)
	var a1 := _p(R, ox, oy, i, hw, h)
	var along := (_p(R, ox, oy, j, 0.0, h) - _p(R, ox, oy, i, 0.0, h)).normalized() * 8.0
	var top := _up * HOOP_H
	for q in [[a0, a0 + top], [a0 + top, a1 + top], [a1 + top, a1]]:
		var p: Vector3 = q[0]
		var e: Vector3 = q[1]
		_quad(st, [p, e, e + along, p + along], c)
		_quad(st, [p + along, e + along, e, p], c)


## A lit chevron across the road at sample i, its point the way `way` (1 up the samples): on a launch
## spur, pointing you up it.
func _chevron(st: SurfaceTool, R, ox: float, oy: float, i: int, h: float, way: float) -> void:
	var hw: float = R.w[i] / 2.0 * 0.62
	var t := Vector3(R.tx[i], 0.0, -R.ty[i]) * way
	var c := Color(1.0, 0.55, 0.12)
	var mid := _p(R, ox, oy, i, 0.0, h + 0.1)
	var run := 90.0   # the arms sweep back this far
	var wide := 18.0  # along the road, each arm
	for sd in [-1.0, 1.0]:
		var e := _p(R, ox, oy, i, sd * hw, h + 0.1) - t * run
		var q := [mid, mid + t * wide, e + t * wide, e] if sd > 0.0 else [e, e + t * wide, mid + t * wide, mid]
		_quad(st, q, c)


## The chunk in hand's ends (a barrier where nothing goes on), its meshes committed.
func _finish(J: Dictionary, R) -> void:
	var r: int = J.r
	var ox: float = J.ox
	var oy: float = J.oy
	var c0: int = J.c0
	var c1: int = J.c1
	var node: Node3D = J.node
	var deco: SurfaceTool = J.st[1]
	var glow: SurfaceTool = J.st[2]
	var lglow: SurfaceTool = J.st[3]
	var lamps: SurfaceTool = J.st[4]
	# an open end (no road beyond it): a launch spur's lip, a catch deck's lip, an on-ramp's mouth on
	# the open ground, or the end of the road (past a turnaround's split: the open ground beyond)
	for e in [c0, c1]:
		if (e == 0 or e == R.N - 1) and not _joined_at(r, e):
			var hw: float = R.w[e] / 2.0
			var he := _h(r, e)
			var te := CraftSim.net_edge(R.w[e], hw).x
			var pa := _p(R, ox, oy, e, -hw, he + te + 0.05)   # (its sides: on the ramps' top)
			var pb := _p(R, ox, oy, e, hw, he + te + 0.05)
			var back := Vector3(R.tx[e], 0.0, -R.ty[e]) * (-1.0 if e == R.N - 1 else 1.0)   # onto the road from its end
			if R.role == "launch":   # the lip: hazard bars up to its edge, lit
				for k in 6:
					_across(lglow, R, ox, oy, e, he, back * (k * 40.0), back * (k * 40.0 + 14.0), Color(1.0, 0.45, 0.1))
				_lip(lglow, R, ox, oy, e, he, Color(1.0, 0.55, 0.15))
			elif R.role == "catch":   # the catch: a green-lit line across its lip, bars onto it
				for k in 4:
					_across(lglow, R, ox, oy, e, he, back * (k * 60.0), back * (k * 60.0 + 10.0), Color(0.3, 1.0, 0.5))
				_lip(lglow, R, ox, oy, e, he, Color(0.3, 1.0, 0.5))
			elif R.role == "on":   # an on-ramp's mouth: lit posts either side, a line across
				for sd in [pa, pb]:
					_box(deco, sd + Vector3.UP * 12.0, Vector3(3.0, 24.0, 3.0), Color(0.3, 0.31, 0.33))
					_box(glow, sd + Vector3.UP * 24.5, Vector3(3.6, 1.2, 3.6), Color(1.0, 0.75, 0.3))
				_across(lglow, R, ox, oy, e, he, Vector3.ZERO, back * 6.0, Color(1.0, 0.75, 0.3))
			else:   # the end of the road: an amber line across, the open ground beyond
				_across(lglow, R, ox, oy, e, he, Vector3.ZERO, back * 8.0, Color(1.0, 0.6, 0.15))
	# one instance, a surface (and its material) each: the floating origin moves every chunk every
	# frame, and four instances a chunk cost ~0.4 ms a frame in transform updates at a crossing
	var mesh := ArrayMesh.new()
	if int(J.rows) > 1:   # the road's grid
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = J.rv
		arr[Mesh.ARRAY_NORMAL] = J.rn
		arr[Mesh.ARRAY_TEX_UV] = J.ru
		arr[Mesh.ARRAY_INDEX] = _grid_index(int(J.rows), int(J.cols))
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, _asph)
	for pair in [[deco, _mat], [glow, _lit], [lglow, _strip_mat]]:
		var n0 := mesh.get_surface_count()
		(pair[0] as SurfaceTool).commit(mesh)
		if mesh.get_surface_count() > n0:
			mesh.surface_set_material(n0, pair[1])
	var mi := MeshInstance3D.new()
	mi.name = "road"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	if int(J.n_lamps) > 0:
		var bm := MeshInstance3D.new()
		bm.name = "beacons"
		bm.mesh = lamps.commit()
		bm.material_override = _beam
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.extra_cull_margin = 400.0
		node.add_child(bm)


## Does a junction take road r on at its sample e (one of its ends)?
func _joined_at(r: int, e: int) -> bool:
	for k in sim.roads[r].jx:
		var J: Array = sim.junctions[k]
		var on_a: bool = int(J[0]) == r
		var z0: int = int(J[1]) if on_a else int(J[4])
		var z1: int = int(J[2]) if on_a else int(J[5])
		if e >= z0 - 2 and e <= z1 + 2:
			return true
	return false


# --- signs ---------------------------------------------------------------------------------------

## Where every sign stands, by chunk: [i, dir (the way the traffic it faces goes), kind, lines].
func _plan_signs() -> void:
	var seen_turn := {}
	for k in sim.junctions.size():
		var J: Array = sim.junctions[k]
		var p := int(J[0])
		var c := int(J[3])
		var C = sim.roads[c]
		var at_start: bool = int(J[4]) == 0
		var cb: int = 0 if at_start else C.N - 1
		var ca := _map(J, cb)
		var sense := int(J[6])
		var dq := 1 if at_start else -1           # into the joining road
		var dp := dq * sense                       # on the parent, the way that takes you in
		var P = sim.roads[p]
		if C.role == "launch":
			_plan_jump(c, p, ca, dp)
			continue
		var at := ca - dp * SIGN_BEFORE
		if at < 1 or at > P.N - 2:
			continue
		var lines := []
		var kind := "exit"
		if C.role != "":
			continue   # a catch deck or an on-ramp, taken backwards: nowhere but an open end
		elif C.name.begins_with("T"):
			if seen_turn.has(c):
				continue
			seen_turn[c] = true
			kind = "end"
			lines = ["END OF THE ROAD", "SHAFT  %d MI" % roundi(SIGN_BEFORE * 24.0 / MILE)]
		elif C.name.begins_with("S"):
			lines = ["SIDE ROAD", "%d MI" % roundi(C.length / MILE)]
		else:
			var d := _dists(c, cb, dq)
			var best := []
			for ci in sim.cities.size():
				if d[ci] < INF:
					best.append([d[ci], ci])
			best.sort_custom(func(x, y): return x[0] < y[0])
			var city := _city_of(c)
			if city >= 0:
				lines = [sim.cities[city].name, "EXIT  %d MI" % maxi(1, roundi((d[city] + SIGN_BEFORE * 24.0) / MILE))]
				kind = "city"
			else:
				lines = ["EXIT"]
				for q in best.slice(0, 2):
					lines.append("%s  %d MI" % [sim.cities[q[1]].name, maxi(1, roundi((q[0] + SIGN_BEFORE * 24.0) / MILE))])
		_add_sign(p, at, dp, kind, lines)
	# braking boards before each city's STARFIGHTER zone, both ways; its name over the terminal
	for ci in sim.cities.size():
		var city: Dictionary = sim.cities[ci]
		var R = sim.roads[city.road]
		var z0 := -1
		var z1 := -1
		for i in R.N:
			if R.mode[i] == 0:
				if z0 < 0:
					z0 = i
				z1 = i
		for mi in BRAKE_MI:
			var n := roundi(mi * MILE / 24.0)
			if z0 - n > 0:
				_add_sign(city.road, z0 - n, 1, "brake", ["%d MI" % mi, "STARFIGHTER ZONE"])
			if z1 + n < R.N - 1:
				_add_sign(city.road, z1 + n, -1, "brake", ["%d MI" % mi, "STARFIGHTER ZONE"])
		_add_sign(city.road, city.i, 1, "terminal", [city.name])
		_add_sign(city.road, city.i, -1, "terminal", [city.name])
	for r in sim.roads.size():
		if sim.roads[r].name.begins_with("S"):
			_plan_corners(r)


## A jump's boards: launch spur c forks off exit ramp p at the ramp's sample `fork`, going dp along it.
## Two on the highway before the ramp's mouth (the arrow up and to the right), one over the fork (the
## arrow straight on: the ramp curves away, the spur doesn't).
func _plan_jump(c: int, p: int, fork: int, dp: int) -> void:
	var mph := 3000
	for jp in sim.jumps:
		if int(jp[0]) == c:
			mph = int(jp[2])
	var lines := ["JUMP", "%d,%03d+ MPH" % [mph / 1000, mph % 1000]]
	var P = sim.roads[p]
	_add_sign(p, clampi(fork - dp * FORK_BEFORE, 1, P.N - 2), dp, "fork", lines)
	# the ramp's mouth this way: the ramp's end behind the fork, on its highway
	var e: int = 0 if dp > 0 else P.N - 1
	for k in sim.junctions.size():
		var J: Array = sim.junctions[k]
		if int(J[3]) != p or not (int(J[4]) <= e and e <= int(J[5])):
			continue
		var h := int(J[0])
		var at_mouth := _map(J, e)
		var way := dp * int(J[6])
		var H = sim.roads[h]
		for back in [SIGN_FAR, SIGN_NEAR]:
			var at: int = at_mouth - way * back
			if at > 0 and at < H.N - 1:
				_add_sign(h, at, way, "jump", lines)


## Side road r's corners: a board before each bend CORNER_MIN_K or tighter, both ways: the speed that
## holds it at CORNER_G and the gear for that speed, so the bend tells you to shift.
func _plan_corners(r: int) -> void:
	var R = sim.roads[r]
	var i := 0
	while i < R.N:
		if absf(R.kap[i]) < CORNER_MIN_K:
			i += 1
			continue
		var e := i
		while e + 1 < R.N and R.kap[e + 1] == R.kap[i]:
			e += 1
		var mph := sqrt(CORNER_G * 9.81 / absf(R.kap[i])) * 2.236936
		var lines := ["%d,%03d" % [int(mph / 100.0) * 100 / 1000, (int(mph / 100.0) * 100) % 1000], "GEAR %d" % gear_for(mph)]
		if i - CORNER_BEFORE > 0:
			_add_sign(r, i - CORNER_BEFORE, 1, "corner", lines)
		if e + CORNER_BEFORE < R.N - 1:
			_add_sign(r, e + CORNER_BEFORE, -1, "corner", lines)
		i = e + 1


## The gear that holds mph on SPEEDCRAFT (QuestControls' ranges).
static func gear_for(mph: float) -> int:
	for k in QuestControls.GEARS.size():
		if mph <= float(QuestControls.GEARS[k][2]) * QuestControls.V_TOP_SPEED * 2.236936:
			return k + 1
	return QuestControls.GEARS.size()


func _add_sign(r: int, i: int, dir: int, kind: String, lines: Array) -> void:
	var key := Vector2i(r, mini(i / CH, (sim.roads[r].N - 2) / CH))
	if not _signs.has(key):
		_signs[key] = []
	_signs[key].append([i, dir, kind, lines])


func _map(J: Array, cb: int) -> int:
	var u := float(cb - int(J[4])) / maxf(1.0, float(int(J[5]) - int(J[4])))
	return roundi(int(J[1]) + u * (int(J[2]) - int(J[1])) if int(J[6]) > 0 else int(J[2]) - u * (int(J[2]) - int(J[1])))


func _city_of(road: int) -> int:
	for ci in sim.cities.size():
		if int(sim.cities[ci].road) == road:
			return ci
	return -1


## Road distance (m) from (road, i) going dir to every city's terminal, by the junctions (the way a
## road can be entered: its start only going up it, its end only going down it).
func _dists(road: int, i: int, dir: int) -> Array:
	var out := []
	out.resize(sim.cities.size())
	out.fill(INF)
	var best := {}
	var heap := [[0.0, road, i, dir]]
	best[Vector3i(road, i, dir)] = 0.0
	while not heap.is_empty():
		var m := 0
		for q in range(1, heap.size()):
			if heap[q][0] < heap[m][0]:
				m = q
		var st: Array = heap.pop_at(m)
		var c: float = st[0]
		var r: int = st[1]
		var at: int = st[2]
		var d: int = st[3]
		if c > best.get(Vector3i(r, at, d), INF):
			continue
		for ci in sim.cities.size():
			var city: Dictionary = sim.cities[ci]
			if int(city.road) == r and (int(city.i) - at) * d >= 0:
				out[ci] = minf(out[ci], c + absi(int(city.i) - at) * 24.0)
		for k in sim.roads[r].jx:
			var J: Array = sim.junctions[k]
			var on_a: bool = int(J[0]) == r
			var C = sim.roads[int(J[3])]
			var cb: int = 0 if int(J[4]) == 0 else C.N - 1
			var ca := _map(J, cb)
			var zc: int = ca if on_a else cb
			if (zc - at) * d <= 0:
				continue
			var q := int(J[3]) if on_a else int(J[0])
			var iq: int = cb if on_a else ca
			var dq := d * int(J[6])
			var Q = sim.roads[q]
			var qz0 := int(J[4]) if on_a else int(J[1])
			var qz1 := int(J[5]) if on_a else int(J[2])
			if qz0 == 0 and dq < 0:
				continue
			if qz1 == Q.N - 1 and dq > 0:
				continue
			var nc := c + absi(zc - at) * 24.0
			var key := Vector3i(q, iq, dq)
			if nc < best.get(key, INF):
				best[key] = nc
				heap.append([nc, q, iq, dq])
	return out


## A sign over road r at its sample spec[0], facing traffic going spec[1].
func _sign(node: Node3D, R, r: int, ox: float, oy: float, spec: Array) -> void:
	var i: int = spec[0]
	var dir: int = spec[1]
	var kind: String = spec[2]
	var lines: Array = spec[3]
	var hw: float = R.w[i] / 2.0 + 4.0
	var h0 := _h(r, i)
	var tx: float = R.tx[i] * dir
	var ty: float = R.ty[i] * dir
	var t := Vector3(tx, 0.0, -ty)
	var b := Basis(Vector3.UP, atan2(ty, tx))
	var mid := _p(R, ox, oy, i, 0.0, h0)
	if kind == "terminal":   # a lit line across the road, and a gantry with the city's name
		var la := _p(R, ox, oy, i, -R.w[i] / 2.0, h0 + 0.06)
		var lb := _p(R, ox, oy, i, R.w[i] / 2.0, h0 + 0.06)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st, [la - t * 3.0, lb - t * 3.0, lb + t * 3.0, la + t * 3.0], Color(1.0, 1.0, 1.0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _bright
		node.add_child(mi)
	var small: bool = kind == "brake" or kind == "corner"
	var arrow: bool = kind == "jump" or kind == "fork"
	var w := JUMP_W if arrow else (BOARD_W if not small else 40.0)
	var h := JUMP_H if arrow else (BOARD_H if not small else 24.0)
	var foot := h0 + BOARD_CLEAR
	var steel := Color(0.22, 0.23, 0.25)
	var parts := []
	for sd in [-1.0, 1.0]:
		var q := _p(R, ox, oy, i, sd * hw, 0.0)
		parts.append([Kit.box(Vector3(2.4, foot + 4.0, 2.4)), Kit.at(q + Vector3(0, (foot + 4.0) / 2.0, 0)), steel])
	parts.append([Kit.box(Vector3(3.0, 4.0, hw * 2.0 + 2.4)), Transform3D(b, Vector3(mid.x, foot + 2.0, mid.z)), steel])
	var sc := Vector3(mid.x, foot + 4.0 + h / 2.0, mid.z)
	parts.append([Kit.box(Vector3(2.0, h + 4.0, w + 4.0)), Transform3D(b, sc), Color(0.1, 0.1, 0.12)])
	var frame := MeshInstance3D.new()
	frame.mesh = Kit.compound(parts)
	frame.material_override = _mat
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(frame)
	var facing := Basis(Vector3.UP, atan2(-tx, ty))   # +Z toward the oncoming craft
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	face.mesh = quad
	face.transform = Transform3D(facing, sc - t * 1.1)
	face.material_override = _arrow_mat if kind == "jump" else (_fork_mat if kind == "fork" else (_end_mat if kind == "end" else (_city_mat if kind == "terminal" or kind == "city" else _board_mat)))
	node.add_child(face)
	var n := lines.size()
	for li in n:
		var l := Label3D.new()
		l.text = lines[li]
		l.font_size = (FONT[0] if li == 0 else FONT[1]) if not small else (FONT[3] if li == 0 else FONT[4])
		if n >= 3 and li > 0:
			l.font_size = FONT[2]
		l.pixel_size = SIGN_PX * (ARROW_WORDS if arrow else 1.0)
		l.outline_size = 0
		l.modulate = Color(0.03, 0.03, 0.04)
		l.double_sided = false
		var up := (h / 2.0 - h / (n + 1.0) * (li + 1.0)) if n > 1 else 0.0
		var aside := facing * Vector3.RIGHT * (-w * ARROW_PANEL / 2.0) if arrow else Vector3.ZERO   # (the words left of the arrow's panel)
		l.transform = Transform3D(facing, sc + Vector3.UP * up - t * 1.4 + aside)
		node.add_child(l)
	boards += 1


## Every glyph the signs use, at every size, rasterised now (labels under the ground, freed a few
## frames on), not when a board streams in at 4,000 mph.
func _warm_fonts() -> void:
	var holder := Node3D.new()
	holder.name = "font_warm"
	add_child(holder)
	for fs in FONT:
		var l := Label3D.new()
		l.text = SIGN_CHARS
		l.font_size = fs
		l.pixel_size = SIGN_PX
		l.position = Vector3(0.0, -400.0, 0.0)
		holder.add_child(l)
	for m in [_arrow_mat, _fork_mat, _end_mat, _city_mat, _board_mat]:   # ... and the boards' shaders, drawn once under the ground
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(4.0, 4.0)
		q.mesh = qm
		q.material_override = m
		q.position = Vector3(0.0, -60.0, -40.0)
		holder.add_child(q)
	get_tree().create_timer(1.0).timeout.connect(holder.queue_free)


# --- skylines ------------------------------------------------------------------------------------

## Each city's towers: a jittered grid round its centre, tallest in the middle, none within 450 m of
## a road; one MultiMesh a city (a box per tower and a lit crown), hazed by view/skyline.gdshader.
func _build_skylines() -> void:
	var near_pts := {}   # Vector2i(500 m cell) -> true, every 4th road sample within 20 km of a city
	for r in sim.roads.size():
		var R = sim.roads[r]
		for i in range(0, R.N, 4):
			for city in sim.cities:
				if absf(R.px[i] - city.cx) < 20000.0 and absf(R.py[i] - city.cy) < 20000.0:
					near_pts[Vector2i(int(floor(R.px[i] / 500.0)), int(floor(R.py[i] / 500.0)))] = true
					break
	var sh := preload("res://view/skyline.gdshader")
	for ci in sim.cities.size():
		var city: Dictionary = sim.cities[ci]
		var pal: Array = PALETTE.get(city.biome, PALETTE.verdant)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (ci + 1)
		var xfs := []
		var cols := []
		var g := 520.0
		for gx in range(-16, 17):
			for gy in range(-16, 17):
				var x: float = city.cx + gx * g + rng.randf_range(-150.0, 150.0)
				var y: float = city.cy + gy * g + rng.randf_range(-150.0, 150.0)
				var rr := Vector2(x - city.cx, y - city.cy).length()
				if rr > 8000.0 or rng.randf() < rr / 9000.0 * 0.6:
					continue
				var cell := Vector2i(int(floor(x / 500.0)), int(floor(y / 500.0)))
				var clear := true
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						if near_pts.has(cell + Vector2i(dx, dy)):
							clear = false
				if not clear:
					continue
				var tall := lerpf(1000.0, 140.0, pow(clampf(rr / 8000.0, 0.0, 1.0), 0.6)) * rng.randf_range(0.55, 1.15)
				var foot := rng.randf_range(70.0, 190.0)
				xfs.append(Transform3D(Basis.from_scale(Vector3(foot, tall, foot * rng.randf_range(0.6, 1.4))).rotated(Vector3.UP, rng.randf() * PI),
					Vector3(x - city.cx, tall / 2.0, -(y - city.cy))))
				cols.append(pal[0].lerp(pal[1], rng.randf()))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Kit.box(Vector3.ONE)
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
			mm.set_instance_color(k, cols[k])
		var node := Node3D.new()
		node.name = "skyline_%s" % city.name
		add_child(node)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("crown", Vector3(pal[2].r, pal[2].g, pal[2].b))
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = TOWER_VIS
		mmi.custom_aabb = AABB(Vector3(-9000, 0, -9000), Vector3(18000, 1300, 18000))
		node.add_child(mmi)
		skylines.append([node, city.cx, city.cy])
		towers += xfs.size()
		cities_built += 1


## Each shaft's shape from far off (down a dead-straight highway you see it coming from 100 km): a flat
## ribbon, unfogged, a blue-grey that sits in the haze, gone where the road's own chunks take over.
func _build_far_shafts() -> void:
	var m := Kit.vertex_colors(true)
	m.disable_fog = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 1.0, 1.0)
	var col := Color(0.46, 0.54, 0.66)
	for sh in sim.shafts:
		var r := int(sh[0])
		var R = sim.roads[r]
		var i0 := int(sh[1])
		var i1 := int(sh[2])
		var o := _wxy(r, i0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hw: float = R.w[i0] / 2.0
		var keep := _up
		for i in range(i0 + 1, i1 - 24, 24):
			var j := mini(i + 24, i1 - 1)
			_up = shaft.at(r, float(i))[5]
			var hi := _h(r, i)
			var hj := _h(r, j)
			_quad(st, [_p(R, o.x, o.y, i, -hw, hi), _p(R, o.x, o.y, i, hw, hi), _p(R, o.x, o.y, j, hw, hj), _p(R, o.x, o.y, j, -hw, hj)], col)
		_up = keep
		var mi := MeshInstance3D.new()
		mi.name = "far_%s" % R.name
		mi.mesh = st.commit()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_begin = VIS * 0.9
		mi.visibility_range_end = TOWER_VIS
		add_child(mi)
		far_shafts.append([mi, o.x, o.y])


# --- mesh helpers --------------------------------------------------------------------------------

## A road `w` wide across (cached by width: a chunk asks every sample), right edge to left, EDGE_SEGS
## facets up each ramp and the flat middle between: o (offsets left of the centreline), h (the ramp's
## height there), c and s (the normal's up and inward parts: banked toward the middle), te (the
## ramps' top), lines ([o0, o1, its height at each, colour]: the edge lines, the ramps' feet).
func _section(w: float) -> Dictionary:
	if _sec_cache.has(w):
		return _sec_cache[w]
	var hw := w / 2.0
	var E := CraftSim.net_edge_span(w)
	var o := PackedFloat32Array()
	for k in EDGE_SEGS + 1:
		o.append(-hw + E * float(k) / EDGE_SEGS)
	for k in EDGE_SEGS + 1:
		o.append(hw - E + E * float(k) / EDGE_SEGS)
	var h := PackedFloat32Array()
	var c := PackedFloat32Array()
	var s := PackedFloat32Array()
	for x in o:
		var e := CraftSim.net_edge(w, x)
		h.append(e.x)
		c.append(cos(e.y))
		s.append(signf(x) * sin(e.y))
	var lines := []
	for sgn in [-1.0, 1.0]:
		for ln in [[hw - 1.5 - LINE_W, hw - 1.5, Color(0.92, 0.92, 0.9)], [hw - E, hw - E + LINE_W, EDGE_FOOT]]:
			var o0: float = minf(sgn * ln[0], sgn * ln[1])   # (o0 < o1 on both sides: the right side's ran outward-in,
			var o1: float = maxf(sgn * ln[0], sgn * ln[1])   # facing down, lit from below: its lines were dim)
			lines.append([o0, o1, CraftSim.net_edge(w, o0).x, CraftSim.net_edge(w, o1).x, ln[2]])
	var out := {"o": o, "h": h, "c": c, "s": s, "te": CraftSim.net_edge(w, hw).x, "lines": lines}
	_sec_cache[w] = out
	return out


## Road r's grid row at its sample s (the deck's height h there): the section's points, banked
## normals, the asphalt's uv (u along, v the offset).
func _road_row(J: Dictionary, R, sec: Dictionary, s: int, h: float) -> void:
	var o: PackedFloat32Array = sec.o
	var hh: PackedFloat32Array = sec.h
	var cc: PackedFloat32Array = sec.c
	var ss: PackedFloat32Array = sec.s
	var left := Vector3(R.nx[s], 0.0, -R.ny[s])
	var mid := Vector3(R.px[s] - J.ox, h + 0.02, -(R.py[s] - J.oy))
	var up := Vector3.UP
	if R.shaft and shaft.on(J.r, float(s)):
		var A: Array = shaft.at(J.r, float(s))
		left = A[4]
		up = A[5]
		mid = Vector3(float(A[0]) - J.ox, A[2], -(float(A[1]) - J.oy)) + up * 0.02
	var u: float = J.u0 + _s[J.r][s]
	var rv: PackedVector3Array = J.rv
	var rn: PackedVector3Array = J.rn
	var ru: PackedVector2Array = J.ru
	for k in o.size():
		rv.append(mid + left * o[k] + up * hh[k])
		rn.append(up * cc[k] - left * ss[k])
		ru.append(Vector2(u, o[k]))
	J.rv = rv
	J.rn = rn
	J.ru = ru
	J.rows = int(J.rows) + 1
	J.cols = o.size()


## The road grid's triangles (rows of `cols` points), cached by size: the same for every chunk.
func _grid_index(rows: int, cols: int) -> PackedInt32Array:
	var key := Vector2i(rows, cols)
	if _idx_cache.has(key):
		return _idx_cache[key]
	var idx := PackedInt32Array()
	for a in rows - 1:
		for k in cols - 1:
			var p := a * cols + k
			for q in [p, p + 1, p + cols + 1, p, p + cols + 1, p + cols]:
				idx.append(q)
	_idx_cache[key] = idx
	return idx


## A band across the road's end sample e (its open end's marks), from `d0` to `d1` off it, over the
## section (the ramps too).
func _across(st: SurfaceTool, R, ox: float, oy: float, e: int, he: float, d0: Vector3, d1: Vector3, c: Color) -> void:
	var sec := _section(R.w[e])
	var o: PackedFloat32Array = sec.o
	var hh: PackedFloat32Array = sec.h
	for k in o.size() - 1:
		var a := _p(R, ox, oy, e, o[k], he + hh[k] + 0.05)
		var b := _p(R, ox, oy, e, o[k + 1], he + hh[k + 1] + 0.05)
		_quad(st, [a + d0, b + d0, b + d1, a + d1], c)


## A lip's lit face: down DECK from the road's end, its ramps too.
func _lip(st: SurfaceTool, R, ox: float, oy: float, e: int, he: float, c: Color) -> void:
	var sec := _section(R.w[e])
	var o: PackedFloat32Array = sec.o
	var hh: PackedFloat32Array = sec.h
	for k in o.size() - 1:
		_quad(st, [_p(R, ox, oy, e, o[k], he - DECK), _p(R, ox, oy, e, o[k + 1], he - DECK), _p(R, ox, oy, e, o[k + 1], he + hh[k + 1] + 0.05), _p(R, ox, oy, e, o[k], he + hh[k] + 0.05)], c)


## A strip along sample i, from o0 to o1 m left of the centreline, raised e0 and e1 there (on the
## edges' ramps).
func _strip(st: SurfaceTool, R, ox: float, oy: float, i: int, o0: float, o1: float, h0: float, h1: float, c: Color, e0 := 0.0, e1 := 0.0) -> void:
	var a := _p(R, ox, oy, i, o0, h0 + e0)
	var b := _p(R, ox, oy, i, o1, h0 + e1)
	var cc := _p(R, ox, oy, i + 1, o1, h1 + e1)
	var d := _p(R, ox, oy, i + 1, o0, h1 + e0)
	for q in [a, b, cc, a, cc, d]:
		st.set_color(c)
		st.set_normal(_up)
		st.add_vertex(q)


func _wall(st: SurfaceTool, a: Vector3, b: Vector3, h0: float, h1: float, c: Color) -> void:
	var nrm := (b - a).cross(_up).normalized()
	for q in [a + _up * h0, b + _up * h0, b + _up * h1, a + _up * h0, b + _up * h1, a + _up * h1]:
		st.set_color(c)
		st.set_normal(nrm)
		st.add_vertex(q)


func _quad(st: SurfaceTool, q: Array, c: Color) -> void:
	var nrm: Vector3 = ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(c)
		st.set_normal(nrm)
		st.add_vertex(q[k])


func _box(st: SurfaceTool, ctr: Vector3, size: Vector3, c: Color) -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var hz := size.z / 2.0
	var v := [ctr + Vector3(-hx, -hy, -hz), ctr + Vector3(hx, -hy, -hz), ctr + Vector3(hx, hy, -hz), ctr + Vector3(-hx, hy, -hz),
		ctr + Vector3(-hx, -hy, hz), ctr + Vector3(hx, -hy, hz), ctr + Vector3(hx, hy, hz), ctr + Vector3(-hx, hy, hz)]
	for f in [[0, 1, 2, 3, Vector3.FORWARD], [5, 4, 7, 6, Vector3.BACK], [4, 0, 3, 7, Vector3.LEFT], [1, 5, 6, 2, Vector3.RIGHT], [3, 2, 6, 7, Vector3.UP]]:
		for q in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.set_color(c)
			st.set_normal(f[4])
			st.add_vertex(v[q])


func _beacon(st: SurfaceTool, p: Vector3, c: Color) -> void:
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_color(c)
		st.set_uv(uv)
		st.set_uv2(Vector2(0.0, 1e6))
		st.set_normal(Vector3.UP)
		st.add_vertex(p)
