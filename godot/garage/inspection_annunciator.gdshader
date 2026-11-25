shader_type spatial;

uniform sampler2D legends : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
varying flat float stage;

void vertex() {
	stage = round(INSTANCE_CUSTOM.r * 4.0);
}

void fragment() {
	// Each tile is a separate printed legend. Matching words, shapes and colors
	// make unequal left/right states readable under any palette.
	vec2 lettering_uv = vec2(UV.x, (stage + UV.y) / 5.0);
	float ink = texture(legends, lettering_uv).r;
	vec3 lens = vec3(.012, .024, .026);
	vec3 tint = vec3(.57, .67, .65);
	if (stage > 3.5) {
		tint = vec3(.29, 1.00, .52);
	} else if (stage > 1.5) {
		tint = vec3(1.0, .59, .15);
	} else if (stage > .5) {
		tint = vec3(.79, .79, .54);
	}
	ALBEDO = mix(lens, tint * .39, ink);
	EMISSION = tint * ink * (stage == 0.0 ? .32 : .90);
	ROUGHNESS = .45;
	SPECULAR = .32;
}
