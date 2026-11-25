shader_type spatial;

// The lamp on the end of each roller hood (garage/garage_environment.gd _shutter): green while the door is shut, amber
// flashing while it runs, amber steady while it stands open. INSTANCE_CUSTOM.r: 0 shut, 1 not; .g: 1 while it runs
// (garage/bay_doors.gd).
varying flat vec2 state;

void vertex() {
	state = INSTANCE_CUSTOM.rg;
}

void fragment() {
	vec3 shut = vec3(0.246, 0.752, 0.565);      // the hall's "Green", #88e1c6, in linear light
	vec3 warning = vec3(1.0, 0.36, 0.035);      // #ffa030
	vec3 lamp = mix(shut, warning, state.x);
	float flash = state.y > 0.5 ? mix(0.18, 1.0, step(0.5, fract(TIME * 1.6))) : 1.0;
	ALBEDO = lamp * mix(0.35, 1.0, flash);
	METALLIC = 0.12;
	ROUGHNESS = 0.45;
	EMISSION = lamp * mix(0.85, 2.2, state.x) * flash;
}
