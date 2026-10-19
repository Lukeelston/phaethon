// The desert floor: the 60 km plane that rides under the pod (CraftView). `org` is the pod's
// sim position mod PERIOD (set every frame), so the pattern stays fixed in the world; every
// lattice here divides PERIOD, so it repeats exactly and never seams when the offset wraps.
//   far       sand in big patches: pale crust, darker desert pavement, a red tinge
//   middle    gravel and drift-sand mottling, and the scrub's shade over the sand
//   near      grain (the speed cue) and, on the range, the dry lake: a pale playa round the
//             runway, cracked into mud polygons
// Every detail fades to its average once it's finer than a couple of pixels.
shader_type spatial;
render_mode cull_back;

#include "res://view/noise.gdshaderinc"

const float PERIOD = 4096.0;
uniform vec2 org = vec2(0.0);       // the pod's (sim x, sim y) mod PERIOD
uniform float pod_y = 0.0;          // the pod's sim y (places the playa band)
uniform float playa = 0.0;          // 1 on the range: a dry lake round the runway
uniform float playa_half = 320.0;   // the lake's mean half-width (m); the shore wanders +/-240 m
uniform float verdant = 0.0;        // 1 on Eridanus: meadows, not sand
uniform float dawn_on = 0.0;        // 1 on the emergency run: the land the dawn has reached warms (view/dawn.gd)
uniform vec2 dawn_u = vec2(1.0, 0.0);   // the front's travel (render x, z)
uniform float dawn_f = 0.0;         // the front's line: dot(render xz, dawn_u) == dawn_f (against the floating origin)

varying vec2 lp;   // plane-local render xz

void vertex() {
	lp = VERTEX.xz;
}

// distance to the nearest cell border of a jittered grid, in cells (periodic)
float cracks(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = mod(i + g, per);
			vec2 o = vec2(hash21(c), hash21(c + vec2(1013.0, 7.0))) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return (d2 - d1) * 0.5;
}

void fragment() {
	vec2 p = vec2(org.x + lp.x, org.y - lp.y);   // sim metres, mod PERIOD
	float fw = length(fwidth(p));
	float sim_y = pod_y - lp.y;

	// far: sand in big patches
	float n1 = pfbm(p / 256.0, PERIOD / 256.0);
	float n2 = pnoise(p / 512.0, PERIOD / 512.0);
	vec3 sand = mix(vec3(0.62, 0.48, 0.34), vec3(0.86, 0.75, 0.58), smoothstep(0.25, 0.75, n1));
	sand = mix(sand, vec3(0.78, 0.52, 0.36), smoothstep(0.55, 0.8, n2) * 0.6);
	// middle: gravel / drift mottling
	float n3 = pfbm(p / 16.0, PERIOD / 16.0);
	sand *= 0.9 + 0.2 * n3;

	// the dry lake: pale, flat, with a wandering shore (RangeWorld.shore() is the same curve, so
	// the scrub starts where the lakebed ends)
	float side = sim_y < 0.0 ? 1.7 : 0.0;
	float shore = playa_half + 120.0 * sin(TAU * 3.0 * p.x / PERIOD + 1.0 + side)
		+ 70.0 * sin(TAU * 11.0 * p.x / PERIOD + 2.0 + side) + 35.0 * sin(TAU * 29.0 * p.x / PERIOD + side);
	shore += 30.0 * (pnoise(p / 32.0, PERIOD / 32.0) - 0.5);
	float lake = playa * (1.0 - smoothstep(shore - 40.0, shore + 40.0, abs(sim_y)));
	vec3 lakebed = vec3(0.80, 0.74, 0.64) * (0.92 + 0.16 * n3) * (0.96 + 0.08 * n1);
	vec3 col = mix(sand, lakebed, lake);

	// scrub on the sand: real bushes stand out to 1.6 km (RangeWorld); the ground just carries
	// their average shade, a little patchy
	float b = (1.0 - lake) * 0.12 * smoothstep(0.3, 0.7, n1 + 0.3 * n3);
	col = mix(col, vec3(0.40, 0.38, 0.26), b);

	// the verdant world (Eridanus): meadow greens in big patches, hay-dry fields and darker clover,
	// wildflowers dotted close by
	if (verdant > 0.0) {
		vec3 grass = mix(vec3(0.27, 0.38, 0.15), vec3(0.45, 0.55, 0.24), smoothstep(0.25, 0.75, n1));
		grass = mix(grass, vec3(0.60, 0.58, 0.30), smoothstep(0.6, 0.85, n2) * 0.7);
		grass = mix(grass, vec3(0.20, 0.30, 0.13), smoothstep(0.55, 0.9, 1.0 - n2) * 0.5 * smoothstep(0.4, 0.8, n3));
		grass *= 0.9 + 0.2 * n3;
		vec2 fc = mod(floor(p), PERIOD);
		float fl = step(0.965, hash21(fc + vec2(91.0, 3.0)));
		vec3 fcol = hash21(fc + vec2(7.0, 7.0)) < 0.5 ? vec3(0.95, 0.85, 0.25)
			: (hash21(fc + vec2(9.0, 1.0)) < 0.5 ? vec3(0.95, 0.95, 0.92) : vec3(0.62, 0.42, 0.85));
		float flower = fl * (1.0 - smoothstep(0.12, 0.12 + fw, length(fract(p) - 0.5))) * detail(0.4, fw);
		col = mix(col, mix(grass, fcol, flower), verdant);
	}

	// near: grain (the speed cue) and the lakebed's mud cracks
	float g = (pnoise(p / 1.0, PERIOD) - 0.5) * detail(1.0, fw) + (pnoise(p / 0.25, PERIOD * 4.0) - 0.5) * detail(0.25, fw) * 0.7;
	col *= 1.0 + 0.16 * g;
	if (lake > 0.01) {
		float cd = cracks(p / 2.0, PERIOD / 2.0) * 2.0;   // metres to the nearest crack
		float crack = aline(cd, 0.03, fw) * detail(0.5, fw) + 0.06 * (1.0 - detail(0.5, fw));
		col = mix(col, vec3(0.50, 0.44, 0.37), crack * lake);
	}
	// the dawn: behind its front the land is lit (a soft edge, a few hundred metres)
	if (dawn_on > 0.0) {
		float lit = smoothstep(-200.0, 400.0, dawn_f - dot(lp, dawn_u));
		col = mix(col, col * vec3(2.3, 1.95, 1.5) + vec3(0.05, 0.035, 0.01), lit * dawn_on);
	}
	ALBEDO = srgb(col);
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
