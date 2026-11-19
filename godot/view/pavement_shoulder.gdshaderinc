// Cast panels and a flush slot drain along the outside of a bank. The distance
// comes from the deck mesh, so the channel follows width changes, bends and rolls.
// Paint, slots and joints lose contrast once their spacing becomes subpixel.
float shoulder_band(float d, float half_width, float footprint) {
	float aa = max(0.015, footprint * 0.5);
	return clamp((half_width + aa - abs(d)) / (2.0 * aa), 0.0, 1.0)
		- clamp((aa - half_width - abs(d)) / (2.0 * aa), 0.0, 1.0);
}

float shoulder_repeat(float x, float pitch, float half_width, float footprint) {
	float center = (fract(x / pitch + 0.5) - 0.5) * pitch;
	return mix(shoulder_band(center, half_width, footprint), 2.0 * half_width / pitch,
		smoothstep(0.2, 0.8, footprint / pitch));
}

void apply_paved_shoulder(vec2 p, vec2 shoulder_uv, vec2 fw, inout vec3 col, inout float rough) {
	float d = shoulder_uv.x;
	// The flat carriageway can be a single polygon, with the shoulder distance
	// held constant between its two bank feet. Use that distance's derivative.
	float across = fwidth(d);
	float cover = shoulder_uv.y * shoulder_band(d - 7.8, 7.8, across);
	if (cover > 0.001) {
		// Two courses of precast panels with staggered joints. Keep the
		// underlying pavement's grain in the concrete.
		float course = step(6.5, d);
		float station = p.x + 10.0 * course;
		float panel_id = mod(floor(station / 20.0), 3200.0);
		float batch = hash21(vec2(panel_id, course + 3.0 * step(0.0, p.y))) - 0.5;
		float panel = batch * (1.0 - smoothstep(3.0, 16.0, fw.x));
		vec3 slab = vec3(0.305, 0.314, 0.315) + col * 0.39 + 0.045 * panel;
		float joint = max(shoulder_repeat(station, 20.0, 0.065, fw.x),
			shoulder_band(d - 6.5, 0.055, across));
		slab *= 1.0 - 0.49 * joint;

		// Dark iron channel in a wider concrete rebate. Individual grates
		// have crossbars and end frames, which average to iron at distance.
		float recess = shoulder_band(d - 13.7, 1.18, across);
		float grate = shoulder_band(d - 13.7, 0.79, across);
		float bars = shoulder_repeat(p.x, 0.40, 0.085, fw.x);
		float frame = shoulder_repeat(p.x, 8.0, 0.22, fw.x);
		vec3 iron = vec3(0.115, 0.135, 0.146) + vec3(0.13) * max(bars, frame);
		slab = mix(slab, slab * 0.65, recess);
		slab = mix(slab, iron, grate);

		// Recessed ivory edge stripe and paired maintenance marks. Their
		// long spacing leaves route, braking and launch guidance dominant.
		float stripe = shoulder_band(d - 1.8, 0.36, across);
		float station_pad = shoulder_repeat(p.x, 128.0, 3.7, fw.x);
		float ticks = max(shoulder_band(d - 3.3, 0.38, across),
			shoulder_band(d - 4.9, 0.38, across)) * station_pad;
		slab = mix(slab, vec3(0.85, 0.85, 0.79) * (0.9 + 0.4 * col.g), max(stripe, ticks));
		col = mix(col, slab, cover);
		rough = mix(rough, mix(0.90, 0.67, grate), cover);
	}
}
