// The Kiln's plasma lance (view/weapons/lance_mount.gd): one ribbon from the emitter's mouth to the beam's end, added.
// Its mesh is a unit quad across X and along Z (QuadMesh, FACE_Y); the node's basis lays its Z on the beam (the +Z end at
// the mouth, the -Z end at the beam's end) and as long as it is. Each point of it is made `width` radians of view wide
// for the eye that draws it, and turned to face that eye about the beam's line: from a few metres off the eye to 600 m
// out it is the same thin line of light, never a sheet across the view. White-hot down its middle, `edge` at its sides;
// it fades in over FADE_IN m off the mouth and out over `fade_out` m at its end.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float width = 0.0105;                          // radians of view across
uniform float span = 1.0;                              // m: the beam's length
uniform float fade_out = 1.0;                          // m it fades out over at its end
uniform vec3 core = vec3(1.0, 0.93, 0.78);
uniform vec3 edge = vec3(1.0, 0.42, 0.1);
uniform float energy = 2.2;
const float FADE_IN = 0.25;

varying float across;
varying float along;                                   // 0 at the beam's end .. 1 at the mouth

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, VERTEX.z, 1.0)).xyz;      // its point on the beam's line
	vec3 line = MODEL_MATRIX[2].xyz;
	vec3 to_eye = INV_VIEW_MATRIX[3].xyz - at;
	vec3 side = cross(line, to_eye);
	float n = length(side);
	side = n > 1e-6 ? side / n : normalize(MODEL_MATRIX[0].xyz);
	VERTEX = at + side * (VERTEX.x * width * length(to_eye));
	MODELVIEW_MATRIX = VIEW_MATRIX;                    // (VERTEX is in the world now)
	across = UV.x * 2.0 - 1.0;
	along = UV.y;
}

void fragment() {
	float a = pow(max(0.0, 1.0 - abs(across)), 2.0);
	float from_mouth = (1.0 - along) * span;
	a *= smoothstep(0.0, FADE_IN, from_mouth) * smoothstep(0.0, max(fade_out, 0.01), along * span);
	vec3 c = mix(edge, core, pow(max(0.0, 1.0 - abs(across)), 6.0));
	ALBEDO = c * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
