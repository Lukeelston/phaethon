shader_type spatial;
render_mode cull_disabled;

uniform vec2 loads = vec2(0.0);
uniform vec4 low : source_color = vec4(0.31,0.84,0.77,1.0);
uniform vec4 high : source_color = vec4(1.0,0.65,0.21,1.0);
uniform vec4 limit : source_color = vec4(1.0,0.23,0.12,1.0);

void fragment(){
	// Each bar grows away from the pilot's centreline. A dark witness mark
	// remains at zero load. The last segment corresponds to a 120 kN cable load.
	float force = UV.y < 0.5 ? loads.x : loads.y;
	float cell = floor(min(UV.x,0.9999)*6.0);
	float edge = abs(fract(UV.x*6.0)-0.5);
	float ink = 1.0-smoothstep(0.38,0.46,edge);
	vec3 led = cell < 3.0 ? low.rgb : (cell < 5.0 ? high.rgb : limit.rgb);
	float lit = smoothstep(cell+0.10,cell+0.40,force*5.5);
	ALBEDO = mix(vec3(0.012),led*(0.05+0.40*lit),ink);
	EMISSION = led*ink*lit*1.45;
	ROUGHNESS = 0.38;
}
