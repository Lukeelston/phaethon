// An engine's exhaust, as a volume of glowing gas. A tube is drawn round the jet and each pixel's
// ray is walked through the gas inside it, so the jet has a body from every side: across it, down
// on it, and end-on from the seat. What it draws is what view/jet_exhaust.gd works out (and that
// file says what each part rests on):
//   the shape   a flat jet out of a flat nozzle, and it stays flat for as far as it glows (a 3:1
//               jet is not round until 14 diameters out): it thickens a little and then draws down
//               to a point as the air eats into the hot core. Not a fan of fire: the old plume
//               spread to two metres across beside the pod, and from the seat was an orange fog
//   the cells   the shock train: `cell` metres apart, each a few per cent shorter than the last,
//               fading down the jet. Behind each shock what fuel is left relights: a diamond in the
//               jet's thin side, a bar across its flat one
//   the colour  dry, almost nothing (hot exhaust gives off no light: what shows is the hot metal
//               up the pipe); on the burner blue-violet where the gas is clean, orange where its
//               soot burns out in the air, white-yellow in the cells; on the ramjet blue-white
//   the bend    the tube and the gas follow a centre line that craft_model.gd traces each frame
//               (`centre`: metres to the engine's right at 12 stations down the jet)
//   the light   what the gas gives off is added to the scene and what it hides is taken out a
//               little, so it glows against a dark road and still has a body against a bright sky
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
#include "res://view/effect_exclusion.gdshaderinc"

const int STATIONS = 12;
const int STEPS = 20;
uniform sampler2D flow_map : repeat_enable, filter_linear_mipmap;
uniform float thrust = 0.0;
uniform float burner = 0.0;                 // the burner's flame, 0..1 (its zones light in turn)
uniform float ramjet = 0.0;
uniform float seed = 0.0;
uniform float reach = 4.0;                  // how far the jet glows, m
uniform float centre[12];                   // its centre line: m to the right at each station
uniform vec2 slot = vec2(0.92, 0.25);       // the nozzle exit's half-width and half-height, m
uniform float cell = 1.4;                   // the first shock cell's length, m
uniform float shock = 0.7;                  // how plainly the cells show
uniform float flash = 0.0;                  // a burner zone lighting: 1 dying to 0
uniform float teb = 0.0;                    // the ramjet's chemical light (green): 1 dying to 0
const float MARGIN = 1.3;                   // the tube stands this far outside the jet's own section (its torn edge reaches it)
varying vec3 local_pos;

// The glowing jet's half-width and half-height `z` metres behind the nozzle.
vec2 girth(float z) {
	float zn = clamp(z / reach, 0.0, 1.0);
	float taper = mix(1.0, 0.36, smoothstep(0.4, 1.0, zn));
	return vec2(slot.x * (1.0 + 0.04 * zn), slot.y * (1.0 + 0.25 * shock * smoothstep(0.0, 0.08, zn)) + 0.03 * z) * taper;
}

float centre_at(float z) {
	float f = clamp(z / reach, 0.0, 1.0) * float(STATIONS - 1);
	int i = int(min(f, float(STATIONS - 2)));
	return mix(centre[i], centre[i + 1], f - float(i));
}

void vertex() {
	// a unit box, twelve stations long, laid along the centre line and drawn in to the jet's girth
	float z = (VERTEX.z + 0.5) * reach;
	vec3 p = vec3(VERTEX.xy * 2.0 * MARGIN * girth(z), z);
	p.x += centre_at(z);
	VERTEX = p;
	local_pos = p;
	effect_world_position = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
}

void fragment() {
	// this eye's ray in the plume's own frame (the node is never scaled: its matrix turns back by its transpose)
	vec3 rd = normalize((-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * mat3(MODEL_MATRIX));
	vec3 ro = local_pos;
	// how far it runs inside the tube. The tube is a box sheared along the centre line: shear the ray instead.
	float station = clamp(ro.z / reach, 0.0, 1.0) * float(STATIONS - 1);
	int i0 = int(min(station, float(STATIONS - 2)));
	float slope = (centre[i0 + 1] - centre[i0]) * float(STATIONS - 1) / reach;
	vec3 so = vec3(ro.x - centre_at(ro.z), ro.y, ro.z);
	vec3 sd = vec3(rd.x - slope * rd.z, rd.y, rd.z);
	vec3 ahead = step(vec3(0.0), sd);
	vec3 pace = max(abs(sd), vec3(1e-5)) * (ahead * 2.0 - 1.0);
	// (the tube is widest near the nozzle: a ray going that way leaves through its wider end)
	vec2 section = MARGIN * girth(ro.z);
	vec3 tt = (mix(vec3(-section, 0.0), vec3(section, reach), ahead) - so) / pace;
	float run = min(tt.x, min(tt.y, tt.z));
	section = MARGIN * max(section, girth(ro.z + rd.z * run));
	tt = (mix(vec3(-section, 0.0), vec3(section, reach), ahead) - so) / pace;
	run = clamp(min(tt.x, min(tt.y, tt.z)), 0.0, 40.0);
	float dt = run / float(STEPS);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))) + TIME * 13.7);

	float hot = clamp(burner, 0.0, 1.0);
	float blue = clamp(ramjet, 0.0, 1.0);
	// what the gas gives off: near the nozzle, where it is clean; further down, where its soot burns
	// out; in the shock cells; and in the ragged sheath where it meets the air
	vec3 near_col = mix(mix(vec3(0.10, 0.13, 0.26), vec3(0.62, 0.42, 1.30), hot), vec3(0.28, 0.50, 1.70), blue);
	vec3 far_col = mix(mix(vec3(0.07, 0.08, 0.12), vec3(1.30, 0.40, 0.10), hot), vec3(0.40, 0.55, 1.50), blue);
	vec3 cell_col = mix(mix(vec3(0.45, 0.55, 0.85), vec3(2.70, 2.00, 1.20), hot), vec3(2.10, 2.40, 2.90), blue);
	vec3 rim_col = mix(mix(vec3(0.20, 0.26, 0.50), vec3(1.50, 0.60, 0.15), hot), vec3(0.45, 0.70, 1.90), blue);
	vec3 sheath_col = mix(vec3(1.50, 0.46, 0.07), vec3(0.50, 0.42, 1.60), blue);
	// (a zone lighting throws a rich yellow torch; the ramjet's chemical shot burns green)
	vec3 pop = vec3(1.9, 1.25, 0.45) * flash + vec3(0.25, 1.9, 0.5) * teb;
	float power = mix(0.045 + 0.085 * smoothstep(0.0, 0.9, thrust), 1.0, hot) * (1.0 + 0.25 * blue);
	float stream = TIME * mix(4.0, 8.5, hot);

	vec3 sum = vec3(0.0);
	float through = 1.0;
	for (int s = 0; s < STEPS; s++) {
		vec3 p = ro + rd * (dt * (float(s) + jitter));
		float z = p.z;
		float zn = z / reach;
		if (zn < 0.0 || zn > 1.0) {
			continue;
		}
		float u = p.x - centre_at(z);
		vec2 q = vec2(u, p.y) / girth(z);
		vec2 q2 = q * q;
		float rho = mix(sqrt(sqrt(dot(q2, q2))), sqrt(q2.x + q2.y), 0.6 * smoothstep(0.2, 1.0, zn));   // a rounded slot, its corners going as it runs
		if (rho > MARGIN) {
			continue;
		}
		// the turbulence, drawn out along the stream and carried down it fast: streaks, not tongues
		vec3 n = textureLod(flow_map, vec2(u * 0.41 + p.y * 0.57 + seed, z * 0.055 - stream), 0.0).rgb;
		float swell = textureLod(flow_map, vec2(u * 0.09 - p.y * 0.13 + seed * 0.7, z * 0.021 - stream * 0.27), 0.0).g;
		// the shear layer grows down the jet and tears its edge
		float mixing = smoothstep(0.02, 0.6, zn);
		float edge = rho * (1.0 + ((n.r - 0.5) * 0.7 + (swell - 0.5) * 0.5) * mixing);
		// the shock train: the shocks cross 0.45 of a cell out and every cell after, each cell a
		// little shorter; the pattern dies down the jet as the shear layer reaches its middle
		float c = z / cell;
		float at = fract(c * (1.0 + 0.04 * c) + 0.55) - 0.5;
		float w = abs(at) * 2.0;                                           // 0 where the shocks cross, 1 midway between
		float train = shock * exp(-0.30 * c) * (1.0 - smoothstep(0.5, 0.92, zn));
		float core_r = mix(0.80, 0.34, smoothstep(0.0, 0.9, zn));
		// (a flat jet's shocks run between its two flat sides: seen edge-on a diamond, and across the
		// flat a bar that draws in toward the jet's sides. The relit gas is brightest at the heart of
		// each and has no edge: it comes up sharply behind the shock and trails away after it)
		float wide = abs(q.x);
		float thin = mix(max(abs(q.y), 0.5 * wide * wide + 0.5 * smoothstep(0.6, 1.0, wide)), rho, 0.5 * smoothstep(0.3, 1.0, zn));
		float off = w * mix(1.4, 0.9, step(0.0, at)) + thin / (core_r * 1.25) + (n.b - 0.5) * 0.3 * mixing;
		float diamond = pow(1.0 - smoothstep(0.0, 1.0, off), 1.35) * train;
		float core = 1.0 - smoothstep(core_r * mix(0.7, 0.15, zn), core_r * 1.2, edge);
		float fade = 1.0 - smoothstep(0.45, 1.0, zn);
		float body = core * mix(1.0, 0.5, smoothstep(0.05, 0.6, zn)) * fade * (1.0 - 0.35 * train * w);
		// the sheath: where what fuel is left meets the air and burns (only a burner has one)
		float sheath = exp(-pow((edge - 0.90) / (0.06 + 0.16 * mixing), 2.0)) * (0.35 + 0.65 * smoothstep(0.3, 0.7, n.g))
				* smoothstep(0.02, 0.25, zn) * fade * hot;
		float cabin = exterior_effect_visibility((MODEL_MATRIX * vec4(p, 1.0)).xyz, CAMERA_POSITION_WORLD);
		float lighting = (1.0 - smoothstep(0.0, 0.45, zn)) * core;
		vec3 light = (mix(near_col, far_col, smoothstep(0.05, 0.55, zn)) * body * 0.26 + mix(rim_col, cell_col, diamond) * diamond * 2.0
				+ sheath_col * sheath * 0.15 + pop * lighting * 1.2) * power * cabin;
		// this step's share: the light of the gas in it, less what that gas itself hides
		float gas = (body * 0.5 + diamond * 1.7 + sheath * 0.3 + lighting * (flash + teb)) * power * cabin;
		float hidden = 1.0 - exp(-gas * dt);
		sum += through * light / max(gas, 1e-4) * hidden;
		through *= 1.0 - hidden;
	}
	ALBEDO = sum;
	ALPHA = (1.0 - through) * mix(0.08, 0.32, hot);
}
