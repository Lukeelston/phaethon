// The start-up's checklist in motion (Luke: "animation to the startup sequence display"): what
// view/approach_projector.gd draws between the projector's glass and its type while the craft is
// being started (vr/startup_sequence.gd display()), and at no other time: the sheet is hidden, and
// nothing here is run, once the checklist is off the glass.
//   the rail      five segments along the foot, one a step: lit when it is behind you, breathing
//                 while you are on it, wiped full and flashed as it is ticked off
//   the bars      under the middle line, where the glass's own rule is: the bus coming up and the
//                 self-test, the binder's charge, each engine from its starter to its idle (a flare
//                 as it catches), the turbines spooling in the run-up
//   the pointer   in the gutter, in the arrow's place: aimed at the pod the control to work hangs
//                 in, nudging toward it on the beat with a ring going out from it; a ring that fills
//                 while there is only waiting to do; a tick as a step is ticked off
//   the sweeps    left to right across the whole glass as the bus comes up, across the top line as
//                 a step is ticked off, across the middle line when what it says changes
//   CLEARED       the rail lights along its length, the bars draw back to their ends (the air
//                 brakes stowing) and chevrons run out after them, a tick in the gutter
// Everything is driven by the sequence's own state and the projector's clock, not TIME, so a still
// taken twice is the same still. Nothing blinks faster than the beat (1.25 Hz; the alert 2.5).
// UV as the glass: p is in units of the glass's height, x across from its middle, y down.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, depth_draw_never;

uniform float scan : hint_range(0.0, 1.0) = 1.0;     // the glass's own reveal, top to bottom
uniform vec4 signal : source_color = vec4(0.737, 0.965, 0.98, 1.0);
uniform vec4 warm : source_color = vec4(1.0, 0.81, 0.47, 1.0);
uniform vec4 alarm : source_color = vec4(1.0, 0.61, 0.52, 1.0);
uniform float age = 10.0;          // s since the checklist came up: the bus's sweep
uniform float phase = 0.0;         // 0..1, 1.25 times a second: the beat
uniform float done = 0.0;          // the steps behind you, 0..5
uniform float tick = 1.0;          // 0..1: the last of them being ticked off (1: settled)
uniform vec2 bars = vec2(0.0);     // the two bars, 0..1
uniform bool pair = false;         // two bars with a gap between (the engines), or one across
uniform vec2 flare = vec2(0.0);    // an engine catching, 0..1
uniform float aim = 0.0;           // the control to work is overhead left (-1) or right (1); 0: none to work
uniform float ask = 0.0;           // 1 while a control is waited for
uniform float alert = 0.0;         // 1 while a refusal is on the glass
uniform float sweep = 1.0;         // 0..1: across the middle line (1: none)
uniform float cleared = -1.0;      // s since the brake came off (-1: it has not)

const float X0 = -1.42;            // the type's left edge, and its right
const float X1 = 1.90;
const float MID = 0.24;
const float TOP_ROW = -0.268;
const float MID_ROW = 0.0175;
const float FOOT_ROW = 0.303;
const float BAR_Y = 0.147;         // (on the glass's own rule)
const float BAR_H = 0.026;
const float RAIL_Y = 0.427;
const float RAIL_H = 0.015;
const float GAP = 0.05;

float box(vec2 p, vec2 centre, vec2 half_size) {
	vec2 d = abs(p - centre) - half_size;
	return max(d.x, d.y);
}

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	return length(p - a - clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0) * ab);
}

float row(float y, float centre, float half_height) {
	return 1.0 - smoothstep(half_height, half_height + 0.025, abs(y - centre));
}

void fragment() {
	vec2 p = (UV - 0.5) * vec2(4.123, 1.0);
	float aa = max(fwidth(p.y), 0.002);
	float beat = 0.5 - 0.5 * cos(phase * TAU);
	float within = smoothstep(X0 - 0.05, X0, p.x) * (1.0 - smoothstep(X1, X1 + 0.05, p.x));
	// the bus comes up: a bar of light across the glass, and everything here is lit behind it
	float bus_x = mix(-2.3, 2.3, clamp(age / 0.7, 0.0, 1.0));
	float born = age >= 0.7 ? 1.0 : 1.0 - smoothstep(bus_x - 0.03, bus_x, p.x);
	float bus = age >= 0.9 ? 0.0 : exp(-pow((p.x - bus_x) / 0.07, 2.0)) * (1.0 - smoothstep(0.6, 0.9, age));

	float ink = 0.0;        // in the signal's colour
	float hot = 0.0;        // how far toward the warm colour
	float red = 0.0;        // ... and the alarm's
	float light = 0.0;      // soft light, as the glass's own flare

	// ---- the rail ----
	float seg_w = (X1 - X0 - 4.0 * GAP) / 5.0;
	bool is_clear = cleared >= 0.0;
	for (int i = 0; i < 5; i++) {
		float left = X0 + (seg_w + GAP) * float(i);
		float d = box(p, vec2(left + seg_w * 0.5, RAIL_Y), vec2(seg_w * 0.5, RAIL_H));
		float inside = 1.0 - smoothstep(-aa, aa, d);
		float edge = inside * smoothstep(-0.007 - aa, -0.007, d);
		float on = smoothstep(0.0, 0.12, age - 0.2 - 0.09 * float(i));     // each in its turn as the bus comes up
		float fill = 0.0;
		if (is_clear) {                                                     // all five, lit along the rail
			fill = smoothstep(0.0, 0.1, cleared - 0.07 * float(i));
			light += inside * fill * (1.0 - smoothstep(0.1, 0.5, cleared - 0.07 * float(i))) * 0.7;
		} else if (float(i) < done - 0.5) {
			fill = 1.0;
			if (float(i) > done - 1.5 && tick < 1.0) {                     // being ticked off: wiped full, and a flash
				fill = 1.0 - smoothstep(-aa, aa, (p.x - left) / seg_w - smoothstep(0.0, 0.5, tick));
				light += inside * fill * (1.0 - smoothstep(0.3, 1.0, tick)) * 0.8;
			}
		} else if (float(i) < done + 0.5) {
			fill = 0.16 + 0.44 * beat;                                      // the step you are on
		}
		ink = max(ink, on * max(edge * 0.55, inside * fill));
	}

	// ---- the bars ----
	float gap = pair || is_clear ? 0.045 : 0.0;
	for (int s = 0; s < 2; s++) {
		float a = s == 0 ? X0 : MID + gap;
		float b = s == 0 ? MID - gap : X1;
		float d = box(p, vec2((a + b) * 0.5, BAR_Y), vec2((b - a) * 0.5, BAR_H));
		float inside = 1.0 - smoothstep(-aa, aa, d);
		float edge = inside * smoothstep(-0.006 - aa, -0.006, d);
		float f = s == 0 ? bars.x : bars.y;
		float head = a + (b - a) * f;
		float fill = 1.0 - smoothstep(-aa, aa, p.x - head);
		float lead = f > 0.002 && f < 0.998 ? exp(-abs(p.x - head) / 0.05) : 0.0;
		if (is_clear) {                                                     // drawn back to its end: the air brakes stowing
			float k = smoothstep(0.1, 0.9, cleared);
			float outer = s == 0 ? a + (b - a) * (1.0 - k) : a + (b - a) * k;
			fill = s == 0 ? 1.0 - smoothstep(-aa, aa, p.x - outer) : smoothstep(-aa, aa, p.x - outer);
			lead = 0.0;
			// chevrons run out after it, two a second past any one place
			float out_d = abs(p.x - MID);
			float gone = s == 0 ? smoothstep(-aa, aa, p.x - outer) : 1.0 - smoothstep(-aa, aa, p.x - outer);
			float stripe = abs(fract((out_d + abs(p.y - BAR_Y) * 1.5 - cleared * 0.44) / 0.22) - 0.5);
			float chevron = (1.0 - smoothstep(0.13, 0.13 + aa * 4.0, stripe)) * gone * (1.0 - smoothstep(BAR_H * 1.5, BAR_H * 1.5 + aa, abs(p.y - BAR_Y)));
			ink = max(ink, chevron * 0.8 * step(a, p.x) * step(p.x, b) * smoothstep(0.15, 0.4, cleared) * (1.0 - smoothstep(2.2, 2.8, cleared)));
		}
		float fl = s == 0 ? flare.x : flare.y;
		ink = max(ink, born * max(edge * 0.5, inside * fill * 0.92));
		light += born * inside * (lead * 0.6 + fl * 0.6);
		hot = max(hot, inside * fl);
	}

	// ---- the line you are on, and the sweeps ----
	light += ask * within * row(p.y, MID_ROW, 0.085) * (0.05 + 0.11 * beat);
	if (sweep < 1.0) {
		float x = mix(X0 - 0.25, X1 + 0.25, sweep);
		light += within * row(p.y, MID_ROW, 0.085) * exp(-pow((p.x - x) / 0.08, 2.0)) * 0.7 * sin(sweep * PI);
	}
	if (tick < 0.7 && !is_clear && age > 1.0) {
		float x = mix(X0 - 0.25, X1 + 0.25, tick / 0.7);
		light += within * row(p.y, TOP_ROW, 0.11) * exp(-pow((p.x - x) / 0.13, 2.0)) * 0.7;
	}
	if (is_clear) {
		light += (1.0 - smoothstep(0.0, 0.3, cleared)) * 0.3;              // one flash, as the brake lets go
	}
	light += bus * 0.55;
	// a refusal: a bar under its words
	float refused = alert * within * (1.0 - smoothstep(0.006, 0.006 + aa, abs(p.y - FOOT_ROW - 0.092))) * (1.0 - smoothstep(0.2, 0.3, p.x));
	red = refused * (0.45 + 0.55 * (0.5 - 0.5 * cos(phase * 2.0 * TAU)));

	// ---- the pointer, in the gutter ----
	vec2 q = vec2(p.x + 1.79, -p.y);
	float glyph = 0.0;
	bool ticked = tick < 1.0 && age > 1.0;
	if (is_clear || ticked) {
		float d = min(segment(q, vec2(-0.105, -0.005), vec2(-0.035, -0.085)), segment(q, vec2(-0.035, -0.085), vec2(0.115, 0.095)));
		glyph = (1.0 - smoothstep(0.02, 0.028 + aa, d)) * (is_clear ? smoothstep(0.05, 0.3, cleared) : 1.0 - smoothstep(0.8, 1.0, tick));
	} else if (aim != 0.0) {
		vec2 dir = normalize(vec2(aim, 1.0));
		vec2 side = vec2(dir.y, -dir.x);
		vec2 c = q - dir * 0.03 * beat * ask;                                // it nudges toward the control
		vec2 tip = dir * 0.13;
		float d = min(segment(c, -dir * 0.13, tip), min(segment(c, tip, tip - dir * 0.085 + side * 0.085), segment(c, tip, tip - dir * 0.085 - side * 0.085)));
		glyph = (1.0 - smoothstep(0.015, 0.023 + aa, d)) * (1.0 - 0.3 * ask * (1.0 - beat));
		float ring = abs(length(q) - (0.15 + 0.07 * phase));
		glyph = max(glyph, ask * (1.0 - smoothstep(0.006, 0.012 + aa, ring)) * (1.0 - phase) * 0.6);
	} else {
		float r = length(q);
		float ring = 1.0 - smoothstep(0.011, 0.016 + aa, abs(r - 0.12));
		float turn = fract(atan(q.x, q.y) / TAU);                            // from twelve o'clock, clockwise
		float amount = (bars.x + bars.y) * 0.5;
		glyph = ring * (turn <= amount ? 1.0 : 0.3);
	}
	ink = max(ink, born * glyph);

	float cover = max(max(ink, red), clamp(light, 0.0, 1.0) * 0.8);
	vec2 rim = abs(p) - vec2(2.055, 0.492);                                // (the glass's own outline)
	cover *= 1.0 - smoothstep(-aa, aa, max(max(rim.x, rim.y), (rim.x + rim.y + 0.095) * 0.7071) + 0.02);
	float reveal = 1.0 - smoothstep(scan - aa, scan + aa, UV.y);
	if (cover * reveal < 0.004) {
		discard;
	}
	vec3 tint = mix(signal.rgb, warm.rgb, clamp(hot, 0.0, 1.0));
	ALBEDO = mix(tint * (1.0 + 0.25 * clamp(light, 0.0, 1.0)), alarm.rgb, clamp(red, 0.0, 1.0));
	ALPHA = cover * reveal;
}
