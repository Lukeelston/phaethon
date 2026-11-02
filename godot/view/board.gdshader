// A braking board's lit face (view/course_world.gd; Luke: "turn the stopping reference point into
// a series of variable lights that tell you how close you're gonna cut it"): the whole face lights
// in the speed guide's colour for the town ahead (green, amber: brake now, red and blinking: full
// brakes won't make it), and a row of ten lamps along the bottom fills with how much of full braking
// you'd need, one lamp a tenth. `q` is view/speed_guide.gd's town_cut, set every frame. The face
// is an 80 x 40 m quad; the miles stand in front of it in black.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

#include "res://view/guide.gdshaderinc"

uniform float q = 0.0;
const float LAMPS = 10.0;
const float BAND0 = 0.83;   // the lamp row, UV.y (down the face) from ...
const float BAND1 = 0.96;   // ... to

void fragment() {
	vec3 col = guide_color(max(q, 0.0));
	float blink = q >= GUIDE_RED_AT ? 0.5 + 0.5 * step(0.5, fract(TIME * 2.5)) : 1.0;
	vec3 face = col * blink;
	if (UV.y > BAND0 && UV.y < BAND1) {
		float x = UV.x * LAMPS;
		float k = floor(x);
		vec2 p = vec2((fract(x) - 0.5) * 8.0, (UV.y - 0.5 * (BAND0 + BAND1)) * 40.0);   // metres on the face
		if (length(p) < 2.4) {
			face = q * LAMPS > k + 0.05 ? mix(col, vec3(1.0), 0.45) * 1.6 : vec3(0.04);
		}
	}
	ALBEDO = pow(face, vec3(2.2));   // no HDR boost: ACES washes bright colours toward white, and the colour is the message
}
