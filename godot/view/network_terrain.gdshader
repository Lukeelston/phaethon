shader_type spatial;
render_mode fog_disabled;
#include "res://view/noise.gdshaderinc"
#include "res://view/air.gdshaderinc"
varying vec3 tint;
varying vec2 local;
varying float grass;
varying float elevation;
varying float slope;
instance uniform float stream_reveal = 1.0;
// Realism spike (tools/art_terrain_hd.py): slope east and north in red and green, shelter in blue.
uniform sampler2D terrain_detail : repeat_enable, filter_linear_mipmap_anisotropic;
global uniform vec3 sky_haze;          // the haze's colour (display values): the afternoon's (0.58, 0.68, 0.80) unless view/outlook.gd says otherwise
global uniform float sky_haze_scale;   // ... and how thick it is: 1 as it was; fog and rain thicken it
global uniform float sky_snow;         // snow lying (view/outlook.gd): 0 none, 1 in a snowfall
void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));
	local = UV*256.0;
	grass = COLOR.a;
	elevation = VERTEX.y;
	slope = 1.0-clamp(NORMAL.y,0.0,1.0);
}
void fragment() {
	float reveal=stream_reveal*(1.0-smoothstep(54000.0,64000.0,length(VERTEX)));
	if(reveal<=fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)))) discard;   // (<=: nothing of a tile faded right out)
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
	// Weathered strata follow elevation, not the camera. Filter thin layers
	// out with distance so geological detail does not shimmer in the headset.
	float rock = smoothstep(0.035,0.22,slope);
	float phase = elevation*0.075+mottling*5.0;
	float strata = sin(phase)*(1.0-smoothstep(0.5,2.0,fwidth(phase)));
	float fractures = smoothstep(0.36,0.58,mottling);
	vec3 stone = base*(0.70+0.28*fractures+0.11*strata);
	base = mix(base,stone,rock*0.85);
	// Pale snow keeps its broad sunlit faces; exposed steep rock breaks up
	// the blanket. Warm sand gains low duneside bands without extra geometry.
	float snow = smoothstep(0.50,0.76,min(tint.r,min(tint.g,tint.b)));
	base = mix(base,base*vec3(0.58,0.63,0.68),snow*rock*0.65);
	float sand = smoothstep(1.3,2.0,tint.r/max(0.02,tint.b))*(1.0-grass);
	float ripple_phase = (local.x+local.y*0.32)*0.13+mottling*6.0;
	float ripples = sin(ripple_phase)*(1.0-smoothstep(0.4,2.0,fwidth(ripple_phase)));
	base *= 1.0+sand*ripples*0.065;
	// Ridges, gullies and scree from the relief map: broad forms on every slope, finer ones
	// close by. The map's mip levels flatten both with distance, so nothing crawls at speed.
	vec3 broad = texture(terrain_detail, local / 2048.0).rgb;
	vec3 near_form = texture(terrain_detail, local / 256.0 + broad.bg * 0.25).rgb;
	float steep = mix(0.22, 1.0, rock);
	vec2 tilt = (broad.rg - 0.5) * 1.5 * steep + (near_form.rg - 0.5) * 0.6 * fade * steep;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_normal = normalize(world_normal - vec3(tilt.x, 0.0, -tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float shelter = mix(broad.b, near_form.b, 0.35 * fade);
	base *= 0.80 + 0.42 * shelter;
	// Bare rock on the steep faces is its own grey-brown, not just a darker field colour.
	base = mix(base, vec3(0.19, 0.175, 0.16) * (0.75 + 0.6 * shelter), rock * (1.0 - snow) * 0.45);
	// snow lying: on everything but the steep rock, a little patchy
	base = mix(base, vec3(0.80, 0.84, 0.88) * (0.90 + 0.14 * mottling), sky_snow * (1.0 - 0.72 * rock) * 0.92);
	// (the haze scale is already thinned for the eye's height over the ground: here for this land's own height)
	float eye = CAMERA_POSITION_WORLD.y;
	float thin = air_between(eye, elevation) / air_between(eye, 0.0);
	float haze = 1.0-exp(-length(VERTEX)*0.000045*sky_haze_scale*thin);
	ALBEDO = base*(1.0-haze);
	EMISSION = pow(sky_haze,vec3(2.2))*haze*0.85;
	ROUGHNESS = mix(0.96, 0.82, rock);
	SPECULAR = mix(0.18, 0.3, rock);
}
