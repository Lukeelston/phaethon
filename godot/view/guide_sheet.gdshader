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
uniform bool expressway = false;

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
		// Sides roll inward to the shield tip. The expressway crest has a
		// shallow scallop on each side of its center peak.
		float x = abs(p.x) / half_size.x;
		float lower = -0.48 + (expressway ? 0.46 : 0.23) * pow(x, 1.8);
		float upper = 0.47 - (expressway ? 0.070 : 0.0) * sin(x * PI);
		edge = max(edge, max(lower - p.y, p.y - upper));
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
		if (expressway) {
			base = mix(base, vec3(0.44, 0.018, 0.022), smoothstep(0.227-aa, 0.227+aa, p.y));
			base = mix(base, pigment, cover(abs(p.y - 0.226) - 0.012, aa));
		}
		vec3 keyline = expressway ? pigment : vec3(0.028, 0.043, 0.034);
		base = mix(base, keyline, cover(abs(edge + 0.037) - 0.020, aa));
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
	float metal = 0.0;
	if (!route_marker) {
		color *= (0.978 + 0.035 * sheet) * (1.0 - 0.13 * seam);
		float pin_x = (fract(strip_x) - 0.5) * aspect / strips;
		vec2 pin = vec2(pin_x, abs(p.y) - 0.441);
		float detail = 1.0 - smoothstep(0.003, 0.018, aa);
		float screw = cover(length(pin) - 0.005, aa) * detail;
		// Dust gathers at the bottom hem. Short runoff trails only resolve
		// close up, where the washer casting each one can also be seen.
		float drop = 0.441 - p.y;
		float runoff = exp(-abs(pin_x)*145.0) * exp(-max(drop,0.0)*22.0) * step(0.0,drop);
		color *= 1.0 - 0.065 * smoothstep(0.40,0.50,-p.y) - 0.095 * runoff * detail;
		color = mix(color, vec3(0.35, 0.38, 0.36), screw);
		metal += screw * 0.68;
	}
	ALBEDO = color;
	ROUGHNESS = 0.72 + sheet * 0.05;
	METALLIC = metal;
	SPECULAR = 0.10;
	// Passive sheeting and its printed type share the craft's forward light.
	// Only the electrically driven arrow studs emit their own light.
	EMISSION = lamps * amber * 1.1;
}

void light() {
	float incidence = max(dot(NORMAL, LIGHT), 0.0);
	// A local source close to the viewer's sightline gets a stronger return.
	// Sunlight supplies ordinary daylight illumination across the whole board.
	float aligned = max(dot(LIGHT, VIEW), 0.0);
	float backscatter = LIGHT_IS_DIRECTIONAL ? 0.0 : 0.48 * pow(aligned, 72.0) * incidence;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * incidence * (1.0 + backscatter) / PI;
}
