// The Network traffic's lamps (view/network_traffic.gd): a pair for each vehicle, its tail lamps
// or, when its nose is toward you, its head lamps. They were one glow a vehicle that never shrank
// below a quarter of a degree (view/beacon.gdshader, made for the lamps along a course's walls):
// past a kilometre the glow was as wide as the vehicle, every glow kept its full strength to the
// horizon, and two hundred of them added up along the road into one red smear (Luke: "it just
// looks like a blur of taillights from far away").
// Here a lamp is the size it is. Two of them stand apart by the vehicle's own width, so near and
// in the middle distance a vehicle shows as a pair, wide for a freighter and close for a racer;
// far off the pair closes to a point. A lamp is never drawn smaller than `min_px` pixels in
// radius (a point smaller than a pixel flickers in and out as it crosses the pixels), and held
// at that size it is dimmed as it would have shrunk, so the far ones fade instead of piling up.
// Held small it is a cone a pixel or two wide: whichever pixels it falls across, the light it
// puts on the picture is much the same, so it does not twinkle as it moves. The haze takes a
// share as well.
// An instance: its origin the middle of the pair; its basis x the vehicle's own left-to-right
// axis, as long as half the pair's spacing (m); the length of its basis y a lamp's radius (m);
// the length of its basis z how far the lamps are from the vehicle's middle (m).
// Each is a quad whose vertices all sit at the origin; UV holds the corner (-1..1) and the vertex
// shader spreads it in view space along the pair and across it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float min_px = 1.5;        // a lamp's least radius on the picture, pixels of the eye's own buffer
uniform float halo = 2.4;          // the glow round a lamp, in lamp radii: what is drawn
uniform float energy = 3.0;        // a lamp at its own size (view/network_traffic.gd sets it by the hour: more by day, to show against a lit road)
uniform float falloff = 1.5;       // held at its least size it dims as (its own size / the size drawn) to this power (2 would keep its light exactly, and nothing shows past 6 km; 1 and the far end of a busy road adds up to a bar again)
uniform float floor_gain = 0.03;   // ... and never below this
uniform float haze = 0.00005;      // a metre of air takes this share of it
uniform float grow_per_m = 0.0;    // the far bodies' own growth (art/traffic/fleet.gdshader): the lamps keep clear of a body drawn larger

varying vec2 q;       // where the fragment is, in drawn lamp radii: x along the pair
varying float sep;    // half the pair's spacing, in drawn lamp radii
varying float wide;   // the drawn radius, pixels
varying vec3 tint;

void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 across = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;      // the vehicle's own width, as the eye sees it
	float lamp = length(MODEL_MATRIX[1].xyz) * halo;
	float dist = max(length(c), 1.0);
	// toward the eye, clear of the body: by a little always, and far off by what the body is drawn larger
	float reach = length(MODEL_MATRIX[2].xyz);
	c *= 1.0 - min(0.5, (0.6 + (max(1.0, dist * grow_per_m) - 1.0) * (reach + 2.0)) / dist);
	float pixel = max(-c.z, 0.5) * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);      // a pixel out there, in metres
	float r = max(lamp, min_px * pixel);
	float half_pair = length(across.xy);
	vec2 along = half_pair > 1e-4 ? across.xy / half_pair : vec2(1.0, 0.0);
	vec2 up = vec2(-along.y, along.x);
	c.xy += along * UV.x * (half_pair + r) + up * UV.y * r;
	POSITION = PROJECTION_MATRIX * vec4(c, 1.0);
	q = vec2(UV.x * (half_pair + r) / r, UV.y);
	sep = half_pair / r;
	wide = r / pixel;
	float gain = max(pow(lamp / r, falloff), floor_gain) * exp(-haze * dist);
	tint = pow(COLOR.rgb, vec3(2.2)) * energy * gain;      // authored sRGB
}

// A lamp's light at p (in drawn radii from its middle): held small, a plain cone; larger, a bright heart and a faint skirt.
float lamp_at(vec2 p, float big) {
	float a = clamp(1.0 - length(p), 0.0, 1.0);
	return mix(a, a * a * a, big);
}

void fragment() {
	float big = smoothstep(1.5, 4.0, wide);
	ALBEDO = tint * (lamp_at(q - vec2(sep, 0.0), big) + lamp_at(q + vec2(sep, 0.0), big));
}
