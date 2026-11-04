shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
void fragment() {
	float d = length(VERTEX);
	float reveal = smoothstep(16000.0,20000.0,d)*(1.0-smoothstep(80000.0,100000.0,d));
	// Opaque screen-door transition: no transparent road sorting or depth holes.
	float threshold = fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)));
	if (reveal < threshold) discard;
	float haze=1.0-exp(-d*0.000045);
	ALBEDO=mix(vec3(0.035),pow(vec3(0.58,0.68,0.80),vec3(2.2))*0.85,haze);
}
