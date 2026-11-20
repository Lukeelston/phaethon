// The Network's city skylines (view/network_world.gd): towers in a MultiMesh (one shared stepped
// mesh, its colour per instance), lit by the suns. Each tower is one of three kinds of building,
// chosen from its place in the city: a glass curtain wall (floor-high panes over a spandrel band,
// between thin mullions), punched windows in masonry, or ribbon glazing between piers. The glass
// is coated: it mirrors the sky, and no two panes sit quite flat, so the reflection breaks up
// pane by pane as it does on a real tower. Some panes have blinds drawn. With `night` up, some
// are lit from inside. Far off the pattern averages out to the facade's overall tone and sheen.
// The towers carry their own haze, much thinner than the scene's fog, so a city stands out of
// the distance from 100 km off while the roads fade at 20 km; it is the same air as the sky
// (atmosphere.gdshaderinc), emitted, so the haze isn't lit twice.
// Every exponent and root takes a clamped argument (MSAA extrapolates edge pixels).
shader_type spatial;
render_mode fog_disabled, cull_back;

#include "res://view/atmosphere.gdshaderinc"

uniform vec3 crown = vec3(1.0);                    // the crown's light (sRGB)
uniform vec3 haze_col = vec3(0.58, 0.68, 0.80);    // the horizon's haze (sRGB): the scene's fog colour
uniform vec3 zenith = vec3(0.19, 0.39, 0.78);      // the sky overhead (sRGB)
uniform float haze = 0.000018;                     // per metre
uniform float suns = 1.0;                          // 0 before dawn: no glow round the suns in the haze
uniform float night = 0.0;                         // 0 afternoon, 1 before dawn: windows lit from inside

varying float ly;      // 0 at the foot, 1 at the top
varying vec3 tint;
varying float tall;    // m
varying vec2 facade;   // m along this face, m up it
varying float roof;
varying flat vec2 style;   // two numbers that belong to this tower alone
varying vec3 along_view;   // the facade's horizontal, in view space

vec3 lin(vec3 c) {
	return pow(clamp(c, vec3(0.0), vec3(1.0)), vec3(2.2));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// How much of a pixel `px` wide, centred at f in a repeating cell, lies inside [lo, hi] (counting
// the cells either side): a pane a pixel or two across keeps its true share of the facade
// instead of shrinking to a dot.
float span(float f, float lo, float hi, float px) {
	float a = f - px * 0.5;
	float b = f + px * 0.5;
	float inside = max(min(b, hi) - max(a, lo), 0.0) + max(min(b, hi + 1.0) - max(a, lo + 1.0), 0.0) + max(min(b, hi - 1.0) - max(a, lo - 1.0), 0.0);
	return clamp(inside / px, 0.0, 1.0);
}

void vertex() {
	// Reshape the tiers above the lower shaft from a number that belongs to this tower alone
	// (its place in the city), so one shared mesh gives a skyline of different ones.
	vec2 place = floor(MODEL_MATRIX[3].xz);
	float kind = fract(sin(dot(place, vec2(127.1, 311.7))) * 43758.5453);
	float other = fract(sin(dot(place, vec2(269.5, 183.3))) * 43758.5453);
	if (VERTEX.y > 0.021) {
		vec2 squeeze = kind < 0.34 ? vec2(1.0) : (kind < 0.67 ? vec2(mix(0.62, 0.9, other)) : vec2(1.12, mix(0.5, 0.8, other)));
		VERTEX.xz *= min(squeeze, vec2(1.16));
	}
	if (VERTEX.y > 0.479) {
		VERTEX.y += (VERTEX.y - 0.479) * 8.0 * step(0.55, other);   // some carry a tall mast
	}
	ly = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	tint = COLOR.rgb;
	tall = max(length(MODEL_MATRIX[1].xyz), 1.0);
	float width = length(MODEL_MATRIX[0].xyz);
	float depth = length(MODEL_MATRIX[2].xyz);
	bool x_face = abs(NORMAL.x) > 0.5;
	facade = vec2(x_face ? VERTEX.z * depth : VERTEX.x * width, ly * tall);
	roof = abs(NORMAL.y);
	style = vec2(fract(kind * 7.31 + other * 3.17), other);
	along_view = normalize((MODELVIEW_MATRIX * vec4(x_face ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0), 0.0)).xyz);
}

void fragment() {
	float d = length(VERTEX);
	float h = clamp(1.0 - exp(-max(d, 0.0) * haze), 0.0, 1.0);
	bool curtain = style.x < 0.52;
	bool punched = !curtain && style.x < 0.84;
	// the facade's grid: a floor every 4 m, a bay every 3 to 6 m
	float bay = mix(3.0, 6.0, style.y);
	vec2 cell = vec2(facade.x / bay, facade.y / 4.0);
	vec2 pane = floor(cell);
	vec2 f = fract(cell);
	vec2 px = max(fwidth(cell), vec2(1e-4));
	float near = 1.0 - smoothstep(0.6, 1.5, max(px.x, px.y));       // 0 once a pane is under a pixel
	float glazed;      // 1 on glass
	float share;       // how much of this kind of facade is glass
	if (curtain) {
		glazed = span(f.x, 0.05, 0.95, px.x) * span(f.y, 0.30, 0.97, px.y);
		share = 0.60;
	} else if (punched) {
		glazed = span(f.x, 0.24, 0.76, px.x) * span(f.y, 0.28, 0.80, px.y);
		share = 0.27;
	} else {
		float pier = span(fract(cell.x / 4.0), 0.07, 0.93, px.x / 4.0);
		glazed = pier * span(f.y, 0.36, 0.86, px.y);
		share = 0.43;
	}
	glazed = mix(share, glazed, near) * (1.0 - roof);
	float seed = hash(pane + style * 91.0);
	float blind = step(0.78, seed) * near;
	// what the wall is made of: the city's colour, pulled most of the way to stone or metal
	vec3 stone = lin(tint);
	stone = mix(vec3(dot(stone, vec3(0.3, 0.55, 0.15))), stone, 0.42) * mix(0.50, 1.05, style.y);
	if (curtain) {
		stone *= 0.55;                                               // dark spandrels and mullions
	}
	// street level sits in the shade of everything round it
	float low = mix(0.62, 1.0, smoothstep(0.0, 70.0, facade.y));
	stone *= low * (0.92 + 0.16 * hash(vec2(pane.y, style.y * 31.0)) * near);
	vec3 glass = mix(vec3(0.46, 0.58, 0.66), vec3(0.55, 0.47, 0.36), step(0.72, style.y)) * (0.85 + 0.3 * seed * near);
	if (punched) {
		glass *= 0.45;                                               // a window set back in a wall is a dark hole
	}
	vec3 drawn = vec3(0.50, 0.48, 0.43) * (0.8 + 0.4 * seed);
	vec3 base = mix(stone, mix(glass, drawn, blind), glazed);
	// roofs and terraces are ballast and plant, not facade
	base = mix(base, vec3(0.16, 0.165, 0.17) * (0.8 + 0.4 * hash(floor(facade.xx * 0.11))), roof * 0.9);
	float shine = glazed * (1.0 - blind) * (1.0 - h);
	// no pane sits quite flat: each leans its own way by a degree or so
	vec3 lean = along_view * (seed - 0.5) * 0.045 + (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz * (hash(pane.yx + 7.0) - 0.5) * 0.03;
	NORMAL = normalize(NORMAL + lean * shine * near);
	// the crown's vertical band is lit; roofs keep their material
	float top = smoothstep(1.0 - 14.0 / tall, 1.0, ly) * (1.0 - roof);
	ALBEDO = base * (1.0 - h) * (1.0 - top);
	METALLIC = shine * (punched ? 0.25 : 0.6);
	ROUGHNESS = mix(0.78, mix(0.26, 0.07 + 0.06 * seed, near), shine);
	SPECULAR = mix(0.35, 0.9, shine) * (1.0 - h);
	// from inside before dawn: a third of the rooms are lit, each its own warmth
	float room = step(0.64, hash(pane * 1.7 + style * 13.0)) * glazed * (1.0 - blind * 0.6);
	vec3 lamp = mix(vec3(1.0, 0.72, 0.38), vec3(0.85, 0.92, 1.0), step(0.8, hash(pane + 3.3)));
	vec3 to_eye = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 air = atmosphere(normalize(vec3(to_eye.x, max(to_eye.y, 0.0) + 0.04, to_eye.z)), lin(zenith), lin(haze_col), suns);
	EMISSION = air * h * 0.85 + lin(crown) * top * 1.6 * (1.0 - 0.7 * h) + lamp * room * night * 1.4 * (1.0 - h);
}
