// The lights of the Aurora line's takeoff and landing areas (view/aurora_stations.gd): the stop bar
// and the pad's outline, the chevrons on the deck, the approach strips under the glass and the
// distance rings round the hull. One material a kind a lock; what each vertex is, is in its colour:
//   COLOR.r   takes the lock's state colour (the bar red until a craft has stopped, the rings the
//             colour of how hard the craft coming must brake)
//   COLOR.g   runs: a pulse of the runner's colour travelling along UV.y, which is metres to the bar
//   COLOR.b   a share of plain white
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec3 state : source_color = vec3(1.0, 0.1, 0.06);
uniform vec3 runner : source_color = vec3(1.0, 0.72, 0.25);
uniform float level = 1.0;        // how bright the state's share is (over 1: it glows)
uniform float run = 0.0;          // m/s the pulses travel toward the bar (negative: away from it; 0: they stand)
uniform float run_level = 1.0;    // how bright the runner's share is
uniform float spacing = 240.0;    // metres from one pulse to the next

void fragment() {
	float phase = fract((UV.y + TIME * run) / spacing);
	float pulse = abs(run) < 0.001 ? 0.3 : 0.12 + 0.88 * pow(run > 0.0 ? 1.0 - phase : phase, 3.0);
	ALBEDO = state * COLOR.r * level + runner * COLOR.g * pulse * run_level + vec3(COLOR.b);
}
