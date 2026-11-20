// The afternoon air, as one function shared by the sky (view/sky.gdshader), the cloud deck and the
// towers' haze, so that anything fading into the distance fades into the sky that is behind it.
// Directions are unit vectors in world space (y up); colours are linear.
//   deep blue overhead paling to the haze as the path through the air lengthens toward the horizon;
//   a little lighter on the suns' side of the sky and deeper away from it;
//   a wide warm glow round each sun, tighter and brighter close in, and stronger low down where
//   there is more air to scatter it.
const vec3 TO_SUN = vec3(0.6824, 0.5, 0.5332);        // the white primary (CraftView.SUN_ROT)
const vec3 TO_SUN2 = vec3(0.7911, 0.4067, 0.4568);    // its orange companion
const vec3 SUN_GLOW = vec3(1.0, 0.93, 0.80);
const vec3 SUN2_GLOW = vec3(1.0, 0.60, 0.28);

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
