shader_type spatial;
render_mode cull_disabled;
#include "res://view/noise.gdshaderinc"
varying vec3 paint;
varying vec3 position_local;
varying vec3 normal_local;
void vertex() {
	paint=pow(COLOR.rgb,vec3(2.2));
	position_local=VERTEX;
	normal_local=NORMAL;
}
void fragment() {
	// Geometry retains the existing vertex-painted bands. Restrict concrete
	// weathering to neutral vertical faces so road markings stay crisp.
	float neutral=1.0-smoothstep(0.025,0.12,max(paint.r,max(paint.g,paint.b))-min(paint.r,min(paint.g,paint.b)));
	float side=1.0-smoothstep(0.55,0.92,abs(normal_local.y));
	vec2 coord=vec2(position_local.x+position_local.z,position_local.y);
	float weather=pnoise(coord/vec2(7.0,90.0),1048576.0);
	float grit=pnoise(coord*2.0,1048576.0);
	float detail=1.0-smoothstep(0.5,4.0,length(fwidth(coord)));
	float seam_distance=min(mod(position_local.y,18.0),18.0-mod(position_local.y,18.0));
	float seam=(1.0-smoothstep(0.10,0.30,seam_distance))*(1.0-smoothstep(0.5,4.0,fwidth(position_local.y)));
	float variation=0.78+0.16*weather+0.08*grit*detail-0.14*seam;
	ALBEDO=paint*mix(1.0,variation,side*neutral);
	ROUGHNESS=mix(0.72,0.94,neutral);
	SPECULAR=0.22;
}
