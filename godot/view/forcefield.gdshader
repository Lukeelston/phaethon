// The pod's forcefield (view/canopy.gd): an ellipsoid round the front of the pod, drawn additively.
// It stays clear where you look straight through it and glows where you see it edge-on, so from the
// cockpit it frames the view rather than fogging it. With speed (`power`) it lights up: a bow ring
// round the nose where the flow meets it (dead ahead stays clear), a faint hex lattice, and streaks
// flowing back over it. Its colour is the handling's (blue SPEEDCRAFT, magenta STARFIGHTER),
// whiter on the burner.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float power = 0.0;    // 0 still .. ~1.5 flat out on the burner
uniform vec3 tint = vec3(0.25, 0.65, 1.0);
uniform float flow = 0.0;     // streak phase, advanced with speed by the script

varying vec3 lp;

float h1(vec2 c) {
	return fract(sin(dot(c, vec2(127.1, 311.7))) * 43758.5453);
}

float n1(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h1(i), h1(i + vec2(1.0, 0.0)), u.x), mix(h1(i + vec2(0.0, 1.0)), h1(i + vec2(1.0, 1.0)), u.x), u.y);
}

// distance to the nearest edge of a hex grid (cell units)
float hexline(vec2 p) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 hr = r * 0.5;
	vec2 a = mod(p, r) - hr;
	vec2 b = mod(p - hr, r) - hr;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	vec2 q = abs(g);
	return 0.5 - max(dot(q, normalize(vec2(1.0, 1.7320508))), q.x);
}

void vertex() {
	lp = VERTEX;   // the unit sphere, before the node's scale
}

void fragment() {
	if (power <= 0.001) {
		discard;
	}
	vec3 d = normalize(lp);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 3.0);
	// the bow: a ring round the nose (local -z), brightest 15-40 deg off the axis, clear dead ahead
	float off = acos(clamp(-d.z, -1.0, 1.0));
	float bow = smoothstep(0.12, 0.3, off) * (1.0 - smoothstep(0.45, 1.0, off));
	// streaks flowing back over the field
	float ang = atan(d.x, d.y);
	float streak = n1(vec2(ang * 9.0, d.z * 4.0 + flow));
	streak = smoothstep(0.55, 0.95, streak);
	// a faint hex lattice, shown where the field is working
	float hx = 1.0 - smoothstep(0.0, 0.05, hexline(vec2(ang * 3.0, d.z * 5.5)));
	float back = 1.0 - smoothstep(-0.2, 0.6, -d.z);   // it fades out toward the back
	float a = power * (0.17 * rim + 0.28 * bow * (0.5 + 0.8 * streak) + 0.06 * hx * (0.3 + rim) + 0.08 * streak * rim) * (1.0 - 0.7 * back);
	ALBEDO = tint * clamp(a, 0.0, 1.6);
}
