// The start panel's own finish (vr/overhead_panel.gd; the art is tools/art_start_panel_hd.py's).
// The pods hang under the roof's header with their faces turned down and aft, away from the sky and
// both suns: lit like the rest of the cockpit they are black slabs. What lights them is what lights
// a real overhead panel: a flood lamp under the rail, raking down across each face. Its light is
// worked out here and given back as the part's own colour (no light of the scene's is spent on it,
// and none of the cockpit's lit pixels pays for it), on the authored maps: the relief in the normal
// map catches it, the baked occlusion shades it, and bare metal mirrors the lamp, the daylight in
// the windscreen and the dark of the cabin instead of the sky (which under a roof reads as neon).
// The fourth map says what lights up by itself: red, paint that is lit from behind (the legends);
// green, how bright a lamp's lens is there; blue, which lamp (a quarter for each: standby, battery,
// engine, brake).
shader_type spatial;

uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic, repeat_disable;       // occlusion, roughness, metal
uniform sampler2D glow_map : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 light = vec3(0.0, 0.77, 0.64);    // toward the lamp, world space (the cockpit turns: set every frame)
uniform vec3 lamp_left = vec3(-0.2, 0.5, 0.4); // where each pod's lamp is, world space: its light falls off down the face
uniform vec3 lamp_right = vec3(0.2, 0.5, 0.4);
uniform vec3 ahead = vec3(0.0, 0.3, -0.95);    // toward the daylight in the windscreen, world space
uniform vec3 overhead = vec3(0.0, 1.0, 0.0);   // the cockpit's own up, world space
uniform float glow = 0.7;                      // what a face square to the lamp gives back of its own colour
uniform float fill = 0.3;                      // ... and what one turned away keeps of that
uniform float backlight = 0.0;                 // the legends, lit from behind
uniform vec3 backlight_colour = vec3(1.0, 0.93, 0.8);
uniform vec3 lamp_standby = vec3(0.0);         // each lamp's light
uniform vec3 lamp_batt = vec3(0.0);
uniform vec3 lamp_engine = vec3(0.0);
uniform vec3 lamp_park = vec3(0.0);

varying vec3 place;

void vertex() {
	place = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = texture(base_map, UV).rgb;
	vec3 orm = texture(orm_map, UV).rgb;
	vec3 lights = texture(glow_map, UV).rgb;
	vec3 mapped = texture(normal_map, UV).rgb;
	vec2 bend = mapped.rg * 2.0 - 1.0;
	vec3 n = normalize(TANGENT * bend.x + BINORMAL * bend.y + NORMAL * sqrt(max(0.0, 1.0 - dot(bend, bend))));
	vec3 l = normalize(mat3(VIEW_MATRIX) * light);
	vec3 day = normalize(mat3(VIEW_MATRIX) * ahead);
	float reach = mix(1.2, 0.74, smoothstep(0.075, 0.17, min(distance(place, lamp_left), distance(place, lamp_right))));
	float shade = mix(0.4, 1.0, orm.r) * reach;
	float rough = orm.g;
	// paint, anodising, rubber, glass: the lamp's light off a matt surface, and its glint
	float facing = clamp(0.5 + 0.5 * dot(n, l), 0.0, 1.0);
	float a = max(rough * rough, 0.02);
	float nh = max(dot(n, normalize(l + VIEW)), 0.0);
	float glint = min(exp((nh * nh - 1.0) / (max(nh * nh, 1e-4) * a * a)) / (4.0 * a * a), 30.0) * max(dot(n, l), 0.0);
	vec3 matt = base * mix(fill, 1.0, facing * facing) * shade + vec3(0.012 * glint) * shade;
	// bare metal: what it mirrors
	vec3 r = reflect(-VIEW, n);
	float lamp_seen = pow(max(dot(r, l), 0.0), mix(90.0, 3.0, rough)) * mix(3.2, 0.8, rough);
	float lamp_wide = pow(clamp(0.5 + 0.5 * dot(r, l), 0.0, 1.0), 4.0);
	float toward = dot(r, day);
	float window = smoothstep(0.72 - 0.9 * rough, 0.98, toward);
	float above = smoothstep(-0.06 - rough, 0.06 + rough, dot(r, normalize(mat3(VIEW_MATRIX) * overhead)));   // over the coaming: glass; under it: the cabin
	float mirrored = mix(0.05, mix(mix(0.1, 0.36, smoothstep(-0.3, 0.3, toward)), 0.95, window), above);
	float scatter = 0.85 * smoothstep(0.12, 0.5, rough) * mix(fill, 1.0, facing * facing);     // brushed and knurled metal scatters the lamp as paint does
	vec3 bare = base * (lamp_seen + 0.22 * lamp_wide + mirrored + scatter) * shade;
	vec3 shown = mix(matt, bare, orm.b) * glow;
	// what lights up
	float which = lights.b;
	vec3 lamp = which > 0.875 ? lamp_park : (which > 0.625 ? lamp_engine : (which > 0.375 ? lamp_batt : (which > 0.125 ? lamp_standby : vec3(0.0))));
	ALBEDO = base * (1.0 - 0.7 * orm.b);
	ROUGHNESS = rough;
	METALLIC = 0.0;
	AO = orm.r;
	NORMAL_MAP = mapped;
	EMISSION = shown + backlight_colour * (backlight * lights.r) + lamp * lights.g;
}
