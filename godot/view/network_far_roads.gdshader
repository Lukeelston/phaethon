shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
global uniform vec3 sky_haze;          // the haze's colour (display values): the afternoon's (0.58, 0.68, 0.80) unless view/outlook.gd says otherwise
global uniform float sky_haze_scale;   // ... and how thick it is: 1 as it was; fog and rain thicken it
uniform vec2 fade = vec2(80000.0, 100000.0);   // m: the ribbon fades out between these (further from high up: NetworkFarRoads.set_reach)
void fragment() {
	float d = length(VERTEX);
	float reveal = smoothstep(16000.0,20000.0,d)*(1.0-smoothstep(fade.x,fade.y,d));
	// Open scenic edges carry metres past the pavement in UV. Other roads have no UVs (zero).
	bool glass = max(UV.x, UV.y) > 0.0;
	if (glass) reveal *= 0.16;
	// Opaque screen-door transition: no transparent road sorting or depth holes.
	float threshold = fract(dot(floor(FRAGCOORD.xy),vec2(0.75487766,0.56984029)));
	if (reveal <= threshold) discard;   // (<=: a ribbon faded right out is not drawn where the pattern is exactly 0)
	float haze=1.0-exp(-d*0.000045*sky_haze_scale);
	vec3 surface = glass ? vec3(0.08, 0.31, 0.55) : vec3(0.035);
	ALBEDO=mix(surface*clamp(dot(sky_haze,vec3(0.5)),0.08,1.0),pow(sky_haze,vec3(2.2))*0.85,haze);
}
