// The night still over the twilight (the emergency run, view/craft_view.gd): a dome of stars
// 110 km out, additive over the sky, thinning toward the horizon and gone on the dawn's side as its
// glow grows. Stars sit in a jittered grid of directions, never smaller than about a pixel, and
// twinkle a little. Every root and power takes a clamped argument: MSAA extrapolates edge pixels.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, fog_disabled, shadows_disabled;

uniform vec3 dawn_dir = vec3(1.0, 0.0, 0.0);   // toward the dawn (render axes)
uniform float fade = 1.0;                       // 1 deep twilight, 0 gone (the front near)
uniform float cells = 220.0;                    // grid cells per radian
uniform float density = 0.06;                   // share of cells with a star

varying vec3 dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 p = d * cells;
	vec3 c = floor(p);
	float h = hash13(c);
	float lit = 0.0;
	if (h < density) {
		vec3 o = vec3(hash13(c + 17.0), hash13(c + 41.0), hash13(c + 73.0)) * 0.6 + 0.2;
		float r = length(fract(p) - o);
		float px = max(length(fwidth(p)), 1e-4);          // a pixel, in cell units
		float size = max(0.06, 0.9 * px);
		float bright = pow(clamp(h / density, 0.0, 1.0), 3.0);   // a few bright, most faint
		float tw = 0.85 + 0.15 * sin(TIME * (2.0 + 5.0 * hash13(c + 5.0)) + h * 60.0);
		lit = smoothstep(size, 0.0, r) * (0.25 + 1.6 * bright) * tw * clamp(size / max(0.9 * px, 1e-4), 0.0, 1.0);
	}
	float up = smoothstep(0.02, 0.25, d.y);                  // thinning into the haze at the horizon
	float away = smoothstep(0.55, -0.35, dot(d, normalize(dawn_dir)));   // none on the dawn's side
	ALBEDO = vec3(0.85, 0.9, 1.0) * lit * up * mix(0.35, 1.0, away) * fade;
}
