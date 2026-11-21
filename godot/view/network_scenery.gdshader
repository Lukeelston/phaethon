// The Network's landmarks and Eridanus' solar works: static compounds tinted by vertex colour,
// hazed by their true distance. Realism spike: vertex alpha now names the material (1 mineral or
// paint, 0.8 painted steel, 0.6 bare alloy), so metal mirrors the sky and suns; cladding has
// panel joints and rain streaks in the structure's own metres; every mass darkens toward its
// foot. The joints and streaks fade out before they get near a pixel.
shader_type spatial;
render_mode fog_disabled, cull_back;
#include "res://view/noise.gdshaderinc"

uniform float glow = 0.0;
global uniform vec3 sky_haze;          // the haze's colour (display values): the afternoon's (0.58, 0.68, 0.80) unless view/outlook.gd says otherwise
global uniform float sky_haze_scale;
#define haze_color sky_haze
varying vec3 tint;
varying float part;
varying vec3 local;
varying vec3 facing;

void vertex() {
	tint = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(2.2));
	part = COLOR.a;
	local = VERTEX;
	facing = NORMAL;
}

void fragment() {
	float haze = clamp(1.0 - exp(-length(VERTEX) * 0.000025 * sky_haze_scale), 0.0, 1.0);
	vec3 sky = pow(haze_color, vec3(2.2));
	// Walls take their joints across and up the face; decks take them in plan.
	vec3 n = abs(normalize(facing));
	vec2 face = n.y > 0.6 ? local.xz : (n.x > n.z ? local.zy : local.xy);
	vec2 fw = max(fwidth(face), vec2(0.001));
	vec2 pitch = vec2(18.0, 12.0);
	vec2 joint = abs(fract(face / pitch + 0.5) - 0.5) * pitch;
	float seam = max(aline(joint.x, 0.25, fw.x), aline(joint.y, 0.25, fw.y)) * detail(1.5, max(fw.x, fw.y));
	float near = detail(4.0, max(fw.x, fw.y));
	float streak = pnoise(vec2(face.x / 2.5, face.y / 60.0), 65536.0);
	float batch = hash21(mod(floor(face / pitch), 4096.0));
	float wall = 1.0 - smoothstep(0.5, 0.8, n.y);
	vec3 base = tint * (1.0 - 0.45 * seam) * (1.0 + (batch - 0.5) * 0.14 * near) * (1.0 - 0.22 * (streak - 0.35) * wall * near);
	// Ground shade: each mass darkens toward where it meets the terrain.
	base *= mix(0.72, 1.0, smoothstep(0.0, 60.0, local.y));
	float metal = part < 0.7 ? 1.0 : (part < 0.9 ? 0.35 : 0.0);
	float lit = 1.0 - min(glow, 1.0);
	ALBEDO = base * (1.0 - haze) * lit;
	EMISSION = sky * haze * 0.85 + tint * glow * (1.0 - haze);
	METALLIC = metal * (1.0 - haze) * lit;
	ROUGHNESS = mix(part < 0.7 ? 0.36 : (part < 0.9 ? 0.52 : 0.84), 0.9, haze) + 0.08 * (streak - 0.5) * wall;
	SPECULAR = mix(0.5, 0.2, haze);
}
