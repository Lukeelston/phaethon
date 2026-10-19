## The 100-mile range around the pod, streamed in 2 km chunks. Chunk meshes live in
## chunk-local coordinates; only each chunk node's position (computed in 64-bit against
## the floating origin) is large-scale, so the far end renders as cleanly as the start.
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")
const Kit := preload("res://view/mesh_kit.gd")
const RouteScript := preload("res://view/route_features.gd")
const Props := preload("res://view/props.gd")

const CHUNK := 2000.0
const AHEAD := 14000.0
const BEHIND := 4000.0
const MILE := 1609.344
const RUNWAY_HALF := 60.0
const TWIST_Y := -400.0
const TWIST_AMP := 180.0
const TWIST_HALF := 30.0
const LAMBDA0 := 3000.0   # sweeper wavelength at mile 0 ...
const LAMBDA1 := 700.0    # ... tightening to this by mile 100
const RAMP_NAMES := {3.0: "SMALL  10 FT", 6.0: "MEDIUM  20 FT", 10.0: "LARGE  33 FT", 15.0: "HUGE  49 FT"}   # heights in m, named in feet
const COUNTDOWN_MI := [20, 15, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]   # miles to the stop box
const COUNTDOWN_FT := [3000, 1500, 750, 300]                    # feet to the stop box
const POST_Y := RUNWAY_HALF + 4.0   # marker poles both sides of the runway, every 50 m
const POST_DX := 50.0
const POLE_Y := -110.0              # telegraph line south of the runway
const POLE_DX := 50.0
const WIRE_Z := [-1.1, 0.0, 1.1]    # three wires across the crossarm
const HWY_Y := -950.0               # traffic corridors (TrafficView drives on them)
const RAIL_Y := 700.0
const ASPHALT_PERIOD := 64000.0     # asphalt UVs wrap here: a whole number of chunks
const EDGE_LIGHT_DX := 60.0         # runway edge lights, both sides
const EDGE_LIGHT_Y := RUNWAY_HALF + 1.5
const AIRFIELD := Rect2(-560.0, 90.0, 900.0, 270.0)   # chunk 0: the start's airfield (sim x, y), between the runway and the jump lane
const PLAYA_HALF := 320.0           # the dry lake round the runway: mean half-width (see shore())
const GROUND_PERIOD := 4096.0       # view/ground.gdshader's PERIOD (the shore curve repeats on it)
const VEG_BLOCK := 500.0            # plants are built in blocks this long, each culled on its own
const BUSHES := 650                 # per block and side: scrub from the shore out ~1.1 km
const TREES := 60                   # per block and side: Joshua trees out ~2.5 km

var sim
var view
var chunks := {}
var mats := {}
var route   # overpasses and landmarks (view/route_features.gd)
var veg_queue := []   # [chunk node, idx, cx, bx0, bx1, side]: vegetation blocks still to build


func build(s, v) -> void:
	sim = s
	view = v
	route = RouteScript.new()
	mats.runway = _asphalt(Color(0.31, 0.30, 0.29), 20.0)   # aggregate, joints and rubber: the nearest speed cue
	mats.line = v._mat(Color(0.96, 0.94, 0.88))
	mats.jump = v._mat(Color(0.95, 0.55, 0.15))
	mats.ramp = v._mat(Color(0.40, 0.37, 0.35))
	mats.pylon = v._mat(Color(1.0, 0.42, 0.08))
	mats.rock = v._mat(Color(0.55, 0.42, 0.28))
	mats.post = v._mat(Color(0.18, 0.19, 0.21))
	mats.box_fill = v._mat(Color(0.78, 0.22, 0.12))
	mats.white = v._mat(Color(0.92, 0.92, 0.9))
	mats.reflect = v._mat(Color(1.0, 0.55, 0.1), true)
	mats.wood = v._mat(Color(0.33, 0.24, 0.17))
	mats.wire = v._mat(Color(0.08, 0.08, 0.09), true)
	mats.asphalt = _asphalt(Color(0.25, 0.245, 0.24), 6.0)
	mats.ballast = v._mat(Color(0.45, 0.41, 0.37))
	mats.rail = v._mat(Color(0.5, 0.5, 0.52))
	mats.strata = Kit.vertex_colors()


## Asphalt (view/asphalt.gdshader): base colour, and how far either side of the centreline the
## rubber is laid. Its UVs are (metres along mod ASPHALT_PERIOD, metres across): see _quad_uv.
func _asphalt(base: Color, lane_half: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://view/asphalt.gdshader")
	m.set_shader_parameter("period", ASPHALT_PERIOD)
	m.set_shader_parameter("base", Vector3(base.r, base.g, base.b))   # sRGB as-is (a Color would arrive linearised)
	m.set_shader_parameter("lane_half", lane_half)
	return m


## Centreline of the twisty lane: sweepers whose wavelength shrinks linearly with distance.
static func twist_y(x: float) -> float:
	var lam := LAMBDA0 + (LAMBDA1 - LAMBDA0) * x / Sim.RANGE_LEN
	var phase := TAU * Sim.RANGE_LEN / (LAMBDA1 - LAMBDA0) * log(lam / LAMBDA0)
	return TWIST_Y + TWIST_AMP * sin(phase)


func sync(ox: float, oy: float, t := 0.0) -> void:
	route.animate(t)
	for idx in chunks:
		for dish in chunks[idx].get_meta("spin", []):
			(dish as Node3D).rotation.y = t * 1.3
	var last := int(ceil((Sim.RANGE_LEN + Sim.OVERRUN) / CHUNK))   # runway runs on through the overrun zone
	var lo := maxi(-1, int(floor((ox - BEHIND) / CHUNK)))
	var hi := mini(last, int(floor((ox + AHEAD) / CHUNK)))
	for idx in chunks.keys():
		if idx < lo or idx > hi:
			chunks[idx].queue_free()
			chunks.erase(idx)
	var built := 0
	for idx in range(lo, hi + 1):
		if not chunks.has(idx) and built < 1:   # one per frame (~3 ms), plants queued: no hitch when streaming
			chunks[idx] = _make_chunk(idx)
			built += 1
	for k in (2 if built == 0 else 0):   # never on a frame that built a chunk
		if veg_queue.is_empty():
			break
		_build_veg(veg_queue.pop_front())
	for idx in chunks:
		chunks[idx].position = Vector3(idx * CHUNK - ox, 0.0, oy)


func _quad(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, h := 0.02) -> void:
	var a := Vector3(x0, h, -y0)
	var b := Vector3(x1, h, -y0)
	var c := Vector3(x1, h, -y1)
	var d := Vector3(x0, h, -y1)
	for v in [a, c, b, a, d, c]:   # clockwise seen from above: Godot's front face, so the sun lights it
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


## A flat quad with asphalt UVs: u = metres along (the chunk's start mod ASPHALT_PERIOD, plus
## chunk-local x), v = metres across from `centre`.
func _quad_uv(st: SurfaceTool, cx: float, x0: float, x1: float, y0: float, y1: float, centre: float, h := 0.02) -> void:
	var u0 := fposmod(cx, ASPHALT_PERIOD)
	for c in [[x0, y0], [x1, y1], [x1, y0], [x0, y0], [x0, y1], [x1, y1]]:   # clockwise from above
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0 + c[0], c[1] - centre))
		st.add_vertex(Vector3(c[0], h, -c[1]))


func _mesh(parent: Node3D, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _make_chunk(idx: int) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var cx := idx * CHUNK
	var x0 := maxf(0.0, cx) - cx
	var x1 := minf(Sim.RANGE_LEN + Sim.OVERRUN, cx + CHUNK) - cx
	if x1 <= x0:
		return node

	# runway: compacted strip, edge lines, centre dashes
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad_uv(strip, cx, x0, x1, -RUNWAY_HALF, RUNWAY_HALF, 0.0, 0.01)
	_mesh(node, strip, mats.runway)
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_quad(paint, x0, x1, s * RUNWAY_HALF - 0.75, s * RUNWAY_HALF + 0.75)
	var dash := ceilf((cx + x0) / 60.0) * 60.0 - cx
	while dash < x1:
		_quad(paint, dash, minf(dash + 30.0, x1), -0.5, 0.5)
		dash += 60.0
	if idx == 0:
		for k in 8:   # start line
			_quad(paint, 0.0, 4.0, -RUNWAY_HALF + k * 15.0, -RUNWAY_HALF + k * 15.0 + 7.5)
	_mesh(node, paint, mats.line)

	# jump lane edges and kickers
	var jl := SurfaceTool.new()
	jl.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_quad(jl, x0, x1, Sim.JUMP_Y + s * Sim.JUMP_W / 2.0 - 0.75, Sim.JUMP_Y + s * Sim.JUMP_W / 2.0 + 0.75)
	_mesh(node, jl, mats.jump)
	for r in sim.ramps:
		var rx: float = r[0] - cx
		if rx >= 0.0 and rx < CHUNK:
			_ramp(node, rx, r[1], r[2])

	# twisty lane pylons, a gate every 25 m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.7
	cone.height = 2.0
	mm.mesh = cone
	var n := int((x1 - x0) / 25.0)
	mm.instance_count = n * 2
	for i in n:
		var lx := x0 + i * 25.0
		var yc := twist_y(cx + lx)
		for s in 2:
			var y := yc + (TWIST_HALF if s == 0 else -TWIST_HALF)
			mm.set_instance_transform(i * 2 + s, Transform3D(Basis(), Vector3(lx, 1.0, -y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mats.pylon
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)

	_roadside(node, cx, x0, x1)

	# the highway and the railway the traffic runs on
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad_uv(road, cx, x0, x1, HWY_Y - 7.5, HWY_Y + 7.5, HWY_Y, 0.02)
	_mesh(node, road, mats.asphalt)
	var bed := SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(bed, x0, x1, RAIL_Y - 2.6, RAIL_Y + 2.6, 0.04)
	_mesh(node, bed, mats.ballast)
	var steel := SurfaceTool.new()
	steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_quad(steel, x0, x1, RAIL_Y + s * 0.72 - 0.04, RAIL_Y + s * 0.72 + 0.04, 0.2)
	_mesh(node, steel, mats.rail)
	var lanes := SurfaceTool.new()
	lanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		_quad(lanes, x0, x1, HWY_Y + s * 6.8 - 0.12, HWY_Y + s * 6.8 + 0.12, 0.03)
	var hd := ceilf((cx + x0) / 12.0) * 12.0 - cx
	while hd < x1:
		_quad(lanes, hd, minf(hd + 3.0, x1), HWY_Y - 0.1, HWY_Y + 0.1, 0.03)
		hd += 12.0
	_mesh(node, lanes, mats.line)

	# mile signs between the runway and the jump lane
	var m := int(ceil((cx + x0) / MILE))
	while m * MILE < cx + x1:
		if m > 0:
			_sign(node, m * MILE - cx, 90.0, "MILE %d" % m, 260)
		m += 1
	if idx % 4 == 0:
		_sign(node, x0 + 300.0, Sim.JUMP_Y + 45.0, "JUMP LANE", 160)
		_sign(node, x0 + 300.0, twist_y(cx + x0 + 300.0) + 60.0, "TWISTY LANE", 160)

	# sprint: countdown boards to the stop box, then the box itself
	for mi in COUNTDOWN_MI:
		var bx: float = Sim.BOX_X - mi * MILE - cx
		if bx >= 0.0 and bx < CHUNK:
			_board(node, bx, "%d MI" % mi)
	for ft in COUNTDOWN_FT:
		var bx: float = Sim.BOX_X - ft * 0.3048 - cx
		if bx >= 0.0 and bx < CHUNK:
			_board(node, bx, "%d FT" % ft)
	var box_lx: float = Sim.BOX_X - cx
	if box_lx >= -Sim.BOX_HALF and box_lx < CHUNK + Sim.BOX_HALF:
		_stop_box(node, box_lx)

	_spires(node, idx, cx, x0, x1)
	route.build_chunk(node, cx, x0, x1)

	# boulders: a speed cue off the lanes, deterministic per chunk
	Props.multi(node, "boulder", rock_xforms(idx, cx, x0, x1), 3000.0)
	# the desert past the dry lake: scrub and Joshua trees, in blocks so each culls on its own;
	# queued, a couple of blocks a frame (chunks stream in 14 km ahead, long before you see them)
	var bx := x0
	while bx < x1 - 1.0:
		var bx1 := minf(bx + VEG_BLOCK, x1)
		for side in [1.0, -1.0]:
			veg_queue.append([node, idx, cx, bx, bx1, side])
		bx = bx1
	_edge_lights(node, cx, x0, x1)
	if idx == 0:
		_airfield(node)
	return node


## The dry lake's shore on one side (side +1 left, -1 right) at sim x: the same curve as
## view/ground.gdshader's (without its small-scale wobble), so the scrub starts where the
## lakebed ends.
static func shore(x: float, side: float) -> float:
	var ph := 1.7 if side < 0.0 else 0.0
	var u := TAU * fposmod(x, GROUND_PERIOD) / GROUND_PERIOD
	return PLAYA_HALF + 120.0 * sin(3.0 * u + 1.0 + ph) + 70.0 * sin(11.0 * u + 2.0 + ph) + 35.0 * sin(29.0 * u + ph)


## Build one queued vegetation block (its chunk may have been freed since).
func _build_veg(task: Array) -> void:
	var node = task[0]   # untyped: a freed chunk must not trip a typed assignment
	if not is_instance_valid(node):
		return
	var veg := veg_xforms(task[1], task[2], task[3], task[4], task[5])
	var blk := Node3D.new()
	blk.position = Vector3((task[3] + task[4]) / 2.0, 0.0, -task[5] * (PLAYA_HALF + 700.0))
	node.add_child(blk)
	var back := Transform3D(Basis(), -blk.position)
	Props.multi(blk, "bush", veg[2].map(func(t): return back * t), 1600.0)
	Props.multi(blk, "joshua0", veg[0].map(func(t): return back * t), 6000.0)
	Props.multi(blk, "joshua1", veg[1].map(func(t): return back * t), 6000.0)


## Plant placements in chunk idx between chunk-local bx0..bx1 on one side (+1 left, -1 right):
## [joshua0 xforms, joshua1 xforms, bush xforms]. Scrub thickest just past the shore, in clumps;
## Joshua trees further out. Clear of every lane, corridor and route feature.
func veg_xforms(idx: int, cx: float, bx0: float, bx1: float, side: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + idx * 64 + int(bx0 / 100.0) * 2 + (0 if side > 0.0 else 1)
	var out := [[], [], []]
	var n := int(BUSHES * (bx1 - bx0) / VEG_BLOCK)
	for i in n + int(TREES * (bx1 - bx0) / VEG_BLOCK):
		var tree := i >= n
		var lx := rng.randf_range(bx0, bx1)
		var x := cx + lx
		var d := 40.0 + (2500.0 if tree else 1100.0) * pow(rng.randf(), 1.5 if tree else 1.8)
		var y := side * (shore(x, side) + d)
		# clumps: thin out where a slow wave says so
		if not tree and sin(x * 0.021 + y * 0.017) + sin(x * 0.0073 - y * 0.011) < -0.6:
			continue
		if not _clear(x, y, 6.0):
			continue
		if tree:
			out[0 if rng.randf() < 0.5 else 1].append(Props.scatter_xf(rng, Vector3(lx, 0.0, -y), 0.8, 1.35))
		else:
			out[2].append(Props.scatter_xf(rng, Vector3(lx, 0.0, -y), 0.8, 2.0, 0.0))
	return out


## Whether (sim x, y) is clear of the lanes, the corridors, the route's features and the airfield.
func _clear(x: float, y: float, margin: float) -> bool:
	return not (absf(y) < RUNWAY_HALF + 20.0 or absf(y - Sim.JUMP_Y) < 50.0 or absf(y - twist_y(x)) < 60.0
		or absf(y - POLE_Y) < 8.0 or absf(y - HWY_Y) < 25.0 or absf(y - RAIL_Y) < 15.0
		or route.blocked(x, y, margin) or AIRFIELD.grow(margin).has_point(Vector2(x, y)))


## Runway edge lights every EDGE_LIGHT_DX both sides (posts and glowing lamps), and at the start a
## green threshold bar across the runway.
func _edge_lights(node: Node3D, cx: float, x0: float, x1: float) -> void:
	var posts: Array[Transform3D] = []
	var x := ceilf((cx + x0) / EDGE_LIGHT_DX) * EDGE_LIGHT_DX - cx + EDGE_LIGHT_DX / 2.0
	while x < x1:
		for sy in [-EDGE_LIGHT_Y, EDGE_LIGHT_Y]:
			posts.append(Transform3D(Basis(), Vector3(x, 0.0, -sy)))
		x += EDGE_LIGHT_DX
	Props.multi(node, "edge_light", posts, 4000.0)
	Props.multi(node, "lamp_white", posts, 4000.0, true)
	if cx <= 0.0 and cx + CHUNK > 0.0:
		var bar: Array[Transform3D] = []
		var yy := -RUNWAY_HALF + 3.0
		while yy < RUNWAY_HALF:
			bar.append(Transform3D(Basis(), Vector3(-cx - 6.0, 0.0, -yy)))
			yy += 4.0
		Props.multi(node, "lamp_green", bar, 4000.0, true)


## The start's airfield, beside the runway behind the start line (chunk 0, sim coordinates): a
## concrete apron, three hangars with their doors to the runway, a control tower, fuel tanks, a
## spinning radar, a windsock and a couple of bowsers.
func _airfield(node: Node3D) -> void:
	var apron := SurfaceTool.new()
	apron.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad_uv(apron, 0.0, AIRFIELD.position.x, AIRFIELD.end.x, AIRFIELD.position.y, AIRFIELD.end.y, 0.0, 0.03)
	var concrete := _asphalt(Color(0.62, 0.6, 0.57), 0.0)
	concrete.set_shader_parameter("joint_every", 7.5)
	_mesh(node, apron, concrete)
	var door_to_runway := Basis(Vector3.UP, PI)   # doors face render +z: toward the runway (smaller sim y)
	for k in 3:
		Props.place(node, "hangar", Transform3D(door_to_runway, Vector3(-500.0 + k * 52.0, 0.0, -300.0)))
	Props.place(node, "tower", Transform3D(door_to_runway, Vector3(-290.0, 0.0, -230.0)))
	for k in 2:
		Props.place(node, "tank", Transform3D(Basis(), Vector3(-200.0 + k * 16.0, 0.0, -320.0)))
	Props.place(node, "radar_base", Transform3D(Basis(), Vector3(-110.0, 0.0, -300.0)))
	var dish := Props.place(node, "radar_dish", Transform3D(Basis(), Vector3(-110.0, 9.0, -300.0)))
	node.set_meta("spin", [dish])
	Props.place(node, "windsock", Transform3D(Basis(), Vector3(140.0, 0.0, -82.0)))
	Props.place(node, "truck", Transform3D(Basis(Vector3.UP, 0.3), Vector3(-380.0, 0.03, -190.0)))
	Props.place(node, "truck", Transform3D(Basis(Vector3.UP, -1.2), Vector3(-230.0, 0.03, -160.0)))


## Rock placements for chunk idx (chunk-local), clear of every lane, corridor and route
## feature. Deterministic per chunk; tests/test_route.gd checks them.
func rock_xforms(idx: int, cx: float, x0: float, x1: float) -> Array[Transform3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + idx
	var placed: Array[Transform3D] = []
	while placed.size() < 160:
		var lx := rng.randf_range(x0, x1)
		var y := rng.randf_range(-1800.0, 1800.0)
		if not _clear(cx + lx, y, 8.0):
			continue
		var sz := rng.randf_range(0.6, 4.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.4, 1.2), sz * rng.randf_range(0.6, 1.4)))
		placed.append(Transform3D(b, Vector3(lx, sz * 0.3, -y)))
	return placed


## Sandstone spires and mesas out in the desert, 0.7-4.5 km off the runway either side, clear
## of every lane and corridor: big parallax, so the middle distance moves too. One mesh per
## chunk, banded in strata.
func _spires(node: Node3D, idx: int, cx: float, x0: float, x1: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4040 + idx
	var bands := [Color(0.62, 0.38, 0.24), Color(0.74, 0.52, 0.33), Color(0.68, 0.45, 0.29), Color(0.82, 0.64, 0.44)]
	var parts := []
	var tries := 0
	var placed := 0
	while placed < 5 and tries < 40:
		tries += 1
		var lx := rng.randf_range(x0, x1)
		var y := rng.randf_range(700.0, 4500.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		if absf(y - HWY_Y) < 140.0 or absf(y - RAIL_Y) < 100.0 or absf(y - twist_y(cx + lx)) < 160.0 \
				or route.blocked(cx + lx, y, 260.0):
			continue
		placed += 1
		var mesa := rng.randf() < 0.3
		var h := rng.randf_range(40.0, 110.0) if mesa else rng.randf_range(60.0, 230.0)
		var r_bot := rng.randf_range(110.0, 240.0) if mesa else rng.randf_range(10.0, 26.0)
		var r_top := r_bot * (rng.randf_range(0.7, 0.85) if mesa else rng.randf_range(0.25, 0.45))
		var segs := 7 if mesa else 6
		var spin := rng.randf() * TAU
		var nb := 3 if mesa else 4
		var z0 := 0.0
		for b in nb:
			var f0 := float(b) / nb
			var f1 := float(b + 1) / nb
			var ra := lerpf(r_bot, r_top, f0)
			var rb := lerpf(r_bot, r_top, f1)
			var bh := h / nb
			parts.append([Kit.cyl(rb, ra, bh, segs), Kit.at(Vector3(lx, z0 + bh / 2.0, -y), Vector3(0, spin, 0)),
				bands[(b + idx) % bands.size()]])
			z0 += bh
		if not mesa:   # hoodoo cap: a harder slab, wider than the neck under it
			parts.append([Kit.cyl(r_top * 1.5, r_top * 1.3, h * 0.06, 6), Kit.at(Vector3(lx, h + h * 0.03, -y), Vector3(0, spin + 0.3, 0)),
				Color(0.5, 0.33, 0.22)])
	if parts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.compound(parts)
	mi.material_override = mats.strata
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)


## Things at a known spacing beside the runway, so speed reads as a rate: 3 m marker poles
## with reflector tops every 50 m on both edges, and a telegraph line (poles every 50 m, three sagging wires).
func _roadside(node: Node3D, cx: float, x0: float, x1: float) -> void:
	var first := ceilf((cx + x0) / POST_DX) * POST_DX - cx
	var xs: Array[float] = []
	var x := first
	while x < x1:
		xs.append(x)
		x += POST_DX
	var body := BoxMesh.new()
	body.size = Vector3(0.22, 3.0, 0.22)
	var cap := BoxMesh.new()
	cap.size = Vector3(0.26, 0.7, 0.26)
	var posts: Array[Transform3D] = []
	var caps: Array[Transform3D] = []
	for px in xs:
		for sy in [-POST_Y, POST_Y]:
			posts.append(Transform3D(Basis(), Vector3(px, 1.5, -sy)))
			caps.append(Transform3D(Basis(), Vector3(px, 2.75, -sy)))
	_multi(node, body, posts, mats.white)
	_multi(node, cap, caps, mats.reflect)

	var pole := CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.17
	pole.height = 11.0
	pole.radial_segments = 8
	var arm := BoxMesh.new()
	arm.size = Vector3(0.14, 0.14, 2.7)
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	for px in xs:
		poles.append(Transform3D(Basis(), Vector3(px, 5.5, -POLE_Y)))
		arms.append(Transform3D(Basis(), Vector3(px, 10.3, -POLE_Y)))
	_multi(node, pole, poles, mats.wood)
	_multi(node, arm, arms, mats.wood)
	var wires := SurfaceTool.new()
	wires.begin(Mesh.PRIMITIVE_LINES)
	for px in xs:   # each pole strings its span to the next, even across the chunk edge
		for wz in WIRE_Z:
			for k in 6:
				for e in [k, k + 1]:
					var u: float = e / 6.0
					wires.add_vertex(Vector3(px + u * POLE_DX, 10.45 - 3.2 * u * (1.0 - u), -POLE_Y + wz))
	_mesh(node, wires, mats.wire)


func _multi(node: Node3D, mesh: Mesh, xf: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mmi)


## Kicker wedge in chunk-local coordinates: 1:slope face up to h, 45-degree back face.
func _ramp(node: Node3D, rx: float, length: float, h: float) -> void:
	var y0 := Sim.JUMP_Y - Sim.JUMP_W / 2.0
	var y1 := Sim.JUMP_Y + Sim.JUMP_W / 2.0
	var p := [Vector3(rx, 0, -y0), Vector3(rx + length, h, -y0), Vector3(rx + length + h, 0, -y0),
		Vector3(rx, 0, -y1), Vector3(rx + length, h, -y1), Vector3(rx + length + h, 0, -y1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tri in [[0, 1, 4], [0, 4, 3], [1, 2, 5], [1, 5, 4], [0, 2, 1], [3, 4, 5]]:
		for k in tri:
			st.add_vertex(p[k])
	st.generate_normals()
	_mesh(node, st, mats.ramp)
	var label: String = RAMP_NAMES.get(h, "%d FT" % roundi(h * 3.28084))
	_sign(node, rx - 60.0, Sim.JUMP_Y + 32.0, label, 120)


## Countdown board: big red numbers on both sides of the runway.
func _board(node: Node3D, lx: float, text: String) -> void:
	for s in [-1.0, 1.0]:
		var y: float = s * (RUNWAY_HALF + 35.0)
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.0, 30.0, 40.0)
		post.mesh = box
		post.material_override = mats.post
		post.position = Vector3(lx, 15.0, -y)
		node.add_child(post)
		var l := Label3D.new()
		l.text = text
		l.font_size = 520
		l.pixel_size = 0.05
		l.outline_size = 24
		l.modulate = Color(0.9, 0.12, 0.06)
		l.outline_modulate = Color(1.0, 0.97, 0.9)
		l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		l.position = Vector3(lx, 48.0, -y)
		node.add_child(l)


## The stop box: a 50 m square painted across the runway centreline, STOP written in it.
func _stop_box(node: Node3D, lx: float) -> void:
	var h: float = Sim.BOX_HALF
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(fill, lx - h, lx + h, -h, h, 0.03)
	_mesh(node, fill, mats.box_fill)
	var edge := SurfaceTool.new()
	edge.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(edge, lx - h - 1.5, lx + h + 1.5, -h - 1.5, -h, 0.04)
	_quad(edge, lx - h - 1.5, lx + h + 1.5, h, h + 1.5, 0.04)
	_quad(edge, lx - h - 1.5, lx - h, -h, h, 0.04)
	_quad(edge, lx + h, lx + h + 1.5, -h, h, 0.04)
	_mesh(node, edge, mats.line)
	var l := Label3D.new()
	l.text = "STOP"
	l.font_size = 400
	l.pixel_size = 0.05
	l.modulate = Color(1.0, 0.97, 0.9)
	# lying flat, reading left-to-right for a pilot approaching along +x
	l.basis = Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
	l.position = Vector3(lx, 0.06, 0)
	node.add_child(l)


func _sign(node: Node3D, lx: float, y: float, text: String, size: int) -> void:
	var post := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, size * 0.06, 1.0)
	post.mesh = box
	post.material_override = mats.post
	post.position = Vector3(lx, size * 0.03, -y)
	node.add_child(post)
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.06
	l.outline_size = 12
	l.modulate = Color(0.12, 0.12, 0.14)
	l.outline_modulate = Color(0.98, 0.92, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = Vector3(lx, size * 0.06 + size * 0.04, -y)
	node.add_child(l)
