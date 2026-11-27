// The Vesper's shock pulse (view/weapons/pulse_mount.gd): one low wall standing round the craft on the road's plane, added.
// Its mesh is a wall round the up axis (radius 1, 1 tall, scaled by the ring's radius and its height): UV.y runs from 0 at
// its foot to 1 at its top. White-hot along its foot with `colour` over it, fading soft to nothing at its top, `energy`
// bright. It reads nothing of the eye that draws it (only its UV and these uniforms): the two eyes in the headset draw the
// same ring.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 colour = vec3(0.86, 0.62, 1.0);
uniform vec3 front = vec3(1.0, 0.94, 1.0);
uniform float energy = 1.6;

void fragment() {
	float u = UV.y;
	float foot = 1.0 - smoothstep(0.0, 0.3, u);      // the white-hot foot
	float body = (1.0 - u) * (1.0 - u);               // ... and soft to its top
	ALBEDO = mix(colour, front, foot) * energy;
	ALPHA = clamp(0.55 * body + 0.45 * foot, 0.0, 1.0);
}
