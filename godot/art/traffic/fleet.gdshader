shader_type spatial;
render_mode cull_back;
uniform sampler2D fleet_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D fleet_finish : filter_linear_mipmap, repeat_disable;
varying vec3 paint;
varying vec2 atlas_uv;

void vertex() {
	paint = COLOR.rgb;
	atlas_uv = UV;
	// The four racing number boards occupy adjacent tiles on the last atlas row.
	if (UV.y > 0.75 && UV.x > 0.5 && UV.x < 0.625) {
		atlas_uv.x += 0.125 * round(INSTANCE_CUSTOM.r * 3.0);
	}
}

void fragment() {
	vec3 base = texture(fleet_color, atlas_uv).rgb;
	vec4 finish = texture(fleet_finish, atlas_uv);
	ALBEDO = base * mix(vec3(1.0), paint, finish.r);
	ROUGHNESS = finish.g;
	METALLIC = finish.b;
	EMISSION = base * finish.a * 2.6;
}
