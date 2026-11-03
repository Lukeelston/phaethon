// A jump's overhead board (view/network_world.gd; Luke: "large arrow markings on these signs directing the
// player towards the jump"): the face strobes in the jump's orange, a chase of lamps runs along its
// edges, and a big lit arrow on a dark panel at its right points at the jump, stripes running along
// it the way it points. The black words stand in front of the face's left. Unfogged, like the boards.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 col = vec3(1.0, 0.55, 0.1);
uniform float aspect = 3.0;      // the board's width over its height
uniform float panel = 0.36;      // the arrow's panel: this share of the width, at the right
uniform float angle = 0.785;     // the way the arrow points: radians from straight right, anticlockwise
uniform float flash_hz = 1.6;
uniform float lamps = 36.0;      // along each edge
uniform float chase_hz = 3.0;    // lamps a second running along

void fragment() {
	float on = step(0.5, fract(TIME * flash_hz));
	vec3 face = mix(col, col * 0.72 + vec3(0.2), on);
	// the arrow's panel: dark, the arrow lit whichever way the face is strobing
	float px = (UV.x - (1.0 - panel)) / panel;
	if (px >= 0.0) {
		vec2 p = vec2((px - 0.5) * panel * aspect, 0.5 - UV.y);   // (board heights, up +y)
		float c = cos(angle), s = sin(angle);
		vec2 q = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);     // q.x along the arrow
		bool head = q.x > 0.02 && q.x < 0.44 && abs(q.y) < (0.44 - q.x) * 1.05;
		bool shaft = q.x >= -0.42 && q.x <= 0.02 && abs(q.y) < 0.13;
		face = vec3(0.05, 0.05, 0.06);
		if (head || shaft) {
			float run = step(0.45, fract(q.x * 3.5 - TIME * 2.4));
			face = mix(vec3(1.0, 0.62, 0.12), vec3(1.0, 0.98, 0.85) * 1.7, run);
		}
	}
	float edge = UV.y < 0.09 ? (0.09 - UV.y) / 0.09 : (UV.y > 0.91 ? (UV.y - 0.91) / 0.09 : -1.0);
	if (edge >= 0.0) {
		float x = UV.x * lamps;
		float k = floor(x);
		vec2 lp = vec2(fract(x) - 0.5, (edge - 0.5) * 0.5);
		float lit = step(0.5, fract((k - TIME * chase_hz) / 4.0));
		face = length(lp) < 0.32 ? mix(vec3(0.05), vec3(1.0, 1.0, 0.95) * 1.6, lit) : vec3(0.06, 0.07, 0.09);
	}
	ALBEDO = pow(clamp(face, vec3(0.0), vec3(4.0)), vec3(2.2));
}
