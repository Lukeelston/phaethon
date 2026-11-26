shader_type spatial;

// The ground outside the hall's two side walls, seen only through an open bay door (garage/bay_doors.gd): a concrete
// apron in jointed 6 m slabs with a yellow lead-out line from each door and a stop bar across it, then mown grass,
// fading with distance into the sky's horizon haze (garage/workshop_sky.gdshader).
uniform sampler2D aggregate : repeat_enable, filter_linear_mipmap_anisotropic;
uniform float wall = 35.0;                 // the hall's half width: the side walls' inner faces
uniform float apron = 42.0;                // how far the concrete runs out from the wall
uniform vec3 rows = vec3(-14.0, 0.0, 14.0);  // the doors' centres along the wall
uniform float door_half = 5.0;
uniform vec3 haze : source_color = vec3(0.47, 0.55, 0.60);    // the sky's far hills (workshop_sky.gdshader) ...
uniform float haze_glow = 1.35;            // ... as bright as the sky draws them
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float d, float half_width, float aa) {
	return 1.0 - smoothstep(half_width - aa, half_width + aa, abs(d));
}

void fragment() {
	float out_from = abs(world.x) - wall;
	vec2 grit = texture(aggregate, world.xz * 0.45).rg - 0.5;
	vec2 aa2 = max(fwidth(world.xz), vec2(0.0008));
	float aa = max(aa2.x, aa2.y);
	// Slabs, 6 m square, with sawn joints that fade under minification.
	vec2 slab = abs(fract(vec2(out_from, world.z) / 6.0 + 0.5) - 0.5) * 6.0;
	float joint = (1.0 - smoothstep(0.006, 0.012 + aa, min(slab.x, slab.y))) * (1.0 - smoothstep(0.05, 0.2, aa));
	vec3 concrete = vec3(0.30, 0.30, 0.28) * (1.0 + grit.x * 0.16) * (1.0 - 0.35 * joint);
	float paint = 0.0;
	vec3 across = vec3(world.z) - rows;
	float lead = step(0.4, out_from) * (1.0 - step(apron - 2.0, out_from));
	float bar = line(out_from - 3.2, 0.11, aa);
	paint = max(paint, max(line(across.x, 0.075, aa), max(line(across.y, 0.075, aa), line(across.z, 0.075, aa))) * lead);
	paint = max(paint, bar * step(min(abs(across.x), min(abs(across.y), abs(across.z))), door_half));
	vec3 apron_paint = mix(concrete, vec3(0.78, 0.55, 0.16) * (1.0 + grit.y * 0.1), paint * 0.92);
	float mown = 0.5 + 0.5 * sin(world.z * 0.42);
	vec3 grass = mix(vec3(0.13, 0.20, 0.08), vec3(0.17, 0.25, 0.10), mown) * (1.0 + grit.x * 0.35);
	float verge = smoothstep(apron, apron + 0.6, out_from);
	vec3 ground = mix(apron_paint, grass, verge);
	float far = 1.0 - exp(-max(out_from - 40.0, 0.0) / 220.0);
	ALBEDO = ground * (1.0 - far);
	ROUGHNESS = mix(0.82 - 0.2 * paint, 0.95, verge);
	METALLIC = 0.0;
	EMISSION = haze * haze_glow * far;
}
