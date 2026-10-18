## Dust the craft tears up: a rooster-tail plume behind each engine, streaming back past the pod,
## and above Mach 1.1 a shock "V" lifting dust off the desert at the Mach angle, asin(1/M):
## a wide fan just past Mach 1 that folds into a narrow dart at Mach 6. Both ride on the craft
## (no world-space particles, so the floating origin can't strand them) and fade out in the air.
##   add_child(dust); dust.build(view)    once
##   dust.sync(sim, delta)                every frame, after the floating origin moves
extends Node3D

const SAND := Color(0.80, 0.66, 0.47)
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec3 color = vec3(0.8, 0.66, 0.47);
uniform float density = 0.0;
uniform float scroll = 0.0;
uniform float tiles = 3.0;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
void fragment() {
	float u = UV.x;               // 0 at the source, 1 at the tail
	float s = UV.y * 2.0 - 1.0;   // across the plume
	float n = texture(noise_tex, vec2(u * tiles - scroll, UV.y * 1.3)).r;
	float n2 = texture(noise_tex, vec2(u * tiles * 2.3 - scroll * 1.6, UV.y * 2.7 + 0.37)).r;
	float a = density * smoothstep(0.0, 0.06, u) * pow(1.0 - u, 1.4) * (1.0 - s * s) * (0.3 + 1.1 * n * n2);
	ALBEDO = color * (0.85 + 0.3 * n);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

var view
var plumes: Array[MeshInstance3D] = []
var plume_mats: Array[ShaderMaterial] = []
var arms: Array[MeshInstance3D] = []
var arm_mat: ShaderMaterial
var _scroll := 0.0
var _arm_scroll := 0.0
var density := 0.0   # latest plume density (tests and tuning read it)


func build(v) -> void:
	view = v
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 256
	tex.height = 256
	tex.generate_mipmaps = true
	var sh := Shader.new()
	sh.code = SHADER
	var trough := _trough()
	for k in 2:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("noise_tex", tex)
		m.set_shader_parameter("color", Vector3(SAND.r, SAND.g, SAND.b))
		var mi := MeshInstance3D.new()
		mi.mesh = trough
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		plumes.append(mi)
		plume_mats.append(m)
	arm_mat = ShaderMaterial.new()
	arm_mat.shader = sh
	arm_mat.set_shader_parameter("noise_tex", tex)
	arm_mat.set_shader_parameter("color", Vector3(0.9, 0.8, 0.64))
	arm_mat.set_shader_parameter("tiles", 5.0)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = trough
		mi.material_override = arm_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		arms.append(mi)


## Unit plume: runs from the origin back along -X to x = -1, an arch (half-ellipse) across Z
## that widens and rises toward the tail. UV.x along, UV.y across.
static func _trough() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 24
	var ns := 10
	var pts := []
	for i in nu + 1:
		var u := float(i) / nu
		var row := []
		for j in ns + 1:
			var s := float(j) / ns * 2.0 - 1.0
			var w := 0.12 + 0.88 * sqrt(u)
			var h := 0.2 + 0.8 * u
			row.append([Vector3(-u, h * sqrt(maxf(0.0, 1.0 - s * s)), s * w * 0.5), Vector2(u, (s + 1.0) / 2.0)])
		pts.append(row)
	for i in nu:
		for j in ns:
			for c in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var p: Array = pts[c[0]][c[1]]
				st.set_uv(p[1])
				st.set_normal(Vector3.UP)
				st.add_vertex(p[0])
	return st.commit()


## How much of the craft is near the ground: 1 skimming, 0 by ~14 m up.
static func _low(z: float) -> float:
	return 1.0 - smoothstep(3.0, 14.0, z)


func sync(sim, delta: float) -> void:
	var p = sim.pod
	var v: float = sqrt(p.vx * p.vx + p.vy * p.vy)
	var heading: float = atan2(p.vy, p.vx) if v > 1.0 else p.th
	var back := Basis(Vector3.UP, heading)   # local -X trails behind the motion
	var crashed: bool = sim.crash_t > 0.0
	var length := 14.0 + 0.06 * v
	var width := 3.0 + 0.004 * v
	var height := 1.6 + 0.0035 * v
	# dust streams back at a good part of ground speed; cap the visible scroll so it never strobes
	_scroll += minf(3.0 * 0.6 * v / length, 5.0) * delta
	var bodies := [sim.eL, sim.eR]
	density = 0.0
	for k in 2:
		var e = bodies[k]
		var d: float = smoothstep(4.0, 60.0, v) * _low(e.z) * (0.35 + 0.65 * minf(e.thrust, 1.0)) * 0.55
		d *= 0.0 if (e.flameout or crashed) else 1.0
		density = maxf(density, d)
		plumes[k].visible = d > 0.005
		if not plumes[k].visible:
			continue
		var nx: float = e.x - cos(e.th) * sim.P.engineLen / 2.0
		var ny: float = e.y - sin(e.th) * sim.P.engineLen / 2.0
		plumes[k].position = view.w3(nx, ny, 0.05)
		plumes[k].basis = back * Basis.from_scale(Vector3(length, height, width))
		plume_mats[k].set_shader_parameter("density", d)
		plume_mats[k].set_shader_parameter("scroll", _scroll)

	# the shock V: Mach angle half-width, from the engine noses back along the ground
	var mach := v / 343.0
	var shock: float = smoothstep(1.05, 1.4, mach) * _low((sim.eL.z + sim.eR.z) / 2.0) * (0.0 if crashed else 1.0)
	var on := shock > 0.01
	arms[0].visible = on
	arms[1].visible = on
	if not on:
		return
	var mu := asin(1.0 / maxf(mach, 1.0001))
	var c := cos(sim.pair_th)
	var s := sin(sim.pair_th)
	var nose: Vector3 = view.w3((sim.eL.x + sim.eR.x) / 2.0 + c * (sim.P.engineLen / 2.0 + 1.0),
		(sim.eL.y + sim.eR.y) / 2.0 + s * (sim.P.engineLen / 2.0 + 1.0), 0.05)
	var arm_len := 320.0
	_arm_scroll += minf(5.0 * 0.4 * v / arm_len, 4.0) * delta
	arm_mat.set_shader_parameter("density", 0.4 * shock)
	arm_mat.set_shader_parameter("scroll", _arm_scroll)
	for k in 2:
		var side := 1.0 if k == 0 else -1.0
		arms[k].position = nose
		arms[k].basis = Basis(Vector3.UP, heading + side * mu) * Basis.from_scale(Vector3(arm_len, 4.0, 18.0))
