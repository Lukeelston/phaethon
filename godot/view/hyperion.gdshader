// Mount Hyperion (view/hyperion.gd body_mesh): the whole mountain as one mesh, 48 km high. Painted as the
// terrain is (view/network_terrain.gdshader: the same mottling, strata, relief and haze, so it meets the
// road's own land and the country at its foot without a seam), but never faded out: it is drawn from as far
// off as the eye is. Beyond PULL_FROM its corners are pulled toward the eye along their own lines of sight,
// to inside the camera's reach (120 km): each stays where it was on the screen (and in each eye), and in
// order of distance, so the mountain shows whole from across the map with nothing else asked to draw further.
shader_type spatial;
render_mode fog_disabled;
#include "res://view/noise.gdshaderinc"
#include "res://view/air.gdshaderinc"

const float PULL_FROM = 88000.0;    // m: nearer than this a corner is where it is
const float PULL_TO = 114000.0;     // ... and none is drawn further than this
const float PULL_OVER = 160000.0;   // (how fast the rest closes on it)

uniform sampler2D terrain_detail : repeat_enable, filter_linear_mipmap_anisotropic;
global uniform vec3 sky_haze;
global uniform float sky_haze_scale;
global uniform float sky_snow;
global uniform float world_lift;    // m the whole world is drawn below its true height (view/craft_view.gd: high on the mountain)

varying vec3 tint;
varying vec2 local;
varying float elevation;
varying float slope;

void vertex() {
	tint = pow(COLOR.rgb, vec3(2.2));
	local = UV * 256.0;
	elevation = VERTEX.y;
	slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
	vec3 seen = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(seen);
	float pulled = d > PULL_FROM ? PULL_FROM + (PULL_TO - PULL_FROM) * (1.0 - exp(-(d - PULL_FROM) / PULL_OVER)) : d;
	POSITION = PROJECTION_MATRIX * vec4(seen * (pulled / max(d, 0.001)), 1.0);
}

void fragment() {
	float d = length(VERTEX);      // (the true distance: VERTEX is not the pulled corner)
	float fw = length(fwidth(local));
	float mottling = pfbm(local / 128.0, 8192.0);
	float fine = pnoise(local / 3.0, 1048576.0);
	float fade = 1.0 - smoothstep(1.0, 12.0, fw);
	vec3 base = tint * (0.83 + 0.32 * mottling) * (0.94 + 0.12 * fine * fade);
	// strata follow elevation: thin ones near, and broad bands that still read from across the map
	float rock = smoothstep(0.035, 0.22, slope);
	float phase = elevation * 0.075 + mottling * 5.0;
	float strata = sin(phase) * (1.0 - smoothstep(0.5, 2.0, fwidth(phase)));
	float broad_phase = elevation * 0.0021 + mottling * 2.4 + pfbm(local / 2600.0, 8192.0) * 3.0;
	float bands = sin(broad_phase) * (1.0 - smoothstep(0.5, 2.0, fwidth(broad_phase)));
	float fractures = smoothstep(0.36, 0.58, mottling);
	vec3 stone = base * (0.70 + 0.28 * fractures + 0.11 * strata + 0.10 * bands);
	base = mix(base, stone, rock * 0.85);
	float snow = smoothstep(0.50, 0.76, min(tint.r, min(tint.g, tint.b)));
	base = mix(base, base * vec3(0.58, 0.63, 0.68), snow * rock * 0.65);
	// ridges, gullies and scree from the terrain's relief map
	vec3 broad = texture(terrain_detail, local / 2048.0).rgb;
	vec3 near_form = texture(terrain_detail, local / 256.0 + broad.bg * 0.25).rgb;
	float steep = mix(0.22, 1.0, rock);
	// (less of it than the terrain takes: laid from above onto slopes this steep the map's pattern shows as a weave)
	vec2 tilt = ((broad.rg - 0.5) * 1.5 * steep + (near_form.rg - 0.5) * 0.6 * fade * steep) * mix(0.55, 0.2, smoothstep(0.3, 0.8, slope));
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_normal = normalize(world_normal - vec3(tilt.x, 0.0, -tilt.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	float shelter = mix(broad.b, near_form.b, 0.35 * fade);
	base *= 0.80 + 0.42 * shelter;
	base = mix(base, vec3(0.19, 0.175, 0.16) * (0.75 + 0.6 * shelter), rock * (1.0 - snow) * 0.45);
	// snow lying (the weather's): on its lower slopes only, and not on its walls
	base = mix(base, vec3(0.80, 0.84, 0.88) * (0.90 + 0.14 * mottling), sky_snow * (1.0 - 0.72 * rock) * 0.92 * (1.0 - smoothstep(9000.0, 14000.0, elevation)));
	float eye = CAMERA_POSITION_WORLD.y + world_lift;
	float thin = air_between(eye, elevation) / air_between(eye, 0.0);
	// (held short of the sky's own colour: from across the country its foot is a shade against the horizon, not gone)
	float haze = min(1.0 - exp(-d * 0.000045 * sky_haze_scale * thin), 0.80);
	ALBEDO = base * (1.0 - haze);
	EMISSION = pow(sky_haze, vec3(2.2)) * haze * 0.80;
	ROUGHNESS = mix(0.96, 0.82, rock);
	SPECULAR = mix(0.18, 0.3, rock);
}
