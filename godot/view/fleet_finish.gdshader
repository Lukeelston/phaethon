// The finish of the pilot craft's baked bodywork (Shrike RS, Orrery IX, Kiln Six, Vesper): the atlas's
// colour, normal and occlusion/roughness/metal maps, as their StandardMaterial3D drew them, plus:
//  - custom paint replaces the enamel islands of the fleet atlas (`repaint`). Inscriptions, seat
//    fabric, bare hardware and inset trim keep their original material response;
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
uniform vec4 enamel : source_color = vec4(1.0);
uniform bool repaint = false;
uniform float normal_depth = 0.74;
// How much of the baked occlusion also falls on direct light: a little, as a crease's own shadow.
uniform float occlusion_on_light : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec3 finish = texture(orm_map, UV).rgb;
	if (repaint) {
		ivec2 tile = ivec2(floor(UV * 4.0));
		bool painted = tile == ivec2(0, 0) || tile == ivec2(2, 2);
		float grain = dot(base, vec3(0.2126, 0.7152, 0.0722));
		base = painted ? enamel.rgb * clamp(0.65 + grain, 0.65, 1.35) : base;
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
