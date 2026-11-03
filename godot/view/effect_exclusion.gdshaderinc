// The full cabin/footwell plus headroom, in its drawn pod-local frame. A short exterior
// fade avoids a hard cut in the dust; outside this envelope the original effect is unchanged.
// Camera position comes from the current render view (the tracked stereo midpoint in XR),
// so leaning/recentring and late headset poses cannot move an eye into a stale CPU mask.
uniform bool effect_mask_enabled = false;
uniform mat4 effect_world_to_pod;
varying vec3 effect_world_position;

float exterior_effect_visibility(vec3 world_position, vec3 camera_position) {
	if (!effect_mask_enabled) {
		return 1.0;
	}
	vec3 cabin = (effect_world_to_pod * vec4(world_position, 1.0)).xyz;
	vec3 q = abs(cabin - vec3(0.0, 0.1, 0.0)) - vec3(1.35, 1.2, 2.5);
	float outside = length(max(q, vec3(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
	float cabin_clearance = smoothstep(0.0, 0.35, outside);
	// 0.6 m clear around the tracked head covers both eyes; restore the cue by 1.1 m.
	float eye_clearance = smoothstep(0.6, 1.1, distance(world_position, camera_position));
	return min(cabin_clearance, eye_clearance);
}
