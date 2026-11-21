// The afternoon air, as one function shared by the sky (view/sky.gdshader), the cloud deck and the
// towers' haze, so that anything fading into the distance fades into the sky that is behind it.
// Directions are unit vectors in world space (y up); colours are linear.
//   deep blue overhead paling to the haze as the path through the air lengthens toward the horizon;
//   a little lighter on the suns' side of the sky and deeper away from it;
//   a wide warm glow round each sun, tighter and brighter close in, and stronger low down where
//   there is more air to scatter it.
// The suns' directions and glow are the project's (project.godot [shader_globals]): their defaults
// are the afternoon's, the white primary at CraftView.SUN_ROT and its orange companion, as these
// constants were. Another time of day or weather sets them (view/outlook.gd).
global uniform vec3 sky_sun;
global uniform vec3 sky_sun2;
global uniform vec3 sky_sun_glow;
global uniform vec3 sky_sun2_glow;
#define TO_SUN sky_sun
#define TO_SUN2 sky_sun2
#define SUN_GLOW sky_sun_glow
#define SUN2_GLOW sky_sun2_glow

vec3 atmosphere(vec3 dir, vec3 zenith, vec3 horizon, float suns) {
	float up = max(dir.y, 0.0);
	float air = 1.0 / (up + 0.085);                     // about 1 overhead, 12 at the horizon
	float pale = 1.0 - exp(-0.42 * (air - 0.92));
	vec3 col = mix(zenith, horizon, pale);
	float toward = dot(dir, TO_SUN);
	col *= 1.0 + 0.14 * toward * suns;
	float thick = 0.3 + 0.7 * pale;
	float g = max(toward, 0.0);
	col += SUN_GLOW * suns * thick * (0.09 * pow(g, 8.0) + 0.20 * pow(g, 64.0));
	g = max(dot(dir, TO_SUN2), 0.0);
	col += SUN2_GLOW * suns * thick * (0.05 * pow(g, 8.0) + 0.12 * pow(g, 64.0));
	return col;
}
