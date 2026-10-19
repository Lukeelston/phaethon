## The mountains: three ranges deep down both sides of the range, plus a ring of high peaks
## all round at 45 km, so there's something on the horizon that creeps by even at Mach 6.
##   9 km   red-sandstone mesas and buttes: terraced, flat-topped, banded in strata
##   16 km  a ridged sierra: grey-brown rock, spurs and gullies
##   26 km  the high range: 1.5-3 km peaks, snow on the summits
##   45 km  the backdrop ring (rides with the pod: at that distance it barely moves anyway),
##          so the far end of the valley has peaks too
## Each strip is a heightfield 40 km long (periodic, so it tiles without a seam: the noise is
## sampled round a cylinder), laid three times round the pod and re-tiled as the pod moves;
## only fposmod(org_x, period) reaches the vertices, so it stays precise at mile 100.
## Lighting is baked into vertex colours from the real sun direction (CraftView.SUN_ROT), one
## colour per face: sunlit slopes bright and warm, the rest in blue sky-shadow. The engine fog
## would erase anything this far out, so the mountains skip it and haze themselves: thick at
## their feet (they melt into the fogged desert in exactly the fog's colour) and thinner with
## height, as real air does, so the summits stand clear.
##   add_child(horizon); horizon.build(view, horizon_color)    once
##   horizon.sync(org_x, org_y)                                 every frame
extends Node3D

const PERIOD := 40000.0
const STEP := 160.0
const ROWS := 16
const HAZE_H := 220.0     # haze scale height (m): the dust thins by e over this much climb
const SKY_BLUE := Color(0.58, 0.68, 0.84)
# name, lateral distance m, depth m, base m, relief m, haze at the summits, seed, feature km,
# length of one period m (the noise wraps round it)
const LAYERS := [
	["mesa", 9000.0, 3500.0, 0.0, 520.0, 0.12, 11, 2.6, PERIOD],
	["sierra", 16000.0, 6000.0, 60.0, 2000.0, 0.22, 23, 3.4, PERIOD],
	["high", 26000.0, 9000.0, 200.0, 3800.0, 0.34, 37, 4.5, PERIOD],
]
const RING_R := 45000.0
const RING_DEPTH := 12000.0
const RING_COLS := 720

var tiles := []   # [node, tile index -1/0/1]
var verdant := false      # Eridanus: green hills and a lower snowline
var rings := []           # a course's world-anchored mountain rings (build_course)
var centre := Vector2.ZERO
var ring: MeshInstance3D       # the range's backdrop ring (riding with the pod); none on a course
var sun_dir := Vector3.UP   # toward the primary sun
var faces := 0              # triangles built (the test reads this)


func build(view, horizon_color: Color) -> void:
	sun_dir = -(Basis.from_euler(view.SUN_ROT * PI / 180.0) * Vector3.FORWARD).normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for layer in LAYERS:
		for side in [1.0, -1.0]:
			var mesh := _strip(layer, side, horizon_color)
			for i in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.extra_cull_margin = 16000.0
				add_child(mi)
				tiles.append([mi, i - 1])
	ring = MeshInstance3D.new()
	ring.mesh = _ring(horizon_color)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.extra_cull_margin = 60000.0
	add_child(ring)


## A course's mountains (Eridanus, 59 x 57 km: the range's strips would cross it): the three
## ranges as closed rings round the course, `pad` beyond each side of its extent, world-anchored
## (placed against the floating origin each frame), so you fly through a valley. The verdant
## palette: forested hills, a sierra greening at its foot, high grey peaks with snow from ~2,000 m.
func build_course(view, horizon_color: Color, c: Vector2, half: Vector2, is_verdant: bool) -> void:
	verdant = is_verdant
	centre = c
	sun_dir = -(Basis.from_euler(view.SUN_ROT * PI / 180.0) * Vector3.FORWARD).normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for layer in [["hills", 7000.0, 5000.0, 0.0, 950.0, 0.10, 61, 3.0], ["sierra", 15000.0, 8000.0, 80.0, 2300.0, 0.22, 73, 4.0],
			["high", 27000.0, 11000.0, 250.0, 3900.0, 0.34, 87, 5.0]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _ellipse(layer, half, horizon_color)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 60000.0
		add_child(mi)
		rings.append(mi)


## One closed ring of a layer round the course: an ellipse (half + the layer's distance) with the
## layer's depth outward, heightfield noise wrapped round it.
func _ellipse(layer: Array, half: Vector2, haze: Color) -> ArrayMesh:
	var noise := _noise(layer[6])
	var rx: float = half.x + layer[1]
	var ry: float = half.y + layer[1]
	var circ := TAU * sqrt((rx * rx + ry * ry) / 2.0)
	var spec: Array = layer.duplicate()
	spec.append(circ)
	var cols := int(circ / 250.0)
	var rows := 12
	var pts := []
	for i in cols + 1:
		var a := TAU * i / cols
		var base := Vector2(cos(a) * rx, sin(a) * ry)
		var out := Vector2(cos(a) / rx, sin(a) / ry).normalized()
		var col := []
		for r in rows + 1:
			var zf := float(r) / rows
			var h := 0.0 if r == 0 or r == rows else height(spec, noise, PERIOD * i / cols, zf)
			var q: Vector2 = base + out * zf * float(layer[2])
			col.append(Vector3(q.x, h, -q.y))
		pts.append(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in cols:
		for r in rows:
			_quad(st, spec, haze, pts[i][r], pts[i + 1][r], pts[i + 1][r + 1], pts[i][r + 1])
	return st.commit()


## Height (m) of a layer at strip x and depth fraction zf (0 front edge .. 1 back edge).
func height(layer: Array, noise: FastNoiseLite, x: float, zf: float) -> float:
	var a := TAU * x / PERIOD
	var rc: float = layer[8] / 1000.0 / layer[7] / TAU   # cylinder radius: one noise unit per feature
	var n := 0.5 + 0.5 * noise.get_noise_3d(cos(a) * rc, sin(a) * rc, zf * layer[2] / 1000.0 / layer[7])
	# rise from the desert, crest a third of the way back, fall away behind
	var env := smoothstep(0.0, 0.3, zf) * (1.0 - smoothstep(0.55, 1.0, zf))
	if layer[0] == "mesa":
		# terraces: flat tops on two levels, steep cliffs between, scree at the foot
		var t := clampf((n - 0.38) * 2.6, 0.0, 1.0)
		var lv := floorf(t * 2.0)
		var f := t * 2.0 - lv
		var tier := (lv + smoothstep(0.75, 0.95, f)) / 2.0
		return layer[3] + layer[4] * tier * env + 25.0 * n * env
	return layer[3] * env + layer[4] * pow(n, 1.3) * env


func _noise(sd: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 1.0
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.45
	return noise


## One period of a layer: a heightfield (x 0..PERIOD; z = -lateral, the render convention).
func _strip(layer: Array, side: float, haze: Color) -> ArrayMesh:
	var noise := _noise(layer[6] + (0 if side > 0.0 else 100))
	var n := int(PERIOD / STEP)
	var d: float = layer[1]
	var pts := []   # [col][row] -> Vector3
	for i in n + 1:
		var col := []
		for r in ROWS + 1:
			var zf := float(r) / ROWS
			var x := i * STEP
			var h := 0.0 if r == 0 or r == ROWS else height(layer, noise, fposmod(x, PERIOD), zf)
			col.append(Vector3(x, h, -side * (d + zf * layer[2])))
		pts.append(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		for r in ROWS:
			var p00: Vector3 = pts[i][r]
			var p10: Vector3 = pts[i + 1][r]
			var p01: Vector3 = pts[i][r + 1]
			var p11: Vector3 = pts[i + 1][r + 1]
			_quad(st, layer, haze, p00, p10, p11, p01)
	return st.commit()


## The far ring: polar heightfield round the pod, peaks to ~3.4 km with snow.
func _ring(haze: Color) -> ArrayMesh:
	var layer := ["ring", RING_R, RING_DEPTH, 300.0, 4200.0, 0.5, 51, 6.0, TAU * RING_R]
	var noise := _noise(51)
	var rows := 8
	var pts := []
	for i in RING_COLS + 1:
		var col := []
		var a := TAU * i / RING_COLS
		for r in rows + 1:
			var zf := float(r) / rows
			var h := 0.0 if r == 0 or r == rows else height(layer, noise, PERIOD * i / RING_COLS, zf)
			var rad := RING_R + zf * RING_DEPTH
			col.append(Vector3(cos(a) * rad, h, sin(a) * rad))
		pts.append(col)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RING_COLS:
		for r in rows:
			_quad(st, layer, haze, pts[i][r], pts[i + 1][r], pts[i + 1][r + 1], pts[i][r + 1])
	return st.commit()


## One flat-shaded quad (two triangles, one colour from their mean normal, so cliffs read as
## faces, not a zigzag): rock colour by layer, height and slope, lit by the sun, then hazed per
## vertex by its height.
func _quad(st: SurfaceTool, layer: Array, haze: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var nrm := ((b - a).cross(c - a) + (c - a).cross(d - a)).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var hmid := (a.y + b.y + c.y + d.y) / 4.0
	var slope := 1.0 - nrm.y   # 0 flat .. 1 vertical
	var rock := _rock(layer, hmid, slope)
	# light: warm sun on the faces turned to it, blue sky-fill everywhere, a touch of bounce
	var lam := maxf(nrm.dot(sun_dir), 0.0)
	var lit := Color(0.36, 0.41, 0.54) * (0.75 + 0.25 * nrm.y) + Color(1.0, 0.9, 0.76) * lam * 1.15
	var col := Color(rock.r * lit.r, rock.g * lit.g, rock.b * lit.b)
	faces += 2
	for p in [a, b, c, a, c, d]:
		# haze: the fog colour at the foot, thinning with height to the layer's summit haze, and
		# a little bluer up high (the warm horizon dust sits low)
		var thin := exp(-p.y / HAZE_H)
		var k: float = layer[5] + (1.0 - layer[5]) * thin
		var tint := haze.lerp(SKY_BLUE, 0.35 * (1.0 - thin))
		st.set_color(col.lerp(tint, k))
		st.add_vertex(p)


func _rock(layer: Array, h: float, slope: float) -> Color:
	if verdant:
		return _green_rock(layer, h, slope)
	match layer[0]:
		"mesa":
			# sandstone strata by height: red, cream, rust, with pale scree on the gentle slopes
			var bands := [Color(0.72, 0.34, 0.18), Color(0.84, 0.60, 0.40), Color(0.62, 0.27, 0.15), Color(0.78, 0.44, 0.26)]
			var band: Color = bands[int(h / 55.0) % bands.size()]
			return band.lerp(Color(0.80, 0.66, 0.50), clampf(1.0 - slope * 3.0, 0.0, 1.0) * 0.6)
		"sierra":
			var rk := Color(0.56, 0.40, 0.31).lerp(Color(0.36, 0.26, 0.22), clampf(slope * 1.6, 0.0, 1.0))
			return rk.lerp(Color(0.70, 0.56, 0.42), clampf(1.0 - slope * 2.5, 0.0, 1.0) * 0.5)
		_:
			var rk := Color(0.48, 0.40, 0.40).lerp(Color(0.30, 0.26, 0.28), clampf(slope * 1.6, 0.0, 1.0))
			# snow above the snowline, clinging only where it isn't too steep
			var snowline: float = 2300.0 if layer[0] == "high" else 2600.0
			var snow := smoothstep(snowline, snowline + 350.0, h) * clampf(1.4 - slope * 1.6, 0.0, 1.0)
			return rk.lerp(Color(0.95, 0.96, 1.0), snow)


## The verdant palette: forest on the hills, the sierra greening at its foot, grey high peaks with
## snow from ~2,000 m wherever it can cling.
func _green_rock(layer: Array, h: float, slope: float) -> Color:
	var flat := clampf(1.0 - slope * 2.2, 0.0, 1.0)
	var steep := clampf(slope * 1.6, 0.0, 1.0)
	match layer[0]:
		"hills":
			var forest := Color(0.17, 0.29, 0.13).lerp(Color(0.32, 0.44, 0.19), flat * 0.6)
			return forest.lerp(Color(0.40, 0.38, 0.32), steep * 0.5)
		"sierra":
			var low := Color(0.20, 0.32, 0.15).lerp(Color(0.36, 0.46, 0.22), flat * 0.5)
			var rock := Color(0.46, 0.45, 0.43).lerp(Color(0.30, 0.30, 0.31), steep)
			return low.lerp(rock, smoothstep(500.0, 1300.0, h))
		_:
			var rk := Color(0.50, 0.50, 0.52).lerp(Color(0.31, 0.31, 0.34), steep)
			rk = Color(0.22, 0.32, 0.17).lerp(rk, smoothstep(600.0, 1400.0, h))
			var snow := smoothstep(1900.0, 2300.0, h) * clampf(1.4 - slope * 1.6, 0.0, 1.0)
			return rk.lerp(Color(0.95, 0.96, 1.0), snow)


func sync(ox: float, oy: float) -> void:
	var base := floorf(ox / PERIOD) * PERIOD
	for t in tiles:
		(t[0] as Node3D).position = Vector3(base + t[1] * PERIOD - ox, 0.0, oy)
	if ring:
		ring.position = Vector3.ZERO
	for r in rings:
		(r as Node3D).position = Vector3(centre.x - ox, 0.0, -(centre.y - oy))
