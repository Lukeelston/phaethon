// The Basilisk gun's light (view/gunnery.gd): bolts, muzzle flashes, strikes and fireballs, added.
// One batch each; the instance colour is the light (it runs past 1 for a hot core).
//   streak = false: a soft disc turned to the eye, its size the instance's scale
//   streak = true:  a ribbon along the instance's Z (its head at -Z), across its X, turned to the eye about its line
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform bool streak = false;

varying vec2 q;
varying vec4 tint;

void vertex() {
	tint = COLOR;
	if (!streak) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	}
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float a;
	if (streak) {
		float across = abs(q.x);
		float along = q.y * 0.5 + 0.5;               // 0 at the head .. 1 at the tail
		float head = smoothstep(0.0, 0.06, along);
		float tail = pow(1.0 - along, 1.4);
		a = pow(max(0.0, 1.0 - across), 2.0) * head * tail;
	} else {
		float r = length(q);
		a = pow(max(0.0, 1.0 - r), 2.2) + 0.6 * pow(max(0.0, 1.0 - r * 2.2), 3.0);
	}
	ALBEDO = tint.rgb * a;
	ALPHA = clamp(a * tint.a, 0.0, 1.0);
}
