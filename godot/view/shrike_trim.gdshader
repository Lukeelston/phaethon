shader_type spatial;

uniform vec4 enamel : source_color = vec4(0.09,0.36,0.38,1.0);

void fragment(){
	// The shared hull batches its fin, cable eyes and thruster collars. Only
	// the original warm enamel and piping receive the Shrike livery.
	vec3 c = COLOR.rgb;
	float paint = smoothstep(0.18,0.34,c.r-c.b)*smoothstep(0.10,0.28,c.r-c.g);
	vec3 alloy = OUTPUT_IS_SRGB ? c : pow(max(c,vec3(0.0)),vec3(2.2));
	ALBEDO = mix(alloy,enamel.rgb,paint);
	METALLIC = mix(0.67,0.32,paint);
	ROUGHNESS = mix(0.29,0.36,paint);
}
