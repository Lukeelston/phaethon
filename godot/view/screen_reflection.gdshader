// The windscreen's reflection of the cockpit under it (Luke: "add some kind of reflection to the
// windscreen, without making it white out"). What a swept screen really shows from the seat: the
// leather of the coaming, the instruments' faces and the sills, faintly, hanging in the glass over
// the view, and sliding across it as your head moves.
//   the picture   view/screen_reflection.gd looks down into the cockpit from where the seated eye's
//                 mirror image is and keeps what it sees (`seen`, with nothing where there was nothing)
//   each pixel    this eye's sight line is turned off the glass, followed down to the height the
//                 cockpit's top lies at, and the picture read where it lands: so the two eyes see
//                 it behind the glass, not painted on it
//   the glass     gives back 4 % head on and more at a glance (times `strength`: by day a real
//                 pane's share is lost against the sky), never more than `ceiling`
// It only ever adds a share of the cockpit's own colours, and draws nothing where that is too
// dark to show: no pane of glass over the whole view (that cost a headset 0.7 ms a frame), no
// sheen of sky. The cockpit is dark but for its lamps, so it cannot white the view out.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D seen : source_color, filter_linear, repeat_disable;
uniform mat4 seen_from;             // canopy space -> the picture's clip space
uniform float lies_at = 0.02;       // the height the reflected cockpit is taken to lie at, canopy space
uniform float strength = 1.0;
uniform float ceiling = 0.5;        // the most of the picture the glass ever gives back (a bare pane's own share at a low glance)
uniform float lamps = 1.5;          // how much brighter than white the cockpit's own lights are
uniform vec4 opening = vec4(0.79, 1.22, 0.15, 0.89);   // the cabin's opening in plan: half-width, half-length aft of its widest point, that point's z, half-length ahead of it
uniform vec2 reach = vec2(0.1, 0.32);                 // ... and how far aft of it is shown: all of it to the first z, none past the second
varying vec3 local_pos;
varying vec3 local_n;

void vertex() {
	local_pos = VERTEX;
	local_n = NORMAL;
}

void fragment() {
	// this eye's sight line in the canopy's frame (never scaled: its matrix turns back by its transpose)
	vec3 sight = normalize((-(INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz) * mat3(MODEL_MATRIX));
	vec3 n = normalize(local_n);
	float facing = dot(-sight, n);
	vec3 off = reflect(sight, n);
	if (facing <= 0.0 || off.y > -0.08) {
		discard;
	}
	vec3 lands = local_pos + off * ((lies_at - local_pos.y) / off.y);
	// only the cabin is under the glass: the hull's outside and the nose are not reflected in it
	vec2 plan = vec2(lands.x / opening.x, (lands.z - opening.z) / (lands.z < opening.z ? opening.w : opening.y));
	float within = (1.0 - smoothstep(0.9, 1.0, dot(plan, plan))) * (1.0 - smoothstep(reach.x, reach.y, lands.z));
	if (within <= 0.0) {
		discard;
	}
	vec4 clip = seen_from * vec4(lands, 1.0);
	vec2 uv = vec2(0.5 + 0.5 * clip.x / clip.w, 0.5 - 0.5 * clip.y / clip.w);
	vec2 inside = min(uv, 1.0 - uv);
	if (clip.w <= 0.0 || min(inside.x, inside.y) <= 0.0) {
		discard;
	}
	vec4 picture = texture(seen, uv);
	float mirror = min((0.04 + 0.96 * pow(1.0 - facing, 5.0)) * strength, ceiling);
	float edge = smoothstep(0.0, 0.06, min(inside.x, inside.y));
	// The picture is an ordinary one: its lamps (the needles, the digits, the rim light, the map) stop
	// at white, where the real ones are several times brighter than anything they light. Give them that
	// back: it is the lamps a pane of glass shows first.
	float lit = smoothstep(0.5, 0.95, max(picture.r, max(picture.g, picture.b)));
	vec3 add = pow(picture.rgb, vec3(0.8)) * picture.a * (1.0 + lamps * lit) * mirror * edge * within;
	if (max(add.r, max(add.g, add.b)) < 0.01) {
		discard;
	}
	ALBEDO = add;
}
