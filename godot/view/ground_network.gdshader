// The Network's floor: the plane that rides under the pod (CraftView's `ground`), on the Network. Its land
// there is each region's colour by its weight (NetworkLandscape.setup_ground), mottled by the gravel's
// noise: view/ground.gdshader's own answer for the Network (its `network_on`), and nothing else (the two are
// drawn against each other, pixel for pixel, by tests/test_network_ground_render.gd).
// That shader works out its sand, its dry lake, its scrub, its other landscapes, their cracks and its
// grain for every pixel, and on the Network threw all of it away. The terrain lies over this plane for
// 54 km round the craft, so on a road little of it shows; from Mount Hyperion's brink, 48 km up, it is the
// whole country below, and it was the dearest thing in that view (GPU at two eyes' worth of pixels, the
// brink looking down: 4.01 ms a frame with that shader, 3.76 with this).
// No shadow is asked of it: the sun's shadows reach 450 m, the terrain covers it for a hundred times
// that, and the asking is not free (the renderer reads the sun's shadow map for every lit pixel however
// far off it is: a third of what this saves).
shader_type spatial;
render_mode cull_back, shadows_disabled;

#include "res://view/noise.gdshaderinc"

const float PERIOD = 4096.0;        // view/ground.gdshader's
uniform vec2 org = vec2(0.0);       // the pod's (sim x, sim y) mod PERIOD
uniform vec2 absolute_org;          // ... and whole
uniform vec3 regions[9];            // each region's middle (x, y) and reach
uniform vec4 region_colors[9];
// What CraftView and the dawn set on every track's floor, and this one has no use for (kept, so that
// setting them and reading them back is what it is on the others).
uniform float pod_y = 0.0;
uniform float playa = 0.0;
uniform float playa_half = 320.0;
uniform float verdant = 0.0;
uniform float ice = 0.0;
uniform float basalt = 0.0;
uniform float mesa = 0.0;
uniform bool network_on = true;
uniform float dawn_on = 0.0;
uniform vec2 dawn_u = vec2(1.0, 0.0);
uniform float dawn_f = 0.0;

varying vec2 lp;   // plane-local render xz

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	vec2 p = vec2(org.x + lp.x, org.y - lp.y);   // sim metres, mod PERIOD
	float n3 = pfbm(p / 16.0, PERIOD / 16.0);    // the gravel's mottling
	vec2 world_p = absolute_org + vec2(lp.x,-lp.y);
	vec3 geographic = vec3(0.0);
	float total = 0.0;
	for (int i=0;i<9;i++) {
		float d = max(length(world_p-regions[i].xy)/regions[i].z,0.035);
		float w = 1.0/(d*d*d*d);
		geographic += region_colors[i].rgb*w;
		total += w;
	}
	ALBEDO = srgb(geographic/total*(0.88+0.16*n3));
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
