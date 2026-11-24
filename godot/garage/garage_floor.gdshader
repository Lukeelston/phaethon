shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D aggregate : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 floor_m;

void vertex() {
	floor_m = VERTEX.xz;
}

void fragment() {
	float grain = texture(aggregate, floor_m * 0.49).r;
	float wear = texture(aggregate, floor_m * 0.043 + vec2(0.26,0.14)).r;
	vec2 cell = abs(fract((floor_m + 3.0) / 6.0) - 0.5) * 6.0;
	float joint = min(cell.x, cell.y);
	float edge = max(0.002, min(0.12, max(fwidth(floor_m.x), fwidth(floor_m.y))));
	float cut = 1.0 - smoothstep(0.007, 0.007 + edge, joint);
	float aisle = 1.0 - smoothstep(2.22, 2.26, abs(floor_m.x));
	vec3 floor_color = mix(vec3(0.170,0.184,0.173), vec3(0.115,0.139,0.140), aisle);
	ALBEDO = floor_color * (0.53 + grain * 0.43 + wear * 0.43) * (1.0 - cut * 0.41);
	ROUGHNESS = mix(0.43, 0.82, grain*.40+wear*.60);
	METALLIC = 0.10;
}
