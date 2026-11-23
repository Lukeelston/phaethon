## Power-ups (Luke, 2026-11-22: "I also think we need power-ups in some way"): lit gates over the
## road. Fly through one and the engines surge for a few seconds (the sims' inp.surge: thrust times
## boostMult, on top of whatever is lit and of the held boost). With the consumables on
## (CraftSim P.limits) they come in three colours, in turn along a road: saffron the surge alone,
## cyan a half charge of the battery with it, ice white the engines cooled by half their scale.
## A first cut, and harmless to ignore: a gate is light, nothing of it can be hit, and it is one
## lane of a wide road.
##   where    the Network's long roads: every 24 km of open road (SPEEDCRAFT's, level, not a
##            shaft, a deck road, the Aurora Line or a jump's ramp), 6 km clear of a road's ends
##            and 2.5 km of its junctions, in one of three lanes; and Eridanus: a gate about
##            every 12 km, on the nearest straight, level, open stretch.
##   seen     the three nearest on the road the craft is on, inside 10 km: two posts, a beam
##            across them 18 m up, a faint sheet of light between and a mast of light 400 m up
##            that says where the next one is from over a crest. Two draws a gate.
##   taken    crossing its line inside its span (and 3 m over): gone for 20 s.
## The view owns it (CraftView.set_power_ups): the sims know nothing of gates, so a replay cannot
## meet one. Not built for a replay or a cruise.
##   var p = preload("res://view/power_ups.gd").new(); view.add_child(p); p.build(view)
##   p.sync()                 every frame, after the view's origin has moved
##   PowerUps.network_gates(sim, road) / course_gates(sim)      where they stand, for a test or a map
extends Node3D

const SPACING := 24000.0           # m of road between gates on the Network ...
const END_CLEAR := 6000.0          # ... none this near a road's end ...
const JUNCTION_CLEAR := 2500.0     # ... or a junction's samples
const MAX_GRADE := 0.05            # nor on a slope steeper than this (the posts stand straight up)
const COURSE_SPACING := 12000.0    # Eridanus: about one every this far
const VIS := 10000.0               # m: drawn inside this
const POOL := 3                    # gates drawn at once
const SURGE_S := 4.0               # the surge a gate gives, s
const REARM_S := 20.0              # a gate taken is back after this, s
const ENERGY_GIFT := 0.5           # the cyan gate's charge, of the battery
const COOLANT_GIFT := 0.5          # the white gate's cooling, of the heat scale
const CATCH := 3.0                 # m outside the posts that still counts
const HIGH := 18.0                 # the posts, m
const MAST := 400.0                # the mast of light over the beam, m ...
const MAST_WIDE := 10.0            # ... and across (3 pixels of a headset's from 5 km)
const POST := 2.4                  # a post's side, m
const LANES := [-0.18, 0.0, 0.18]  # a gate's middle, of the road's width left of its centreline
const SPAN := 0.09                 # its half-span, of the road's width ...
const SPAN_MIN := 14.0             # ... and never under or over these, m
const SPAN_MAX := 36.0
const ORDER := ["boost", "energy", "boost", "coolant"]
const COLOURS := {"boost": Color(1.0, 0.5, 0.06), "energy": Color(0.05, 1.0, 0.85), "coolant": Color(0.5, 0.58, 1.0)}

var view
var sim
var on := true                 # false: nothing drawn, nothing taken
var taken := {}                # "road:sample" -> the sim time it is back
var took := 0                  # gates taken this flight
var _gates := {}               # road -> its gates (network_gates / course_gates), found once
var _slots: Array = []         # the drawn gates: {node, mesh_instance, key, look}
var _prev: Array = []          # [road, f] a frame ago
var _lit := {}                 # kind -> the posts' material
var _soft := {}                # kind -> the sheet's and the mast's
var _meshes := {}              # "half-span|kind" -> ArrayMesh


## Which gate the k-th on a road is: with the consumables off every one is the plain surge.
static func kind_of(k: int, limits: bool) -> String:
	return String(ORDER[posmod(k, ORDER.size())]) if limits else "boost"


static func _span(w: float) -> float:
	return clampf(w * SPAN, SPAN_MIN, SPAN_MAX)


## The Network: road r's gates, [{road, i (sample), lat (m left of the centreline), hw (half-span, m), k}].
static func network_gates(s, r: int) -> Array:
	var out := []
	if s.kind != "network" or r < 0 or r >= s.roads.size():
		return out
	var R = s.roads[r]
	if R.shaft or R.deck or R.role != "" or r == int(s.NET_PRESSURE[0]) or R.N < 4:
		return out
	var step: float = s.NET_STEP
	var total := float(R.N - 1) * step
	var k := 0
	var d := END_CLEAR + fmod(float(r) * 7919.0, SPACING * 0.5)      # (a phase a road: they do not line up across the country)
	while d < total - END_CLEAR:
		var i := int(round(d / step))
		if _network_ok(s, r, R, i):
			var w: float = R.w[i]
			var hw := _span(w)
			var flat: float = maxf(0.0, w / 2.0 - s.net_edge_span(w) - hw)      # (the whole gate on the road's flat, clear of its edges' ramps)
			out.append({"road": r, "i": i, "lat": clampf(float(LANES[posmod(r + k, LANES.size())]) * w, -flat, flat), "hw": hw, "k": k})
			k += 1
		d += SPACING
	return out


static func _network_ok(s, r: int, R, i: int) -> bool:
	if i < 2 or i > R.N - 3 or i >= R.mode.size() or R.mode[i] != 1:      # the towns are STARFIGHTER's: none there
		return false
	var step: float = s.NET_STEP
	if absf(s.net_height(r, float(i + 2)) - s.net_height(r, float(i - 2))) / (4.0 * step) > MAX_GRADE:
		return false
	var clear := int(JUNCTION_CLEAR / step)
	for table in [[R.jx, s.junctions], [R.sjx, s.get("surface_junctions")]]:
		if table[1] == null:
			continue
		for j in table[0]:
			if int(j) < 0 or int(j) >= (table[1] as Array).size():
				continue
			var J: Array = table[1][int(j)]
			for side in [0, 3]:
				if J.size() > side + 2 and int(J[side]) == r:
					var lo := mini(int(J[side + 1]), int(J[side + 2]))
					var hi := maxi(int(J[side + 1]), int(J[side + 2]))
					if i >= lo - clear and i <= hi + clear:
						return false
	return true


## Eridanus: the loop's gates, the same shape (road 0).
static func course_gates(s) -> Array:
	var out := []
	if not s.course or s.track_name != "eridanus" or s.N < 16:
		return out
	var n := clampi(int(round(s.track_length / COURSE_SPACING)), 3, 8)
	var reach := maxi(4, int(0.05 * s.N))
	for g in n:
		var want := int((float(g) + 0.5) / float(n) * float(s.N))
		var best := -1
		for o in reach + 1:
			for sgn in [1, -1]:
				var i := posmod(want + o * sgn, s.N)
				if best < 0 and _course_ok(s, i):
					best = i
			if best >= 0:
				break
		if best >= 0:
			var w: float = s.tw[best]
			out.append({"road": 0, "i": best, "lat": float(LANES[g % LANES.size()]) * w, "hw": _span(w), "k": g})
	return out


static func _course_ok(s, i: int) -> bool:
	var N: int = s.N
	if s.tw[i] < 300.0:                                       # the open country's width: not a town's
		return false
	if not s.tb.is_empty() and absf(s.tb[i]) > 0.005:         # level across
		return false
	if s.tcover.size() == N and s.tcover[i] != 0:             # not under a covered ramp
		return false
	for o in [-6, 6]:                                         # straight: the road's heading holds 6 samples either way
		var j := posmod(i + o, N)
		if s.ttx[i] * s.ttx[j] + s.tty[i] * s.tty[j] < 0.99995:
			return false
		if absf(s.tw[j] - s.tw[i]) > 1.0:
			return false
	return true


func build(v) -> void:
	view = v
	sim = v.sim
	name = "PowerUps"
	for kind in COLOURS:
		var c: Color = COLOURS[kind]
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.albedo_color = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6)
		lit.cull_mode = BaseMaterial3D.CULL_DISABLED
		_lit[kind] = lit
		var soft := StandardMaterial3D.new()
		soft.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		soft.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		soft.cull_mode = BaseMaterial3D.CULL_DISABLED
		soft.vertex_color_use_as_albedo = true
		soft.albedo_color = Color(c.r, c.g, c.b, 1.0)
		soft.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_soft[kind] = soft
	for k in POOL:
		var node := Node3D.new()
		node.name = "Gate%d" % k
		node.visible = false
		var mi := MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mi)
		add_child(node)
		_slots.append({"node": node, "mi": mi, "key": "", "look": ""})


## The gates of the road the craft is on (none off the roads, on a branch, or on a road that has none).
func gates_on(road: int) -> Array:
	if not _gates.has(road):
		_gates[road] = network_gates(sim, road) if sim.kind == "network" else (course_gates(sim) if road == 0 else [])
	return _gates[road]


## Where the pod is: [road, fractional sample, m left of the centreline], [] where there are no gates.
func where() -> Array:
	var P = sim.pod
	if sim.kind == "network":
		if P.off_road or P.path < 0 or P.path >= sim.roads.size():
			return []
		var R = sim.roads[P.path]
		var i := clampi(int(P.hint), 0, R.N - 1)
		var dx: float = P.x - R.px[i]
		var dy: float = P.y - R.py[i]
		return [int(P.path), float(i) + (dx * R.tx[i] + dy * R.ty[i]) / maxf(1.0, R.len[i]), dx * R.nx[i] + dy * R.ny[i]]
	if sim.course and int(P.path) == 0 and sim.N > 0:
		var i := posmod(int(P.hint), sim.N)
		var dx: float = P.x - sim.tpx[i]
		var dy: float = P.y - sim.tpy[i]
		return [0, float(i) + (dx * sim.ttx[i] + dy * sim.tty[i]) / maxf(1.0, sim.tlen[i]), dx * sim.tnx[i] + dy * sim.tny[i]]
	return []


static func key_of(g: Dictionary) -> String:
	return "%d:%d" % [int(g.road), int(g.i)]


## A gate's place in the world: its middle on the road's surface, across the road, standing straight up.
func gate_xf(g: Dictionary) -> Transform3D:
	var i: int = g.i
	var px: float
	var py: float
	var t: Vector2
	var n: Vector2
	var h := 0.0
	var up := Vector3.UP
	if sim.kind == "network":
		var R = sim.roads[int(g.road)]
		px = R.px[i]
		py = R.py[i]
		t = Vector2(R.tx[i], R.ty[i])
		n = Vector2(R.nx[i], R.ny[i])
		h = sim.net_deck(int(g.road), float(i), float(g.lat)) + sim.net_edge(R.w[i], float(g.lat)).x
		if R.banked and R.bank[i] != 0.0:      # (on a banked bend it stands square to the deck)
			up = Vector3.UP * cos(R.bank[i]) + Vector3(n.x, 0.0, -n.y) * sin(R.bank[i])
	else:
		px = sim.tpx[i]
		py = sim.tpy[i]
		t = Vector2(sim.ttx[i], sim.tty[i])
		n = Vector2(sim.tnx[i], sim.tny[i])
		h = sim.surface_at(px + n.x * float(g.lat), py + n.y * float(g.lat), i, 0).x
	var x := px + n.x * float(g.lat)
	var y := py + n.y * float(g.lat)
	return Transform3D(Basis.looking_at(Vector3(t.x, 0.0, -t.y), up), Vector3(x - view.org_x, h, -(y - view.org_y)))


## A frame: gates crossed since the last are taken, the nearest are drawn.
func sync() -> void:
	var at: Array = where() if on else []
	if at.is_empty():
		_prev = []
		for slot in _slots:
			(slot.node as Node3D).visible = false
		return
	var road: int = at[0]
	var f: float = at[1]
	var lat: float = at[2]
	var gates := gates_on(road)
	if not _prev.is_empty() and int(_prev[0]) == road and absf(f - float(_prev[1])) < 60.0 and sim.crash_t <= 0.0:
		for g in gates:
			var a := float(_prev[1]) - float(g.i)
			var b := f - float(g.i)
			if ((a <= 0.0 and b > 0.0) or (a >= 0.0 and b < 0.0)) and absf(lat - float(g.lat)) <= float(g.hw) + CATCH \
					and sim.time >= float(taken.get(key_of(g), -1.0)):
				taken[key_of(g)] = sim.time + REARM_S
				took += 1
				view.power_up(kind_of(int(g.k), bool(sim.P.limits)))
	_prev = [road, f]
	# the nearest, drawn: a gate keeps its slot while it is one of them
	var step: float = sim.NET_STEP if sim.kind == "network" else sim.track_length / maxf(1.0, float(sim.N))
	var near := []
	for g in gates:
		var d := absf(float(g.i) - f)
		if sim.kind != "network":
			d = minf(d, float(sim.N) - d)      # (the loop closes)
		d *= step
		if d <= VIS and sim.time >= float(taken.get(key_of(g), -1.0)):
			near.append([d, g])
	near.sort_custom(func(p, q): return p[0] < q[0])
	near.resize(mini(near.size(), POOL))
	var wanted := {}
	for row in near:
		wanted[key_of(row[1])] = row[1]
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
	for kind in _soft:
		(_soft[kind] as StandardMaterial3D).albedo_color.a = pulse
	for slot in _slots:
		if slot.key != "" and not wanted.has(slot.key):
			slot.key = ""
			(slot.node as Node3D).visible = false
	for key in wanted:
		var slot = null
		for s in _slots:
			if s.key == key:
				slot = s
		if slot == null:
			for s in _slots:
				if slot == null and s.key == "":
					slot = s
		if slot == null:
			continue
		var g: Dictionary = wanted[key]
		slot.key = key
		var kind := kind_of(int(g.k), bool(sim.P.limits))
		var look := "%.1f|%s" % [float(g.hw), kind]
		if slot.look != look:
			slot.look = look
			(slot.mi as MeshInstance3D).mesh = _mesh(float(g.hw), kind)
		(slot.node as Node3D).transform = gate_xf(g)
		(slot.node as Node3D).visible = true


func drawn() -> int:
	var n := 0
	for slot in _slots:
		n += int((slot.node as Node3D).visible)
	return n


static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, colour: Color) -> void:
	var h := size / 2.0
	var corners := []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(xf * Vector3(sx * h.x, sy * h.y, sz * h.z))
	# (corner index = 4 * x + 2 * y + z)
	for face in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for c in tri:
				st.set_color(colour)
				st.add_vertex(corners[face[c]])


## A gate of half-span hw: its posts, beam and chevron (one lit surface), the sheet between the
## posts and the mast over the beam (one soft one), about its middle on the road, x across.
func _mesh(hw: float, kind: String) -> ArrayMesh:
	var key := "%.1f|%s" % [hw, kind]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_box(st, Transform3D(Basis.IDENTITY, Vector3(side * (hw + POST / 2.0), HIGH / 2.0, 0.0)), Vector3(POST, HIGH, POST), Color.WHITE)
		# the chevron over the lane: two bars leaning to a point, the way to go through
		_box(st, Transform3D(Basis.from_euler(Vector3(0.0, 0.0, side * deg_to_rad(52.0))), Vector3(side * hw * 0.2, HIGH * 0.55, 0.0)),
			Vector3(1.3, hw * 0.52, 1.3), Color.WHITE)
	_box(st, Transform3D(Basis.IDENTITY, Vector3(0.0, HIGH + POST / 2.0, 0.0)), Vector3(2.0 * hw + 2.0 * POST, POST, POST), Color.WHITE)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	mesh.surface_set_material(0, _lit[kind])
	var c: Color = COLOURS[kind]
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# the sheet: faint at the road, a little stronger under the beam
	var low := Color(c.r, c.g, c.b, 0.07)
	var top := Color(c.r, c.g, c.b, 0.26)
	for tri in [[[-hw, 0.0, low], [hw, 0.0, low], [hw, HIGH, top]], [[-hw, 0.0, low], [hw, HIGH, top], [-hw, HIGH, top]]]:
		for p in tri:
			st.set_color(p[2])
			st.add_vertex(Vector3(float(p[0]), float(p[1]), 0.0))
	# the mast: two crossed sheets of light over the beam, fading as they climb
	var foot := Color(c.r, c.g, c.b, 0.8)
	var head := Color(c.r, c.g, c.b, 0.0)
	for across in [Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)]:
		var a: Vector3 = across * (MAST_WIDE / 2.0)
		var y0 := HIGH + POST
		for tri in [[[-1.0, y0, foot], [1.0, y0, foot], [1.0, y0 + MAST, head]], [[-1.0, y0, foot], [1.0, y0 + MAST, head], [-1.0, y0 + MAST, head]]]:
			for p in tri:
				st.set_color(p[2])
				st.add_vertex(a * float(p[0]) + Vector3(0.0, float(p[1]), 0.0))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
	mesh.surface_set_material(1, _soft[kind])
	_meshes[key] = mesh
	return mesh
