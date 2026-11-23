// The map on the windscreen (Luke: "add a switch to the map that projects it via the hud"). The map
// pod's own drawing (vr/minimap_panel.gd: triangles on its flat screen, a colour at every vertex) is
// drawn a second time by this, and each vertex is moved from the pod's screen to the place in the
// roof's swept glass where the seated eye is to find it: lines of light on the glass, nothing behind
// them. view/minimap_glass.gd works those places out once, on a grid across the drawing, and hands
// them over as a small picture (`lies`); a vertex takes its place from the four nearest.
//   lies    a point of the canopy's space at each node of the grid (rgb = x, y, z), the drawing's
//           lower left corner first
//   panel   the drawing's width and height on the pod's screen (its own units)
//   level   0 dark .. 1 lit (the switch coming on, the night's dimming)
//   gain    how much brighter than the pod's own inks: the glass has the day behind it
//   lit     the least any ink shines: a scheme's dark inks (PAPER's, made for a pale screen) are lifted
//           to this in their own hue, for glass can only be lit, and a dark craft on it at night is no craft
// Things in front of the glass hide it, as they hide the glass.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D lies : filter_nearest, repeat_disable;
uniform vec2 panel = vec2(0.22, 0.22);
uniform float level = 1.0;
uniform float gain = 1.0;
uniform float lit = 0.75;

void vertex() {
	float peak = max(COLOR.r, max(COLOR.g, COLOR.b));
	COLOR.rgb *= max(peak, lit) / max(peak, 0.001);
	ivec2 nodes = textureSize(lies, 0);
	vec2 at = clamp(VERTEX.xy / panel + 0.5, vec2(0.0), vec2(1.0)) * vec2(nodes - ivec2(1));
	ivec2 cell = min(ivec2(floor(at)), nodes - ivec2(2));
	vec2 f = at - vec2(cell);
	vec3 a = texelFetch(lies, cell, 0).rgb;
	vec3 b = texelFetch(lies, cell + ivec2(1, 0), 0).rgb;
	vec3 c = texelFetch(lies, cell + ivec2(0, 1), 0).rgb;
	vec3 d = texelFetch(lies, cell + ivec2(1, 1), 0).rgb;
	VERTEX = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	ALBEDO = COLOR.rgb * gain;
	ALPHA = COLOR.a * level;
}
