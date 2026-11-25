shader_type spatial;

uniform sampler2D aggregate : repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 wall_m;

void vertex() {
	vec3 pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = MODEL_NORMAL_MATRIX * NORMAL;
	wall_m = vec2(abs(axis.x) > abs(axis.z) ? pos.z : pos.x, pos.y);
}

void fragment() {
	// 400 by 200 mm nominal masonry with alternating vertical joints. The
	// mortar fades under minification to keep the far end steady in stereo.
	float row = floor(wall_m.y / 0.20);
	vec2 uv = wall_m / vec2(0.40, 0.20);
	uv.x += 0.5 * mod(row, 2.0);
	vec2 proximity = (0.5 - abs(fract(uv) - 0.5)) * vec2(0.40, 0.20);
	vec2 aa = max(fwidth(wall_m), vec2(0.0005));
	vec2 joint = (1.0 - smoothstep(vec2(0.002), vec2(0.004) + aa, proximity))
			* (1.0 - smoothstep(vec2(0.01), vec2(0.07), aa));
	float grout = max(joint.x, joint.y);
	float pores = texture(aggregate, wall_m * 1.6).r;
	ALBEDO = vec3(0.057, 0.086, 0.093) * (0.89 + 0.23 * pores) * (1.0 - 0.24 * grout);
	ROUGHNESS = 0.68 + 0.15 * pores + 0.10 * grout;
	SPECULAR = 0.35;
}
