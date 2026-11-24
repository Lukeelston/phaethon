// The Basilisk gun's dust and smoke (view/gunnery.gd): soft blended puffs turned to the eye, lit a little
// from above. The instance colour carries the puff's colour and how much of it is left (alpha).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

varying vec2 q;
varying vec4 tint;

void vertex() {
	tint = COLOR;
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	q = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(q);
	// A lumpy edge, so a puff is not a disc.
	float ang = atan(q.y, q.x);
	float edge = 0.82 + 0.1 * sin(ang * 5.0 + tint.r * 40.0) + 0.06 * sin(ang * 9.0 - tint.g * 31.0);
	float a = 1.0 - smoothstep(edge * 0.35, edge, r);   // (edges in order: reversed, smoothstep is undefined)
	float lit = 0.8 + 0.35 * clamp(-q.y, -1.0, 1.0);   // (UV.y runs down the quad: its top is lit)
	ALBEDO = tint.rgb * lit;
	ALPHA = a * tint.a;
}
