// The finish of the pilot craft's baked bodywork (Shrike RS, Orrery IX, Kiln Six, Vesper, Basilisk): the
// atlas's colour, normal and occlusion/roughness/metal maps, as their StandardMaterial3D drew them, plus:
//  - a livery (`repaint`, view/livery.gd): its mask (tools/art_livery_masks.py) gives each texel's share
//    of each of four of the craft's own colours (R its enamel, G its bands, B its trim lines, A the
//    lettering on its bands: `from_` the colour the atlas was painted in, `to_` the livery's), and just
//    that share moves, carrying the texel's own light and dark with it (its luminance against the colour
//    it was painted in): the grain, the mottling and the soft edges of the atlas stay, and what the mask leaves out
//    (metal, rubber, ceramics, printed numbers and names, panel lines, fasteners) is drawn exactly as it
//    was. One texture read more, and only on a craft in a livery. Off, the factory finish;
//  - the ambient occlusion baked into each vertex's colour alpha by tools/art_bake_ao.py (geometry
//    pass, 2026-11-23): where a hoop sits on a body or a pipe enters a saddle, the ambient light is
//    shut out, as it is on a real machine. A mesh without colours reads alpha 1 and is unchanged;
//  - specular anti-aliasing from the geometry's own curvature (Tokuyoshi and Kaplanyan's kernel):
//    a radiused edge a pixel or two wide turns its normal through a right angle within the pixel,
//    and its highlight would crawl in the headset. Roughness widens just there, to what the pixel
//    can show. A few instructions, no texture reads.
shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool repaint = false;
uniform sampler2D livery_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 from_r : source_color = vec4(0.0);
uniform vec4 from_g : source_color = vec4(0.0);
uniform vec4 from_b : source_color = vec4(0.0);
uniform vec4 from_a : source_color = vec4(0.0);
uniform vec4 to_r : source_color = vec4(0.0);
uniform vec4 to_g : source_color = vec4(0.0);
uniform vec4 to_b : source_color = vec4(0.0);
uniform vec4 to_a : source_color = vec4(0.0);
uniform float normal_depth = 0.74;
// How much of the baked occlusion also falls on direct light: a little, as a crease's own shadow.
uniform float occlusion_on_light : hint_range(0.0, 1.0) = 0.3;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec3 finish = texture(orm_map, UV).rgb;
	if (repaint) {
		vec4 share = texture(livery_mask, UV);
		vec3 made = share.r * from_r.rgb + share.g * from_g.rgb + share.b * from_b.rgb + share.a * from_a.rgb;
		float rest = max(1.0 - share.r - share.g - share.b - share.a, 0.0);
		float shade = dot(base, LUMA) / max(dot(made + rest * base, LUMA), 0.0005);
		shade = clamp(shade, 0.5, 1.6);
		vec3 turn = share.r * (to_r.rgb - from_r.rgb) + share.g * (to_g.rgb - from_g.rgb) + share.b * (to_b.rgb - from_b.rgb) + share.a * (to_a.rgb - from_a.rgb);
		// where a texel is wholly the craft's colours, it is the livery's in the texel's own light and dark
		// alone: the atlas's grain was drawn into each channel alike, and kept as a difference it is a
		// colour of its own on a paint much darker or lighter than the one it was drawn on
		vec3 pure = (share.r * to_r.rgb + share.g * to_g.rgb + share.b * to_b.rgb + share.a * to_a.rgb) * shade + rest * base;
		base = max(mix(base + turn * shade, pure, smoothstep(0.85, 1.0, 1.0 - rest)), vec3(0.0));
	}
	ALBEDO = base;
	AO = finish.r * COLOR.a;
	AO_LIGHT_AFFECT = occlusion_on_light;
	METALLIC = finish.b;
	vec3 dndx = dFdx(NORMAL);
	vec3 dndy = dFdy(NORMAL);
	float kernel = min(0.5 * (dot(dndx, dndx) + dot(dndy, dndy)), 0.18);
	float alpha2 = finish.g * finish.g * finish.g * finish.g;
	ROUGHNESS = sqrt(sqrt(clamp(alpha2 + kernel, 0.0, 1.0)));
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
