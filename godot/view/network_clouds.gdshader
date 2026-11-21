// The Network's clouds: one plane at the cumulus' base. From it the shader walks up through a
// slab of cloud along the line of sight, so the heaps have height: flat grey bases, rounded tops
// that stand in front of one another, and more of their sides showing the further off they are.
// Through the same plane a second, higher layer of cirrus is found along the sight line, so the
// two slide against each other as the craft moves.
// Shapes come from a seamless map (tools/art_sky_hd.py): weather decides where the fields are,
// heaps make the clouds (the same map read finer frays their edges), and each heap's sunward side
// is already marked in it. Low in a dense heap is in its own shade; its top and its suns' side
// are white; thin cloud between the eye and a sun glows. Far off, everything fades into the air
// the sky is made of (atmosphere.gdshaderinc).
// From over the deck (up a mountain) the same walk is made the other way: from the heaps' tops, on
// the eye's side of this plane, down to it, so the eye looks on lit tops and not on bases; and the
// cirrus, which is found by looking up through this plane, is not drawn.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

#include "res://view/atmosphere.gdshaderinc"

uniform sampler2D cloud_cover : repeat_enable, filter_linear_mipmap;
uniform vec2 world_offset;
uniform vec3 zenith : source_color = vec3(0.19, 0.39, 0.78);
uniform vec3 horizon : source_color = vec3(0.58, 0.68, 0.80);
uniform vec3 lit_col = vec3(1.0, 0.975, 0.93);
uniform vec3 shade_col = vec3(0.27, 0.33, 0.46);   // deep in a thick cloud: lit by the sky alone
uniform float cover = 0.62;                        // 0 clear, 1 overcast
uniform float depth = 1900.0;                      // m: the cumulus, base to the highest tops
uniform float cirrus_above = 6000.0;               // m over this plane
uniform float cirrus = 0.42;                       // how much of the high wisps shows (none under an overcast)
// Round the great mountain the deck thins to a few small heaps (it stands in its own clearing): from
// the highway its whole height shows, and from its road the country below does, not a floor of
// cloud. Under an overcast the cover is past what this takes off: the road climbs out through it.
uniform vec2 clearing_at = vec2(0.0);              // the mountain's place in this plane's own space (m)
uniform float clearing = 0.0;                      // how much cover it takes off at its middle

const int STEPS = 20;
const float TEXEL = 23.4;                          // m: one texel of the map at the heaps' scale

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 ray = normalize(world - CAMERA_POSITION_WORLD);
	vec2 q = world.xz + world_offset;
	float weather = texture(cloud_cover, q / 384000.0).r;
	float thinned = cover - clearing * (1.0 - smoothstep(46000.0, 92000.0, length(world.xz - clearing_at)));
	float threshold = mix(0.84, 0.24, clamp(thinned + (weather - 0.5) * 1.3, 0.0, 1.0));
	float through = pow(max(dot(ray, TO_SUN), 0.0), 5.0);
	// the cumulus: up through the slab. Each reading of the map is smoothed to the distance one
	// step slides across it, so neighbouring readings overlap. (Read sharper than its own
	// spacing, as it was, the walk showed every level as a separate sheet, each a cut-out of the
	// one below slid along the view: Luke, in the headset, "like stacks of napkins".) Straight
	// up nothing slides and the map is read sharp; toward the horizon the heaps go soft.
	bool above = ray.y < 0.0;                           // the eye is over the deck, looking down on it
	float climb = abs(ray.y);
	float range = length(world - CAMERA_POSITION_WORLD);
	float path = min(depth / max(climb, 0.02), 15000.0);
	if (above) {
		path = min(path, range);                        // (no further back than the eye)
	}
	float way = above ? -1.0 : 1.0;                     // along the ray from this plane: on, or back toward the eye
	float pace = path / float(STEPS);
	float blur = max(log2(pace * length(ray.xz) / TEXEL) - 0.5, 0.0);
	// ... and never sharper than the screen can show. Toward the horizon one pixel row spans a
	// kilometre of the map, so neighbouring rows read unrelated cloud: fine lines across the far
	// sky, the other half of the stacked look (and the headset's pixels are that coarse).
	blur = max(blur, textureQueryLod(cloud_cover, q / 48000.0).y);
	// the frayed edge is read once, half way up the slab: fine detail that cannot stack
	float fray = texture(cloud_cover, (q + ray.xz * way * path * 0.5) / 9600.0).g;
	float clear = 1.0;
	vec3 lit = vec3(0.0);
	// The map is read at the ends of each step. A cloud's edge is taken to lie where a straight line
	// between two readings crosses it, and only that much of the step is cloud: so an edge slides
	// smoothly through a step. (Each step used to switch on whole, and every step's edge drew its
	// own faint contour across the far clouds, like a relief map.)
	float e0 = -1.0;                                       // under the base: no cloud
	float h0 = 0.0;
	float side0 = 0.5;
	for (int i = 0; i <= STEPS; i++) {
		float along = above ? path - float(i) * pace : float(i) * pace;   // nearest the eye first, either way
		float h = min(along * climb / depth, 1.0);          // 0 at the base, 1 at the tops
		vec4 heap = textureLod(cloud_cover, (q + ray.xz * way * along) / 48000.0, blur);
		// a heap narrows as it rises, so its top is a dome over a flat base
		float e1 = heap.g * 0.82 + fray * 0.18 - threshold - h * h * 0.30;
		if (i > 0 && (e0 > 0.0 || e1 > 0.0)) {
			bool whole = e0 > 0.0 && e1 > 0.0;
			float part = whole ? 1.0 : max(e0, e1) / (abs(e0) + abs(e1));
			float excess = whole ? 0.5 * (e0 + e1) : 0.5 * max(e0, e1);
			// where the cloudy part of the step sits between its ends: its far end if the ray is going in
			float mid = whole ? 0.5 : (e1 > e0 ? 1.0 - 0.5 * part : 0.5 * part);
			float hm = mix(h0, h, mid);
			float side = mix(side0, heap.b, mid);
			float rho = smoothstep(0.0, 0.12, excess);
			// (a long step is not let to hide everything behind it in one go: far heaps would band)
			float a = 1.0 - exp(-rho * part * min(pace, 380.0) / 300.0);
			// light: the sky alone low in a dense heap; the suns higher up and on the side facing them
			float sun = clamp(0.04 + 0.78 * hm + (side - 0.5) * (0.5 + 1.0 * hm) + 0.6 * (1.0 - smoothstep(0.0, 0.16, excess)), 0.0, 1.0);
			vec3 c = mix(shade_col, lit_col, sun);
			c += lit_col * 0.45 * through * (1.0 - smoothstep(0.0, 0.2, excess)) + SUN2_GLOW * 0.07 * side * sun;
			lit += clear * a * c;
			clear *= 1.0 - a;
			if (clear < 0.04) {
				break;
			}
		}
		e0 = e1;
		h0 = h;
		side0 = heap.b;
	}
	float a_cumulus = 1.0 - clear;
	// the cirrus, where this line of sight meets the higher layer
	vec2 q2 = q + ray.xz / max(ray.y, 0.03) * cirrus_above;
	float wisps = smoothstep(0.50, 0.98, texture(cloud_cover, q2 / 128000.0).a + (texture(cloud_cover, q2 / 384000.0).r - 0.5) * 0.5);
	// (from under the deck only, and thinning out as the eye climbs to it: there is no plane up there to draw it on from above)
	float a_cirrus = above ? 0.0 : wisps * cirrus * (1.0 - smoothstep(-1500.0, -150.0, CAMERA_POSITION_WORLD.y - world.y));
	// near over far, then the air between here and there
	float alpha = a_cumulus + a_cirrus * clear;
	vec3 col = (lit + lit_col * (0.92 + 0.45 * through) * a_cirrus * clear) / max(alpha, 1e-4);
	col = mix(col, atmosphere(ray, zenith, horizon, 1.0), 1.0 - exp(-range / 52000.0));
	ALBEDO = col;
	ALPHA = alpha * (1.0 - smoothstep(110000.0, 172000.0, range));
}
