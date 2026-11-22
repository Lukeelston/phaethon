// The field across a pressure lock's bore (view/aurora_line.gd). At rest it is a faint ripple,
// bright only at its lip. While the lock cycles for a craft stopped on its pad
// (view/aurora_stations.gd) it lifts toward a colour (amber unequal, cyan equalised, green clear)
// and an iris of twelve blades of light closes across the bore and opens again. With all three
// inputs at 0 it is the resting field exactly.
shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never, shadows_disabled;

uniform float charge = 0.0;     // the field lifted, 0..1
uniform float iris = 0.0;       // the blades closed across the bore, 0 open .. 1 shut
uniform vec3 tint : source_color = vec3(0.57, 1.2, 1.02);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float wave = 0.5 + 0.5 * cos(r * 46.0 - TIME * 1.4 + p.x * 0.9);
	float edge = pow(r, 7.0);
	vec3 rest = mix(vec3(0.09, 0.65, 0.74), vec3(0.57, 1.2, 1.02), wave);
	float alpha = 0.015 + edge * (0.09 + 0.21 * wave);
	// the cycle: outside the aperture the blades, their seams bright; at the aperture a lip of light
	float shut = step(0.001, iris);
	float open = 1.0 - iris;
	float turn = atan(p.x, p.y) / TAU + 0.5;
	float blade = fract(turn * 12.0 + r * 0.9 - iris * 0.4);
	float seam = 1.0 - smoothstep(0.0, 0.07, blade) * smoothstep(1.0, 0.93, blade);
	float blades = smoothstep(open - 0.02, open + 0.02, r) * shut;
	float lip = exp(-abs(r - open) * 40.0) * shut;
	vec3 lifted = mix(vec3(0.05, 0.4, 0.45), tint, 0.4 + 0.6 * wave);
	ALBEDO = mix(rest, lifted, charge) + tint * (blades * seam * 0.9 + lip * 1.7) * charge;
	ALPHA = clamp(alpha + charge * (0.05 + 0.10 * wave + blades * (0.22 + 0.45 * seam) + lip * 0.8), 0.0, 0.92);
}
