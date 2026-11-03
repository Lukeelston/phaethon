shader_type spatial;
render_mode fog_disabled, cull_back;

uniform float glow = 0.0;
uniform vec3 haze_color = vec3(0.58, 0.68, 0.80);
varying vec3 tint;

void vertex() {
	tint = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
}

void fragment() {
	float haze = clamp(1.0 - exp(-length(VERTEX) * 0.000025), 0.0, 1.0);
	vec3 sky = pow(haze_color, vec3(2.2));
	ALBEDO = tint * (1.0 - haze) * (1.0 - min(glow, 1.0));
	EMISSION = sky * haze * 0.85 + tint * glow * (1.0 - haze);
	ROUGHNESS = 0.72;
	SPECULAR = 0.22;
}
