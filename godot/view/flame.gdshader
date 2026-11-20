// An engine's exhaust, as a volume of burning gas. (Luke, of the two painted shells this replaces:
// "The flames aren't convincing, and don't seem to really vector.") A tube is drawn round the jet
// and each pixel's ray is walked through the gas inside it, so the plume has a body from every
// side: across it, down on it, and end-on from the seat, where a painted skin is all edge.
//   the gas    a hot core that leaves the slot nozzle flat and turns round within a few metres,
//              pinching and swelling through a train of shock cells, each pinch white hot; a thin
//              blue lip where the fuel meets the air; and round the core, further down, a ragged
//              flame that the flow map tears along the stream
//   the bend   the tube and the gas follow a centre line that craft_model.gd traces each frame
//              (`centre`: metres to the engine's right at 12 stations down the plume): out of the
//              nozzle the way the vanes point, then swept round into the slipstream
//   the light  what the gas gives off is added to the scene and what it hides is taken out a
//              little, so it glows against a dark road and still has a body against a bright sky
// On dry thrust: a short faint blue jet. On the burner: orange, long. On the ramjet: blue-white.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
#include "res://view/effect_exclusion.gdshaderinc"

const int STATIONS = 12;
const int STEPS = 24;
uniform sampler2D flow_map : repeat_enable, filter_linear_mipmap;
uniform float thrust = 0.0;
uniform float burner = 0.0;
uniform float ramjet = 0.0;
uniform float seed = 0.0;
uniform float reach = 4.0;                  // the plume's length, m
uniform float centre[12];                   // its centre line: m to the right at each station
uniform vec2 slot = vec2(0.92, 0.27);       // the nozzle's half-width and half-height, m
const float MARGIN = 1.8;                   // the tube stands this far outside the jet's own section (the torn edge reaches it)
varying vec3 local_pos;

// The jet's half-width and half-height `z` metres behind the nozzle: a flat slot that is a round
// plume a few metres on, spreading slowly.
vec2 girth(float z) {
	return mix(slot, vec2(0.48 + 0.05 * z), smoothstep(0.0, 3.2, z));
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
	// (the tube widens downstream: a ray going that way leaves through its wider end)
	vec2 section = MARGIN * girth(ro.z);
	vec3 tt = (mix(vec3(-section, 0.0), vec3(section, reach), ahead) - so) / pace;
	float run = min(tt.x, min(tt.y, tt.z));
	section = MARGIN * girth(max(ro.z, ro.z + rd.z * run));
	tt = (mix(vec3(-section, 0.0), vec3(section, reach), ahead) - so) / pace;
	run = clamp(min(tt.x, min(tt.y, tt.z)), 0.0, 40.0);
	float dt = run / float(STEPS);
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))) + TIME * 13.7);

	float hot = clamp(burner, 0.0, 1.0);
	float blue = clamp(ramjet, 0.0, 1.0);
	// what the gas glows, from its coolest to its hottest: dry, on the burner, on the ramjet
	vec3 low = mix(mix(vec3(0.03, 0.05, 0.28), vec3(0.55, 0.08, 0.012), hot), vec3(0.10, 0.08, 0.60), blue);
	vec3 mid = mix(mix(vec3(0.16, 0.36, 1.05), vec3(1.90, 0.62, 0.10), hot), vec3(0.30, 0.75, 2.00), blue);
	vec3 top = mix(mix(vec3(0.75, 0.95, 1.50), vec3(2.60, 2.10, 1.50), hot), vec3(2.00, 2.30, 2.70), blue);
	vec3 lip_col = mix(mix(vec3(0.15, 0.30, 1.00), vec3(0.25, 0.35, 1.50), hot), vec3(0.60, 0.30, 1.60), blue);
	float power = mix(0.16 + 0.34 * smoothstep(0.0, 0.9, thrust), 1.0, hot) * (1.0 + 0.25 * blue);
	float stream = TIME * mix(1.6, 2.6, hot);

	vec3 sum = vec3(0.0);
	float through = 1.0;
	for (int s = 0; s < STEPS; s++) {
		vec3 p = ro + rd * (dt * (float(s) + jitter));
		float z = p.z;
		float zn = z / reach;
		float u = p.x - centre_at(z);
		float round_out = smoothstep(0.0, 3.2, z);
		vec2 q = vec2(u, p.y) / girth(z);
		vec2 q2 = q * q;
		float rho = mix(sqrt(sqrt(dot(q2, q2))), sqrt(q2.x + q2.y), round_out);   // a rounded slot, then a circle
		if (rho > MARGIN || zn < 0.0 || zn > 1.0) {
			continue;
		}
		// the turbulence, carried down the stream: two sheets of the flow map, one lying across the
		// jet and one standing in it (read round the axis instead, it speckles where a ray crosses the middle)
		vec3 flat_n = textureLod(flow_map, vec2(u * 0.37 + seed, z * 0.11 - stream), 0.0).rgb;
		vec3 tall_n = textureLod(flow_map, vec2(p.y * 0.37 + seed + 0.43, z * 0.13 - stream * 1.13), 0.0).rgb;
		vec2 n = vec2(flat_n.r + tall_n.g, flat_n.b + tall_n.r) * 0.5;
		float billow = textureLod(flow_map, vec2(u * 0.13 + p.y * 0.09 + seed, z * 0.045 - stream * 0.35), 0.0).g;
		// the shear layer grows down the jet and tears its edge
		float mixing = smoothstep(0.05, 0.6, zn);
		float edge = rho * (1.0 + ((n.x - 0.5) * 1.2 + (billow - 0.5) * 0.4) * mixing);
		// the shock train: the core pinches and swells, and in each pinch the gas is white hot again:
		// a diamond, widest where the shocks cross and drawn to a point either way along the jet
		float train = 1.0 - smoothstep(0.14, 0.62, zn);
		float phase = z * (0.95 + 0.05 * z) + 0.12;
		float wave = cos(TAU * phase);
		float core_w = mix(0.66, 0.34, smoothstep(0.0, 0.7, zn)) * (1.0 - 0.26 * wave * train);
		float diamond = edge / (1.05 * core_w) + abs(fract(phase + 0.5) - 0.5) * 2.1;
		float cell = (1.0 - smoothstep(0.45, 1.0, diamond)) * train * mix(1.0, 0.6, smoothstep(0.0, 0.5, zn));
		float core = exp(-(edge * edge) / (core_w * core_w));
		float fade = 1.0 - smoothstep(0.35, 1.0, zn);
		float heat = (core * 0.55 + cell * 1.25) * mix(1.0, 0.42, smoothstep(0.08, 0.5, zn)) * fade;
		// the flame round the core (only a burner has one): torn into tongues, hottest in its middle
		float tongues = 0.3 + 0.7 * smoothstep(0.32, 0.66, n.y);
		float body = (1.0 - smoothstep(0.35, 1.1, edge)) * tongues * smoothstep(0.03, 0.3, zn) * fade;
		heat = max(heat, body * hot * mix(0.55, 0.2, smoothstep(0.2, 1.0, edge)));
		float lip = exp(-pow((rho - 0.92) / 0.10, 2.0)) * (1.0 - smoothstep(0.0, 0.2, zn));
		vec3 col = mix(low, mid, smoothstep(0.0, 0.4, heat));
		col = mix(col, top, smoothstep(0.45, 1.25, heat));
		float cabin = exterior_effect_visibility((MODEL_MATRIX * vec4(p, 1.0)).xyz, CAMERA_POSITION_WORLD);
		float gas = (heat + 0.4 * lip) * power * cabin;
		vec3 light = (col * heat * 5.2 + lip_col * lip * 2.0) * power * cabin;
		// this step's share: the light of the gas in it, less what that gas itself hides
		float hidden = 1.0 - exp(-gas * 2.6 * dt);
		sum += through * light / max(gas * 2.6, 1e-4) * hidden;
		through *= 1.0 - hidden;
	}
	ALBEDO = sum;
	ALPHA = (1.0 - through) * mix(0.12, 0.5, hot);
}
