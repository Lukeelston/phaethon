shader_type spatial;
render_mode fog_disabled;
#include "res://view/noise.gdshaderinc"
varying vec3 tint;
varying vec2 local;
varying float grass;
instance uniform float stream_reveal = 1.0;
void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));
	local = UV*256.0;
	grass = COLOR.a;
}
void fragment() {
	float reveal=stream_reveal*(1.0-smoothstep(54000.0,64000.0,length(VERTEX)));
	if(reveal<fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)))) discard;
	float fw = length(fwidth(local));
	float mottling = pfbm(local/128.0,8192.0);
	float fine = pnoise(local/3.0,1048576.0);
	float fade = 1.0-smoothstep(1.0,12.0,fw);
	vec2 field_p = local/1100.0;
	float field = hash21(floor(field_p));
	vec2 edge = min(fract(field_p),1.0-fract(field_p));
	float hedge = 1.0-smoothstep(0.003,0.012,min(edge.x,edge.y));
	float farmland = grass*smoothstep(0.35,0.8,field);
	vec3 base = tint*(0.83+0.32*mottling)*(0.94+0.12*fine*fade);
	base = mix(base,base*mix(vec3(0.74,0.87,0.63),vec3(1.17,1.03,0.72),field),farmland*0.48);
	base *= 1.0-hedge*farmland*0.20;
	float haze = 1.0-exp(-length(VERTEX)*0.000045);
	ALBEDO = base*(1.0-haze);
	EMISSION = pow(vec3(0.58,0.68,0.80),vec3(2.2))*haze*0.85;
	ROUGHNESS = 0.96;
	SPECULAR = 0.18;
}
