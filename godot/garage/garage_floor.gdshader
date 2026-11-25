shader_type spatial;
render_mode specular_schlick_ggx;

#include "res://view/noise.gdshaderinc"

uniform sampler2D aggregate : hint_default_white, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D contact : hint_default_white, repeat_disable, filter_linear_mipmap_anisotropic;
uniform vec2 floor_size;
uniform vec2 gate_centers[6];
varying vec2 floor_m;

void vertex() {
	floor_m = VERTEX.xz;
}

void fragment() {
	// The mineral texture packs both surface slopes in GB. Read its fine grain
	// at a concrete scale and its binder at a larger, oblique finishing scale.
	vec4 stone = texture(aggregate, floor_m * 0.86);
	vec2 trowel = vec2(dot(floor_m, vec2(0.92, 0.39)), dot(floor_m, vec2(-0.39, 0.92)));
	float finish = texture(aggregate, trowel * vec2(0.041, 0.075) + vec2(0.26, 0.14)).a - 0.5;
	float mineral = stone.r - 0.55;

	// Six-metre pours. Each cut keeps its physical width as it recedes; the
	// footprint across a cut can be much smaller than along it at pilot height.
	vec2 footprint = max(fwidth(floor_m), vec2(0.001));
	vec2 slab = floor_m / 6.0;
	vec2 distance_to_cut = (0.5 - abs(fract(slab) - 0.5)) * 6.0;
	float seal = max(aline(distance_to_cut.x, 0.005, footprint.x), aline(distance_to_cut.y, 0.005, footprint.y));
	float shoulder = max(aline(distance_to_cut.x, 0.019, footprint.x), aline(distance_to_cut.y, 0.019, footprint.y));
	float pour = hash21(floor(slab)) - 0.5;

	float side = abs(floor_m.x);
	float aisle = 1.0 - smoothstep(2.21 - footprint.x, 2.26 + footprint.x, side);
	float footsteps = 1.0 - smoothstep(0.65, 2.18, side + finish * 0.55);
	// Foot traffic buffs the approach to each of the three gates on this side.
	int column = floor_m.x < 0.0 ? 0 : 1;
	vec2 gate = gate_centers[column];
	for (int row = 2; row < 6; row += 2) {
		vec2 candidate = gate_centers[row + column];
		if (abs(floor_m.y - candidate.y) < abs(floor_m.y - gate.y)) {
			gate = candidate;
		}
	}
	float crossing = abs(floor_m.y - gate.y + finish * 0.8);
	float service = (1.0 - smoothstep(0.42, 1.6, crossing)) * (1.0 - smoothstep(0.34, 4.14, side - abs(gate.x)));
	float polish = max(footsteps, service) * clamp(0.70 + finish * 1.25, 0.32, 1.0);

	vec3 slab_color = mix(vec3(0.210, 0.208, 0.188), vec3(0.167, 0.180, 0.180), pour + 0.5);
	vec3 paint = vec3(0.094, 0.125, 0.130);
	vec3 base = mix(slab_color, paint, aisle);
	base *= 1.0 + finish * 0.59 + mineral * mix(0.40, 0.23, aisle);
	base *= 1.0 - polish * 0.077;
	// The fixed equipment also intercepts diffuse fill from the hall fixtures.
	float visibility = texture(contact, floor_m / floor_size + vec2(0.5)).r;
	AO = visibility;
	AO_LIGHT_AFFECT = 0.14;
	ALBEDO = base * mix(0.65, 1.0, visibility) * (1.0 + (shoulder - seal) * 0.11 - seal * 0.54);
	ROUGHNESS = clamp(0.69 + mineral * 0.32 + finish * 0.29 + pour * 0.065 - 0.06 * aisle - 0.20 * polish - 0.10 * seal, 0.37, 0.83);
	NORMAL_MAP = vec3(stone.gb, 1.0);
	NORMAL_MAP_DEPTH = mix(0.18, 0.08, max(aisle, polish));
}
