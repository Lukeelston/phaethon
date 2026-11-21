// Helios from far off (view/helios.gd far_mesh): the whole mountain as one mesh, drawn where the
// terrain's tiles are not (they dissolve between 54 and 64 km; this comes in under them from 48),
// hazed as the terrain is, with the air thinning up its height: the summit stands out of the haze.
shader_type spatial;
render_mode fog_disabled, cull_disabled;

#include "res://view/air.gdshaderinc"

global uniform vec3 sky_haze;
global uniform float sky_haze_scale;

varying vec3 tint;
varying float altitude;

void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));
	altitude = VERTEX.y;
}

void fragment() {
	float d = length(VERTEX);
	float reveal = smoothstep(48000.0, 56000.0, d);
	// (<=, not <: where the pattern's value comes out exactly 0, a surface faded right out was still drawn there: stray single pixels)
	if (reveal <= fract(dot(floor(FRAGCOORD.xy), vec2(0.75487766, 0.56984029)))) {
		discard;
	}
	float eye = CAMERA_POSITION_WORLD.y;
	float thin = air_between(eye, altitude) / air_between(eye, 0.0);
	float haze = 1.0 - exp(-d * 0.000045 * sky_haze_scale * thin);
	ALBEDO = tint * (1.0 - haze);
	EMISSION = pow(sky_haze, vec3(2.2)) * haze * 0.85;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
