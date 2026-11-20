// The digital speed readout and gear digit in the centre gauge (vr/gauge_cluster.gd): slanted
// seven-segment figures drawn in the shader, so they stay sharp at any distance. Unlit segments
// show faintly, as they do on a real display. UV runs 0-1 over each window; UV2 is (which
// window: 0 speed, 1 gear; the window's width over its height).
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform int speed = 0;
uniform int gear = 0;               // 0: blank
uniform vec3 ink : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 gear_ink : source_color = vec3(0.95, 0.95, 0.9);
uniform float level = 1.0;
uniform float energy = 1.7;

const int SEGMENTS[10] = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111};   // bit 0 the top bar, clockwise, bit 6 the middle

float bar(vec2 p, vec2 centre, float reach, bool lying) {
	vec2 q = abs(p - centre);
	if (!lying) {
		q = q.yx;
	}
	return max(q.y - 0.062, q.x + q.y - reach);
}

// p: one figure high, centred. Returns (lit, any segment).
vec2 figure(vec2 p, int n, float soft) {
	p.x -= p.y * 0.14;
	float d[7];
	d[0] = bar(p, vec2(0.0, 0.5), 0.198, true);
	d[1] = bar(p, vec2(0.22, 0.25), 0.228, false);
	d[2] = bar(p, vec2(0.22, -0.25), 0.228, false);
	d[3] = bar(p, vec2(0.0, -0.5), 0.198, true);
	d[4] = bar(p, vec2(-0.22, -0.25), 0.228, false);
	d[5] = bar(p, vec2(-0.22, 0.25), 0.228, false);
	d[6] = bar(p, vec2(0.0, 0.0), 0.198, true);
	int mask = n < 0 ? 0 : SEGMENTS[n];
	vec2 found = vec2(0.0);
	for (int i = 0; i < 7; i++) {
		float cover = 1.0 - smoothstep(-soft, soft, d[i]);
		found.y = max(found.y, cover);
		if (((mask >> i) & 1) == 1) {
			found.x = max(found.x, cover);
		}
	}
	return found;
}

void fragment() {
	bool is_gear = UV2.x > 0.5;
	float tall = is_gear ? 0.68 : 0.74;                      // a figure's height, of the window's
	vec2 p = vec2((UV.x - 0.5) * UV2.y, 0.5 - UV.y) / tall;
	vec2 found = vec2(0.0);
	vec3 colour = ink;
	if (is_gear) {
		found = figure(p, gear > 0 ? gear % 10 : -1, fwidth(p.y));
		colour = gear_ink;
	} else {
		int cells = speed >= 10000 ? 5 : 4;
		float pitch = 0.68;
		float comma = 0.17;
		float wide = float(cells) * pitch + comma - 0.12;
		float fit = min(1.0, (UV2.y / tall - 0.24) / wide);  // five figures are set a little smaller
		p /= fit;
		float soft = fwidth(p.y);
		int rest = speed;
		for (int k = 0; k < cells; k++) {
			float x = wide * 0.5 - 0.28 - pitch * float(k) - (k >= 3 ? comma : 0.0);
			int n = (k == 0 || rest > 0) ? rest % 10 : -1;
			found = max(found, figure(p - vec2(x, 0.0), n, soft));
			rest /= 10;
		}
		// the thousands mark, a short slanted stroke at the foot
		float x = wide * 0.5 - 0.28 - pitch * 2.5 - comma * 0.5 - 0.04;
		vec2 q = p - vec2(x, -0.56);
		q.x -= q.y * 0.5;
		float mark = 1.0 - smoothstep(-soft, soft, max(abs(q.x) - 0.04, abs(q.y) - 0.1));
		found = max(found, vec2(speed >= 1000 ? mark : 0.0, mark));
	}
	float glow = found.x + 0.03 * found.y * (1.0 - found.x);
	ALBEDO = vec3(0.004, 0.005, 0.006) + colour * 0.02 * found.y;
	EMISSION = colour * glow * level * energy + vec3(0.008, 0.011, 0.014) * level;
	ROUGHNESS = 0.16;
	SPECULAR = 0.5;
}
