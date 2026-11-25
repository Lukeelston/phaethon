shader_type spatial;

uniform sampler2D aggregate : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float plane_center_z;
// Side wall X, rear and front wall Z, and half the clear portal width.
uniform vec4 walls;
varying vec2 floor_m;

void vertex() {
	floor_m = VERTEX.xz + vec2(0.0,plane_center_z);
}

float distance_to_foot(vec2 to_center, vec2 half_size) {
	return length(max(abs(to_center)-half_size,vec2(0.0)));
}

void fragment() {
	// A fine mineral broadcast and broad squeegee passes show through the resin.
	vec4 grain = texture(aggregate, floor_m * 1.65);
	vec2 stroke_m = vec2(dot(floor_m,vec2(.84,.54)),dot(floor_m,vec2(-.54,.84)));
	float undercoat = texture(aggregate,stroke_m*vec2(.079,.127)+vec2(.47,.11)).a - .5;
	float flank = smoothstep(4.02, 4.65, abs(floor_m.x));
	float traffic = (1.0 - smoothstep(0.65, 2.05, abs(floor_m.x))) * (1.0 - flank);
	float mix_grain = grain.r - .54;
	float side_or_rear = min(walls.x-abs(floor_m.x),floor_m.y-walls.y);
	float front = length(max(vec2(walls.w-abs(floor_m.x),walls.z-floor_m.y),vec2(0.0)));
	float clearance = min(side_or_rear,front);
	// The three actual plinths stand directly on the slab. The centre knee space
	// under the inspection counter receives light between the two pedestals.
	clearance = min(clearance,distance_to_foot(floor_m-vec2(walls.x-.32,-3.44),vec2(.275,.760)));
	clearance = min(clearance,distance_to_foot(floor_m-vec2(-1.34,walls.y+.45),vec2(.355,.335)));
	clearance = min(clearance,distance_to_foot(floor_m-vec2(1.28,walls.y+.45),vec2(.425,.335)));
	float contact = smoothstep(-.09,.32,clearance);
	float knee = smoothstep(0.0,.78,distance_to_foot(floor_m-vec2(0.0,walls.y+.41),vec2(1.75,.37)));
	float visibility = min(.53+.47*contact,.87+.13*knee);
	AO = visibility;
	AO_LIGHT_AFFECT = .14;
	ALBEDO = mix(vec3(.156,.194,.185),vec3(.121,.154,.149),flank)
			* (1.0 + .29*mix_grain + .32*undercoat) * mix(.74,1.0,visibility);
	ROUGHNESS = .64 - .10*traffic + .16*mix_grain + .14*undercoat;
	NORMAL_MAP = vec3(grain.gb,1.0);
	NORMAL_MAP_DEPTH = .075;
}
