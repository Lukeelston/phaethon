## The 100-mile range around the pod, streamed in 2 km chunks. Chunk meshes live in
## chunk-local coordinates; only each chunk node's position (computed in 64-bit against
## the floating origin) is large-scale, so the far end renders as cleanly as the start.
extends Node3D

const Sim := preload("res://sim/craft_sim.gd")

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
const RAMP_NAMES := {3.0: "SMALL  3 m", 6.0: "MEDIUM  6 m", 10.0: "LARGE  10 m", 15.0: "HUGE  15 m"}
const COUNTDOWN_MI := [20, 15, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]   # miles to the stop box
const COUNTDOWN_M := [1000, 500, 250, 100]                      # metres to the stop box

var sim
var view
var chunks := {}
var mats := {}


func build(s, v) -> void:
	sim = s
	view = v
	mats.runway = v._mat(Color(0.66, 0.55, 0.40))
	mats.line = v._mat(Color(0.96, 0.94, 0.88))
	mats.jump = v._mat(Color(0.95, 0.55, 0.15))
	mats.ramp = v._mat(Color(0.40, 0.37, 0.35))
	mats.pylon = v._mat(Color(1.0, 0.42, 0.08))
	mats.rock = v._mat(Color(0.55, 0.42, 0.28))
	mats.post = v._mat(Color(0.18, 0.19, 0.21))
	mats.box_fill = v._mat(Color(0.78, 0.22, 0.12))


## Centreline of the twisty lane: sweepers whose wavelength shrinks linearly with distance.
static func twist_y(x: float) -> float:
	var lam := LAMBDA0 + (LAMBDA1 - LAMBDA0) * x / Sim.RANGE_LEN
	var phase := TAU * Sim.RANGE_LEN / (LAMBDA1 - LAMBDA0) * log(lam / LAMBDA0)
	return TWIST_Y + TWIST_AMP * sin(phase)


func sync(ox: float, oy: float) -> void:
	var last := int(ceil((Sim.RANGE_LEN + Sim.OVERRUN) / CHUNK))   # runway runs on through the overrun zone
	var lo := maxi(-1, int(floor((ox - BEHIND) / CHUNK)))
	var hi := mini(last, int(floor((ox + AHEAD) / CHUNK)))
	for idx in chunks.keys():
		if idx < lo or idx > hi:
			chunks[idx].queue_free()
			chunks.erase(idx)
	var built := 0
	for idx in range(lo, hi + 1):
		if not chunks.has(idx) and built < 2:   # at most two per frame: no hitch when streaming
			chunks[idx] = _make_chunk(idx)
			built += 1
	for idx in chunks:
		chunks[idx].position = Vector3(idx * CHUNK - ox, 0.0, oy)


func _quad(st: SurfaceTool, x0: float, x1: float, y0: float, y1: float, h := 0.02) -> void:
	var a := Vector3(x0, h, -y0)
	var b := Vector3(x1, h, -y0)
	var c := Vector3(x1, h, -y1)
	var d := Vector3(x0, h, -y1)
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


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
	_quad(strip, x0, x1, -RUNWAY_HALF, RUNWAY_HALF, 0.01)
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
	for metres in COUNTDOWN_M:
		var bx: float = Sim.BOX_X - metres - cx
		if bx >= 0.0 and bx < CHUNK:
			_board(node, bx, "%d m" % metres)
	var box_lx: float = Sim.BOX_X - cx
	if box_lx >= -Sim.BOX_HALF and box_lx < CHUNK + Sim.BOX_HALF:
		_stop_box(node, box_lx)

	# rocks: a speed cue off the lanes, deterministic per chunk
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + idx
	var rocks := MultiMesh.new()
	rocks.transform_format = MultiMesh.TRANSFORM_3D
	rocks.mesh = BoxMesh.new()
	var placed: Array[Transform3D] = []
	while placed.size() < 160:
		var lx := rng.randf_range(x0, x1)
		var y := rng.randf_range(-1800.0, 1800.0)
		if absf(y) < RUNWAY_HALF + 20.0 or absf(y - Sim.JUMP_Y) < 50.0 or absf(y - twist_y(cx + lx)) < 60.0:
			continue
		var sz := rng.randf_range(0.6, 4.0)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.4, 1.2), sz * rng.randf_range(0.6, 1.4)))
		placed.append(Transform3D(b, Vector3(lx, sz * 0.3, -y)))
	rocks.instance_count = placed.size()
	for i in placed.size():
		rocks.set_instance_transform(i, placed[i])
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = rocks
	rmi.material_override = mats.rock
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(rmi)
	return node


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
	var label: String = RAMP_NAMES.get(h, "%d m" % h)
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
