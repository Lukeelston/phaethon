// Slot jet with a contracting luminous core inside a rolling shear layer.
// Gas flows through fixed pressure cells; the nozzle fixes the upstream boundary.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://view/effect_exclusion.gdshaderinc"

uniform sampler2D flow_map : repeat_enable, filter_linear_mipmap;
uniform float thrust = 0.0;
uniform float burner = 0.0;
uniform float ramjet = 0.0;
uniform float layer = 0.0;
uniform float seed = 0.0;
uniform float aspect = 4.0;
uniform float wake_bend = 0.0;
varying float along;
varying vec3 jet_axis;
varying float span;

float cell_phase(float z) {
	// Expansion cells shorten and lose definition as the jet mixes downstream.
	return z * (3.9 + 1.95*z) + 0.04;
}

void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
	float z = along;
	vec2 circle = normalize(VERTEX.xz);
	span = circle.x;
	vec2 slot = sign(circle)*pow(abs(circle),vec2(mix(0.53,1.0,smoothstep(0.0,0.38,z))));
	float cell = cos(TAU * cell_phase(z));
	float pulse = 0.5 + 0.5*cell;
	float gas = textureLod(flow_map,vec2(UV.x*2.0+seed,z*1.7-TIME*1.5),1.0).r-0.5;
	float mix_out = smoothstep(0.04,0.65,z);
	float outer = (1.0+0.16*sin(PI*z)+mix_out*gas*0.66)*(1.0-smoothstep(0.57,1.0,z)*0.76);
	float core = mix(0.38,0.99,pulse)*(1.0-0.54*z);
	core = mix(0.90*(1.0-0.77*z),core,smoothstep(0.0,0.10,z)*mix(0.18,0.88,burner));
	VERTEX.xz = slot*mix(outer,core,layer);
	VERTEX.xz += mix_out*vec2(0.095*sin(9.0*z-TIME*4.1+seed),0.13*cos(13.0*z-TIME*4.7+seed));
	VERTEX.x += wake_bend*z*z*mix(1.04,0.94,layer);
	jet_axis = (MODELVIEW_MATRIX*vec4(0.0,-1.0,0.0,0.0)).xyz;
	effect_world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	float z = clamp(along,0.0,1.0);
	vec2 stream = vec2(2.0*UV.x+seed,2.0*z-TIME*(1.2+0.52*burner));
	vec2 flow = texture(flow_map,stream).rg;
	float wisps = texture(flow_map,vec2(5.0*UV.x+flow.r*0.33+seed,3.0*z-TIME*2.1)).b;
	float axial = abs(dot(normalize(jet_axis),normalize(VIEW)));
	float chord = min(abs(dot(normalize(NORMAL),normalize(VIEW)))/max(0.10,1.0-axial*axial),1.45);
	float edge = min(chord,0.12 + z*aspect/max(axial,0.08));
	float shear = smoothstep(0.17+0.24*z,0.80,flow.r*0.60+wisps*0.40);
	float cells = pow(0.5-0.5*cos(TAU*cell_phase(z)),2.6)*(1.0-smoothstep(0.27,0.87,z));
	float crossing = abs(2.0*fract(cell_phase(z)+0.5)-1.0);
	float shock = (1.0-smoothstep(0.03,0.28,abs(crossing-abs(span)*0.82))) * (1.0-smoothstep(0.35,0.86,z));
	float reach = 1.0-smoothstep(mix(0.24,0.46,burner),0.97,z);
	float dry = smoothstep(0.0,0.9,thrust);
	vec3 blue = vec3(0.035,0.23,1.05);
	vec3 violet = vec3(0.23,0.12,0.81);
	vec3 amber = vec3(1.32,0.26,0.047);
	vec3 outer = mix(blue,violet,smoothstep(0.04,0.32,z));
	outer = mix(outer,mix(amber,vec3(0.17,0.57,1.04),ramjet),smoothstep(0.13,0.45,z)*burner);
	vec3 core = mix(vec3(0.15,0.49,1.12),mix(vec3(1.32,0.52,0.13),vec3(0.30,0.65,1.25),ramjet),
		smoothstep(0.10,0.36,z)*burner);
	float compression = clamp(0.65*cells+0.65*shock,0.0,1.0);
	core = mix(core,vec3(1.54,1.41,1.19),compression*mix(0.30,0.90,burner));
	float skin = (0.045+0.80*shear)*mix(0.32,0.70,burner);
	float mixing = smoothstep(0.12+0.26*z,0.71,flow.g*0.72+wisps*0.28);
	float bright = (0.12+0.24*(1.0-smoothstep(0.0,0.18,z))+1.19*compression)*(0.27+0.80*mixing);
	float energy = mix(0.12+0.60*dry,1.06,burner);
	float cabin = exterior_effect_visibility(effect_world_position,CAMERA_POSITION_WORLD);
	ALBEDO = mix(outer,core,layer);
	ALPHA = clamp(mix(skin,bright,layer)*energy*reach*edge*cabin,0.0,1.0);
}
