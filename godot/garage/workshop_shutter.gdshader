shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D numbers : hint_default_black, repeat_disable, filter_linear_mipmap_anisotropic;
uniform sampler2D powder : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
varying vec2 sheet;
varying flat int bay;

void vertex() {
	sheet = VERTEX.xy;
	bay = INSTANCE_ID;
}

void fragment() {
	// Print directly on the corrugations. Every facet carries its portion
	// of the digit and still catches its own highlight as the pilot walks.
	vec2 uv = (sheet - vec2(0.0, 2.64)) / vec2(2.85, -2.45) + .5;
	vec2 tile = vec2(float(bay % 3), float(bay / 3));
	vec2 cell_size = vec2(3.0, 2.0);
	float numeral = textureGrad(numbers, (clamp(uv,0.0,1.0) + tile) / cell_size,
			dFdx(uv)/cell_size, dFdy(uv)/cell_size).r;
	vec2 grit = texture(powder, sheet * 3.3).rg - .5;
	float toe_wear = 1.0 - smoothstep(.06, .65, sheet.y);
	vec3 galvanized = mix(vec3(.157,.195,.201),vec3(.126,.155,.158),toe_wear);
	ALBEDO = mix(galvanized * (1.0+grit.x*.12),vec3(.72,.75,.67),numeral*.90);
	METALLIC = mix(.63,.18,numeral);
	ROUGHNESS = mix(.48 + toe_wear*.13 + grit.y*.18,.65,numeral);
}
