shader_type spatial;
render_mode fog_disabled, cull_back;
instance uniform float stream_reveal = 1.0;
varying vec3 tint;
void vertex() { tint=pow(clamp(COLOR.rgb,vec3(0.0),vec3(1.0)),vec3(2.2)); }
void fragment() {
	float d=length(VERTEX);
	float reveal=stream_reveal*(1.0-smoothstep(22000.0,30000.0,d));
	if(reveal<fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)))) discard;
	float haze=1.0-exp(-d*0.000025);
	ALBEDO=tint*(1.0-haze);
	EMISSION=pow(vec3(0.58,0.68,0.80),vec3(2.2))*haze*0.85;
	ROUGHNESS=0.78;
	SPECULAR=0.2;
}
