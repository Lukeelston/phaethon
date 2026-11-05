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
const SceneryScript := preload("res://view/network_scenery.gd")
const SupportClearance := preload("res://view/network_support_clearance.gd")
const CH := 40                    # samples (~960 m), aligned with highway masts and the furniture cycle
const CELL := 8000.0              # the grid's cells, m
const VIS := 26000.0              # detailed roads; coarse pavement extends to 100 km
const DROP := 34000.0             # free them past this
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
const EDGE_SEGS := 6              # identical shoulder topology on both sides of every chunk boundary
const JOIN_EDGE_SEGS := EDGE_SEGS # overlap chunks must not change cross-section tessellation
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
const JUMP_AMBER := Color(1.0, 0.55, 0.08)
const BRAKE_MI := [4, 2, 1]       # braking boards, miles before a city's STARFIGHTER zone
const MILE := 1609.344
# the signs' glyphs: rendered at these sizes (px) and scaled up (SIGN_PX m a pixel), so a streamed
# board's first letters cost little to rasterise; all of them warmed at the start (_warm_fonts).
# (At 200 px each new glyph cost ~200 ms in the middle of a run.)
const FONT := [72, 43, 36, 79, 25]   # a board's title, its lines, three lines' lines; a braking board's miles, its words
const SIGN_PX := 0.139
const SIGN_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789/:+-.>,"
const JUMP_W := 300.0             # a jump's board: wider, its arrow on a panel at the right
const JUMP_H := 78.0
const ARROW_PANEL := 0.36
const SIGN_FAR := 536             # samples (8 mi) before a jump's exit: time to choose at highway speed
const SIGN_NEAR := 268             # samples (4 mi) before the exit
const ARROW_WORDS := 2.1          # a jump's board's words, this much bigger (the same glyphs, scaled)
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

var sim: CraftSim
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
var profile_streaming := false # optional benchmark instrumentation, disabled in play
var stream_profile := {}
var _catching_up := true  # finish the initial/teleport batch before reverting to flight's small slices
var sync_ms := 0.0        # this frame's sync (streaming and placing), ms
var setup_ms := 0
var walls_open := 0
var boards := 0
var cities_built := 0
var towers := 0
var skylines := []        # [node, cx, cy]
var far_shafts := []      # [node, ox, oy]: each shaft's shape from far off, before its chunks stream in
var _signs := {}
var _approaches := {}     # road -> [first, last, direction, lateral centre] for amber exit guidance
var halls := {}            # road -> [first, last sample] of its hall (the cities' terminals; CourseAudio reads it)
var hall_samples := 0      # samples built under a hall's roof (tests)          # Vector2i(road, chunk) -> Array of sign specs
var _s := []              # per road: distance along it at each sample (PackedFloat64Array)
var _heights := []        # immutable exact sample heights, shared by all streamed decoration
var _height_curves := {}  # current Hermite interval per road for fractional junction queries
var _deco_templates := {} # repeated straight, flat road furniture; asphalt UVs remain per chunk
var _asph: ShaderMaterial
var _mat: ShaderMaterial
var _lit: StandardMaterial3D
var _bright: StandardMaterial3D
var _strip_mat: StandardMaterial3D   # the walls' strips: lit, but not HDR-bright
var _paint_key := []
var _paint_rows := {}
var _paint_fine := false
var _sec_cache := {}               # road widths -> their sections (_section)
var _idx_cache := {}               # Vector2i(rows, cols) -> the road grid's triangles (_grid_index)
var _beam: ShaderMaterial
var _board_mat: ShaderMaterial
var _end_mat: ShaderMaterial
var _jump_mat: ShaderMaterial
var _city_mat: ShaderMaterial
var _arrow_mat: ShaderMaterial
var _fork_mat: ShaderMaterial
var _job := {}            # the chunk being built, a slice a frame (_start_chunk, _work)
var _join_surface_cache := {}     # Vector2(sample, offset), for the current chunk's road
var _join_projections := {}       # one nearest-road query shared by exact walls and the shaping apron
var _join_hints := {}             # sample -> joining roads and their nearest centreline hints
var _prepared_join_hints := {}    # road -> centreline projections in the immutable junction intervals
var _physical_join_cache := {}    # road -> exact immutable shoulder results in physical overlap intervals
var _join_cache_road := -1
var scenery: Node3D
var far_roads: Node3D
var scenery_ground_height := 0.0 # set by NetworkLandscape when its ground is present
var _pillar_cells := {} # fixed scenery, queried near the craft rather than scanning the whole map
var _pillars_indexed := false
var _pillar_specs_cache := {}   # immutable road/sample -> already cleared render/collision supports
var _support_clearance: RefCounted
const PILLAR_CELL := 512.0


func build(s, v) -> void:
	var t0 := Time.get_ticks_msec()
	sim = s
	view = v
	_paint_key.clear()
	_paint_rows.clear()
	_pillar_specs_cache.clear()
	_pillar_cells.clear()
	_pillars_indexed = false
	_support_clearance = null
	shaft = ShaftScript.new()
	shaft.setup(sim)
	for r in shaft.maps:
		_smap[sim.roads[int(r)]] = int(r)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://view/network_structure.gdshader")
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
	_jump_mat = _end_mat.duplicate() as ShaderMaterial
	_jump_mat.set_shader_parameter("flash_hz", 0.0) # stable amber remains legible; border lamps still chase
	_city_mat = ShaderMaterial.new()
	_city_mat.shader = preload("res://view/authorized.gdshader")
	_city_mat.set_shader_parameter("col", Vector3(0.25, 0.65, 1.0))
	_arrow_mat = ShaderMaterial.new()   # a jump's board on the highway: the arrow up and to the right, to the exit
	_arrow_mat.shader = preload("res://view/arrow_board.gdshader")
	_arrow_mat.set_shader_parameter("aspect", JUMP_W / JUMP_H)
	_arrow_mat.set_shader_parameter("panel", ARROW_PANEL)
	_arrow_mat.set_shader_parameter("angle", deg_to_rad(52.0))
	_arrow_mat.set_shader_parameter("flash_hz", 0.0) # accepted steady text; only the arrow and lamps animate
	_fork_mat = _arrow_mat.duplicate()  # ... over the fork: straight on
	_fork_mat.set_shader_parameter("angle", PI / 2.0)
	_asph = ShaderMaterial.new()
	_asph.shader = preload("res://view/asphalt.gdshader")
	_asph.set_shader_parameter("period", ASPHALT_PERIOD)
	_asph.set_shader_parameter("base", Vector3(0.21, 0.205, 0.205))
	_asph.set_shader_parameter("spec", 0.2)
	_asph.set_shader_parameter("lane_half", 60.0)
	for r in sim.roads.size():
		var R: CraftSim.TrackPath = sim.roads[r]
		var acc := PackedFloat64Array()
		acc.resize(R.N)
		var heights := PackedFloat64Array()
		heights.resize(R.N)
		var d := 0.0
		for i in R.N:
			acc[i] = d
			heights[i] = sim.net_height(r, float(i))
			d += R.len[i]
		_s.append(acc)
		_heights.append(heights)
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
	_warm_join_hints()
	_warm_physical_joins()
	_plan_signs()
	for c in sim.cities:   # a hall over each city's terminal: the Network's tunnels
		halls[int(c.road)] = [int(c.i) - HALL_HALF, int(c.i) + HALL_HALF]
	_build_skylines()
	_build_far_shafts()
	far_roads = preload("res://view/network_far_roads.gd").new()
	add_child(far_roads)
	far_roads.build(self)
	scenery = SceneryScript.new()
	add_child(scenery)
	scenery.build(sim, self)
	_warm_fonts()
	_warm_deco_templates()
	# Prepare nearby detail while the map is loading. Accurate junction paint
	# costs more to construct; the pilot should start on finished pavement,
	# rather than spend their first seconds watching that work stream in.
	var warm_deadline:=Time.get_ticks_usec()+220000
	for warm_frame in 28:
		sync(sim.pod.x,sim.pod.y)
		if (wanted==0 and _job.is_empty()) or Time.get_ticks_usec()>=warm_deadline: break
	setup_ms = Time.get_ticks_msec() - t0


## Junction centreline projections are static and reused by each shoulder offset.
## Prepare every declared interval, merging its padding to visit each row once.
## This avoids repeating the same nearest-segment search in adjacent chunks.
func _warm_join_hints() -> void:
	for r in sim.roads.size():
		var R: CraftSim.TrackPath = sim.roads[r]
		var intervals := []
		for ji in R.sjx:
			var join: Array = sim.surface_junctions[ji]
			var side := 0 if int(join[0]) == r else 3
			intervals.append(Vector2i(maxi(0, int(join[side + 1]) - 4), mini(R.N - 1, int(join[side + 2]) + 4)))
		intervals.sort_custom(func(a, b): return a.x < b.x)
		_join_hints = {}
		var last := -1
		for interval in intervals:
			for i in range(maxi(last + 1, interval.x), interval.y + 1):
				_joining_at(r, i)
			last = maxi(last, interval.y)
		_prepared_join_hints[r] = _join_hints
	_join_hints = {}
	_join_cache_road = -1


## Shared launch/highway shoulders never move. Prepare their exact projections
## while the map loads instead of spending the stream budget rediscovering them.
## Only the declared physical intervals are cached; no meshes or chunk nodes exist
## here. Curves and endpoint semantics use the same simulation search as before.
func _warm_physical_joins() -> void:
	for ji in range(sim.junctions.size(), sim.surface_junctions.size()):
		var join: Array = sim.surface_junctions[ji]
		for side in [0, 3]:
			var r := int(join[side])
			var R: CraftSim.TrackPath = sim.roads[r]
			if not _physical_join_cache.has(r):
				_physical_join_cache[r] = {}
			var cache: Dictionary = _physical_join_cache[r]
			for i in range(maxi(0, int(join[side + 1]) - 4), mini(R.N - 1, int(join[side + 2]) + 4) + 1):
				var sec := _section(R.w[i], true)
				for k in (sec.o as PackedFloat32Array).size():
					if float(sec.h[k]) <= 0.0:
						continue
					var off := float(sec.o[k])
					cache[Vector3(i, off, 24.0)] = _joined_surface(r, i, off, 24.0)
				for sgn in [-1.0, 1.0]:
					var off: float = sgn * R.w[i] / 2.0
					cache[Vector3(i, off, 0.0)] = _joined_surface(r, i, off)


## Prime reusable furniture while the map is loading, like the sign glyph cache.
## Temporary nodes are freed immediately; no live road chunks are preinstalled.
func _warm_deco_templates() -> void:
	var seen := {}
	var candidates := []
	var here := Vector2(sim.pod.x, sim.pod.y)
	for cell in grid:
		for entry in grid[cell]:
			var key := Vector2i(entry[0], entry[1])
			if seen.has(key):
				continue
			seen[key] = true
			var distance := (Vector2(entry[2], entry[3]) - here).length() - float(entry[4])
			if distance < VIS:
				candidates.append([distance, key])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for candidate in candidates:
		var key: Vector2i = candidate[1]
		var R: CraftSim.TrackPath = sim.roads[key.x]
		var first := key.y * CH
		var last := mini(first + CH, R.N - 1)
		var joined := false
		for ji in R.sjx:
			var join: Array = sim.surface_junctions[ji]
			var lo: int = join[1] if int(join[0]) == key.x else join[4]
			var hi: int = join[2] if int(join[0]) == key.x else join[5]
			if first <= hi + 4 and last >= lo - 4:
				joined = true
				break
		var name := _deco_template_key({"r": key.x, "c0": first, "c1": last, "joins": joined}, R)
		if name == "" or _deco_templates.has(name):
			continue
		_start_chunk(key.x, key.y)
		_job.signs = []
		_work(Time.get_ticks_usec() + 60000000)
		(chunks[key][0] as Node3D).free()
		chunks.erase(key)
		built -= 1
		if _deco_templates.size() >= 16:
			break


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
	if want.size() > BACKLOG:
		_catching_up = true
	var behind: bool = _catching_up or (not want.is_empty() and float(want[0][0]) < CATCH_UP) or (not _job.is_empty() and float(_job.d) < CATCH_UP)
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
	if wi >= want.size() and _job.is_empty():
		_catching_up = false
	for key in chunks.keys():
		var c: Array = chunks[key]
		var R: CraftSim.TrackPath = sim.roads[key.x]
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
		(sk[0] as Node3D).position = Vector3(sk[1] - org_x, scenery_ground_height, -(sk[2] - org_y))
	for sk in far_shafts:
		(sk[0] as Node3D).position = Vector3(sk[1] - org_x, 0.0, -(sk[2] - org_y))
	if scenery:
		scenery.sync(org_x, org_y, scenery_ground_height)
	if far_roads:
		far_roads.sync(org_x,org_y)
	sync_ms = (Time.get_ticks_usec() - t_in) / 1000.0


## The deck's height at sample i of road r (0 but on a flyover).
func _h(r: int, i: int) -> float:
	if r < _heights.size():
		return _heights[r][i]
	return sim.net_height(r, float(i))


## The same Hermite height as the sim, with interval coefficients reused across
## adjacent shoulder vertices instead of searching the entire profile each time.
func _height_at(r: int, sample: float) -> float:
	var curve: Array = _height_curves.get(r, [])
	if curve.is_empty() or sample < float(curve[0]) or sample > float(curve[1]):
		curve = []
		var keys: Array = sim._net_h.get(r, [])
		for k in range(keys.size() - 1):
			var a: Array = keys[k]
			var b: Array = keys[k + 1]
			if sample < float(a[0]) or sample > float(b[0]):
				continue
			var count := maxf(1.0, float(b[0]) - float(a[0]))
			var d := count * CraftSim.NET_STEP
			var c1 := d * float(a[2])
			var c2 := -3.0 * float(a[1]) + 3.0 * float(b[1]) - d * (2.0 * float(a[2]) + float(b[2]))
			var c3 := 2.0 * float(a[1]) - 2.0 * float(b[1]) + d * (float(a[2]) + float(b[2]))
			curve = [float(a[0]), float(b[0]), 1.0 / count, float(a[1]), c1, c2, c3]
			_height_curves[r] = curve
			break
	if curve.is_empty():
		return 0.0
	var u := (sample - float(curve[0])) * float(curve[2])
	return ((float(curve[6]) * u + float(curve[5])) * u + float(curve[4])) * u + float(curve[3])


## A point `off` m left of road r's sample i, `h` up, against the chunk origin (ox, oy).
func _p(R: CraftSim.TrackPath, ox: float, oy: float, i: int, off: float, h: float) -> Vector3:
	if _smap.has(R) and shaft.on(_smap[R], float(i)):
		var A: Array = shaft.at(_smap[R], float(i))
		return Vector3(float(A[0]) - ox, A[2], -(float(A[1]) - oy)) + (A[4] as Vector3) * off + (A[5] as Vector3) * (h - float(A[2]))
	return Vector3(R.px[i] + R.nx[i] * off - ox, h, -(R.py[i] + R.ny[i] * off - oy))


## Road r's sample i in the world's plan (a shaft's stretch isn't where the sims' plan has it).
func _wxy(r: int, i: int) -> Vector2:
	var R: CraftSim.TrackPath = sim.roads[r]
	if shaft.on(r, float(i)):
		var A: Array = shaft.at(r, float(i))
		return Vector2(A[0], A[1])
	return Vector2(R.px[i], R.py[i])


## Is the wall on side sgn of road r's sample i open (another road joins there: the edge point is
## inside its corridor)?
func _open(r: int, i: int, sgn: float) -> bool:
	return _joined_surface(r, i, sgn * sim.roads[r].w[i] / 2.0).x < INF


## The lowest adjoining surface at an offset across this road. Only declared junctions
## participate: a highway passing under a flyover must keep its own shoulders.
## (height, normal.x, normal.y, normal.z), or INF when outside every joining corridor.
func _joined_surface(r: int, i: int, off: float, apron := 0.0) -> Vector4:
	var key := Vector3(i, off, apron)
	if _physical_join_cache.has(r) and (_physical_join_cache[r] as Dictionary).has(key):
		return _physical_join_cache[r][key]
	if _join_cache_road != r:
		_join_surface_cache.clear()
		_join_projections.clear()
		_join_hints.clear()
		_join_cache_road = r
	if _join_surface_cache.has(key):
		return _join_surface_cache[key]
	var reach := maxf(24.0, apron)
	var projection_key := Vector3(i, off, reach)
	if not _join_projections.has(projection_key):
		var records := []
		var R: CraftSim.TrackPath = sim.roads[r]
		for join in _joining_at(r, i):
			var q: int = join[0]
			var m := int(join[1]) + roundi(off * float(join[2]))
			sim._nearest_on(q, R.px[i] + R.nx[i] * off, R.py[i] + R.ny[i] * off, m, 1)
			var needed := absf(sim._n_lat) - sim._n_w / 2.0 + 1.0
			if sim._n_off or needed >= reach:
				continue
			var edge := CraftSim.net_edge(sim._n_w, sim._n_lat)
			var height := _height_at(q, sim._n_i + sim._n_t) + edge.x
			var bank := signf(sim._n_lat) * sin(edge.y)
			records.append([needed, Vector4(height, -sim._n_nx * bank, cos(edge.y), sim._n_ny * bank)])
		_join_projections[projection_key] = records
	var out := Vector4(INF, 0.0, 1.0, 0.0)
	for record in _join_projections[projection_key]:
		if float(record[0]) < apron and (record[1] as Vector4).x < out.x:
			out = record[1]
	_join_surface_cache[key] = out
	return out


func _joining_at(r: int, i: int) -> Array:
	if _prepared_join_hints.has(r):
		return _prepared_join_hints[r].get(i, [])
	if _join_hints.has(i):
		return _join_hints[i]
	var R: CraftSim.TrackPath = sim.roads[r]
	var joins := []
	for k in R.sjx:
		var J: Array = sim.surface_junctions[k]
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
		var reach := 16
		# Adjacent road rows are 24 m apart. Reuse the previous row's exact
		# projection when present; four samples retain ample curvature margin
		# without rescanning the full padded junction interval for every row.
		for previous in _join_hints.get(i - 1, []):
			# A turnaround joins the same highway twice. Its two intervals must
			# keep separate hints even though both point at the same road.
			if int(previous[3]) == k:
				m = int(previous[1])
				reach = 4
				break
		sim._nearest_on(q, R.px[i], R.py[i], m, reach)
		joins.append([q, sim._n_i, (R.nx[i] * sim._n_tx + R.ny[i] * sim._n_ty) / sim.roads[q].len[sim._n_i], k])
	_join_hints[i] = joins
	return joins


## A whole chunk now (tests; the stream builds them a slice at a time, _start_chunk and _work).
func _build_chunk(r: int, k: int) -> void:
	_start_chunk(r, k)
	_work(Time.get_ticks_usec() + 60000000)


## The chunk's node, in place (empty) and in `chunks`, and its build in hand.
func _start_chunk(r: int, k: int) -> void:
	_join_surface_cache.clear()
	_join_projections.clear()
	_join_hints.clear()
	_join_cache_road = r
	var R: CraftSim.TrackPath = sim.roads[r]
	var c0 := k * CH
	var c1 := mini((k + 1) * CH, R.N - 1)
	var joins := false
	var fine_joins := false
	for ji in R.sjx:
		var join: Array = sim.surface_junctions[ji]
		var start := int(join[1]) if int(join[0]) == r else int(join[4])
		var finish := int(join[2]) if int(join[0]) == r else int(join[5])
		if c0 <= finish + 4 and c1 >= start - 4:
			joins = true
			fine_joins = fine_joins or ji >= sim.junctions.size()
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
	_job = {"key": key, "r": r, "c0": c0, "c1": c1, "i": c0, "ox": ox, "oy": oy, "node": node, "st": st, "joins": joins, "fine_joins": fine_joins,
		"deco_spans": {},
		"n_lamps": 0, "made": false, "signs": _signs.get(key, []), "si": 0, "us": 0, "d": 0.0,
		"rv": PackedVector3Array(), "rn": PackedVector3Array(), "ru": PackedVector2Array(), "rows": 0, "cols": 0,
		"u0": fposmod(_s[r][c0], ASPHALT_PERIOD) - _s[r][c0]}   # (the asphalt's u, continuous along the chunk)
	var template_key := _deco_template_key(_job, R)
	_job.template_key = template_key
	_job.template = _deco_templates.get(template_key, []) if template_key != "" else []


func _deco_template_key(J: Dictionary, R: CraftSim.TrackPath) -> String:
	if R.role != "" or _smap.has(R) or int(J.c1) - int(J.c0) != CH or int(J.c0) == 0 or int(J.c1) == R.N - 1:
		return ""
	var start: int = J.c0
	var finish: int = J.c1
	if halls.has(J.r) and finish >= int(halls[J.r][0]) and start <= int(halls[J.r][1]):
		return ""
	for guide in _approaches.get(J.r, []):
		if finish >= int(guide[0]) and start <= int(guide[1]):
			return ""
	var height := _h(J.r, start)
	var left_open := _open(J.r, start, -1.0) if J.joins else false
	var right_open := _open(J.r, start, 1.0) if J.joins else false
	for i in range(start, finish + 1):
		if R.tx[i] != R.tx[start] or R.ty[i] != R.ty[start] or R.w[i] != R.w[start] or R.mode[i] != R.mode[start] or _h(J.r, i) != height or absf(R.len[i] - R.len[start]) > 0.0000001:
			return ""
		if J.joins and (_open(J.r, i, -1.0) != left_open or _open(J.r, i, 1.0) != right_open):
			return ""
	# Supports are baked into the reused furniture. Equal deck shapes can cross different
	# roads underneath, so include the surviving sides at every support row in this chunk.
	var support_mask := 0
	if height > DECK + 2.0:
		var spacing := 40 if height > 150.0 else PILLAR_EVERY
		var first := start + posmod(-start,spacing)
		var slot := 0
		for i in range(first,finish,spacing):
			for pillar in pillar_specs(J.r,i):
				var side := posmod(-int(pillar.id)-1,2)
				support_mask |= 1 << (slot*2+side)
			slot += 1
	# All discrete furniture periods divide 120 (6/8/40); colour phase divides8.
	return "%.10f:%.10f:%.10f:%s:%s:%s:%s:%s:%s:%s" % [R.tx[start], R.ty[start], R.len[start], R.w[start], R.mode[start], height, start % 120, left_open, right_open, support_mask]


## Build on the chunk in hand until `end` (usec): its samples, then its meshes, then its boards one at
## a time. True when it's finished (and _job is empty again).
func _work(end: int) -> bool:
	var J := _job
	var t0 := Time.get_ticks_usec()
	var R: CraftSim.TrackPath = sim.roads[J.r]
	var done := false
	while true:
		var phase_start := Time.get_ticks_usec() if profile_streaming else 0
		var phase := "sample"
		if J.i < J.c1:
			_sample(J, R, J.i)
			J.i += 1
		elif not J.made:
			phase="finish"
			_finish(J, R)
			J.made = true
		elif J.si < (J.signs as Array).size():
			phase="sign"
			_sign(J.node, R, J.r, J.ox, J.oy, J.signs[J.si])
			J.si += 1
		else:
			done = true
			break
		if profile_streaming:
			stream_profile[phase]=maxi(stream_profile.get(phase,0),Time.get_ticks_usec()-phase_start)
		if Time.get_ticks_usec() >= end:
			break
	J.us += Time.get_ticks_usec() - t0
	if done:
		build_ms_max = maxf(build_ms_max, J.us / 1000.0)
		_job = {}
	return done


## One source for the rendered support boxes and their optional collision footprints.
func pillar_specs(r: int, i: int) -> Array:
	var key := Vector2i(r,i)
	if _pillar_specs_cache.has(key):
		return _pillar_specs_cache[key]
	for roll in sim.twists:
		if int(roll[0]) == r and i >= int(roll[1]) and i <= int(roll[2]):
			return [] # no physical support may pierce the rolled deck, even before build()
	if sim.roads[r].shaft:
		for sh in sim.shafts:
			if int(sh[0]) == r and i > int(sh[1]) and i < int(sh[2]):
				return [] # also works before build(): no invisible supports in the collision index
	var h := _h(r, i)
	var high := h > 150.0
	if h <= DECK + 2.0 or i % (40 if high else PILLAR_EVERY) != 0:
		return []
	var R: CraftSim.TrackPath = sim.roads[r]
	var thick := 20.0 + h * 0.02 if high else 14.0
	if _support_clearance == null:
		_support_clearance = SupportClearance.new()
		_support_clearance.setup(sim, shaft, grid, _heights)
	var out := []
	for side in 2:
		var off: float = (-1.0 if side == 0 else 1.0) * (R.w[i] / 2.0 - 30.0)
		var pillar := {"id": -(r * 1000000 + i * 2 + side + 1), "r": 0.0, "halfSize": thick / 2.0,
			"x": R.px[i] + R.nx[i] * off, "y": R.py[i] + R.ny[i] * off,
			"zMin": 0.0, "zMax": h - DECK, "vx": 0.0, "vy": 0.0}
		if not _support_clearance.blocks(r,pillar):
			out.append(pillar)
	_pillar_specs_cache[key] = out
	return out

func _index_pillars() -> void:
	for r in sim.roads.size():
		for spacing in [PILLAR_EVERY, 40]:
			for i in range(0, sim.roads[r].N - 1, spacing):
				if (_h(r, i) > 150.0) != (spacing == 40):
					continue
				for pillar in pillar_specs(r, i):
					var cell := Vector2i(floori(pillar.x / PILLAR_CELL), floori(pillar.y / PILLAR_CELL))
					if not _pillar_cells.has(cell):
						_pillar_cells[cell] = []
					_pillar_cells[cell].append(pillar)
	_pillars_indexed = true

func obstacles_near(x: float, y: float, radius: float = 1000.0) -> Array:
	if not _pillars_indexed:
		_index_pillars()
	var out := []
	var cell := Vector2i(floori(x / PILLAR_CELL), floori(y / PILLAR_CELL))
	var reach := ceili(radius / PILLAR_CELL) + 1
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			for pillar in _pillar_cells.get(cell + Vector2i(dx, dy), []):
				if Vector2(pillar.x - x, pillar.y - y).length() <= radius + pillar.halfSize:
					out.append(pillar)
	return out

## Sample i of the chunk in hand: its stretch of road, lines, deck, walls, masts.
func _sample(J: Dictionary, R: CraftSim.TrackPath, i: int) -> void:
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
	var sec := _section(R.w[i], bool(J.fine_joins))
	var te: float = sec.te   # the edges' ramps' top: the walls stand on it
	var on_shaft: bool = shaft.on(r, float(i))
	_up = (shaft.at(r, float(i))[5] as Vector3) if on_shaft else Vector3.UP
	# the road: a flat middle and a ramp up each side (the sims' net_edge), a row of the chunk's grid
	# a sample (its normals banked with the ramps)
	if i == int(J.c0):
		_road_row(J, R, sec, i, hi)
	_road_row(J, R, sec, j, hj)
	if not J.template.is_empty():
		return
	var span := _deco_span(J, R, i)
	if span == 0:
		return # asphalt retains every sample; only identical coplanar decoration is joined
	if span==1:
		_paint_row(R,r,ox,oy,i,J) # reuse the asphalt already generated above
	j = i + span
	hj = _h(r, j)
	var up_j: Vector3 = shaft.at(r,float(j))[5] if shaft.on(r,float(j)) else Vector3.UP
	var hw_j: float = R.w[j]*0.5
	var te_j: float = CraftSim.net_edge(R.w[j],hw_j).x
	var open_i := [false, false]
	var open_j := [false, false]
	if J.joins and not _joining_at(r, i).is_empty():
		open_i = [_open(r, i, -1.0), _open(r, i, 1.0)]
	if J.joins and not _joining_at(r, j).is_empty():
		open_j = [_open(r, j, -1.0), _open(r, j, 1.0)]
	for ln in sec.lines:   # the edge lines on the ramps' tops, a dim one at each ramp's foot
		# An internal shoulder is the junction's drivable opening, not a lane edge.
		var side := 0 if ln[0] < 0.0 else 1
		if open_i[side] or open_j[side]:
			continue
		_strip(deco, R, ox, oy, i, ln[0], ln[1], hi + 0.04, hj + 0.04, ln[4], ln[2], ln[3], span)
	# The ascent lane has broad amber rails and repeated forward chevrons, visible through its S.
	if R.role == "launch":
		for side in [-1.0, 1.0]:
			_strip(lglow, R, ox, oy, i, side * (hw * 0.55) - 1.75, side * (hw * 0.55) + 1.75, hi + 0.12, hj + 0.12, JUMP_AMBER)
	for guide in _approaches.get(r, []):
		if i < int(guide[0]) or i >= int(guide[1]):
			continue
		var centre: float = guide[3]
		for side in [-1.0, 1.0]:
			_strip(lglow, R, ox, oy, i, centre + side * 12.0 - 1.5, centre + side * 12.0 + 1.5, hi + 0.12, hj + 0.12, JUMP_AMBER, 0.0, 0.0, span)
		if i % 20 == 0:
			_approach_arrow(lglow, R, ox, oy, i, hi, float(guide[2]), centre)
	# a flyover's deck: its edges, its underside, its pillars
	if hi > 4.0 or hj > 4.0:
		for sgn in [-1.0, 1.0]:
			var side := 0 if sgn < 0.0 else 1
			if open_i[side] or open_j[side]:
				continue
			var ea := _p(R, ox, oy, i, sgn * hw, hi)
			var eb := _p(R, ox, oy, j, sgn * hw_j, hj)
			_quad(deco, [ea - _up * DECK, eb - up_j * DECK, eb + up_j * te_j, ea + _up * te], Color(0.55, 0.55, 0.53))
			_quad(lglow, [ea - _up * DECK, eb - up_j * DECK, eb - up_j * (DECK - 0.8), ea - _up * (DECK - 0.8)], STRIP_LIGHT)
		_quad(deco, [_p(R, ox, oy, i, hw, hi - DECK), _p(R, ox, oy, i, -hw, hi - DECK), _p(R, ox, oy, j, -hw, hj - DECK), _p(R, ox, oy, j, hw, hj - DECK)], Color(0.32, 0.32, 0.31))
		for pillar in pillar_specs(r, i):
			var thick: float = pillar.halfSize * 2.0
			var center := Vector3(pillar.x - ox, pillar.zMax / 2.0, -(pillar.y - oy))
			_box(deco, center, Vector3(thick, pillar.zMax, thick), Color(0.6, 0.6, 0.58))
	if halls.has(r) and i >= int(halls[r][0]) and i < int(halls[r][1]):
		_hall(J, R, i, hw, hi + te, hj + te)
	if on_shaft and i % HOOP_EVERY == 0:
		_hoop(J, R, i, hw, hi + te, i % (HOOP_EVERY * 2) == 0)
	if R.role == "launch" and i % CHEV_EVERY == 0 and i < R.N - 4:
		_chevron(lglow, R, ox, oy, i, hi, 1.0)
	# the walls, the strip on top, the masts
	for sgn in [-1.0, 1.0]:
		var side := 0 if sgn < 0.0 else 1
		if open_i[side] or open_j[side]:
			walls_open += 1
			continue
		var wa := _p(R, ox, oy, i, sgn * hw, hi + te)   # (on the ramp's top)
		var wb := _p(R, ox, oy, j, sgn * hw_j, hj + te_j)
		var top := BAND_H
		_wall(deco, wa, wb, 0.0, WALL_H, Color(0.72, 0.71, 0.68), up_j)
		_wall(deco, wa, wb, WALL_H, BAND_H, (BAND_SF if city else BAND)[(i / 4) % 2], up_j)
		if city:
			var slate := 0.2 + 0.035 * ((i / 4) % 2)
			_wall(deco, wa, wb, BAND_H, FENCE_H, Color(slate, slate + 0.01, slate + 0.03), up_j)
			top = FENCE_H
		_wall(lglow, wa, wb, top, top + STRIP_H, WALL_STRIP_SF if city else WALL_STRIP, up_j)
		if i % (8 if city else MAST_EVERY) == 0 and not on_shaft:
			var foot := _p(R, ox, oy, i, sgn * (hw + 0.4), hi + te)
			_box(deco, foot + Vector3.UP * (MAST_H / 2.0), Vector3(0.6, MAST_H, 0.6), Color(0.3, 0.31, 0.33))
			_box(glow, foot + Vector3.UP * (MAST_H + 0.45), Vector3(0.9, 0.9, 0.9), STRIP_LIGHT)
			_beacon(lamps, foot + Vector3.UP * (MAST_H + 0.45), BAND_SF[0] if city else STRIP_LIGHT)
			J.n_lamps += 1


## Keep every asphalt row, but avoid four copies of an identical straight wall/stripe.
## 4 divides the wall colour, mast and arrow periods. Low-deck pillars (period 6),
## halls, launch chevrons, rolls, changing openings and curved/graded profiles opt out.
func _deco_span(J: Dictionary, R: CraftSim.TrackPath, i: int) -> int:
	var first := i - i % 4
	if not J.deco_spans.has(first):
		var last := first + 4
		var r: int = J.r
		var eligible: bool = last <= int(J.c1) and R.role != "launch" and not _smap.has(R)
		var h0 := _h(r, first)
		var h1 := _h(r, mini(last, R.N - 1))
		eligible = eligible and not ((h0 > DECK + 2.0 and h0 <= 150.0) or (h1 > DECK + 2.0 and h1 <= 150.0))
		if halls.has(r) and last >= int(halls[r][0]) and first <= int(halls[r][1]):
			eligible = false
		for guide in _approaches.get(r, []):
			if (first < int(guide[0]) and last > int(guide[0])) or (first < int(guide[1]) and last > int(guide[1])):
				eligible = false
		if eligible:
			var left_open := _open(r, first, -1.0) if J.joins else false
			var right_open := _open(r, first, 1.0) if J.joins else false
			for row in range(first, last + 1):
				if R.w[row] != R.w[first] or R.mode[row] != R.mode[first] or absf(R.tx[row] - R.tx[first]) + absf(R.ty[row] - R.ty[first]) > 0.0000001 or absf(_h(r, row) - lerpf(h0, h1, float(row - first) / 4.0)) > 0.000001:
					eligible = false
					break
				if J.joins and (_open(r, row, -1.0) != left_open or _open(r, row, 1.0) != right_open):
					eligible = false
					break
		J.deco_spans[first] = eligible
	return (4 if i == first else 0) if J.deco_spans[first] else 1


## A city's hall over sample i (the Network's tunnels, as Eridanus' covered ramps): its walls on up
## from the fence to a roof HALL_H over the road, the roof, a lit strip down each wall, a steel rib
## every HALL_RIB_EVERY samples, a lit bar across the roof every HALL_LIGHT_EVERY (the speed cue
## overhead), a lit band round each portal.
func _hall(J: Dictionary, R: CraftSim.TrackPath, i: int, hw: float, hi: float, hj: float) -> void:
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
func _hoop(J: Dictionary, R: CraftSim.TrackPath, i: int, hw: float, h: float, lit: bool) -> void:
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


## Clip each arrow arm to actual pavement triangles in (sample, lateral) coordinates.
## A twisted road is triangulated, not a bilinear surface: interpolating row frames
## alone can put paint underneath the diagonal between two differently banked rows.
func _paint_arrow(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, i: int, way: float, off: float, half_width: float, run: float, thickness: float) -> void:
	var tip := float(i)
	var tail := tip - way * run / CraftSim.NET_STEP
	var wide := way * thickness / CraftSim.NET_STEP
	for side in [-1.0,1.0]:
		var edge: float = off + side * half_width
		_paint_polygon(st,R,ox,oy,PackedVector2Array([Vector2(tip,off),Vector2(tip+wide,off),Vector2(tail+wide,edge),Vector2(tail,edge)]),JUMP_AMBER)


## Project marking polygons onto the SAME triangles used by each road chunk.
## Coordinates are continuous sample index and metres left of the centreline.
func _paint_polygon(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, shape: PackedVector2Array, color: Color) -> void:
	var r: int = sim.roads.find(R)
	var bounds := Rect2(shape[0],Vector2.ZERO)
	for point in shape: bounds = bounds.expand(point)
	var first := maxi(0,floori(bounds.position.x))
	var last := mini(R.N-1,ceili(bounds.end.x))
	for row in range(first,last):
		var geometry := _paint_row(R,r,ox,oy,row)
		var sec: Dictionary=geometry[0]
		var grid: Dictionary=geometry[1]
		var cols: int = grid.cols
		for col in cols-1:
			var lo: float = sec.o[col]
			var hi: float = sec.o[col+1]
			if hi < bounds.position.y or lo > bounds.end.y: continue
			var cell := [Vector2(row,lo),Vector2(row,hi),Vector2(row+1,hi),Vector2(row+1,lo)]
			var corners := [col,col+1,col+cols+1,col+cols]
			for indices in [[0,1,2],[0,2,3]]:
				var a: Vector2 = cell[indices[0]]
				var b: Vector2 = cell[indices[1]]
				var c: Vector2 = cell[indices[2]]
				var va: Vector3 = grid.rv[corners[indices[0]]]
				var vb: Vector3 = grid.rv[corners[indices[1]]]
				var vc: Vector3 = grid.rv[corners[indices[2]]]
				var normal := (vc-va).cross(vb-va).normalized()
				var ab := b-a
				var ac := c-a
				var determinant := ab.cross(ac)
				for polygon in Geometry2D.intersect_polygons(shape,PackedVector2Array([a,b,c])):
					var points := PackedVector3Array()
					for point in polygon:
						var d: Vector2 = point-a
						points.append(va+(vb-va)*d.cross(ac)/determinant+(vc-va)*ab.cross(d)/determinant+normal*0.1)
					st.set_color(color)
					st.set_normal(normal)
					for k in range(1,points.size()-1):
						var pa := points[0]
						var pb := points[k]
						var pc := points[k+1]
						if (pb-pa).cross(pc-pa).dot(normal)>0.0:
							var swap := pb
							pb=pc
							pc=swap
						st.add_vertex(pa)
						st.add_vertex(pb)
						st.add_vertex(pc)


## Bound this CPU cache to one chunk. Multiple markings share the same pavement
## rows; no GPU readback and no repeated nearest-road projections per stripe.
func _paint_row(R: CraftSim.TrackPath,r: int,ox: float,oy: float,row: int,source: Dictionary={}) -> Array:
	var chunk_start := (row / CH)*CH
	var key := [r,chunk_start,ox,oy]
	if key != _paint_key:
		_paint_key=key
		_paint_rows.clear()
		_paint_fine=false
		var chunk_end:=mini(chunk_start+CH,R.N-1)
		for ji in R.sjx:
			if ji<sim.junctions.size(): continue
			var join: Array=sim.surface_junctions[ji]
			var lo:=int(join[1]) if int(join[0])==r else int(join[4])
			var hi:=int(join[2]) if int(join[0])==r else int(join[5])
			if chunk_start<=hi+4 and chunk_end>=lo-4: _paint_fine=true
	if not _paint_rows.has(row):
		var sec:=_section(R.w[row],_paint_fine)
		var grid: Dictionary={"r":r,"ox":ox,"oy":oy,"u0":0.0,"rv":PackedVector3Array(),"rn":PackedVector3Array(),"ru":PackedVector2Array(),"rows":0,"cols":0,"joins":true}
		if not source.is_empty():
			grid.cols=source.cols
			grid.rows=2
			grid.rv=(source.rv as PackedVector3Array).slice(source.rv.size()-2*int(source.cols))
		else:
			_road_row(grid,R,sec,row,_h(r,row))
			_road_row(grid,R,sec,row+1,_h(r,row+1))
		_paint_rows[row]=[sec,grid]
	return _paint_rows[row]


## Broad launch chevrons and narrow exit-lane arrows share the actual road frame.
func _chevron(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, i: int, _h0: float, way: float) -> void:
	_paint_arrow(st,R,ox,oy,i,way,0.0,R.w[i] * 0.31,90.0,18.0)


func _approach_arrow(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, i: int, _h0: float, way: float, off: float) -> void:
	_paint_arrow(st,R,ox,oy,i,way,off,22.0,48.0,10.0)


## The chunk in hand's ends (a barrier where nothing goes on), its meshes committed.
func _finish(J: Dictionary, R: CraftSim.TrackPath) -> void:
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
	var cpu_surfaces := []
	if not J.template.is_empty():
		var cached: Array = J.template[0]
		for surface in cached:
			var index := mesh.get_surface_count()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface[0])
			mesh.surface_set_material(index, surface[1])
	else:
		for pair in [[deco, _mat], [glow, _lit], [lglow, _strip_mat]]:
			var n0 := mesh.get_surface_count()
			var arrays := (pair[0] as SurfaceTool).commit_to_arrays()
			if arrays[Mesh.ARRAY_VERTEX] != null and arrays[Mesh.ARRAY_VERTEX].size() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				mesh.surface_set_material(n0,pair[1])
				cpu_surfaces.append([arrays,pair[1]])
	var mi := MeshInstance3D.new()
	mi.name = "road"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var beacon_mesh: ArrayMesh = J.template[1] if not J.template.is_empty() else (lamps.commit() if int(J.n_lamps) > 0 else null)
	if beacon_mesh:
		var bm := MeshInstance3D.new()
		bm.name = "beacons"
		bm.mesh = beacon_mesh
		bm.material_override = _beam
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.extra_cull_margin = 400.0
		node.add_child(bm)
	if J.template_key != "" and J.template.is_empty():
		_deco_templates[J.template_key] = [cpu_surfaces, beacon_mesh]


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
		var R: CraftSim.TrackPath = sim.roads[city.road]
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
	var C = sim.roads[c]
	var title := "ASCENT %s" % C.name
	var minimum := "MIN %d,%03d MPH AT LIP" % [mph / 1000, mph % 1000]
	var P = sim.roads[p]
	# Junction intervals describe shared pavement, not the exact physical fork.
	sim._nearest_on(p, C.px[0], C.py[0], fork, 80)
	fork = sim._n_i
	_add_sign(p, clampi(fork - dp * FORK_BEFORE, 1, P.N - 2), dp, "fork", [title, minimum, "STRAIGHT ON"])
	# The spur forks off an exit ramp. Advance guidance belongs on the highway before that ramp.
	var e: int = 0 if dp > 0 else P.N - 1
	_add_approach(p, e, fork, dp, 0.0)
	for J in sim.junctions:
		if int(J[3]) != p or not (int(J[4]) <= e and e <= int(J[5])):
			continue
		var h := int(J[0])
		var at_mouth := _map(J, e)
		var way := dp * int(J[6])
		var H = sim.roads[h]
		sim._nearest_on(h, P.px[e], P.py[e], at_mouth, 160)
		at_mouth = sim._n_i
		_add_approach(h, at_mouth - way * SIGN_NEAR, at_mouth, way, -way * 90.0)
		for back in [SIGN_FAR, SIGN_NEAR, 20]:
			var at: int = at_mouth - way * back
			if at > 0 and at < H.N - 1:
				var entry := "ENTER RIGHT" if back < 30 else "RIGHT EXIT  %d MI" % roundi(float(back) * 24.0 / MILE)
				_add_sign(h, at, way, "jump", [title, minimum, entry])
	_add_sign(c, mini(300, C.N - 2), 1, "fork", [title, minimum, "FOLLOW AMBER"])
	_add_sign(c, maxi(1, C.N - 61), 1, "fork", [title, minimum, "LIFT-OFF  1 MI"])


func _add_approach(r: int, first: int, last: int, direction: int, centre: float) -> void:
	if not _approaches.has(r):
		_approaches[r] = []
	_approaches[r].append([maxi(0, mini(first, last)), mini(sim.roads[r].N - 1, maxi(first, last)), direction, centre])


## Side road r's corners: a board before each bend CORNER_MIN_K or tighter, both ways: the speed that
## holds it at CORNER_G and the gear for that speed, so the bend tells you to shift.
func _plan_corners(r: int) -> void:
	var R: CraftSim.TrackPath = sim.roads[r]
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
	# Profile zero belongs to STARFIGHTER; SPEEDCRAFT uses profiles/display gears 1-4.
	for k in range(1, QuestControls.GEARS.size()):
		if mph <= float(QuestControls.GEARS[k][2]) * QuestControls.V_TOP_SPEED * 2.236936:
			return k
	return QuestControls.GEARS.size() - 1


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
func _sign(node: Node3D, R: CraftSim.TrackPath, r: int, ox: float, oy: float, spec: Array) -> void:
	var i: int = spec[0]
	var dir: int = spec[1]
	var kind: String = spec[2]
	var lines: Array = spec[3]
	# Both terminal approaches are planned at the same sample. One two-faced gantry covers
	# the pair; building the second would stack identical lit faces and labels in the same plane.
	if kind == "terminal" and dir < 0:
		return
	var hw: float = R.w[i] / 2.0 + 4.0
	var h0 := _h(r, i)
	var tx: float = R.tx[i] * dir
	var ty: float = R.ty[i] * dir
	var t := Vector3(tx, 0.0, -ty)
	var b := Basis(Vector3.UP, atan2(ty, tx))
	var mid := _p(R, ox, oy, i, 0.0, h0)
	if kind == "terminal":   # a lit line across the road, and a gantry with the city's name
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_across(st,R,ox,oy,i,h0,-t*3.0,t*3.0,Color.WHITE)
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
	_sign_face(node, sc, t, kind, lines, w, h, false)
	var rear := lines
	if kind == "jump" or kind == "fork":
		rear = [lines[0], lines[1], "APPROACH OTHER SIDE"]
	elif kind != "terminal":
		rear = [lines[1] if kind == "brake" else lines[0], "OPPOSITE APPROACH"]
	_sign_face(node, sc, -t, kind, rear, w, h, true)
	boards += 1


## Each face has its own outward normal and sits outside the solid two-metre backing.
## A double-sided label alone would be mirrored from behind and buried inside that backing.
func _sign_face(node: Node3D, sc: Vector3, t: Vector3, kind: String, lines: Array, w: float, h: float, rear: bool) -> void:
	var facing := Basis(Vector3.UP, atan2(-t.x, -t.z))   # +Z toward this side's approaching craft
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	face.mesh = quad
	face.transform = Transform3D(facing, sc - t * 1.1)
	var small: bool = kind == "brake" or kind == "corner"
	var arrow: bool = (kind == "jump" or kind == "fork") and not rear
	face.material_override = (_arrow_mat if kind == "jump" else _fork_mat) if arrow else (_jump_mat if kind == "jump" or kind == "fork" else (_end_mat if kind == "end" else (_city_mat if kind == "terminal" or kind == "city" else _board_mat)))
	node.add_child(face)
	var n := lines.size()
	for li in n:
		var l := Label3D.new()
		l.text = lines[li]
		l.font_size = (FONT[0] if li == 0 else FONT[1]) if not small else (FONT[3] if li == 0 else FONT[4])
		if n >= 3 and li > 0:
			l.font_size = FONT[2]
		if rear and small:
			l.font_size = FONT[4] # rear has a zone name, not the front's large mile numeral
		l.pixel_size = SIGN_PX
		if kind == "jump" or kind == "fork":
			l.pixel_size *= ARROW_WORDS
		var width := ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x
		var text_w := w * (1.0 - ARROW_PANEL) if arrow else w
		l.pixel_size = minf(l.pixel_size, (text_w - 8.0) / maxf(width, 1.0))
		l.outline_size = 0
		l.modulate = Color(0.03, 0.03, 0.04)
		l.double_sided = false
		var up := (h / 2.0 - h / (n + 1.0) * (li + 1.0)) if n > 1 else 0.0
		var aside := facing * Vector3.RIGHT * (-w * ARROW_PANEL / 2.0) if arrow else Vector3.ZERO   # (the words left of the arrow's panel)
		l.transform = Transform3D(facing, sc + Vector3.UP * up - t * 1.4 + aside)
		node.add_child(l)


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
		var R: CraftSim.TrackPath = sim.roads[r]
		for i in range(0, R.N, 4):
			for city in sim.cities:
				if absf(R.px[i] - city.cx) < 20000.0 and absf(R.py[i] - city.cy) < 20000.0:
					near_pts[Vector2i(int(floor(R.px[i] / 500.0)), int(floor(R.py[i] / 500.0)))] = true
					break
	var sh := preload("res://view/skyline.gdshader")
	# Shared stepped architecture: podium, main floors and a recessed crown.
	# Keep the old unit-box envelope so existing road clearances still apply.
	var tower_mesh:=Kit.compound([
		[Kit.box(Vector3(1.0,0.10,1.0)),Kit.at(Vector3(0,-0.45,0)),Color.WHITE],
		[Kit.box(Vector3(0.84,0.78,0.84)),Kit.at(Vector3(0,-0.01,0)),Color.WHITE],
		[Kit.box(Vector3(0.64,0.12,0.64)),Kit.at(Vector3(0,0.44,0)),Color.WHITE]])
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
		mm.mesh = tower_mesh
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
		var R: CraftSim.TrackPath = sim.roads[r]
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
func _section(w: float, joined := false) -> Dictionary:
	var facets := JOIN_EDGE_SEGS if joined else EDGE_SEGS
	var key := Vector2(w, facets)
	if _sec_cache.has(key):
		return _sec_cache[key]
	var hw := w / 2.0
	var E := CraftSim.net_edge_span(w)
	var o := PackedFloat32Array()
	for k in facets + 1:
		o.append(-hw + E * float(k) / facets)
	for k in facets + 1:
		o.append(hw - E + E * float(k) / facets)
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
	_sec_cache[key] = out
	return out


## Road r's grid row at its sample s (the deck's height h there): the section's points, banked
## normals, the asphalt's uv (u along, v the offset).
func _road_row(J: Dictionary, R: CraftSim.TrackPath, sec: Dictionary, s: int, h: float) -> void:
	var o: PackedFloat32Array = sec.o
	var hh: PackedFloat32Array = sec.h
	var cc: PackedFloat32Array = sec.c
	var ss: PackedFloat32Array = sec.s
	var left := Vector3(R.nx[s], 0.0, -R.ny[s])
	var mid := Vector3(R.px[s] - J.ox, h + 0.02, -(R.py[s] - J.oy))
	var up := Vector3.UP
	if shaft.on(J.r, float(s)):
		var A: Array = shaft.at(J.r, float(s))
		left = A[4]
		up = A[5]
		mid = Vector3(float(A[0]) - J.ox, A[2], -(float(A[1]) - J.oy)) + up * 0.02
	var u: float = J.u0 + _s[J.r][s]
	var rv: PackedVector3Array = J.rv
	var rn: PackedVector3Array = J.rn
	var ru: PackedVector2Array = J.ru
	if not J.joins or _joining_at(int(J.r), s).is_empty():
		for k in o.size():
			rv.append(mid + left * o[k] + up * hh[k])
			rn.append(up * cc[k] - left * ss[k])
			ru.append(Vector2(u, o[k]))
	else:
		for k in o.size():
			var height := h + hh[k]
			var normal := up * cc[k] - left * ss[k]
			if hh[k] > 0.0:
				# A triangle spans two 24 m rows. Extend only its shoulder shaping one
				# row past the exact corridor, so its outside vertex cannot bridge over
				# the neighbouring pavement. Wall openings still use the exact corridor.
				var joined := _joined_surface(int(J.r), s, o[k], 24.0)
				if joined.x < height:
					height = joined.x
					normal = Vector3(joined.y, joined.z, joined.w)
			rv.append(mid + left * o[k] + up * (height - h))
			rn.append(normal)
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
func _across(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, e: int, _he: float, d0: Vector3, d1: Vector3, c: Color) -> void:
	var forward := Vector3(R.tx[e],0,-R.ty[e])
	var a := float(e)+d0.dot(forward)/CraftSim.NET_STEP
	var b := float(e)+d1.dot(forward)/CraftSim.NET_STEP
	var hw: float = R.w[e]*0.5
	_paint_polygon(st,R,ox,oy,PackedVector2Array([Vector2(a,-hw),Vector2(a,hw),Vector2(b,hw),Vector2(b,-hw)]),c)



## A lip's lit face: down DECK from the road's end, its ramps too.
func _lip(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, e: int, he: float, c: Color) -> void:
	var sec := _section(R.w[e])
	var o: PackedFloat32Array = sec.o
	var hh: PackedFloat32Array = sec.h
	for k in o.size() - 1:
		_quad(st, [_p(R, ox, oy, e, o[k], he - DECK), _p(R, ox, oy, e, o[k + 1], he - DECK), _p(R, ox, oy, e, o[k + 1], he + hh[k + 1] + 0.05), _p(R, ox, oy, e, o[k], he + hh[k] + 0.05)], c)


## A strip along sample i, from o0 to o1 m left of the centreline, raised e0 and e1 there (on the
## edges' ramps).
func _strip(st: SurfaceTool, R: CraftSim.TrackPath, ox: float, oy: float, i: int, o0: float, o1: float, _h0: float, _h1: float, c: Color, _e0 := 0.0, _e1 := 0.0, span := 1) -> void:
	var r: int=sim.roads.find(R)
	var j:=i+span
	# Exact fast path for coplanar strips. Curved/banked/joining surfaces use
	# triangle clipping; straight stretches need only split at section facets.
	if not _smap.has(R) and absf(R.tx[i]-R.tx[j])+absf(R.ty[i]-R.ty[j])<0.0000001 and R.w[i]==R.w[j] and _joining_at(r,i).is_empty() and _joining_at(r,j).is_empty():
		var sec:=_section(R.w[i])
		for k in sec.o.size()-1:
			var lo: float=maxf(o0,sec.o[k])
			var hi: float=minf(o1,sec.o[k+1])
			if hi<=lo: continue
			var h_lo: float=lerpf(sec.h[k],sec.h[k+1],inverse_lerp(sec.o[k],sec.o[k+1],lo))
			var h_hi: float=lerpf(sec.h[k],sec.h[k+1],inverse_lerp(sec.o[k],sec.o[k+1],hi))
			var a:=_p(R,ox,oy,i,lo,_h(r,i)+h_lo+0.02)
			var b:=_p(R,ox,oy,i,hi,_h(r,i)+h_hi+0.02)
			var cc:=_p(R,ox,oy,j,hi,_h(r,j)+h_hi+0.02)
			var d:=_p(R,ox,oy,j,lo,_h(r,j)+h_lo+0.02)
			var normal: Vector3=(cc-a).cross(b-a).normalized()
			st.set_color(c)
			st.set_normal(normal)
			for point in [a,b,cc,a,cc,d]: st.add_vertex(point+normal*0.1)
		return
	# A rectangular stripe has a closed-form intersection with each grid
	# triangle. This avoids invoking a general polygon boolean per facet.
	for row in range(i,i+span):
		var geometry:=_paint_row(R,r,ox,oy,row)
		var sec: Dictionary=geometry[0]
		var grid: Dictionary=geometry[1]
		var cols: int=grid.cols
		for k in cols-1:
			var lo: float=maxf(o0,sec.o[k])
			var hi: float=minf(o1,sec.o[k+1])
			if hi<=lo: continue
			var low: float=inverse_lerp(sec.o[k],sec.o[k+1],lo)
			var high: float=inverse_lerp(sec.o[k],sec.o[k+1],hi)
			var a: Vector3=grid.rv[k]
			var b: Vector3=grid.rv[k+1]
			var cc: Vector3=grid.rv[k+cols+1]
			var d: Vector3=grid.rv[k+cols]
			var normal: Vector3=(cc-a).cross(b-a).normalized()
			if absf((d-a).dot(normal))<0.00001:
				_paint_quad(st,[a.lerp(b,low),a.lerp(b,high),d.lerp(cc,high),d.lerp(cc,low)],normal,c)
				continue
			var diagonal_low:=a.lerp(cc,low)
			var diagonal_high:=a.lerp(cc,high)
			_paint_quad(st,[a.lerp(b,low),a.lerp(b,high),diagonal_high,diagonal_low],(cc-a).cross(b-a).normalized(),c)
			_paint_quad(st,[diagonal_low,diagonal_high,d.lerp(cc,high),d.lerp(cc,low)],(d-a).cross(cc-a).normalized(),c)

func _paint_quad(st: SurfaceTool,points: Array,normal: Vector3,color: Color) -> void:
	st.set_color(color)
	st.set_normal(normal)
	for tri in [[0,1,2],[0,2,3]]:
		if points[tri[0]].is_equal_approx(points[tri[1]]) or points[tri[1]].is_equal_approx(points[tri[2]]): continue
		for k in tri: st.add_vertex(points[k]+normal*0.1)



func _wall(st: SurfaceTool, a: Vector3, b: Vector3, h0: float, h1: float, c: Color, end_up := Vector3.ZERO) -> void:
	var up_b := _up if end_up==Vector3.ZERO else end_up
	var nrm := (b - a).cross(_up).normalized()
	st.set_color(c)
	st.set_normal(nrm)
	for q in [a + _up * h0, b + up_b * h0, b + up_b * h1, a + _up * h0, b + up_b * h1, a + _up * h1]:
		st.add_vertex(q)


func _quad(st: SurfaceTool, q: Array, c: Color) -> void:
	var nrm: Vector3 = ((q[1] as Vector3) - (q[0] as Vector3)).cross((q[3] as Vector3) - (q[0] as Vector3)).normalized()
	st.set_color(c)
	st.set_normal(nrm)
	for k in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[k])


func _box(st: SurfaceTool, ctr: Vector3, size: Vector3, c: Color) -> void:
	var hx := size.x / 2.0
	var hy := size.y / 2.0
	var hz := size.z / 2.0
	var v := [ctr + Vector3(-hx, -hy, -hz), ctr + Vector3(hx, -hy, -hz), ctr + Vector3(hx, hy, -hz), ctr + Vector3(-hx, hy, -hz),
		ctr + Vector3(-hx, -hy, hz), ctr + Vector3(hx, -hy, hz), ctr + Vector3(hx, hy, hz), ctr + Vector3(-hx, hy, hz)]
	st.set_color(c)
	for f in [[0, 1, 2, 3, Vector3.FORWARD], [5, 4, 7, 6, Vector3.BACK], [4, 0, 3, 7, Vector3.LEFT], [1, 5, 6, 2, Vector3.RIGHT], [3, 2, 6, 7, Vector3.UP]]:
		st.set_normal(f[4])
		for q in [f[0], f[1], f[2], f[0], f[2], f[3]]:
			st.add_vertex(v[q])


func _beacon(st: SurfaceTool, p: Vector3, c: Color) -> void:
	st.set_color(c)
	st.set_uv2(Vector2(0.0, 1e6))
	st.set_normal(Vector3.UP)
	for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		st.set_uv(uv)
		st.add_vertex(p)
