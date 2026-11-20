// The gauge cluster's dial faces and everything printed or lit on them (vr/gauge_cluster.gd).
// One mesh, one draw: the atlas holds colour in RGB and, in alpha, how much of each texel is
// translucent print that the backlight shines through. Per vertex: UV2 is the point on its dial
// in metres from the dial's centre; COLOR is (occlusion, gloss, gauge / 8, lamp / 64).
// Lamp 0 is the backlight; every other lamp is a legend or segment that is dark until lit.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 lamp[40];              // colour, and level in alpha
uniform vec4 needle[8];             // gauge, pivot x, pivot y, length (metres); length 0 = unused
uniform float needle_angle[8];      // radians, anticlockwise from three o'clock
uniform float energy = 1.5;

void fragment() {
	vec4 print = texture(atlas, UV);
	int id = int(COLOR.a * 64.0 + 0.5);
	int gauge = int(COLOR.b * 8.0 + 0.5);
	vec4 light = lamp[id];
	// each needle rides a few millimetres over its dial: a soft shadow under it, a little low
	float shade = 1.0;
	for (int i = 0; i < 8; i++) {
		float reach = needle[i].w;
		if (reach <= 0.0 || int(needle[i].x + 0.5) != gauge) {
			continue;
		}
		vec2 dir = vec2(cos(needle_angle[i]), sin(needle_angle[i]));
		vec2 p = UV2 - needle[i].yz - vec2(0.0008, -0.0026);
		float along = clamp(dot(p, dir), 0.0, reach);
		float half_width = mix(0.05, 0.014, along / reach) * reach * 0.5;
		shade *= 1.0 - 0.6 * (1.0 - smoothstep(half_width * 0.5, half_width + 0.0035, length(p - dir * along)));
	}
	float gloss = COLOR.g;
	if (id == 0) {
		ALBEDO = print.rgb * shade;
	} else {
		ALBEDO = print.rgb * mix(vec3(0.075), light.rgb * 0.5, light.a) * shade;
	}
	EMISSION = print.rgb * print.a * light.rgb * light.a * energy + vec3(0.008, 0.011, 0.014) * gloss * light.a;
	ROUGHNESS = mix(0.84, 0.14, gloss);
	SPECULAR = mix(0.3, 0.5, gloss);
	AO = COLOR.r;
	AO_LIGHT_AFFECT = 0.5;
}
