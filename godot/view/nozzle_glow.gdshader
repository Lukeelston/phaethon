// The fire up an engine's tailpipe, seen from behind: where the pilot sits, the exhaust plume
// (view/flame.gdshader) is looked at end-on, and the pipe itself is in plain view. A sheet across
// the pipe just behind the flame holder's gutters (the flame stands on their lee), drawn
// additively: on dry thrust the turbine's dull orange glow, and little of it (it was a white ball a
// metre across that hid the nozzle it sat in); on the burner a boiling flame, lit zone by zone from
// the middle out, yellow-white where it is fiercest and orange between; blue-white on the ramjet. A
// zone lighting flares yellow, and the ramjet's chemical shot green. It dies away as the pipe turns
// side-on: the fire is inside it.
// craft_model.gd feeds it the same numbers as the plume.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform float thrust = 0.0;   // 0..1+ (the engine's real thrust)
uniform float burner = 0.0;   // 0..1: the burner's zones alight
uniform float ramjet = 0.0;   // 0..1, eased
uniform float flash = 0.0;    // a zone lighting: 1 dying to 0
uniform float teb = 0.0;      // the ramjet's chemical light: 1 dying to 0
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

float noise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i.x + i.y * 57.0);
	float b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0);
	float d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p * vec2(1.0, 0.8));
	// the pipe's own section: full across its middle, falling off toward the liner
	float inside = (1.0 - smoothstep(0.72, 1.0, abs(p.x))) * (1.0 - smoothstep(0.5, 1.0, abs(p.y))) * (1.0 - 0.3 * r * r);
	// the flame itself: a boil of bright and less bright, never still
	float boil = 0.6 * noise2(p * vec2(7.0, 3.2) + vec2(seed, TIME * 9.0)) + 0.4 * noise2(p * vec2(15.0, 6.5) - vec2(TIME * 14.0, seed));
	// the flame holder's two gutters: the flame sits in them
	float gutters = exp(-pow((abs(p.y) - 0.34) / 0.17, 2.0));
	// zones light from the middle outward
	float alight = 1.0 - smoothstep(burner * 1.55 - 0.25, burner * 1.55, r);
	float t = clamp(thrust, 0.0, 1.5);
	vec3 dry = vec3(1.0, 0.36, 0.10) * (0.05 + 0.16 * min(t, 1.0)) * inside;
	vec3 lit = mix(vec3(1.0, 0.44, 0.12), vec3(1.0, 0.86, 0.62), boil) * (0.55 + 1.5 * boil + 0.6 * gutters) * alight * inside;
	vec3 ram = mix(vec3(0.55, 0.45, 1.0), vec3(0.82, 0.90, 1.0), boil) * (0.8 + 1.8 * boil + 0.6 * gutters) * inside;
	vec3 col = dry + mix(lit, ram, ramjet) * (0.6 + 0.4 * min(t, 1.0)) * smoothstep(0.0, 0.08, burner + ramjet);
	col += (vec3(1.0, 0.72, 0.30) * flash + vec3(0.20, 1.0, 0.36) * teb) * 2.2 * inside;
	float flick = 0.94 + 0.06 * noise1(TIME * 37.0 + seed * 13.0);
	float up_the_pipe = smoothstep(0.0, 0.45, dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col * flick * up_the_pipe;
}
