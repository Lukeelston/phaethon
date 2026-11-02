// An engine's exhaust plume, drawn additively on an uncapped cone hanging back from the nozzle
// (`along`: 0 at the nozzle, 1 at the tip; a CylinderMesh's side UV.y only runs 0..0.5). Dry thrust is nearly invisible: a short pale-blue core and haze.
// The burner is a long plume, blue-white at the nozzle through yellow-orange to a fading red,
// with shock diamonds (bright bands that shrink and fade down the plume). Soft edges (faces seen
// edge-on fade out), flicker and a little turbulence. craft_model.gd sets the uniforms per engine.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float thrust = 0.0;   // 0..1+ (the engine's real thrust)
uniform float burner = 0.0;   // 0..1, eased: the afterburner's share
uniform float ramjet = 0.0;   // 0..1, eased: hotter, bluer
uniform float layer = 0.0;    // 0 the outer plume, 1 the inner core
uniform float seed = 0.0;     // per engine, so the two don't flicker in step
uniform float aspect = 4.0;   // the plume's length over the nozzle's height (the side-view chord)

varying float along;
varying vec3 axis;   // the plume's axis in view space

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	along = UV.y * 2.0;
	axis = (MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
}

void fragment() {
	float t = clamp(thrust, 0.0, 1.6);
	// how much glowing gas the eye looks through here, relative to a side view: a ray at angle
	// th to the axis crosses a slender cone over 2r*(N.V)/sin^2(th), so the rim (edge-on, N.V
	// ~ 0) fades to nothing from any side, while looking down the plume from the cockpit sees
	// through its length and it brightens (capped) instead of vanishing. A ray that leaves
	// through the open nozzle end only crosses the gas back to the nozzle plane (along*L/cos th),
	// so the nozzle's rim, seen from behind, doesn't light up as a ring.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float ax = dot(normalize(axis), normalize(VIEW));
	float to_nozzle = along * aspect * mix(1.0, 2.0, layer) / max(abs(ax), 0.05);
	float thick = min(min(facing / max(1.0 - ax * ax, 0.03), to_nozzle), 2.5);
	float edge = thick < 1.0 ? pow(max(thick, 0.0), mix(1.6, 0.9, layer)) : thick;   // max: MSAA edge pixels run `along` off the quad
	// colour temperature down the plume
	vec3 nozzle = mix(vec3(0.55, 0.75, 1.0), vec3(0.85, 0.9, 1.0), ramjet);    // blue-white at the exit
	vec3 mid = mix(vec3(1.0, 0.62, 0.18), vec3(0.75, 0.55, 1.0), ramjet);      // yellow-orange (violet on the ramjet)
	vec3 tail = vec3(0.6, 0.12, 0.05);                                          // fading red
	vec3 col = mix(nozzle, mid, smoothstep(0.02, 0.35, along));
	col = mix(col, tail, smoothstep(0.45, 1.0, along));
	// dry thrust: a short, faint blue core only; the burner fills the whole plume
	float dry_len = 0.35 + 0.25 * t;
	float reach = mix(1.0 - smoothstep(dry_len * 0.4, dry_len, along), 1.0 - smoothstep(0.5, 1.0, along), burner);
	float strength = mix(0.3 + 0.35 * t, 0.62, burner) * mix(1.0, 1.4, layer);
	// shock diamonds: evenly spaced bright knots with dimmer gaps between, shrinking and fading
	// down the plume; they modulate brightness, so the plume stays translucent between them
	float bands = pow(0.5 + 0.5 * cos(along * 6.2831 * 4.5 + 1.2), 8.0) * (1.0 - smoothstep(0.1, 0.75, along));
	float knots = mix(1.0, 0.45 + 1.6 * bands, burner * (1.0 - 0.6 * smoothstep(0.5, 0.9, along)));
	col = mix(col, vec3(1.0, 0.92, 0.85), bands * burner * 0.7);
	// flicker and turbulence: slow breathing plus fast ripples moving down the plume
	float flick = 0.82 + 0.18 * noise1(TIME * 9.0 + seed * 13.0);
	float ripple = 0.75 + 0.25 * noise1(along * 14.0 - TIME * 38.0 + seed * 7.0);
	float a = clamp(edge * reach * strength * knots * flick * ripple, 0.0, 2.0);
	ALBEDO = col * a;
}
