shader_type spatial;
render_mode cull_back, fog_disabled;
varying vec2 p;
instance uniform vec2 world_offset;
void vertex() { p = VERTEX.xz + world_offset; }
void fragment() {
	float ripple = sin(p.x*0.13+TIME*0.6)*cos(p.y*0.17-TIME*0.4);
	float visible = 1.0-smoothstep(1.0,8.0,length(fwidth(p)));
	float haze = 1.0-exp(-length(VERTEX)*0.00004);
	ALBEDO = vec3(0.035,0.105,0.075)*(1.0+0.10*ripple*visible)*(1.0-haze);
	EMISSION = pow(vec3(0.58,0.68,0.80),vec3(2.2))*haze*0.85;
	ROUGHNESS = 0.26;
	SPECULAR = 0.7;
	METALLIC = 0.25;
}
