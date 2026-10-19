// Periodic lattice noise for world-anchored surfaces under a floating origin: every lattice
// wraps at `per` cells, so a pattern built from cells that divide the surface's period repeats
// exactly and nothing seams when the period's offset wraps. Plus a helper that fades detail
// out once it gets finer than a couple of pixels (no shimmer at speed or in the headset).

// integer hash of a lattice cell (integer-valued coords, exact to 2^24): stays well mixed
// even a million cells out, where float-fract hashes fall apart
float hash21(vec2 c) {
	uvec2 q = uvec2(ivec2(c)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * 2.3283064e-10;
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
	return pow(c, vec3(2.2));
}

// a line of half-width hw at distance d, antialiased; its average darkening is kept as it
// shrinks below a pixel (it greys out rather than flickering)
float aline(float d, float hw, float fw) {
	return (1.0 - smoothstep(hw, hw + fw, d)) * (2.0 * hw) / (2.0 * hw + fw);
}
