// An authored fitting drawn from its own maps, with its orange turned to the livery's accent
// (view/accent.gd): the coaming's enamel, the stitching's thread, the grips' anodised bands, the
// engines' armour plates. Everything else in the map is left exactly as it was painted: the test is
// a window of hue (9 to 30 degrees, in the map's own display colours) on well-saturated texels only,
// which the leather, the carbon, the tan welt thread (33 degrees, pale) and the red guards (4
// degrees) all fall outside.
shader_type spatial;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;   // occlusion, roughness, metal
uniform vec3 accent_hsv = vec3(0.6, 0.9, 0.8);   // the accent: hue 0..1, saturation, value (display colours)
uniform float normal_depth = 1.0;
uniform float occlusion = 0.0;                   // how far the baked occlusion dims direct light (the material's own setting)
uniform vec3 glow = vec3(0.0);                   // the fitting's own light, times its colour (the headliner's)

const vec3 ORANGE_HSV = vec3(0.052, 0.90, 0.76); // what the fittings' orange is, on average

vec3 to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-6)), d / (q.x + 1e-6), q.x);
}

vec3 to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 base = texture(albedo_map, UV).rgb;
	vec3 shown = pow(max(base, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 hsv = to_hsv(shown);
	float orange = smoothstep(0.025, 0.036, hsv.x) * (1.0 - smoothstep(0.078, 0.088, hsv.x)) * smoothstep(0.5, 0.64, hsv.y) * smoothstep(0.08, 0.16, hsv.z);
	vec3 turned = to_rgb(vec3(accent_hsv.x, clamp(hsv.y * accent_hsv.y / ORANGE_HSV.y, 0.0, 1.0), clamp(hsv.z * accent_hsv.z / ORANGE_HSV.z, 0.0, 1.0)));
	vec3 colour = mix(base, pow(max(turned, vec3(0.0)), vec3(2.2)), orange);
	vec3 orm = texture(orm_map, UV).rgb;
	ALBEDO = colour;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
	AO = orm.r;
	AO_LIGHT_AFFECT = occlusion;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	EMISSION = colour * glow;
}
