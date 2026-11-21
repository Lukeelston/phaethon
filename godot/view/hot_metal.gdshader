// Metal and ceramic the exhaust washes: the tailpipe's liner, the flame holder's gutters, the vanes,
// the faces of the nozzle's flaps and walls. In daylight its own sooted colour; hot, it glows, and
// not all one colour: each part runs at its own share of the temperature craft_model.gd hands over
// (`kelvin`, from view/jet_exhaust.gd), written into the mesh's vertex alpha (0 is half the rise
// over the air, 1 is 1.1 times it), so the pipe's floor is orange while the flaps' teeth are still
// cherry red. The scale is the one a smith reads: nothing under 798 K (the Draper point), dull red
// by 950, cherry by 1,100, orange by 1,300, yellow past 1,500; and it is a scale for daylight, where
// cherry-red steel is a dull thing beside a sunlit road and only the pipe's shaded inside shows it
// plainly. (JetExhaust.metal_glow() is the same scale, for the tests.)
shader_type spatial;
render_mode shadows_disabled;

uniform float kelvin = 288.0;

vec3 glow(float t) {
	vec3 c = vec3(0.45, 0.02, 0.0) * 0.03 * smoothstep(798.0, 950.0, t);
	c = mix(c, vec3(0.90, 0.07, 0.005) * 0.16, smoothstep(950.0, 1100.0, t));
	c = mix(c, vec3(1.0, 0.22, 0.02) * 0.5, smoothstep(1100.0, 1300.0, t));
	c = mix(c, vec3(1.0, 0.38, 0.06) * 1.0, smoothstep(1300.0, 1450.0, t));
	return mix(c, vec3(1.0, 0.60, 0.20) * 1.8, smoothstep(1450.0, 1600.0, t));
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));      // (the colours are written as paint is, not as light)
	ROUGHNESS = 0.74;
	METALLIC = 0.1;
	EMISSION = glow(288.0 + (kelvin - 288.0) * (0.5 + 0.6 * COLOR.a));
}
