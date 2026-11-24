shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 hot : source_color;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float lens = 1.0 - COLOR.a;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	METALLIC = mix(0.48, 0.16, lens);
	ROUGHNESS = mix(0.37, 0.19, lens);
	EMISSION = lens * (0.23 * ALBEDO + (heat * 1.9) * hot.rgb);
}
