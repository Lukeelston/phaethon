shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// UV is turns around the bore and metres along a repeating pressure section.
instance uniform float sector = 0.0;
float line(float u, float half_width) {
	float fw = max(fwidth(u), 0.00005);
	return (1.0 - smoothstep(half_width, half_width + fw, abs(fract(u + 0.5) - 0.5)))
		* (1.0 - smoothstep(0.18, 0.50, fw));
}
void fragment() {
	float d = length(VERTEX);
	float a = UV.x;
	float s = UV.y;
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.4);
	float seam = max(line(a * 40.0, 0.004), line(s / 48.0, 0.002));
	float grid = seam * (1.0 - smoothstep(650.0, 3500.0, d));
	float doublet = max(line(a * 8.0 - 0.043, 0.006), line(a * 8.0 + 0.043, 0.003));
	float spiral = line(a * 3.0 - s / 1536.0, 0.004) * 0.54;
	float lamp = max(doublet, spiral) * (1.0 - smoothstep(1200.0, 10500.0, d));
	float crown = smoothstep(0.15, 0.9, -cos(a * TAU));
	vec3 polar = mix(vec3(0.13, 0.91, 0.78), vec3(0.49, 0.58, 1.05), smoothstep(0.08, 0.94, sector));
	vec3 guide = mix(polar, vec3(1.12, 0.43, 0.11), crown);
	float gleam = 0.5 + 0.5 * cos(a * TAU * 2.0 - 0.8);
	vec3 film = mix(vec3(0.12, 0.39, 0.49), vec3(0.51, 0.77, 0.82), gleam);
	ALBEDO = mix(mix(film, vec3(0.12, 0.18, 0.22), grid), guide, lamp);
	ALPHA = clamp(0.039 + fresnel * 0.15 + grid * 0.37 + lamp * 0.64, 0.0, 0.86);
}
