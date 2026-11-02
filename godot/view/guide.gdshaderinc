// The speed guide's sums on the GPU, for the beacons, light columns and braking boards: the same
// model and thresholds as view/speed_guide.gd, which sets these uniforms every frame. How close
// you'd cut a point ahead: the share of full braking it takes to be down to its safe speed by the
// time you get there (green under 0.6, amber up to 1.0, red past it: full brakes won't make it).
uniform float guide_on = 0.0;                           // 1 once the guide is running
uniform float v_now = 0.0;                              // the craft's speed, m/s
uniform float s_now = 0.0;                              // how far along the lap it is, m
uniform float lap = 1.0;                                // the lap, m
uniform vec4 brake = vec4(0.0, 1e-4, 1e-4, 1e-4);       // live handling: c0, c2 flaps shut, half, full
uniform vec4 brake_sf = vec4(0.0, 1e-3, 1e-3, 1e-3);    // STARFIGHTER's (below its engage speed)
uniform vec3 speeds = vec3(670.6, 1117.6, 558.8);       // front flaps from, to; STARFIGHTER engages below

const float GUIDE_AMBER_AT = 0.6;
const float GUIDE_RED_AT = 1.0;
const float GUIDE_REACH = 30000.0;
const float GUIDE_HEADROOM = 1.05;
const float GUIDE_NEAR = 100.0;
const vec3 GUIDE_GREEN = vec3(0.15, 0.95, 0.3);
const vec3 GUIDE_AMBER = vec3(1.0, 0.65, 0.05);
const vec3 GUIDE_RED = vec3(1.0, 0.08, 0.05);
const vec3 GUIDE_IDLE = vec3(0.85, 0.9, 1.0);           // behind you, or out of reach

float guide_seg(float va, float vb, float c0, float c2) {
	return va > vb ? log((c0 + c2 * va * va) / (c0 + c2 * vb * vb)) / (2.0 * c2) : 0.0;
}

// Full brakes from v down to vt, m: the live handling (front flaps full, half, shut) down to
// STARFIGHTER's engage speed, then STARFIGHTER's.
float guide_stop(float v, float vt) {
	if (v <= vt) {
		return 0.0;
	}
	float d = 0.0;
	float a = v;
	float lo = max(vt, speeds.z);
	if (a > speeds.y) {
		float e = max(lo, speeds.y);
		d += guide_seg(a, e, brake.x, brake.w);
		a = e;
	}
	if (a > vt && a > speeds.x) {
		float e = max(lo, speeds.x);
		d += guide_seg(a, e, brake.x, brake.z);
		a = e;
	}
	if (a > vt && a > speeds.z) {
		d += guide_seg(a, lo, brake.x, brake.y);
		a = lo;
	}
	if (a > vt) {
		d += guide_seg(a, vt, brake_sf.x, brake_sf.y);
	}
	return d;
}

// The cut for the point `s_at` m along the lap with safe speed `v_at`: -1 behind or out of reach.
float guide_cut(float s_at, float v_at) {
	float d = mod(s_at - s_now + lap, lap);
	if (d > GUIDE_REACH) {
		return -1.0;
	}
	return guide_stop(v_now, v_at * GUIDE_HEADROOM) / max(d, GUIDE_NEAR);
}

vec3 guide_color(float q) {
	if (q < 0.0) {
		return GUIDE_IDLE;
	}
	return mix(mix(GUIDE_GREEN, GUIDE_AMBER, smoothstep(GUIDE_AMBER_AT - 0.1, GUIDE_AMBER_AT + 0.1, q)),
		GUIDE_RED, smoothstep(GUIDE_RED_AT - 0.08, GUIDE_RED_AT, q));
}
