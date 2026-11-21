shader_type spatial;
render_mode fog_disabled, cull_back;
instance uniform float stream_reveal = 1.0;
global uniform vec3 sky_haze;          // the haze's colour (display values): the afternoon's (0.58, 0.68, 0.80) unless view/outlook.gd says otherwise
global uniform float sky_haze_scale;   // ... and how thick it is: 1 as it was; fog and rain thicken it
global uniform float sky_snow;         // snow lying (view/outlook.gd)
varying vec3 tint;
void vertex() { tint=pow(clamp(COLOR.rgb,vec3(0.0),vec3(1.0)),vec3(2.2)); }
void fragment() {
	float d=length(VERTEX);
	float reveal=stream_reveal*(1.0-smoothstep(22000.0,30000.0,d));
	if(reveal<=fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)))) discard;   // (<=: nothing of a prop faded right out)
	float haze=1.0-exp(-d*0.000025*sky_haze_scale);
	ALBEDO=mix(tint,vec3(0.80,0.84,0.88),sky_snow*0.5)*(1.0-haze);
	EMISSION=pow(sky_haze,vec3(2.2))*haze*0.85;
	ROUGHNESS=0.78;
	SPECULAR=0.2;
}
