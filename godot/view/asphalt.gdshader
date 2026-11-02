// Asphalt for the range runway, the highway and the GP. UV is (metres along, metres across from
// the centreline), baked into the mesh: along wraps at `period` (a multiple of the range's
// 2 km chunks; the GP's along runs 0..lap length, its one seam under the start line).
//   aggregate     4 cm stones, light and dark
//   wear          mottling and big sun-bleached / fresher patches
//   rubber        dark streaks laid down the lanes, a little glossier
//   joints        a sealed transverse joint every 25 m (a rate cue at speed) and paving seams
//                 along every 6 m
//   cracks        meandering tar-sealed cracks, black and shiny
//   patches       rectangles of fresh, darker repair
// Every detail fades to its average once it's finer than a couple of pixels.
shader_type spatial;
render_mode cull_disabled;

#include "res://view/noise.gdshaderinc"

uniform float period = 64000.0;
uniform vec3 base = vec3(0.30, 0.295, 0.29);   // sRGB (converted once, below)
uniform float lane_half = 20.0;    // the rubber lies within this of the centreline
uniform float joint_every = 25.0;
uniform float spec = 0.4;           // the sheen toward the suns (the Network's: 0.2)

varying vec2 tp;

void vertex() {
	tp = UV;
}

void fragment() {
	vec2 p = tp;
	float fw = length(fwidth(p));
	vec3 col = base;
	float rough = 0.88;

	// aggregate and wear
	float agg = (hash21(mod(floor(p / 0.04), period / 0.04)) - 0.5) * detail(0.04, fw);
	float fine = (pnoise(p / 0.25, period / 0.25) - 0.5) * detail(0.25, fw);
	float mott = pfbm(p / 4.0, period / 4.0) - 0.5;
	float bleach = pfbm(p / 40.0, period / 40.0) - 0.5;
	col *= 1.0 + agg * 0.3 + fine * 0.14 + mott * 0.16 + bleach * 0.26;

	// rubber: long thin streaks down the lanes
	float lane = 1.0 - smoothstep(lane_half * 0.5, lane_half, abs(p.y));
	float streak = smoothstep(0.5, 0.85, pnoise(vec2(p.x / 25.0, p.y / 0.75), period / 25.0));
	float rub = mix(0.28, streak, detail(0.75, fw)) * lane;
	col *= 1.0 - 0.28 * rub;
	rough = mix(rough, 0.62, rub);

	// repair patches: some 50 x 12 m cells get one fresh rectangle
	vec2 pc = floor(vec2(p.x / 50.0, p.y / 12.0));
	vec2 pcm = mod(pc, vec2(period / 50.0, 4096.0));
	if (hash21(pcm + vec2(3.0, 0.0)) < 0.14) {
		vec2 lo = pc * vec2(50.0, 12.0) + vec2(4.0 + 20.0 * hash21(pcm + vec2(0.0, 11.0)), 1.0 + 4.0 * hash21(pcm + vec2(0.0, 13.0)));
		vec2 sz = vec2(4.0 + 12.0 * hash21(pcm + vec2(0.0, 17.0)), 2.0 + 5.0 * hash21(pcm + vec2(0.0, 19.0)));
		vec2 q = abs(p - (lo + sz * 0.5)) - sz * 0.5;
		float inside = 1.0 - smoothstep(0.0, fw, max(q.x, q.y));
		col = mix(col, base * 0.72 * (1.0 + agg * 0.2), inside);
		col *= 1.0 - 0.5 * aline(abs(max(q.x, q.y)), 0.03, fw);   // its sealed edge
	}

	// joints across every joint_every m, seams along every 6 m
	float dj = abs(fract(p.x / joint_every + 0.5) - 0.5) * joint_every;
	float ds = abs(fract(p.y / 6.0 + 0.5) - 0.5) * 6.0;
	col *= 1.0 - 0.55 * aline(dj, 0.03, fw) - 0.18 * aline(ds, 0.015, fw);

	// cracks: some 16 x 12 m cells get one meandering crack across part of the cell, tar-sealed
	vec2 cc = floor(vec2(p.x / 16.0, p.y / 12.0));
	vec2 ccm = mod(cc, vec2(period / 16.0, 4096.0));
	float h1 = hash21(ccm + vec2(9.0, 1.0));
	if (h1 < 0.4) {
		float h2 = hash21(ccm + vec2(9.0, 2.0));
		float h3 = hash21(ccm + vec2(9.0, 3.0));
		float cx = cc.x * 16.0 + 4.0 + 8.0 * h2 + 0.8 * sin(p.y * 0.9 + 6.3 * h3) + 0.2 * sin(p.y * 3.7 + 2.0 * h2);
		float y0 = cc.y * 12.0 + 12.0 * h3 * 0.5;
		float span = 1.0 - smoothstep(0.0, 0.3, max(y0 - p.y, p.y - (y0 + 3.0 + 6.0 * h2)));
		float tar = aline(abs(p.x - cx), 0.018, fw) * span * 0.75;
		col = mix(col, vec3(0.05, 0.05, 0.055), tar);
		rough = mix(rough, 0.35, tar * detail(0.07, fw));
	}

	ALBEDO = srgb(col);
	ROUGHNESS = rough;
	SPECULAR = spec;
}
