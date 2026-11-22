shader_type spatial;
render_mode cull_back;
uniform sampler2D fleet_color : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D fleet_finish : filter_linear_mipmap, repeat_disable;
// A far body never shrinks below a couple of pixels (a body under a pixel wide flickers in and out, and a
// road of them is noise): past the distance where a car would, every body of the batch is drawn larger by
// the same share, about its own middle. Zero (the default) leaves a batch the size it is.
instance uniform float grow_per_m = 0.0;
varying vec3 paint;
varying vec2 atlas_uv;

void vertex() {
	paint = COLOR.rgb;
	if (grow_per_m > 0.0) {
		VERTEX *= max(1.0, length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz) * grow_per_m);
	}
	atlas_uv = UV;
	// The four racing number boards occupy adjacent tiles on the last atlas row.
	if (UV.y > 0.75 && UV.x > 0.5 && UV.x < 0.625) {
		atlas_uv.x += 0.125 * round(INSTANCE_CUSTOM.r * 3.0);
	}
}

void fragment() {
	vec3 base = texture(fleet_color, atlas_uv).rgb;
	vec4 finish = texture(fleet_finish, atlas_uv);
	ALBEDO = base * mix(vec3(1.0), paint, finish.r);
	ROUGHNESS = finish.g;
	METALLIC = finish.b;
	EMISSION = base * finish.a * 2.6;
}
