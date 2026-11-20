// Reflective sheeting, applied border, panel joints and face rivets. Coordinates
// are in panel heights so the border and the arrow keep their physical proportions.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 field : source_color = vec4(0.016, 0.34, 0.215, 1.0);
uniform vec4 ink : source_color = vec4(0.94, 0.95, 0.88, 1.0);
uniform float aspect = 3.0;
uniform float radius = 0.055;
uniform float border = 0.016;
uniform float advisory = 0.0;
uniform float left_patch = 0.0;
uniform float arrow_side = 0.0;
uniform float arrow_angle = 0.785398;
uniform bool beacons = false;
uniform bool route_marker = false;

float rounded_rect(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}
float cover(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, -1.0);
	vec2 half_size = vec2(aspect, 1.0) * 0.5;
	float aa = max(max(fwidth(p.x), fwidth(p.y)) * 0.55, 0.0002);
	float edge = rounded_rect(p, half_size, radius);
	if (route_marker) {
		// A fictional Network route marker: square shoulders above a shallow shield tip.
		edge = max(edge, -p.y - 0.49 + abs(p.x / half_size.x) * 0.19);
	}
	if (edge > 0.0) { discard; }
	vec3 base = field.rgb;
	vec3 pigment = ink.rgb;
	vec3 amber = vec3(0.92, 0.53, 0.025);
	if (advisory > 0.0 && UV.y > 1.0 - advisory) {
		base = amber;
		pigment = vec3(0.024, 0.031, 0.021);
	}
	if (left_patch > 0.0 && UV.x < left_patch) {
		base = amber;
		pigment = vec3(0.025);
	}
	float outline = cover(abs(edge + border * 1.7) - border * 0.5, aa);
	if (route_marker) {
		base = mix(base, vec3(0.028, 0.063, 0.047), cover(abs(edge + 0.058) - 0.022, aa));
		outline = 0.0;
	}
	float letters = outline;
	float lamps = 0.0;
	if (abs(arrow_side) > 0.5) {
		vec2 centre = vec2(arrow_side * (half_size.x - 0.48), advisory * 0.50);
		vec2 delta = p - centre;
		vec2 axis = vec2(cos(arrow_angle) * arrow_side, sin(arrow_angle));
		vec2 q = vec2(dot(delta, axis), dot(delta, vec2(-axis.y, axis.x)));
		// Tapered head, broad stem, squared tail. The entire silhouette is visible at all times.
		float shank = max(max(-0.265 - q.x, q.x - 0.075), abs(q.y) - 0.048);
		float head = max(max(0.012 - q.x, q.x - 0.307), abs(q.y) - (0.307-q.x)*0.62);
		letters = max(letters, cover(min(shank, head), aa));
		if (beacons) {
			vec2 lamp = vec2(mod(q.x + 0.225 + 0.038, 0.076) - 0.038, q.y);
			float holes = cover(length(lamp) - 0.021, aa) * step(-0.256, q.x) * step(q.x, 0.206);
			float pulse = smoothstep(0.30, 0.75, cos(q.x * 10.0 - TIME * 5.0));
			lamps = holes * pulse;
			base = mix(base, amber, holes);
			letters *= 1.0 - holes;
		}
	}
	vec3 color = mix(base, pigment, letters);
	// Individual strips have slightly different reflectance. Filter the seams and fasteners
	// out once they become sub-pixel, instead of sparkling at highway speed.
	float strips = max(1.0, floor(aspect * 1.75 + 0.5));
	float strip_x = UV.x * strips;
	float seam = (1.0 - smoothstep(0.001, 0.005 + aa, abs(fract(strip_x + 0.5) - 0.5))) * (1.0 - smoothstep(0.003, 0.012, aa));
	float sheet = fract(sin(floor(strip_x) * 71.41 + 9.1) * 4375.24);
	color *= (0.973 + 0.042 * sheet) * (1.0 - 0.17 * seam);
	float metal = 0.0;
	if (!route_marker) {
		vec2 pin = vec2((fract(strip_x) - 0.5) * aspect / strips, abs(p.y) - 0.441);
		float screw = cover(length(pin) - 0.007, aa) * (1.0 - smoothstep(0.003, 0.020, aa));
		color = mix(color, vec3(0.35, 0.38, 0.36), screw);
		metal += screw * 0.68;
	}
	ALBEDO = color;
	ROUGHNESS = 0.72 + sheet * 0.05;
	METALLIC = metal;
	SPECULAR = 0.10;
	// Approximate the pilot's forward lights returning toward the eye. Distance and
	// incidence gate the return; the sun and sky still light a distant or oblique board.
	float d = length(VERTEX);
	float retro = pow(max(0.0, dot(normalize(NORMAL), VIEW)), 6.0) / (1.0 + d*d/280000.0);
	EMISSION = color * (0.14 + 0.43 * retro) + lamps * amber * 1.1;
}
