## Distant ridgelines both sides of the range, two layers deep: something on the horizon that
## creeps by even at Mach 6, where everything near is a smear. Each layer is a 40 km strip of
## noisy skyline (periodic, so it tiles without a seam), laid three times around the pod and
## re-tiled as the pod moves: only fposmod(org_x, period) reaches the vertices, so it stays
## precise at mile 100. The engine fog would erase anything this far out (12-22 km), so the
## ridges skip it and are hazed toward the horizon colour by their own distance instead.
##   add_child(horizon); horizon.build(view, horizon_color)    once
##   horizon.sync(org_x, org_y)                                 every frame
extends Node3D

const PERIOD := 40000.0
const STEP := 250.0
# [lateral distance m, base height m, relief m, haze 0..1, noise seed, depth m]
const LAYERS := [
	[11000.0, 120.0, 520.0, 0.38, 11, 2500.0],
	[20000.0, 380.0, 1500.0, 0.58, 23, 5000.0],
]

var tiles := []   # [node, layer side y]


func build(_view, horizon_color: Color) -> void:
	for layer in LAYERS:
		var rock := Color(0.48, 0.31, 0.21).lerp(horizon_color, layer[3])
		var lit := Color(0.70, 0.46, 0.31).lerp(horizon_color, layer[3])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.disable_fog = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for side in [1.0, -1.0]:
			var mesh := _strip(layer, side, rock, lit, horizon_color)
			for i in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = mat
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.extra_cull_margin = 4000.0
				add_child(mi)
				tiles.append([mi, i - 1])


## One period of skyline: a front face rising from the desert to the crest, then a back slope
## falling away, in strip-local metres (x 0..PERIOD; z = -lateral, the render convention).
static func _strip(layer: Array, side: float, rock: Color, lit: Color, haze: Color) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = layer[4] + (0 if side > 0.0 else 100)
	noise.frequency = 1.0
	noise.fractal_octaves = 4
	var n := int(PERIOD / STEP)
	var r := 6.0   # sample the noise round a circle: the skyline wraps seamlessly at PERIOD
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var d: float = layer[0] * side
	var back: float = (layer[0] + layer[5]) * side
	var crest := []
	for i in n + 1:
		var a := TAU * i / n
		var hn := 0.5 + 0.5 * noise.get_noise_2d(cos(a) * r, sin(a) * r)
		var peaks := pow(hn, 1.8)
		crest.append(layer[1] + layer[2] * peaks * 1.6)
	for i in n:
		var x0 := i * STEP
		var x1 := x0 + STEP
		var h0: float = crest[i]
		var h1: float = crest[i + 1]
		var cz0 := -(d + (back - d) * 0.35)   # crest sits a third of the way back
		# front face: base colour at the foot, lit near the crest
		for v in [[x0, 0.0, -d, rock], [x1, 0.0, -d, rock], [x1, h1, cz0, lit],
				[x0, 0.0, -d, rock], [x1, h1, cz0, lit], [x0, h0, cz0, lit]]:
			st.set_color(v[3])
			st.add_vertex(Vector3(v[0], v[1], v[2]))
		# back slope, dimming into the haze
		for v in [[x0, h0, cz0, lit], [x1, h1, cz0, lit], [x1, 0.0, -back, haze],
				[x0, h0, cz0, lit], [x1, 0.0, -back, haze], [x0, 0.0, -back, haze]]:
			st.set_color(v[3])
			st.add_vertex(Vector3(v[0], v[1], v[2]))
	return st.commit()


func sync(ox: float, oy: float) -> void:
	var base := floorf(ox / PERIOD) * PERIOD
	for t in tiles:
		(t[0] as Node3D).position = Vector3(base + t[1] * PERIOD - ox, 0.0, oy)
