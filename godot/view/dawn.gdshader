// The dawn's wall (view/dawn.gd): an additive curtain of light standing on the front's line,
// hottest along the ground and fading up its 3 miles, its far ends fading out. Unlit and
// unfogged, so it reads from across the valley. UVs are clamped first: MSAA extrapolates them
// past the quad's edge, and the fades take powers of them.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 col = vec3(1.0, 0.80, 0.52);
uniform float intensity = 1.0;   // the wall's brightness (dawn.gd eases it in as the front nears)

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	float up = 1.0 - uv.y;   // 0 at the ground, 1 at the top
	float ends = smoothstep(0.0, 0.2, uv.x) * smoothstep(0.0, 0.2, 1.0 - uv.x);
	float body = pow(clamp(1.0 - up, 0.0, 1.0), 2.2) * 1.3;
	float edge = exp(-up * 40.0) * 3.0;   // the hot line where the light meets the ground
	// shafts: the light standing up in streaks, slowly drifting, so it reads as a wall, not a haze
	float shafts = 0.65 + 0.2 * sin(uv.x * 2300.0 + TIME * 0.4) + 0.15 * sin(uv.x * 6100.0 - TIME * 0.9);
	ALBEDO = col * (body * shafts + edge) * ends * intensity;
}
