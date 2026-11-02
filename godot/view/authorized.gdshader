// The SPEED AUTHORIZED sign where the speed loop begins (view/course_world.gd; Luke: "turn the
// 'speedcraft' bridge into a flashing sign that says something like 'speed authorized'"): the
// face strobes between SPEEDCRAFT blue and white, and a chase of lamps runs along its top and
// bottom edges toward the loop. The black words stand in front of it. Unfogged, like the boards.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

uniform vec3 col = vec3(0.25, 0.65, 1.0);
uniform float flash_hz = 1.6;
uniform float lamps = 24.0;     // along each edge
uniform float chase_hz = 3.0;   // lamps a second running along

void fragment() {
	float on = step(0.5, fract(TIME * flash_hz));
	vec3 face = mix(col, vec3(0.92, 0.97, 1.0), on);
	float edge = UV.y < 0.12 ? (0.12 - UV.y) / 0.12 : (UV.y > 0.88 ? (UV.y - 0.88) / 0.12 : -1.0);
	if (edge >= 0.0) {
		float x = UV.x * lamps;
		float k = floor(x);
		vec2 p = vec2(fract(x) - 0.5, (edge - 0.5) * 0.5);
		float lit = step(0.5, fract((k - TIME * chase_hz) / 4.0));   // every fourth lamp, running
		face = length(p) < 0.32 ? mix(vec3(0.05), vec3(1.0, 1.0, 0.95) * 1.6, lit) : vec3(0.06, 0.07, 0.09);
	}
	ALBEDO = pow(clamp(face, vec3(0.0), vec3(4.0)), vec3(2.2));   // clamped: the shade line's gate uses it too (MSAA edge pixels)
}
