## Speed context: the Mach number and how long a mile takes at this speed (a dash line), and
## a vapor cone that shrouds the craft as it punches through Mach 1 (the boom is in WindAudio).
##   add_child(cues); cues.build(view)    once
##   cues.sync(sim, delta)                every frame, after the floating origin moves
extends Node3D

const SOUND := 343.0   # m/s, sea level

const CONE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float strength = 0.0;
varying float along;
void vertex() {
	along = 0.5 - VERTEX.y;   // 0 at the apex (engine noses), 1 at the open end (behind the pod)
}
void fragment() {
	// a condensation shroud reads at glancing angles: edge-on rings, nearly clear face-on
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = smoothstep(0.0, 0.2, along) * (1.0 - smoothstep(0.55, 1.0, along));
	float ripple = 0.85 + 0.15 * sin(along * 22.0 - TIME * 30.0);
	ALBEDO = vec3(0.97, 0.98, 1.0);
	ALPHA = clamp(strength * fade * ripple * pow(edge, 1.5), 0.0, 1.0);
}
"""

var view
var mach := 0.0
var mile_s := INF      # seconds per mile at the current speed
var _prev_mach := 0.0
var _flash := 0.0
var cone: MeshInstance3D
var cone_mat: ShaderMaterial


func build(v) -> void:
	view = v
	cone = MeshInstance3D.new()
	var m := CylinderMesh.new()   # unit length along +Y; scaled to the craft each frame
	m.top_radius = 0.04
	m.bottom_radius = 0.26
	m.height = 1.0
	m.cap_top = false
	m.cap_bottom = false
	m.radial_segments = 48
	m.rings = 12
	cone.mesh = m
	var sh := Shader.new()
	sh.code = CONE_SHADER
	cone_mat = ShaderMaterial.new()
	cone_mat.shader = sh
	cone.material_override = cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.visible = false
	add_child(cone)


func sync(sim, delta: float) -> void:
	var v: float = sqrt(sim.pod.vx * sim.pod.vx + sim.pod.vy * sim.pod.vy)
	mach = v / SOUND
	mile_s = 1609.344 / v if v > 1.0 else INF

	# vapor cone: a flash on the way through Mach 1, a faint shroud while transonic
	if _prev_mach < 1.0 and mach >= 1.0:
		_flash = 1.0
	_prev_mach = mach
	_flash = maxf(0.0, _flash - delta * 1.2)
	var transonic := exp(-pow((mach - 1.0) / 0.05, 2.0))
	var a := clampf(0.9 * _flash + 0.45 * transonic, 0.0, 1.0)
	cone.visible = a > 0.01 and sim.crash_t <= 0.0
	if not cone.visible:
		return
	cone_mat.set_shader_parameter("strength", a)
	# apex at the engine noses, open end a few metres behind the pod: you ride inside it
	var c := cos(sim.pair_th)
	var s := sin(sim.pair_th)
	var nose_d: float = sim.P.engineLen / 2.0 + 1.0
	var apex: Vector3 = view.w3((sim.eL.x + sim.eR.x) / 2.0 + c * nose_d, (sim.eL.y + sim.eR.y) / 2.0 + s * nose_d,
		(sim.eL.z + sim.eR.z) / 2.0 + 0.6)
	var tail: Vector3 = view.w3(sim.pod.x - c * 5.0, sim.pod.y - s * 5.0, sim.pod.z + 0.6)
	var axis := apex - tail
	var length := axis.length()
	var yb := axis / length
	var xb := Vector3.UP.cross(yb).normalized()
	var zb := xb.cross(yb)
	var grow := 1.0 + 0.25 * (1.0 - _flash)   # billows outward as the flash fades
	cone.basis = Basis(xb * length * grow, yb * length, zb * length * grow)
	cone.position = (apex + tail) / 2.0


## Dash line: Mach number and how long a mile takes at this speed.
func readout() -> String:
	var mile := ("   MILE / %.2f s" % mile_s) if mile_s < 10.0 else ""
	return "MACH %.2f%s" % [mach, mile] if mach < 1.0 else "MACH %.1f%s" % [mach, mile]
