// Rain (view/outlook.gd): thin streaks in a box that rides with the eye. Each streak's six vertices
// start at one point of the box; here it is carried back through the box by the craft's travel and
// down by its own fall, and drawn as a sliver along the way it is moving, turned to face the eye.
// Standing still it falls; at speed it comes at the pilot nearly level, longer the faster. Nothing
// is drawn through the cabin (a corridor round the eye's own line is left empty) or right at the eye.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 box = vec3(22.0, 12.0, 90.0);   // across, up, ahead (m)
uniform float travel = 0.0;                  // how far the craft has come, wrapped to the box's length
uniform float fall = 0.0;                    // how far the rain has fallen, wrapped to its height
uniform float speed = 0.0;                   // the craft's, m/s
uniform vec3 tint = vec3(0.8, 0.85, 0.9);
uniform float cover = 0.0;                   // 1 under a roof: nothing falls there
uniform float snow = 0.0;                    // 1: flakes. They drift down a sixth as fast, wander, are short and broad, and nearly white

varying float shown;

void vertex() {
	float seed = COLOR.r;
	vec3 at = VERTEX;
	at.z = -mod(-at.z - travel * (0.85 + 0.3 * seed) + box.z, box.z);       // toward the eye, and round again at the far end
	at.y = mod(at.y - fall * (0.8 + 0.4 * seed) + 0.5 * box.y, box.y) - 0.5 * box.y;
	at.x += snow * 0.6 * sin(fall * 1.7 + seed * 40.0);                      // a flake wanders as it comes down
	vec3 way = normalize(vec3(0.0, -mix(9.0, 1.7, snow), speed + 0.5));      // the way it moves past the eye
	float len = mix(clamp(0.25 + speed * 0.0045, 0.25, 7.0), clamp(0.07 + speed * 0.0011, 0.07, 1.8), snow) * (0.7 + 0.6 * seed);
	vec3 turned = cross(way, normalize(at));                                 // across the streak, facing the eye
	vec3 across = dot(turned, turned) > 0.0004 ? normalize(turned) : vec3(1.0, 0.0, 0.0);
	vec3 p = at + way * len * (UV.y - 0.5) + across * mix(0.011 + 0.006 * seed, 0.05 + 0.035 * seed, snow) * (UV.x - 0.5);
	// not through the cabin, nor on the eye
	float cabin = step(abs(at.x), 1.7) * step(abs(at.y + 0.3), 1.5);
	shown = (1.0 - cabin) * smoothstep(1.5, 5.0, -at.z) * (1.0 - smoothstep(0.7 * box.z, box.z, -at.z));
	VERTEX = p;
}

void fragment() {
	ALBEDO = mix(tint, vec3(0.94, 0.96, 0.98), snow);
	// (a streak is a pixel or two wide: under multisampling its UV is read at pixel centres that lie
	// outside it, so nothing here may go negative, or the blend takes light away: black specks)
	float along = clamp(UV.y, 0.0, 1.0);
	ALPHA = clamp(shown, 0.0, 1.0) * (1.0 - cover) * mix(0.30, 0.72, snow) * clamp(1.0 - pow(abs(2.0 * along - 1.0), 3.0), 0.0, 1.0)     // tapered to its ends
		* mix(1.0, clamp(1.0 - pow(abs(2.0 * clamp(UV.x, 0.0, 1.0) - 1.0), 2.0), 0.0, 1.0), snow);      // (a flake is soft at its sides too)
}
