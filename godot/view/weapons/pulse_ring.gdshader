// The Vesper's shock pulse (view/weapons/pulse_mount.gd): one flat ring on the road's plane, added. Its mesh is a band
// round the up axis (outer radius 1, scaled by the ring's radius): UV.y runs from 0 at its inner edge to 1 at its outer,
// the ring's front. A white-hot front edge with `colour` round it, and a faint wash of it behind, `energy` bright. It
// reads nothing of the eye that draws it (only its UV and these uniforms): the two eyes in the headset draw the same ring.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour = vec3(0.86, 0.62, 1.0);
uniform vec3 front = vec3(1.0, 0.94, 1.0);
uniform float energy = 1.6;

void fragment() {
	float u = UV.y;
	float edge = smoothstep(0.45, 0.93, u) * (1.0 - smoothstep(0.97, 1.0, u));      // the front, sharp on its outer side
	float wash = 0.18 * u * u;                                                       // ... and behind it, fading inward
	ALBEDO = mix(colour, front, edge * edge) * energy;
	ALPHA = clamp(edge + wash, 0.0, 1.0);
}
