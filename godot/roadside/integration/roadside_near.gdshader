shader_type spatial;
render_mode fog_disabled, cull_back;
uniform sampler2D color_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
instance uniform float stream_reveal = 1.0;

global uniform vec3 sky_haze;
global uniform float sky_haze_scale;
global uniform float sky_snow;

void fragment() {
    float distance_m = length(VERTEX);
    float reveal = stream_reveal * (1.0 - smoothstep(22000.0, 30000.0, distance_m));
    if (reveal <= fract(dot(floor(FRAGCOORD.xy), vec2(0.75487766, 0.56984029)))) discard;
    vec3 orm = texture(orm_atlas, UV).rgb;
    float haze = 1.0 - exp(-distance_m * 0.000025 * sky_haze_scale);
    vec3 tint = texture(color_atlas, UV).rgb * COLOR.rgb;
    ALBEDO = mix(tint, vec3(0.80, 0.84, 0.88), sky_snow * 0.5) * (1.0 - haze);
    ROUGHNESS = orm.g;
    METALLIC = orm.b;
    AO = orm.r;
    EMISSION = pow(sky_haze, vec3(2.2)) * haze * 0.85;
}
