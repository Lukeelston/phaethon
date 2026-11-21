// The start panel's own finish (vr/overhead_panel.gd). The pods hang under the roof's header with
// their faces turned down and aft, away from the sky and both suns: lit like the rest of the cockpit
// they are black slabs. What lights them is what lights a real overhead panel: a flood lamp under
// the rail, raking down across each face. Its light is worked out here and given back as the part's
// own colour (no light of the scene's is spent on it, and none of the cockpit's lit pixels pays for
// it), so a face square to the lamp is bright, one turned from it keeps a share (`fill`), and a
// rounded handle is rounded.
// A part's colour is its vertex colour (MeshKit.compound's), as the pilot would name it.
shader_type spatial;

uniform vec3 light = vec3(0.0, 0.77, 0.64);   // toward the lamp, world space (the cockpit turns: set every frame)
uniform float glow = 0.7;                      // what a face square to the lamp gives back of its own colour
uniform float fill = 0.3;                      // ... and what one turned away keeps of that
uniform float sheen = 0.0;                     // the lamp's own highlight (bare metal)
uniform float roughness = 0.6;

void fragment() {
	vec3 colour = pow(COLOR.rgb, vec3(2.2));
	vec3 n = normalize(NORMAL);
	vec3 l = normalize(mat3(VIEW_MATRIX) * light);
	float facing = clamp(0.5 + 0.5 * dot(n, l), 0.0, 1.0);
	float glint = sheen * pow(max(dot(n, normalize(l + VIEW)), 0.0), 26.0);
	ALBEDO = colour;
	ROUGHNESS = roughness;
	METALLIC = 0.0;         // (bare metal that mirrors the sky reads as strips of neon under a roof)
	EMISSION = colour * glow * mix(fill, 1.0, facing * facing) + vec3(glint);
}
