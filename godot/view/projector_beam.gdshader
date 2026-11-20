// The approach projector's beam (Luke: "add a light projector beam from the roof mounted hud
// projector to the actual hud"): a thin fan of light from the lens under the header rail, out
// through the screen, to the top edge of the image it throws. Seen from the seat it lies in the
// shade band between the housing and the readout, never over the words.
//   UV    u across the fan, v from the lens (0) to the image (1)
//   lit   how far the image is thrown (the readout's own sweep): the beam comes up and dies with it
// A few slow rays in a faint body, a glow at the lens, thinning as it spreads. Added to the view,
// and drawn nowhere it is too faint to see.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float lit : hint_range(0.0, 1.0) = 0.0;
uniform vec4 signal : source_color = vec4(0.45, 0.92, 1.0, 1.0);
uniform float strength = 0.2;

void fragment() {
	float across = UV.x * 2.0 - 1.0;
	float v = UV.y;
	float rays = 0.6 * pow(0.5 + 0.5 * sin(UV.x * 61.0 + 1.3 * sin(TIME * 0.43)), 8.0)
		+ 0.4 * pow(0.5 + 0.5 * sin(UV.x * 23.0 - 0.9 * sin(TIME * 0.31) + 2.0), 6.0);
	float sides = 1.0 - smoothstep(0.93, 1.0, abs(across));
	// thinner as it spreads, and gone before the image: the readout stays its own
	float along = smoothstep(0.0, 0.03, v) * mix(1.0, 0.5, v) * (1.0 - smoothstep(0.9, 1.0, v));
	float lens = 0.6 * exp(-v * 30.0);
	// the fan's two edges, from the ends of the lens to the image's corners: they give it its shape
	float edges = 0.55 * smoothstep(0.78, 0.9, abs(across));
	float light = ((0.26 + rays + edges) * along + lens) * sides * lit * strength;
	if (light < 0.004) {
		discard;
	}
	ALBEDO = mix(signal.rgb, vec3(0.75, 0.95, 1.0), 0.5);
	ALPHA = light;
}
