// A scenic road's open edge (view/network_world.gd): where the land falls away beside the road,
// that side's ramp is a forcefield you can see the sea or the valley through. The sims still ride
// it and its wall still turns you back; only its look changes. Nearly clear looking down through
// it, a little sky off it at a glance, and a faint lattice so the eye can still tell where it is:
// a line across every 24 m of road, a line along it every 10 m up the ramp, both gone with distance
// (a wireframe to the horizon hid the sea it was there to show).
// UV: metres along the road, metres left of the centreline. UV2.x: metres in from the edge.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec3 tint : source_color = vec3(0.42, 0.78, 1.0);
uniform float clear_alpha = 0.035;
uniform float glance_alpha = 0.16;
uniform float line_alpha = 0.3;

void fragment() {
	vec2 g = vec2(UV.x / 24.0, UV2.x / 10.0);
	vec2 w = fwidth(g);
	vec2 d = abs(fract(g + 0.5) - 0.5);                       // 0 on a line
	vec2 on = (1.0 - smoothstep(vec2(0.0), vec2(0.008, 0.02) + w, d)) * (1.0 - smoothstep(vec2(0.04), vec2(0.22), w));
	float lattice = max(on.x * 0.5, on.y);
	float glance = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = tint * (0.55 + 1.3 * lattice);
	ALPHA = clamp(clear_alpha + glance_alpha * glance + line_alpha * lattice, 0.0, 0.85);
}
