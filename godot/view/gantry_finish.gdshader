// Hot-dip finish and cast concrete share a draw call. Vertex alpha marks metal.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
varying vec3 part_pos;
varying vec4 finish;
void vertex() {
	part_pos = VERTEX;
	finish = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
}
float hash_cell(vec3 v) {
	v = fract(v * vec3(0.1031, 0.1030, 0.0973));
	v += dot(v, v.yxz + 33.33);
	return fract((v.x + v.y) * v.z);
}
void fragment() {
	float metal = step(0.5,finish.a);
	float footprint = length(fwidth(part_pos));
	float flake = hash_cell(floor(part_pos * 11.5)) - 0.5;
	flake *= 1.0 - smoothstep(0.015, 0.12, footprint);
	float patina = sin(part_pos.y*1.3 + sin(part_pos.x*0.57) + part_pos.z*0.9);
	ALBEDO = finish.rgb * (0.98 + 0.037*patina + 0.10*flake);
	METALLIC = mix(0.0,0.67,metal);
	ROUGHNESS = mix(0.94,0.52 + 0.08*flake + 0.04*patina,metal);
	SPECULAR = mix(0.18,0.35,metal);
}
