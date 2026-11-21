// The ring of light round the start button (vr/overhead_panel.gd): two dozen segments. All of them
// breathe when a start is on offer; while the engines turn over they fill clockwise from the top,
// one for each step of the way to both running; then they stand green.
// UV.x runs once round the ring, clockwise from the top as the pilot sees it; UV.y from its inner
// edge to its outer.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 lit : source_color = vec3(1.0, 0.62, 0.12);
uniform float level = 0.0;          // how bright a lit segment is (over 1: it glows)
uniform float progress = 1.0;       // segments up to here are lit, 0..1 round the ring
uniform float rest = 0.07;          // what an unlit segment still shows of it
uniform float segments = 24.0;

void fragment() {
	float along = fract(UV.x * segments);
	float gap = smoothstep(0.0, 0.14, along) * smoothstep(1.0, 0.86, along);
	float lip = smoothstep(0.0, 0.16, UV.y) * smoothstep(1.0, 0.84, UV.y);
	float index = (floor(UV.x * segments) + 0.5) / segments;
	float on = step(index, progress);
	ALBEDO = lit * level * mix(rest, 1.0, on) * gap * lip;
}
