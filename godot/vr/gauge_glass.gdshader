// The convex glass over each gauge (vr/gauge_cluster.gd): clear, so it only adds what it
// reflects. A dome facing the seat mirrors the cabin over most of its face and the sky only
// near its upper edge, where the reflection clears the pilot's head; the engine's sky
// reflection knows nothing of the cabin, so that is decided here from where the mirror points.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, specular_schlick_ggx;

uniform vec3 up_local = vec3(0.0, 0.958, 0.286);   // the cockpit's up, in the cluster's own frame
uniform vec3 cabin : source_color = vec3(0.016, 0.016, 0.019);
uniform float sky_from = 0.14;                     // sine of the mirror direction's elevation where the sky begins ...
uniform float sky_to = 0.5;                        // ... and where it is all sky

void fragment() {
	ALBEDO = vec3(0.006);   // a trace of dust, so sunlight shows the dome
	ROUGHNESS = 0.05;
	SPECULAR = 0.7;         // two surfaces
	vec3 mirror = mat3(INV_VIEW_MATRIX) * reflect(-VIEW, NORMAL);
	float sky = smoothstep(sky_from, sky_to, dot(normalize(transpose(mat3(MODEL_MATRIX)) * mirror), up_local));
	RADIANCE = vec4(cabin, 1.0 - sky);
	IRRADIANCE = vec4(0.0, 0.0, 0.0, 1.0);
}
