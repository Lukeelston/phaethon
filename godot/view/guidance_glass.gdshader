// Transparent optical combiner. The sweep is driven by the instrument state
// rather than TIME, so countdown updates do not flash and a settled display is still.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, depth_draw_never;

uniform float scan : hint_range(0.0, 1.0) = 0.0;
uniform vec4 signal : source_color = vec4(0.45,0.92,1.0,1.0);
uniform float direction = 0.0;
uniform bool wrong_way = false;
uniform float pointer = 1.0;       // 0: the gutter's arrow is left out (the start-up draws its own pointer there)

float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b-a;
	return length(p-a-clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0)*ab);
}

void fragment() {
	// Working in units of glass height keeps strokes isotropic in both eyes.
	vec2 p = (UV-0.5)*vec2(4.123,1.0);
	vec2 a = abs(p)-vec2(2.055,0.492);
	float edge = max(max(a.x,a.y), (a.x+a.y+0.095)*0.7071);
	float aa = max(fwidth(p.y),0.002);
	float inside = 1.0-smoothstep(-aa,aa,edge);
	float reveal = 1.0-smoothstep(scan-aa,scan+aa,UV.y);
	if (inside*reveal < 0.005) { discard; }
	float rim = 1.0-smoothstep(0.004,0.010+aa,abs(edge+0.014));
	float brackets = max(step(1.86,abs(p.x)),step(0.462,abs(p.y))*step(abs(p.x),0.81));
	float divider = 1.0-smoothstep(0.001,0.004+aa,abs(p.y-0.143));
	divider *= smoothstep(-1.48,-1.30,p.x)*(1.0-smoothstep(1.85,1.96,p.x));
	float gutter = (1.0-smoothstep(0.002,0.005+aa,abs(p.x+1.53)))*(1.0-smoothstep(0.28,0.40,abs(p.y)));
	vec2 icon = vec2(p.x+1.79, -p.y);
	float glyph;
	if (wrong_way) {
		glyph = min(segment(icon,vec2(-0.09,0.09),vec2(0.09,-0.09)),segment(icon,vec2(-0.09,-0.09),vec2(0.09,0.09)));
	} else {
		vec2 aim = normalize(vec2(direction,1.0));
		vec2 normal = vec2(aim.y,-aim.x);
		vec2 tip = aim*0.14;
		glyph = min(segment(icon,-aim*0.14,tip),min(segment(icon,tip,normal*0.097),segment(icon,tip,-normal*0.097)));
	}
	float arrow = (1.0-smoothstep(0.014,0.023+aa,glyph))*pointer;
	float flare = (1.0-smoothstep(0.0,0.066,abs(UV.y-scan)))*smoothstep(0.0,0.08,scan)*(1.0-smoothstep(0.91,1.0,scan));
	float marks = max(rim*mix(0.32,0.96,brackets),max(divider*0.48,gutter*0.55));
	float etched = 0.023*cos(UV.y*175.93)*(1.0-smoothstep(0.008,0.022,aa));
	vec3 glass = mix(vec3(0.008,0.034,0.048),vec3(0.014,0.081,0.10),exp(-8.0*UV.y));
	vec3 glow = vec3(0.20,0.79,0.90);
	ALBEDO = mix(glass*(1.0+etched),glow,marks) + signal.rgb*(arrow*1.13+flare*0.45);
	ALPHA = inside*reveal*max(0.72-0.12*smoothstep(0.2,1.0,UV.y),max(marks,max(arrow,flare)));
}
