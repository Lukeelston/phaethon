shader_type spatial;

varying vec2 panel_m;

void vertex() {
	vec3 pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 axis = MODEL_NORMAL_MATRIX * NORMAL;
	panel_m = vec2(abs(axis.x) > abs(axis.z) ? pos.z : pos.x, pos.y);
}

void fragment() {
	// Tongue-and-groove folded steel sheets, 1.25 m cover, with a shallow
	// embossed flute down each edge. Filter the folds at long sight distances.
	float width = 1.25;
	float slot = (fract((panel_m.x + 0.625) / width) - 0.5) * width;
	float aa = max(fwidth(panel_m.x), 0.0005);
	float resolved = 1.0 - smoothstep(0.025, 0.10, aa);
	float seam = (1.0 - smoothstep(0.002, 0.006 + aa, abs(slot))) * resolved;
	float bevel = (1.0 - smoothstep(0.0, 0.010 + aa, abs(slot - 0.010))) * resolved;
	float crown = cos(TAU * slot / width);
	float panel = floor((panel_m.x + 0.625) / width);
	float batch = fract(sin(mod(panel, 17.0) * 8.72) * 19.36);
	float enamel = 0.97 + 0.045 * batch + 0.014 * crown;
	ALBEDO = vec3(0.266, 0.320, 0.324) * enamel * (1.0 - 0.27 * seam + 0.12 * bevel);
	METALLIC = 0.24;
	ROUGHNESS = 0.56 + 0.07 * batch + 0.13 * seam;
}
