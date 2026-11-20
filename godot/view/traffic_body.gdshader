// Realism spike: the Network's traffic bodies. One batched mesh per kind (view/traffic_models.gd),
// its parts told apart by vertex alpha: paint takes the vehicle's own colour under a clear coat,
// glazing is a dark mirror for the sky and suns, metal is bare and brushed, trim is matte.
// Painted panels carry their shut lines, a shoulder crease and (on freight) pressed ribs, all in
// the body's own metres and all faded out before they shrink to a pixel.
shader_type spatial;
render_mode cull_disabled;
#include "res://view/noise.gdshaderinc"

uniform vec4 cuts = vec4(1000.0);   // stations along the body (m) of door and panel cuts
uniform float belt = 1000.0;        // height (m) of the shoulder crease
uniform float ribs = 0.0;           // spacing (m) of pressed ribs along the flanks; 0 for none

varying vec3 local;
varying vec3 facing;

void vertex() {
	local = VERTEX;
	facing = NORMAL;
}

void fragment() {
	float part = COLOR.a;
	vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));   // authored sRGB, as the old material read it
	// Bodies hover close to the road: their undersides and skirts sit in their own shade.
	float shade = mix(0.45, 1.0, smoothstep(0.15, 1.1, local.y));
	if (part > 0.9) {
		float fz = max(fwidth(local.z), 0.001);
		float fy = max(fwidth(local.y), 0.001);
		float flank = smoothstep(0.35, 0.75, abs(normalize(facing).x));
		float cut = 0.0;
		for (int i = 0; i < 4; i++) {
			cut = max(cut, aline(abs(local.z - cuts[i]), 0.018, fz));
		}
		cut *= detail(0.12, fz);
		float crease = aline(abs(local.y - belt), 0.02, fy) * flank * detail(0.12, fy);
		float pressed = ribs > 0.0 ? (0.5 + 0.5 * cos(local.z / ribs * TAU)) * flank * detail(ribs, fz) : 0.0;
		float dirt = pnoise(vec2(local.z * 0.9, local.y * 3.0), 4096.0) * (1.0 - smoothstep(0.3, 1.3, local.y));
		ALBEDO = tint * shade * (1.0 - 0.72 * max(cut, crease)) * (1.0 - 0.16 * pressed) * (1.0 - 0.3 * dirt);
		ROUGHNESS = 0.36 + 0.3 * dirt;
		CLEARCOAT = 1.0 - 0.6 * dirt;
		CLEARCOAT_ROUGHNESS = 0.07 + 0.2 * dirt;
	} else if (part > 0.7) {
		ALBEDO = vec3(0.022, 0.026, 0.032) * shade;
		ROUGHNESS = 0.62;
	} else if (part > 0.5) {
		ALBEDO = vec3(0.56, 0.58, 0.61) * shade;
		METALLIC = 1.0;
		ROUGHNESS = 0.3;
	} else {
		ALBEDO = vec3(0.035, 0.07, 0.10);
		METALLIC = 0.92;
		ROUGHNESS = 0.05;
	}
	SPECULAR = 0.5;
	AO = shade;
	AO_LIGHT_AFFECT = 0.3;
}
