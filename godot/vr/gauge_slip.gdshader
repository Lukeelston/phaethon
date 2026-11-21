// The g-meter's slip bar on the status strip (vr/gauge_cluster.gd): a ball in a tube, drawn on the
// strip's glass beside the figure. The ball goes where the pilot is thrown, so in a left turn it
// runs to the right; how far is the turn's load on the dial's own scale of decades, and the marks
// along the tube are 1 g, 10 and (its ends) 100 either way. UV runs 0-1 over the bar.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

uniform float aspect = 17.0;        // the bar's width over its height
uniform float ball = 0.0;           // -1 at the left end .. 1 at the right
uniform float hard = 0.0;           // 1 in a hard turn: the ball goes orange
uniform vec3 ink : source_color = vec3(0.62, 0.62, 0.58);
uniform vec3 lit : source_color = vec3(0.95, 0.95, 0.9);
uniform vec3 hot : source_color = vec3(1.0, 0.45, 0.1);

const float MARKS[2] = {0.1502, 0.5196};    // 1 g and 10 g on the scale: log(1 + g) / log(101)

void fragment() {
	// in units of half the bar's height: x across from the middle, y up
	vec2 p = vec2((UV.x - 0.5) * 2.0 * aspect, (0.5 - UV.y) * 2.0);
	float soft = fwidth(p.y);
	float run = aspect - 1.0;                                      // the ball's travel either way
	// the tube: a capsule's outline
	float tube = length(vec2(max(abs(p.x) - run, 0.0), p.y)) - 0.9;
	float wall = 1.0 - smoothstep(0.07, 0.07 + soft, abs(tube));
	// the gate either side of the ball at rest, and the decades along the tube
	float marks = 0.0;
	float gate = abs(abs(p.x) - 1.12);
	marks = max(marks, (1.0 - smoothstep(0.07, 0.07 + soft, gate)) * step(abs(p.y), 0.9));
	for (int i = 0; i < 2; i++) {
		float at = abs(abs(p.x) - MARKS[i] * run);
		marks = max(marks, (1.0 - smoothstep(0.045, 0.045 + soft, at)) * step(0.5, abs(p.y)) * step(abs(p.y), 0.9) * 0.8);
	}
	float where = clamp(ball, -1.0, 1.0) * run;
	float round_ball = 1.0 - smoothstep(0.68 - soft, 0.68, length(p - vec2(where, 0.0)));
	// its trail back to the middle, so how far it has run is read at a glance
	float trail = step(min(0.0, where), p.x) * step(p.x, max(0.0, where)) * (1.0 - smoothstep(0.3, 0.3 + soft, abs(p.y)));
	float lines = max(wall, marks) * (1.0 - round_ball);
	float cover = max(max(lines * 0.9, trail * 0.75), round_ball);
	if (cover < 0.01) {
		discard;
	}
	vec3 live = mix(lit, hot, hard);
	ALBEDO = mix(mix(ink, live, trail * (1.0 - max(wall, marks))), live, round_ball);
	ALPHA = cover;
}
