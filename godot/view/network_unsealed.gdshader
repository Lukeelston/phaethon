// UV is in metres along and across the road. Texture scales divide the
// 64 km UV wrap so the graded bed continues across floating-origin chunks.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D aggregate : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 earth : source_color;
uniform float gravel = 0.0;

void fragment() {
	vec2 p = UV;
	vec4 grain = texture(aggregate, p * 0.5);
	float silt = texture(aggregate, p / vec2(128.0, 32.0)).a;
	float drift = texture(aggregate, p / vec2(500.0, 125.0)).r - 0.5;
	// Parallel swept lanes expose darker, firmer ground. Loose wind-blown
	// material accumulates at their edges and against the raised shoulders.
	float offset = p.y + drift * 3.8 + 0.6 * sin(p.x * (6.2831853 / 400.0));
	float crown = smoothstep(0.1, 0.85, cos(offset * 6.2831853 / 23.0));
	float shoulder = smoothstep(49.0, 87.0, abs(p.y) + drift * 24.0 + silt * 6.0);
	float packed = crown * (1.0 - shoulder);
	float phase = p.x * (6.2831853 / 3.2) + p.y * 0.63 + silt * 9.0;
	float ripple = sin(phase) * (1.0 - smoothstep(0.45, 2.7, fwidth(phase)));
	float texture_gain = mix(0.52, 0.86, gravel);
	float value = 0.93 + (grain.r - 0.5) * texture_gain + (silt - 0.5) * 0.30 + drift * 0.44;
	value += ripple * (1.0 - packed) * mix(0.053, 0.018, gravel) - packed * 0.12;
	// Windrows and exposed soil break up the edge of the graded bed.
	vec3 verge = mix(vec3(0.81, 0.68, 0.48), vec3(0.82, 0.52, 0.33), gravel);
	ALBEDO = earth.rgb * mix(vec3(1.0), verge, shoulder) * value;
	ROUGHNESS = 0.98 - packed * 0.09;
	SPECULAR = 0.14;
}
