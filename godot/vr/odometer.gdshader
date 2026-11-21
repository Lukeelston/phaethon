// The points counter (Luke: "points on an odometer roller"): a row of numbered drums behind a small
// window in the gauge cluster's fascia (vr/gauge_cluster.gd), drawn on one flat tile.
//   value     the count, as a real number: the units drum turns with it all the time, and each drum
//             above turns over only while the one below it is passing 9 to 0, as geared drums do
//   numerals  the ten figures stacked in one strip, 0 at the top (tools/art_gauge_faces.py)
//   UV        u across the window from its highest drum, v down it
// Each drum is a cylinder seen side on: its figures close up and its face darkens toward the top and
// bottom of the window, and a figure rolling in shows its neighbour's edge above or below.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D numerals : filter_linear_mipmap, repeat_disable;
uniform float value = 0.0;
uniform int drums = 6;
uniform float level = 1.0;                                    // the instrument lighting
uniform vec3 print_colour : source_color = vec3(0.86, 0.84, 0.76);
uniform vec3 drum_colour : source_color = vec3(0.014, 0.014, 0.016);
uniform float seen = 0.50;                                    // half the angle of drum the window shows, radians (a figure is 0.628 of the way round: at 0.62 half of each neighbour showed)

void fragment() {
	float across = UV.x * float(drums);
	int k = drums - 1 - int(floor(across));                   // 0: the units drum
	float u = fract(across);
	float below = 1.0;                                        // 10 to the k
	for (int i = 0; i < k; i++) {
		below *= 10.0;
	}
	float own = mod(floor(value / below), 10.0);
	float turning = clamp(mod(value, below) - (below - 1.0), 0.0, 1.0);
	// up the window is round the drum; the count going up brings the next figure in from below
	float angle = asin(clamp((0.5 - UV.y) * 2.0, -1.0, 1.0) * sin(seen));
	float figure = own + turning - angle / 0.6283 + 0.5;
	float cell = mod(floor(figure), 10.0);
	vec2 at = vec2((u - 0.5) / 0.9 + 0.5, (cell + fract(figure)) / 10.0);
	float ink = (at.x > 0.0 && at.x < 1.0) ? textureGrad(numerals, at, vec2(dFdx(UV.x) * float(drums) / 0.9, 0.0), vec2(0.0, dFdy(UV.y) * 0.1)).r : 0.0;
	// the drum's own round, the dark seam between two drums, and a worn edge beside it
	float round_off = cos(angle);
	float seam = smoothstep(0.0, 0.05, u) * smoothstep(0.0, 0.05, 1.0 - u);
	float edge = (1.0 - smoothstep(0.05, 0.11, u)) + (1.0 - smoothstep(0.05, 0.11, 1.0 - u));
	vec3 face = mix(drum_colour * (1.0 + 2.0 * edge), print_colour, ink);
	float lit = pow(round_off, 2.4) * seam;
	ALBEDO = face * lit;
	EMISSION = face * lit * 0.55 * level;
	ROUGHNESS = 0.42;
	SPECULAR = 0.4;
}
