// Custom paint replaces the enamel islands of the atlas. Inscriptions, seat
// fabric, bare hardware and inset trim keep their original material response.
shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 enamel : source_color;

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec3 finish = texture(orm_map, UV).rgb;
	ivec2 tile = ivec2(floor(UV * 4.0));
	bool painted = tile == ivec2(0, 0) || tile == ivec2(2, 2);
	float grain = dot(base, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = painted ? enamel.rgb * clamp(0.65 + grain, 0.65, 1.35) : base;
	AO = finish.r;
	ROUGHNESS = finish.g;
	METALLIC = finish.b;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.74;
}
