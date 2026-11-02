// The shade line's gate face, shut (view/shade_line.gd): a red field pulsing slowly, hazard
// stripes along its top and bottom; PRIVATE LINE in black letters stands in front. Unlit and
// unfogged, like the boards. UVs are clamped first: MSAA extrapolates them past the quad's edge.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 col = vec3(0.95, 0.12, 0.08);
uniform float pulse_hz = 0.8;
uniform float stripes = 30.0;   // along the face

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec3 face = col * (0.75 + 0.25 * sin(TIME * 6.2831853 * pulse_hz));
	if (uv.y < 0.12 || uv.y > 0.88) {
		float stripe = step(0.5, fract(uv.x * stripes + uv.y * 4.0));
		face = mix(vec3(0.05), vec3(1.0, 0.82, 0.08), stripe);
	}
	ALBEDO = pow(clamp(face, vec3(0.0), vec3(1.0)), vec3(2.2));
}
