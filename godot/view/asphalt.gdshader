// Road UVs are metres along the pavement and metres left of centre. Every
// longitudinal scale wraps at the same floating-origin period as the road mesh.
shader_type spatial;
render_mode cull_disabled;

#include "res://view/noise.gdshaderinc"
#include "res://view/pavement_shoulder.gdshaderinc"

// Linear data: mineral value, slope along, slope across, binder variation.
uniform sampler2D pavement_detail : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float period = 64000.0;
uniform vec3 base = vec3(0.30, 0.295, 0.29); // authored sRGB
uniform float lane_half = 20.0; // zero selects the range's concrete apron
uniform float joint_every = 25.0;
uniform float spec = 0.4;
// Start station, length and spacing (m) of the fixed shelter light wells.
uniform vec3 shelter = vec3(0.0);

// A box filtered independently along and across the road. A grazing viewing
// angle can put several metres of road inside a pixel but only a few cm across.
float road_box(vec2 dist_to_edge, vec2 fw) {
	vec2 coverage = 1.0 - smoothstep(-fw * 0.5, fw * 0.5, dist_to_edge);
	return coverage.x * coverage.y;
}

void fragment() {
	vec2 p = UV;
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	vec2 fw = max(abs(dx) + abs(dy), vec2(0.002));
	vec4 stone = texture(pavement_detail, p * 0.5);
	float district = pnoise(vec2(p.x / 400.0, p.y / 40.0), period / 400.0);
	float binder = texture(pavement_detail, p / vec2(128.0, 32.0) + vec2(district * 0.59, district * 0.31)).a;
	float grit = stone.r - 0.50;
	vec3 col = base;
	float rough = 0.86;
	float polish = 0.0;
	float coat = (binder - 0.5) * 0.58 + (district - 0.5) * 0.13;
	if (lane_half > 0.0) {
		// A paving train lays one lift at a time. Its feed, rolling and age
		// change over long stretches, independently of the next pass.
		float pass_pos = (p.y + (binder - 0.5) * 0.30) / 7.2 + 0.5;
		float lift = floor(pass_pos);
		float seed = hash21(vec2(lift, 13.0));
		float run = floor((p.x + seed * 148.0) / 160.0);
		float batch = hash21(vec2(mod(run, period / 160.0), lift));
		float lift_detail = detail(7.2, fw.y);
		float age = 0.60 + ((batch - 0.5) * 0.78 + (seed - 0.5) * 0.28) * lift_detail * detail(160.0, fw.x);
		col = mix(base * vec3(0.91, 0.95, 1.02), base * vec3(1.32, 1.31, 1.28), clamp(age, 0.0, 1.0));
		col *= 1.0 + coat + grit * 0.69;
		rough += (age - 0.5) * 0.085 + (binder - 0.5) * 0.17;

		// Moist binder and polished aggregate make a dark, slightly smoother
		// racing line. Station colour carries its signed offset on curved courses.
		float worn_y = p.y - (COLOR.r - COLOR.g) * 64.0;
		float track_y = abs(worn_y) / lane_half;
		float lane = 1.0 - smoothstep(0.50, 1.0, track_y);
		float traces = texture(pavement_detail, vec2(p.x / 256.0 + district * 0.2, worn_y / 8.0 + district * 0.18)).a;
		float path = (track_y - 0.19) / 0.23;
		float rib = exp(-path * path);
		polish = lane * (0.14 + 0.41 * rib + 0.36 * smoothstep(0.34, 0.67, traces));
		col *= 1.0 - 0.245 * polish;
		rough -= 0.23 * polish;

		// The cold joint has a sealed core and a weathered lip on one side.
		float inset = fract(pass_pos) * 7.2;
		float cold_joint = aline(min(inset, 7.2 - inset), 0.042, fw.y);
		float lip = aline(abs(inset - 0.17), 0.066, fw.y) * lift_detail;
		col *= 1.0 - 0.31 * cold_joint + 0.085 * lip;
		rough -= 0.12 * cold_joint;
		float joint_phase = (p.x + (seed - 0.5) * 4.0) / joint_every;
		float cross_joint = abs(fract(joint_phase + 0.5) - 0.5) * joint_every;
		col *= 1.0 - 0.39 * aline(cross_joint, 0.04, fw.x);

		// Occasional saw-cut inlays replace a stretch of a single paving pass.
		// A weak aggregate-coloured lip catches the light beside the tar seal.
		vec2 cell = vec2(mod(run, period / 160.0), lift);
		float repair = hash21(cell + vec2(12.0, 21.0));
		if (repair < 0.24) {
			float repair_size = hash21(cell + vec2(21.0, 7.0));
			float station = fract((p.x + seed * 148.0) / 160.0) * 160.0;
			vec2 q = abs(vec2(station - (46.0 + batch * 52.0), inset - (2.9 + repair_size))) -
					vec2(5.0 + 14.0 * repair_size, 1.3 + 1.35 * batch);
			float fill = road_box(q, fw) * lift_detail * detail(48.0, fw.x);
			float seal = (road_box(q - 0.10, fw) - road_box(q + 0.045, fw)) * lift_detail;
			vec3 patch = base * vec3(0.84, 0.88, 0.94) * (1.0 + grit * 0.56 + coat * 0.42);
			col = mix(col, patch, fill) * (1.0 - 0.29 * seal);
			rough = mix(rough, 0.73 + 0.12 * binder, fill) - seal * 0.12;
		}
		// A sealed stress crack rarely crosses the entire pass. Its two bends
		// are in local metres, so the shape closes at the 64 km UV wrap.
		float crack_cell = floor(p.x / 40.0);
		vec2 crack_id = vec2(mod(crack_cell, period / 40.0), lift);
		float crack_seed = hash21(crack_id + vec2(1.0, 7.0));
		if (crack_seed < 0.18) {
			float depth = hash21(crack_id + vec2(19.0, 3.0));
			float bend = 0.52 * sin(inset * 1.4 + 24.0 * depth) + 0.14 * sin(inset * 4.3 + 16.0 * depth);
			float crack_x = mod(p.x, 40.0) - (6.0 + 27.0 * depth + bend + 0.49 * inset);
			float span = 1.0 - smoothstep(2.0 + 3.2 * depth, 2.6 + 3.2 * depth, inset);
			float tar = aline(abs(crack_x), 0.029, fw.x + fw.y) * span;
			col *= 1.0 - 0.40 * tar;
			rough -= 0.21 * tar;
		}
	} else {
		vec2 spacing = vec2(joint_every, 6.0);
		vec2 joint = abs(fract(p / spacing + 0.5) - 0.5) * spacing;
		float seal = max(aline(joint.x, 0.029, fw.x), aline(joint.y, 0.029, fw.y));
		col *= (1.0 + coat * 0.43 + grit * 0.26) * (1.0 - 0.41 * seal);
	}

	// These meshes have no tangent streams. The position and road-coordinate
	// gradients carry the measured aggregate slopes into the banked surface's
	// own frame, including when the vehicle is driving up a vertical shaft.
	vec3 axis_x = cross(dFdy(VERTEX), NORMAL);
	vec3 axis_y = cross(NORMAL, dFdx(VERTEX));
	float det = dot(axis_x, dFdx(VERTEX));
	vec2 slope = (stone.gb - 0.5) / 1.8 * (1.0 - 0.42 * polish);
	slope *= lane_half > 0.0 ? 1.0 : 0.35;
	vec3 gradient = axis_x * dot(dx, slope) + axis_y * dot(dy, slope);
	NORMAL = normalize(NORMAL - gradient * sign(det) / max(abs(det), 0.000001));
	rough += grit * 0.11;

	// The Network's divider paint sits between the actual vehicle paths.
	// Alpha fades it out before a merge, amber ascent, hall or shaft. Other
	// surfaces leave alpha at one. These are dry, abraded stripes in daylight.
	if (COLOR.a < 0.999) {
		float wide_road = step(0.5, COLOR.b);
		float pitch = mix(50.0, 45.0, wide_road);
		float divider = round(p.y / pitch);
		if (abs(divider) <= mix(1.0, 3.0, wide_road)) {
			float width = 0.84 + 0.14 * (binder - 0.5);
			float across = shoulder_band(p.y - divider * pitch, width, fw.y);
			float dash = shoulder_repeat(p.x, 128.0, 21.0, fw.x);
			float worn = clamp(0.77 + 0.96 * (binder - 0.5) - 0.49 * max(grit, 0.0), 0.38, 0.93);
			float paint = (1.0 - COLOR.a) * across * dash * worn;
			col = mix(col, vec3(0.74, 0.735, 0.685) * (0.98 + 0.13 * grit), paint);
			rough = mix(rough, 0.86, paint);
		}
	}
	apply_paved_shoulder(p, UV2, fw, col, rough);
	ALBEDO = srgb(col);
	if (shelter.z > 0.0) {
		float station = mod(p.x - shelter.x + 0.5 * period, period) - 0.5 * period;
		float indoors = smoothstep(-8.0, 32.0, min(station, shelter.y - station));
		float lamp_distance = abs(fract(station / shelter.z + 0.5) - 0.5) * shelter.z;
		float across = (abs(p.y) - 37.0) / 52.0;
		float along = lamp_distance / 33.0;
		float pool = exp(-across * across - along * along);
		// Baked diffuse floor illumination. The same real fixtures light both eyes
		// and the stone wear remains visible through the pools.
		EMISSION = ALBEDO * vec3(0.45, 0.75, 0.88) * (1.25 * indoors * pool);
	}
	ROUGHNESS = clamp(rough, 0.39, 0.98);
	SPECULAR = spec;
}
