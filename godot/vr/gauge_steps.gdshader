// The start-up's five steps on the status strip (vr/gauge_cluster.gd), under the checklist's two
// lines of words: a rail of five cells, read left to right as the glass's rail is. A step behind
// you is filled green with a tick cut out of it; the step in hand is an amber outline that breathes
// with the panel's lamps and fills from the left as it goes (the self-test, the binder's charge,
// each engine in its own half while they start, the turbines' spool); the steps to come are dim
// outlines. A refused control turns the step in hand red for as long as the glass says why.
// UV runs 0-1 over the rail.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform float aspect = 24.0;        // the rail's width over its height
uniform float done = 0.0;           // how many of the five steps are behind you (5: cleared)
uniform vec2 bars = vec2(0.0);      // the step in hand, 0..1: one amount end to end (left, then right), or ...
uniform float pair = 0.0;           // ... 1: the two engines, the left in the cell's left half
uniform float alert = 0.0;          // 1: a control was refused
uniform vec3 ink : source_color = vec3(0.62, 0.62, 0.58);
uniform vec3 good : source_color = vec3(0.3, 1.0, 0.45);
uniform vec3 asked : source_color = vec3(1.0, 0.62, 0.12);
uniform vec3 bad : source_color = vec3(1.0, 0.25, 0.15);

float box(vec2 p, vec2 half, float r) {
	vec2 q = abs(p) - half + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float stroke(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

void fragment() {
	// in units of half the rail's height: x across from the middle, y up
	vec2 p = vec2((UV.x - 0.5) * 2.0 * aspect, (0.5 - UV.y) * 2.0);
	float soft = fwidth(p.y);
	float pitch = 2.0 * aspect / 5.0;                             // a cell and the gap after it
	float k = clamp(floor((p.x + aspect) / pitch), 0.0, 4.0);
	vec2 q = vec2(p.x + aspect - (k + 0.5) * pitch, p.y);          // from the cell's middle
	vec2 half = vec2(pitch * 0.5 - 0.55, 0.84);
	float d = box(q, half, 0.34);
	float inside = 1.0 - smoothstep(-soft, 0.0, d);
	float edge = inside * smoothstep(-0.2 - soft, -0.2, d);        // a line just inside the cell's edge
	float behind = step(k + 0.5, done);
	float in_hand = step(k - 0.5, done) * (1.0 - behind);
	// behind: filled, a tick cut out of it
	float tick = min(stroke(q, vec2(-0.62, -0.02), vec2(-0.18, -0.44)), stroke(q, vec2(-0.18, -0.44), vec2(0.66, 0.46)));
	float cut = 1.0 - smoothstep(0.13, 0.13 + soft, tick);
	// in hand: the outline breathing (1.3 Hz, as the panel's lamps), the cell filling from the left
	float breath = 0.55 + 0.45 * sin(TIME * 8.168);
	float flash = step(0.0, sin(TIME * 25.0));
	float along = clamp((q.x + half.x) / (2.0 * half.x), 0.0, 1.0);
	float whole = step(along, 0.5 * (bars.x + bars.y));
	float halves = along < 0.5 ? step(along * 2.0, bars.x) : step(along * 2.0 - 1.0, bars.y);
	halves *= step(0.012, abs(along - 0.5));                      // (a hair between the two engines)
	float filled = mix(whole, halves, pair) * inside;
	vec3 live = mix(asked, bad, alert);
	float lit_behind = inside * (1.0 - cut) * 0.92;
	float lit_hand = max(edge * mix(breath, 0.4 + 0.6 * flash, alert), filled * 0.6);
	float lit_ahead = edge * 0.45;
	float cover = mix(mix(lit_ahead, lit_hand, in_hand), lit_behind, behind);
	if (cover < 0.01) {
		discard;
	}
	ALBEDO = mix(mix(ink, live, in_hand), good, behind);
	ALPHA = cover;
}
