shader_type spatial;

// Each lamp has eight separate molded lens segments. Vertex positions are pod-local.
uniform vec2 brakes = vec2(0.0);
varying float port;

void vertex() {
	port = step(VERTEX.x, 0.0);
}

void fragment() {
	float load = mix(brakes.y, brakes.x, port);
	vec3 lens = vec3(0.46, 0.012, 0.002);
	ALBEDO = lens;
	ROUGHNESS = 0.23;
	METALLIC = 0.08;
	EMISSION = lens * (0.30 + 4.2 * load);
}
