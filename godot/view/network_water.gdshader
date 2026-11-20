shader_type spatial;
render_mode cull_back, fog_disabled;
varying vec2 p;
instance uniform vec2 world_offset;
instance uniform float stream_reveal = 1.0;
void vertex() { p = VERTEX.xz + world_offset; }
void fragment() {
	float reveal=stream_reveal*(1.0-smoothstep(54000.0,64000.0,length(VERTEX)));
	if(reveal<fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)))) discard;
	float ripple = sin(p.x*0.13+TIME*0.6)*cos(p.y*0.17-TIME*0.4);
	float visible = 1.0-smoothstep(1.0,8.0,length(fwidth(p)));
	float haze = 1.0-exp(-length(VERTEX)*0.00004);
	// Realism spike: still water is a mirror for the sky and the suns, broken by a light chop.
	vec2 chop = vec2(cos(p.x*0.13+TIME*0.6)*cos(p.y*0.17-TIME*0.4)*0.13, -sin(p.x*0.13+TIME*0.6)*sin(p.y*0.17-TIME*0.4)*0.17)
		+ vec2(cos(p.x*0.71-TIME*1.1), cos(p.y*0.83+TIME*0.9)) * 0.05;
	vec3 world_normal = normalize(vec3(-chop.x * 0.35 * visible, 1.0, -chop.y * 0.35 * visible));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ALBEDO = vec3(0.012,0.045,0.048)*(1.0+0.10*ripple*visible)*(1.0-haze);
	EMISSION = pow(vec3(0.58,0.68,0.80),vec3(2.2))*haze*0.85;
	ROUGHNESS = 0.07;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
