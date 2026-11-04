// The Network's city skylines (view/network_world.gd): towers in a MultiMesh (a unit box per tower,
// its colour per instance), lit by the suns, with floor lines and a lit crown. Their own haze, much
// thinner than the scene's fog, so a city stands out of the distance from 100 km off while the
// roads fade at 20 km: the colour falls away into the horizon's (emitted, so the haze isn't lit).
// Every exponent and root takes a clamped argument (MSAA extrapolates edge pixels).
shader_type spatial;
render_mode fog_disabled, cull_back;

uniform vec3 crown = vec3(1.0);                    // the crown's light (sRGB)
uniform vec3 haze_col = vec3(0.72, 0.80, 0.86);    // the horizon's haze (sRGB): the scene's fog colour
uniform float haze = 0.000018;                     // per metre

varying float ly;      // 0 at the foot, 1 at the top
varying vec3 tint;
varying float tall;    // m
varying vec2 facade;
varying float roof;

vec3 lin(vec3 c) {
	return pow(clamp(c, vec3(0.0), vec3(1.0)), vec3(2.2));
}

void vertex() {
	ly = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	tint = COLOR.rgb;
	tall = max(length(MODEL_MATRIX[1].xyz), 1.0);
	float width = length(MODEL_MATRIX[0].xyz);
	float depth = length(MODEL_MATRIX[2].xyz);
	facade = vec2(abs(NORMAL.x)>0.5 ? VERTEX.z*depth : VERTEX.x*width,ly*tall);
	roof = abs(NORMAL.y);
}

void fragment() {
	float d = length(VERTEX);
	float h = clamp(1.0 - exp(-max(d, 0.0) * haze), 0.0, 1.0);
	float f = ly * tall / 4.0;                                            // a floor every 4 m
	float fw = max(fwidth(f), 1e-4);
	float floors = (1.0 - smoothstep(0.25, 0.6, fw)) * 0.12 * step(0.55, fract(f));
	vec3 base = lin(tint) * (0.7 + 0.3 * ly) * (1.0 - floors);
	vec2 cell = facade/vec2(9.0,8.0);
	vec2 pixel = max(fwidth(cell),vec2(0.001));
	vec2 glass = smoothstep(vec2(0.10),vec2(0.10)+pixel,fract(cell))*(1.0-smoothstep(vec2(0.83)-pixel,vec2(0.83),fract(cell)));
	float windows = glass.x*glass.y*(1.0-roof)*(1.0-smoothstep(0.3,1.0,max(pixel.x,pixel.y)));
	base = mix(base,lin(vec3(0.18,0.31,0.39))*(0.65+0.35*ly),windows*0.72);
	float fins = (1.0-smoothstep(0.02,0.07,abs(fract(facade.x/36.0)-0.5)))*(1.0-roof);
	base *= 1.0+fins*0.18;
	float top = smoothstep(1.0 - 14.0 / tall, 1.0, ly);
	ALBEDO = base * (1.0 - h) * (1.0 - top);
	EMISSION = lin(haze_col) * h * 0.85 + lin(crown) * top * 3.0 * (1.0 - 0.7 * h);
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
}
