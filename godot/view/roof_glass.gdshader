// The closed canopy's glass (tools/art_roof_hd.py's RoofGlass): the shade band along the top of the
// windscreen and of each side window, darkest at the frame, fading to nothing below it. The rest of
// each pane is not drawn at all: clear glass over the whole view cost a headset's frame 0.7 ms.
// UV: u across the pane, 1 - v down it (v 0 on the cockpit's rim, 1 at the header or the rail).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.62, 0.78, 0.92);
uniform vec3 band_tint : source_color = vec3(0.07, 0.11, 0.15);
uniform float clear_alpha = 0.04;
uniform float glance_alpha = 0.14;
uniform float band_alpha = 0.5;

void fragment() {
	float v = 1.0 - UV.y;
	float band = smoothstep(0.78, 0.99, v);
	float glance = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 4.0);
	ALBEDO = mix(tint, band_tint, band);
	ALPHA = clamp((clear_alpha + glance_alpha * glance) * smoothstep(0.745, 0.83, v) + band_alpha * band, 0.0, 1.0);
	ROUGHNESS = 0.04;
	SPECULAR = 0.6;
}
