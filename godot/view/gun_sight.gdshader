// The Basilisk's sight (view/gunnery.gd): drawn where the gaze lands, at that distance (so each eye
// sees it on what it is on), at a fixed angular size, over everything.
//   state 0 searching (amber ring), 1 a vehicle under it (red: four corner brackets close round it, the
//         middle left clear so the vehicle shows through; the quad is then sized to the vehicle),
//         2 out of the gun's reach or its line fouled by the craft (grey, crossed), 3 coming up (dim, ticks turning)
//   pipper: where the gun's bore is now, as an offset on the quad (-1..1), and how near it is to the aim
// Fixed guns (view/weapons/fixed_guns_mount.gd) draw two of these: their boresight ring is this same sight (shape 0)
// small, out along the bore; their lead pip (shape 1) is a diamond round a dot where the bolts are laid on a raider,
// closing as the lock builds: state 1 red, 2 grey (the guns hot).
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform int shape = 0;          // 0 the sight above; 1 a lead pip
uniform int state = 0;
uniform float power = 1.0;
uniform vec2 pipper = vec2(0.0);
uniform float pipper_on = 0.0;
uniform float heat = 0.0;       // the gun's coils: the ring brightens as it fires
uniform float lock = 0.0;       // 0..1, the diamond closing as a vehicle holds under the sight
uniform float spin = 0.0;

varying vec2 q;

void vertex() {
	// Face the eye: the quad's own axes are laid in the view's plane; its scale is the instance's.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	q = UV * 2.0 - 1.0;
}

float band(float x, float c, float w) {
	float aa = fwidth(x) * 1.2;
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - c));
}

void fragment() {
	float r = length(q);
	float a = atan(q.y, q.x);
	vec3 amber = vec3(1.0, 0.56, 0.12);
	vec3 red = vec3(1.0, 0.16, 0.08);
	vec3 grey = vec3(0.55, 0.58, 0.62);
	vec3 col = state == 1 ? red : (state == 2 ? grey : amber);
	float m = 0.0;
	if (shape == 1) {
		// A lead pip: a diamond round a dot, closing as the lock builds.
		float k = mix(0.86, 0.62, lock);
		m += band(abs(q.x) + abs(q.y), k, 0.05) * 1.2;
		m += 1.0 - smoothstep(0.09, 0.14, r);
	} else if (state == 1) {
		// A vehicle: four corner brackets close in round it as the lock builds, and nothing over it.
		float k = mix(0.98, 0.78, lock);
		vec2 aq = abs(q);
		float corner = step(0.5 * k, max(aq.x, aq.y)) * step(min(aq.x, aq.y), k) * step(k * 0.55, min(aq.x, aq.y));
		float edge = max(band(aq.x, k, 0.02) * step(aq.y, k + 0.02), band(aq.y, k, 0.02) * step(aq.x, k + 0.02));
		m += edge * corner * 1.3;
	} else {
		// The ring, broken at the four ticks.
		float gaps = smoothstep(0.10, 0.16, abs(sin(2.0 * (a - spin))));
		m += band(r, 0.62, 0.024) * (state == 3 ? 0.5 + 0.5 * gaps : mix(1.0, gaps, 0.85));
		// Four ticks in from the ring.
		float ticks = band(r, 0.47, 0.11) * (1.0 - smoothstep(0.03, 0.05, abs(sin(2.0 * (a - spin))) * r));
		m += ticks;
		// The centre dot.
		m += 1.0 - smoothstep(0.03, 0.05, r);
	}
	// Fouled or out of reach: a cross through it.
	if (state == 2) {
		m += band(abs(q.x) - abs(q.y), 0.0, 0.03) * step(r, 0.5) * 0.9;
	}
	// The gun's own pipper: a small square where the bore points.
	vec2 pq = abs(q - pipper);
	float sq = max(pq.x, pq.y);
	m += band(sq, 0.075, 0.016) * pipper_on;
	float glow = (1.0 + 0.8 * heat) * (state == 3 ? 0.45 : 1.0);
	ALBEDO = col * m * glow * power * 1.25;
	ALPHA = 1.0;
}
