// Trackside beacons (view/course_world.gd): a glow that never shrinks below a few pixels, so the
// lines of lights along the walls trace the course kilometres ahead (a 1 m lamp is a fraction of
// a pixel past ~1 km; this one stays `min_ang` across at any distance, like approach lights).
// Each beacon is a quad whose four vertices all sit at its centre; UV holds the corner (-1..1)
// and the vertex shader spreads it in view space (a billboard): `size` metres across, or
// `min_ang` radians, whichever is larger. Unfogged; the far ones a little dimmer, for depth.
// With the speed guide on (view/guide.gdshaderinc), each lights in its point's guide colour: green
// where your speed is safe, amber where it's time to brake, red where you'd blow past. UV2 holds
// the beacon's distance along the lap and its safe speed.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

#include "res://view/guide.gdshaderinc"

uniform float size = 1.6;
uniform float min_ang = 0.0065;
uniform float energy = 2.6;
uniform float far_dim = 0.6;

varying float dist;
varying vec3 tint;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	dist = -c.z;
	c.xy += UV * max(size, dist * min_ang);
	POSITION = PROJECTION_MATRIX * c;
	tint = pow(guide_on > 0.5 ? guide_color(guide_cut(UV2.x, UV2.y)) : COLOR.rgb, vec3(2.2));   // authored sRGB
}

void fragment() {
	float r = length(UV);
	float a = clamp(1.0 - r, 0.0, 1.0);
	a = a * a * (0.5 + 0.5 * a);
	float k = mix(1.0, far_dim, smoothstep(2000.0, 30000.0, dist));
	ALBEDO = tint * energy * a * k;
}
