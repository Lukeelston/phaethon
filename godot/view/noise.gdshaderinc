// Periodic lattice noise for world-anchored surfaces under a floating origin: every lattice
// wraps at `per` cells, so a pattern built from cells that divide the surface's period repeats
// exactly and nothing seams when the period's offset wraps. Plus a helper that fades detail
// out once it gets finer than a couple of pixels (no shimmer at speed or in the headset).

// Project-authored integer lattice mixer. Prime coordinate weights and xor folds
// keep the pattern stable at large world coordinates; the result is in [0, 1).
float hash21(vec2 c) {
	uvec2 cell = uvec2(ivec2(c));
	uint n = (cell.x * 1013u) ^ (cell.y * 1619u) ^ 31337u;
	n = (n ^ (n >> 11u)) * 65521u;
	n = (n ^ (n >> 7u)) * 32771u;
	n ^= n >> 15u;
	return float(n & 16777215u) / 16777216.0;
}

// value noise on the lattice of cells `p` (cell units), wrapping every `per` cells
float pnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(mod(i, per));
	float b = hash21(mod(i + vec2(1.0, 0.0), per));
	float c = hash21(mod(i + vec2(0.0, 1.0), per));
	float d = hash21(mod(i + vec2(1.0, 1.0), per));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// four octaves, each twice as fine; per = the base lattice's period in cells
float pfbm(vec2 p, float per) {
	float s = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 4; k++) {
		s += amp * pnoise(p, per);
		p *= 2.0;
		per *= 2.0;
		amp *= 0.5;
	}
	return s / 0.9375;
}

// 1 while a feature of size `size` metres spans several pixels, fading to 0 as it shrinks
// below about two (fw: metres per pixel here)
float detail(float size, float fw) {
	return 1.0 - smoothstep(0.25, 0.6, fw / size);
}

vec3 srgb(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));   // max: pow() of a negative is NaN
}

// a line of half-width hw at distance d, antialiased; its average darkening is kept as it
// shrinks below a pixel (it greys out rather than flickering)
float aline(float d, float hw, float fw) {
	return (1.0 - smoothstep(hw, hw + fw, d)) * (2.0 * hw) / (2.0 * hw + fw);
}
