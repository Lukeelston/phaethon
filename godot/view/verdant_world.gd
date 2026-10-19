## Eridanus' world round the track (the track itself is view/course_world.gd): a green river valley.
##   the river   the Eridanus, from the north-western hills, across the home town (a bridge), south
##               of the start straight, across the start town at T2 (a bridge), east along the plains
##               to the lake by the Lake Village. Water: view/water.gdshader. Where it meets the track
##               the track bridges it: stone parapets on both walls, piers in the water.
##   poplars     the Heliades: lining the river's banks and both sides of every town section
##   trees       oaks, pines and poplars scattered off the track, thinning with distance
##   villages    houses round both towns, a church spire in each
## Everything sits under one root placed against the floating origin (like the GP); trees and
## houses are binned (view/props.gd), each bin culled on its own.
##   add_child(vw); vw.build(sim, view)      once
##   vw.sync(org_x, org_y)                   every frame
extends Node3D

const Kit := preload("res://view/mesh_kit.gd")
const Props := preload("res://view/props.gd")
const RIVER_W := 90.0
# the river, sim km, from the hills to the lake (see tools/design_eridanus.py for the track)
const RIVER := [[-16.0, 20.0], [-9.0, 9.0], [-5.0, 4.0], [-1.5, 2.6], [1.5, 1.2], [5.0, 1.15], [7.0, 1.0], [16.0, 0.9],
	[26.0, 1.3], [36.0, 1.8], [46.0, 5.5], [53.0, 12.0], [57.5, 22.0], [59.2, 27.6]]
const LAKE := [59.6, 31.6, 3.0, 4.4]   # centre x, y km; half-axes km
const CHURCHES := [[1.6, -0.3], [56.4, 37.6]]

var sim
var view
var water_mat: ShaderMaterial
var river := PackedVector2Array()   # metres, densified
var bridges := []                   # [first sample, last sample] where the track crosses the river
var trees := 0                      # tests read these
var houses := 0
var spots := PackedVector2Array()   # every tree and house, sim x, y (tests: a headless MultiMesh reads back empty)
var _near := {}                     # 50 m cells near the track (no trees there)
var _rcells := {}                   # 200 m cells near the river -> the river points close to them


func build(s, v) -> void:
	sim = s
	view = v
	water_mat = ShaderMaterial.new()
	water_mat.shader = preload("res://view/water.gdshader")
	water_mat.set_shader_parameter("flow", 1.2)
	_river()
	_lake()
	_find_bridges()
	_bridge_parapets()
	_near = _near_track(120.0)
	_poplar_lines()
	_scatter()
	_villages()


func sync(ox: float, oy: float) -> void:
	position = Vector3(-ox, 0.0, oy)
	water_mat.set_shader_parameter("org", Vector2(fposmod(ox, 4096.0), fposmod(oy, 4096.0)))


# --- water ----------------------------------------------------------------------------------------

## The river: the polyline smoothed (Catmull-Rom) and densified to ~60 m, laid as a ribbon.
func _river() -> void:
	var ctl := []
	for q in RIVER:
		ctl.append(Vector2(q[0], q[1]) * 1000.0)
	for k in ctl.size() - 1:
		var p0: Vector2 = ctl[maxi(k - 1, 0)]
		var p1: Vector2 = ctl[k]
		var p2: Vector2 = ctl[k + 1]
		var p3: Vector2 = ctl[mini(k + 2, ctl.size() - 1)]
		var n := maxi(2, int(p1.distance_to(p2) / 60.0))
		for i in n:
			var t := float(i) / n
			river.append(0.5 * (2.0 * p1 + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	river.append(ctl[ctl.size() - 1])
	for i in river.size():
		var c := Vector2i(floori(river[i].x / 200.0), floori(river[i].y / 200.0))
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var key := Vector2i(c.x + dx, c.y + dy)
				if not _rcells.has(key):
					_rcells[key] = []
				_rcells[key].append(i)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in river.size() - 1:
		var a: Vector2 = river[i]
		var b: Vector2 = river[i + 1]
		var na := _side(i)
		var nb := _side(i + 1)
		var w := RIVER_W / 2.0
		var q := [Vector3(a.x + na.x * w, 0.012, -(a.y + na.y * w)), Vector3(a.x - na.x * w, 0.012, -(a.y - na.y * w)),
			Vector3(b.x - nb.x * w, 0.012, -(b.y - nb.y * w)), Vector3(b.x + nb.x * w, 0.012, -(b.y + nb.y * w))]
		for v in [q[0], q[2], q[1], q[0], q[3], q[2]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "river"
	mi.mesh = st.commit()
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _side(i: int) -> Vector2:
	var a: Vector2 = river[maxi(i - 1, 0)]
	var b: Vector2 = river[mini(i + 1, river.size() - 1)]
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


func _lake() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(LAKE[0] * 1000.0, 0.012, -LAKE[1] * 1000.0)
	var n := 96
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var wob0 := 1.0 + 0.06 * sin(a0 * 5.0) + 0.04 * sin(a0 * 11.0)
		var wob1 := 1.0 + 0.06 * sin(a1 * 5.0) + 0.04 * sin(a1 * 11.0)
		var p0 := c + Vector3(cos(a0) * LAKE[2] * 1000.0 * wob0, 0.0, -sin(a0) * LAKE[3] * 1000.0 * wob0)
		var p1 := c + Vector3(cos(a1) * LAKE[2] * 1000.0 * wob1, 0.0, -sin(a1) * LAKE[3] * 1000.0 * wob1)
		for v in [c, p1, p0]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "lake"
	mi.mesh = st.commit()
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Distance (m) from (x, y) to the river's centreline, and whether it's in the lake.
func water_dist(x: float, y: float) -> float:
	var best := 1.0e6   # far from the river (only cells within ~400 m of it are searched)
	var p := Vector2(x, y)
	for i in _rcells.get(Vector2i(floori(x / 200.0), floori(y / 200.0)), []):
		if i >= river.size() - 1:
			continue
		var a: Vector2 = river[i]
		var b: Vector2 = river[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	var lx := (x / 1000.0 - LAKE[0]) / LAKE[2]
	var ly := (y / 1000.0 - LAKE[1]) / LAKE[3]
	if lx * lx + ly * ly < 1.15:
		best = 0.0
	return best


# --- bridges ------------------------------------------------------------------------------------

## Runs of track samples whose surface spans the river.
func _find_bridges() -> void:
	var run := -1
	for i in sim.N:
		var over: bool = water_dist(sim.tpx[i], sim.tpy[i]) < RIVER_W / 2.0 + sim.tw[i] / 2.0
		if over and run < 0:
			run = i
		elif not over and run >= 0:
			bridges.append([run, i - 1])
			run = -1


## Over the river: stone parapets outside both walls and two piers in the water.
func _bridge_parapets() -> void:
	var stone := Color(0.72, 0.68, 0.6)
	for br in bridges:
		var parts := []
		for i in range(br[0] - 4, br[1] + 5):
			var k := posmod(i, sim.N)
			var j: int = (k + 1) % sim.N
			for sgn in [-1.0, 1.0]:
				var a := _edge(k, sgn * (sim.tw[k] / 2.0 + 1.2))
				var b := _edge(j, sgn * (sim.tw[j] / 2.0 + 1.2))
				var mid := (a + b) / 2.0
				var d := b - a
				parts.append([Kit.box(Vector3(1.4, 2.2, d.length() + 0.1)), Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), mid + Vector3.UP * 1.1), stone])
		var m: int = (br[0] + br[1]) / 2
		for off in [-0.25, 0.25]:
			var p := _edge(m, off * sim.tw[m])
			parts.append([Kit.box(Vector3(6.0, 6.0, 6.0)), Kit.at(p + Vector3(0, -2.0, 0)), stone.darkened(0.15)])
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.compound(parts)
		mi.material_override = Kit.vertex_colors()
		add_child(mi)


func _edge(i: int, off: float) -> Vector3:
	return Vector3(sim.tpx[i] + sim.tnx[i] * off, sim.bank_height(sim.tw[i] / 2.0, off, sim.tb[i]), -(sim.tpy[i] + sim.tny[i] * off))


# --- trees ----------------------------------------------------------------------------------------

## The Heliades: poplars down both banks of the river and both sides of every town section.
func _poplar_lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var xs := []
	for i in range(0, river.size(), 1):
		var p: Vector2 = river[i]
		var n := _side(i)
		for sgn in [-1.0, 1.0]:
			var q: Vector2 = p + n * sgn * (RIVER_W / 2.0 + 14.0)
			# dry land only: the banks run on into the lake where the river reaches it
			if not _near.has(Vector2i(floori(q.x / 50.0), floori(q.y / 50.0))) and water_dist(q.x, q.y) > RIVER_W / 2.0 + 10.0:
				xs.append(Props.scatter_xf(rng, Vector3(q.x, 0.0, -q.y), 0.85, 1.2, 0.02))
	for i in range(0, sim.N, 3):
		if sim.tmode[i] != 0:
			continue
		for sgn in [-1.0, 1.0]:
			var q := _edge(i, sgn * (sim.tw[i] / 2.0 + 30.0))
			if water_dist(q.x, -q.z) > RIVER_W:
				xs.append(Props.scatter_xf(rng, Vector3(q.x, 0.0, q.z), 0.85, 1.15, 0.02))
	trees += xs.size()
	_note(xs)
	Props.binned(self, "poplar", xs, 2000.0, 9000.0)


## Oaks, pines and poplars off the track: thickest within a kilometre of it, thinning out to ~3 km.
func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var sets := {"oak": [], "pine": [], "poplar": []}
	for k in 26000:
		var i := rng.randi_range(0, sim.N - 1)
		var d := 140.0 + 2900.0 * pow(rng.randf(), 1.6)
		var sd := 1.0 if rng.randf() < 0.5 else -1.0
		var x: float = sim.tpx[i] + sim.tnx[i] * d * sd + rng.randf_range(-20.0, 20.0)
		var y: float = sim.tpy[i] + sim.tny[i] * d * sd + rng.randf_range(-20.0, 20.0)
		if _near.has(Vector2i(floori(x / 50.0), floori(y / 50.0))) or water_dist(x, y) < RIVER_W:
			continue
		# clumps: woods and open meadow
		if sin(x * 0.0011 + y * 0.0007) + sin(x * 0.0005 - y * 0.0013) < -0.3:
			continue
		var r := rng.randf()
		var kind := "oak" if r < 0.5 else ("pine" if r < 0.8 else "poplar")
		sets[kind].append(Props.scatter_xf(rng, Vector3(x, 0.0, -y), 0.75, 1.35, 0.04))
	for kind in sets:
		trees += sets[kind].size()
		_note(sets[kind])
		Props.binned(self, kind, sets[kind], 2000.0, 7000.0)


func _note(xs: Array) -> void:
	for t in xs:
		spots.append(Vector2((t as Transform3D).origin.x, -(t as Transform3D).origin.z))


## 50 m cells (sim x, y) within r of the track's walls (none of the scenery goes there).
func _near_track(r: float) -> Dictionary:
	var cells := {}
	for i in range(0, sim.N, 2):
		var reach: float = sim.tw[i] / 2.0 + r
		var span := int(ceil(reach / 50.0))
		var cx := floori(sim.tpx[i] / 50.0)
		var cy := floori(sim.tpy[i] / 50.0)
		for dx in range(-span, span + 1):
			for dy in range(-span, span + 1):
				cells[Vector2i(cx + dx, cy + dy)] = true
	for B in sim.branches:   # the shade line too (its canopy's pillars stand 7 m out)
		for i in range(0, B.N, 2):
			var reach: float = B.w[i] / 2.0 + r
			var span := int(ceil(reach / 50.0))
			var cx := floori(B.px[i] / 50.0)
			var cy := floori(B.py[i] / 50.0)
			for dx in range(-span, span + 1):
				for dy in range(-span, span + 1):
					cells[Vector2i(cx + dx, cy + dy)] = true
	return cells


# --- villages ---------------------------------------------------------------------------------

## Houses round both towns (out past the walls and the poplars), and a church spire in each.
func _villages() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1111
	var h0 := []
	var h1 := []
	for i in range(0, sim.N, 2):
		if sim.tmode[i] != 0:
			continue
		for k in 2:
			var d := rng.randf_range(160.0, 650.0)
			var sd := 1.0 if rng.randf() < 0.5 else -1.0
			var x: float = sim.tpx[i] + sim.tnx[i] * d * sd + rng.randf_range(-40.0, 40.0)
			var y: float = sim.tpy[i] + sim.tny[i] * d * sd + rng.randf_range(-40.0, 40.0)
			if _near.has(Vector2i(floori(x / 50.0), floori(y / 50.0))) or water_dist(x, y) < RIVER_W:
				continue
			if rng.randf() < 0.55:
				continue
			var yaw := atan2(sim.tty[i], sim.ttx[i]) + (0.0 if rng.randf() < 0.7 else PI / 2.0) + rng.randf_range(-0.15, 0.15)
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * rng.randf_range(0.85, 1.25)), Vector3(x, 0.0, -y))
			(h0 if rng.randf() < 0.6 else h1).append(xf)
	houses = h0.size() + h1.size()
	_note(h0)
	_note(h1)
	Props.binned(self, "house0", h0, 1500.0, 6000.0)
	Props.binned(self, "house1", h1, 1500.0, 6000.0)
	for c in CHURCHES:
		Props.place(self, "spire", Transform3D(Basis(Vector3.UP, 0.4), Vector3(c[0] * 1000.0, 0.0, -c[1] * 1000.0)))
