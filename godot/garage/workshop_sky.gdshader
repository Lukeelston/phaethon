shader_type sky;

// Two skies in one. The hall's reflections and ambient light still come from the panorama captured inside it (the
// radiance pass, as the PanoramaSkyMaterial it replaces drew it), so nothing inside the hall changes. What a pilot
// sees through an open bay door (garage/bay_doors.gd), the only place the background shows, is daylight: a clear sky
// paling toward a low line of hazy hills, with a soft glow around the clerestory's low sun. Through a door 30 m off
// only the first ten degrees above the horizon show, so the blue has to begin low.
uniform sampler2D panorama : source_color, filter_linear, hint_default_black;
uniform vec3 sun = vec3(0.0, 0.36, 0.93);    // toward the sun: the hall's ClerestoryDaylight, reversed
uniform vec3 zenith : source_color = vec3(0.30, 0.52, 0.86);
uniform vec3 horizon : source_color = vec3(0.70, 0.80, 0.90);
uniform vec3 hills : source_color = vec3(0.47, 0.55, 0.60);     // the far ridge, blue with distance
uniform float brightness = 1.35;

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = texture(panorama, SKY_COORDS).rgb;
	} else {
		float up = EYEDIR.y;
		vec3 day = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.35));
		// A ridge a degree or two high all round, its skyline from the bearing (no texture to fetch).
		float bearing = atan(EYEDIR.x, EYEDIR.z);
		float skyline = 0.022 + 0.012 * sin(bearing * 5.0 + 0.7) + 0.007 * sin(bearing * 13.0 + 2.1)
				+ 0.004 * sin(bearing * 31.0);
		float aa = max(fwidth(up), 0.0004);
		day = mix(day, hills, 1.0 - smoothstep(skyline - aa, skyline + aa, up));
		float toward = max(dot(EYEDIR, normalize(sun)), 0.0);
		day += vec3(1.0, 0.90, 0.74) * (0.22 * pow(toward, 9.0) + 2.5 * pow(toward, 900.0));
		COLOR = day * brightness;
	}
}
