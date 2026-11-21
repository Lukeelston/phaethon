shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never, shadows_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float wave = 0.5 + 0.5 * cos(r * 46.0 - TIME * 1.4 + p.x * 0.9);
	float edge = pow(r, 7.0);
	ALBEDO = mix(vec3(0.09, 0.65, 0.74), vec3(0.57, 1.2, 1.02), wave);
	ALPHA = 0.015 + edge * (0.09 + 0.21 * wave);
}
