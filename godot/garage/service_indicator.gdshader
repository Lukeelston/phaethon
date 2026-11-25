shader_type spatial;

varying flat float state;

void vertex() {
	state = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 tint = state > 0.75 ? vec3(0.055, 0.72, 0.18) : vec3(1.0, 0.32, 0.025);
	float on = step(0.25, state);
	float rib = 0.91 + 0.09 * cos(TAU * UV.y * 3.0);
	ALBEDO = mix(vec3(0.028, 0.044, 0.046), tint * 0.40, on);
	EMISSION = tint * (1.45 * rib * on);
	ROUGHNESS = 0.30;
	SPECULAR = 0.60;
}
