shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://view/noise.gdshaderinc"
uniform vec2 world_offset;
varying vec2 p;
varying vec3 local;
void vertex() { p = (VERTEX.xz + world_offset) / 18000.0; local = VERTEX; }
void fragment() {
	float cloud = pfbm(p,128.0);
	float edge = smoothstep(0.47,0.66,cloud);
	float horizon = 1.0-smoothstep(60000.0,170000.0,length(local.xz));
	ALBEDO = mix(vec3(0.55,0.65,0.77),vec3(0.94,0.95,0.96),smoothstep(0.48,0.72,cloud));
	ALPHA = edge * horizon * 0.68;
}
