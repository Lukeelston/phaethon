// Water for Eridanus' river and lake: a flat sheet that takes the sky. Fresnel mixes a deep
// green-blue body toward the sky's reflection (from the environment: roughness near 0), small
// wind ripples (two scrolling noise normals) break up the reflection, and the sun leaves a glitter
// path. The river's current (`flow`, m/s along +UV.x) drags its ripples downstream. World-anchored
// like the ground: `org` is the pod's sim position mod PERIOD; ripples are fine detail and fade
// to the calm average far off.
shader_type spatial;
render_mode cull_disabled;

#include "res://view/noise.gdshaderinc"

const float PERIOD = 4096.0;
uniform vec2 org = vec2(0.0);
uniform float flow = 0.0;
uniform vec3 deep = vec3(0.10, 0.22, 0.24);      // sRGB
uniform vec3 shallow = vec3(0.20, 0.36, 0.34);

varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = vec2(org.x + wp.x, org.y - wp.y);
	float fw = length(fwidth(p));
	float t = TIME;
	vec2 drift = vec2(flow * t, 0.0);
	// two layers of ripples, their slopes as a normal perturbation
	float e = 0.35;
	vec2 q1 = (p + drift) / 3.0 + vec2(t * 0.05, t * 0.03);
	vec2 q2 = (p + drift * 0.6) / 1.2 - vec2(t * 0.08, -t * 0.05);
	float h0 = pnoise(q1, PERIOD / 3.0) + 0.5 * pnoise(q2, PERIOD / 1.2);
	float hx = pnoise(q1 + vec2(e, 0.0), PERIOD / 3.0) + 0.5 * pnoise(q2 + vec2(e, 0.0), PERIOD / 1.2);
	float hz = pnoise(q1 + vec2(0.0, e), PERIOD / 3.0) + 0.5 * pnoise(q2 + vec2(0.0, e), PERIOD / 1.2);
	float k = 0.35 * detail(1.5, fw);
	vec3 n_world = normalize(vec3(-(hx - h0) * k / e, 1.0, -(hz - h0) * k / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 body = mix(srgb(shallow), srgb(deep), smoothstep(0.2, 0.8, facing));
	ALBEDO = body;
	METALLIC = 0.0;
	ROUGHNESS = 0.04 + 0.08 * (1.0 - detail(1.5, fw));
	SPECULAR = 0.7;
}
