shader_type spatial;
render_mode cull_back;

uniform float heat : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = pow(COLOR.rgb, vec3(2.2));
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = 0.76;
	ROUGHNESS = mix(0.34, 0.50, UV.x);
	vec3 coil = mix(vec3(0.025, 0.007, 0.002), vec3(1.0, 0.32, 0.065), heat);
	EMISSION = UV.x * coil * (0.15 + 4.0 * heat);
}
