// The afternoon sky (view/craft_view.gd; the emergency run's twilight keeps its own). The air is
// view/atmosphere.gdshaderinc; this adds the two suns themselves: a disc that darkens toward its
// limb, and the tight glare round it that the bloom then spreads. Nothing here changes from frame
// to frame, so the engine filters it for the ambient light and the reflections once.
shader_type sky;

#include "res://view/atmosphere.gdshaderinc"

uniform vec3 zenith : source_color = vec3(0.30, 0.50, 0.80);
uniform vec3 horizon : source_color = vec3(0.58, 0.68, 0.80);
uniform vec3 ground : source_color = vec3(0.36, 0.44, 0.28);

vec3 sun(vec3 dir, vec3 to_light, vec3 colour, float energy, float size) {
	float angle = acos(clamp(dot(dir, to_light), -1.0, 1.0));
	float inside = clamp(angle / max(size, 1e-4), 0.0, 1.0);
	float disc = (1.0 - smoothstep(0.92, 1.0, angle / max(size, 1e-4))) * mix(0.6, 1.0, sqrt(1.0 - inside * inside));
	float glare = exp(-angle / (size * 2.2)) * 0.06 + exp(-angle / (size * 9.0)) * 0.008;
	return colour * energy * (disc + glare);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 col = atmosphere(dir, zenith, horizon, 1.0);
	// below the horizon: the haze, then the land's own colour (the ground plane covers most of it)
	col = mix(col, ground, smoothstep(0.0, -0.3, dir.y));
	if (LIGHT0_ENABLED) {
		col += sun(dir, LIGHT0_DIRECTION, LIGHT0_COLOR, LIGHT0_ENERGY, LIGHT0_SIZE) * step(-0.01, dir.y);
	}
	if (LIGHT1_ENABLED) {
		col += sun(dir, LIGHT1_DIRECTION, LIGHT1_COLOR, LIGHT1_ENERGY, LIGHT1_SIZE) * step(-0.01, dir.y);
	}
	COLOR = col;
}
