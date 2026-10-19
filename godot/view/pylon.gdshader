// Light columns along the speed loop (view/course_world.gd; Luke: "make ... the markers more
// vertically visible from further away"): a tall beam of light standing on a mast, red on the
// left wall and green on the right, that never thins below `min_ang` on screen, so the walls'
// lines of columns stand up out of the haze 10-40 km ahead. Each column is a quad whose bottom two
// vertices sit at its foot and top two at its head; UV.x is the side (-1..1), UV.y 0 at the foot
// and 1 at the head. The vertex shader turns it to face the camera about its vertical axis.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float width = 0.9;       // m: the half-width up close
uniform float min_ang = 0.0022;  // rad: never thinner than this
uniform float energy = 2.4;
uniform float far_dim = 0.55;

varying float dist;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 side = normalize(cross(axis, normalize(c.xyz)));
	dist = length(c.xyz);
	c.xyz += side * UV.x * max(width, dist * min_ang);
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	float across = 1.0 - abs(UV.x);
	float a = across * across * pow(1.0 - UV.y, 1.4);
	vec3 col = pow(COLOR.rgb, vec3(2.2));   // vertex colours are authored sRGB
	float k = mix(1.0, far_dim, smoothstep(2000.0, 30000.0, dist));
	ALBEDO = col * energy * a * k;
}
