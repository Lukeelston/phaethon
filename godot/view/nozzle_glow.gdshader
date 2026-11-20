// The fire inside an engine's nozzle, seen from behind: where the pilot sits, the exhaust plume
// (view/flame.gdshader) is looked at end-on and all but vanishes, but the nozzle itself is in
// plain view. A quad across the slot, drawn additively and bright enough for the bloom to
// spread: a dull orange turbine glow on dry thrust; on the burner a blue-white core in an orange
// halo; hotter and violet on the ramjet. It fades out as the nozzle turns side-on. craft_model.gd
// feeds it the same numbers as the plume.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform float thrust = 0.0;   // 0..1+ (the engine's real thrust)
uniform float burner = 0.0;   // 0..1, eased: the afterburner's share
uniform float ramjet = 0.0;   // 0..1, eased
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float core = exp(-r2 * 4.5);
	float halo = exp(-r2 * 1.5) * (1.0 - smoothstep(0.7, 1.0, sqrt(r2)));
	float t = clamp(thrust, 0.0, 1.6);
	vec3 dry = vec3(1.0, 0.42, 0.14) * (0.18 + 0.45 * t) * halo;
	vec3 lit = vec3(0.72, 0.84, 1.0) * core * 3.4 + vec3(1.0, 0.52, 0.16) * halo * 1.5;
	vec3 ram = vec3(0.86, 0.82, 1.0) * core * 4.4 + vec3(0.68, 0.42, 1.0) * halo * 1.6;
	vec3 col = mix(dry, mix(lit, ram, ramjet) * (0.6 + 0.4 * min(t, 1.0)), burner);
	float flick = 0.88 + 0.12 * noise1(TIME * 11.0 + seed * 13.0);
	float from_behind = smoothstep(0.05, 0.4, dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = col * flick * from_behind;
}
