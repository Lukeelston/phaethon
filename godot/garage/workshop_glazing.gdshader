shader_type spatial;

// Ribbed, obscured glass. Keep it opaque so the clerestory has no transparent
// overdraw or eye-order sorting. The shadow opening is cut into the actual wall.
varying vec3 hall_position;
varying float pane_height;

void vertex() {
	hall_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	pane_height = VERTEX.y + 0.5;
}

void fragment() {
	float height = clamp(pane_height, 0.0, 1.0);
	float entrance_side = smoothstep(19.0, 21.0, hall_position.z);
	float high_window = smoothstep(4.0, 4.6, hall_position.y);
	float rib = hall_position.x / 0.026;
	float resolved = 1.0 - smoothstep(0.12, 0.52, fwidth(rib));
	float flute = cos(TAU * rib) * resolved;
	// Daylight grades from the shaded sill up to the open sky. The smaller
	// vision panes in the service doors borrow their glow from the room beyond.
	float horizon = smoothstep(0.04, 0.83, height + 0.045 * sin(hall_position.x * 0.68));
	vec3 sky = mix(vec3(0.22, 0.33, 0.37), vec3(0.81, 0.96, 1.05), horizon);
	sky = mix(sky, sky * vec3(1.19, 1.09, 0.99), entrance_side);
	float lower_seal = smoothstep(0.01, 0.17, height);
	ALBEDO = vec3(0.22, 0.34, 0.36);
	EMISSION = sky * mix(0.23, 1.10, high_window) * mix(0.81, 1.0, lower_seal) * (1.0 + flute * 0.045);
	ROUGHNESS = 0.34 + 0.06 * flute;
	SPECULAR = 0.52;
}
