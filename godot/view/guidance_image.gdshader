// The approach guidance where the projector throws it: on the windscreen (Luke: "it should project
// onto the windscreen and bend with its curve"). view/approach_projector.gd draws the readout (its
// combiner glass and its five lines of type) into a small picture of its own, and this lays that
// picture in the swept screen's inner face, on a patch of the screen's own surface: it bows across
// with the glass and lies back with it, and both eyes find it at the glass, not out over the nose.
//   picture   the readout, already multiplied by its own coverage (a clear picture's colour is)
//   UV        across the image, and from its top edge (nearest the header) down
// Seen only from inside. Nothing is drawn where the picture is empty.
// The picture is finer than a headset shows it and a view's picture has no smaller copies of itself
// to fall back on, so each pixel takes four readings across its own footprint: one reading left
// the smallest type ragged and crawling.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D picture : source_color, filter_linear, repeat_disable;
uniform float gain = 1.0;

void fragment() {
	vec2 across = dFdx(UV) * 0.25;
	vec2 down = dFdy(UV) * 0.25;
	vec4 seen = 0.25 * (texture(picture, UV + across + down) + texture(picture, UV - across - down)
		+ texture(picture, UV + across - down) + texture(picture, UV - across + down));
	if (seen.a < 0.004) {
		discard;
	}
	ALBEDO = seen.rgb * gain;
	ALPHA = seen.a;
}
