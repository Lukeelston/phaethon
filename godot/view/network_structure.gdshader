shader_type spatial;
render_mode cull_disabled;
#include "res://view/noise.gdshaderinc"
varying vec3 paint;
varying vec3 position_local;
varying vec3 normal_local;
void vertex() {
	paint=pow(COLOR.rgb,vec3(2.2));
	position_local=VERTEX;
	normal_local=NORMAL;
}

// A signed clearance from an axis-aligned rectangle, filtered independently
// along and up the wall. Long panels stay distinct at glancing angles.
float panel_rect(vec2 q, vec2 aa) {
	vec2 coverage = 1.0 - smoothstep(-aa, aa, q);
	return coverage.x * coverage.y;
}

void fragment() {
	if (UV.y > 15.0) {
		vec2 p = UV - vec2(0.0, 16.0);
		vec2 aa = max(fwidth(p) * 0.5, vec2(0.004));
		float panel = mod(floor(p.x / 12.0), 240.0);
		float x = (fract(p.x / 12.0 + 0.5) - 0.5) * 12.0;
		float streak = pnoise(vec2(p.x / 2.0, p.y / 7.0), 1440.0);
		float grain = pnoise(p * 5.0, 14400.0);
		float formwork = 0.96 + 0.10 * (hash21(vec2(panel, 1.0)) - 0.5)
			+ 0.19 * (streak - 0.5) + 0.11 * (grain - 0.5) * detail(0.2, length(aa) * 2.0);
		float expansion = aline(abs(x), 0.055, aa.x * 2.0);
		float bevel = aline(abs(x - 0.15), 0.050, aa.x * 2.0);
		float toe = 1.0 - smoothstep(0.08, 0.46 + 0.35 * streak, p.y);
		vec3 body = paint * formwork * (1.0 - 0.55 * expansion + 0.20 * bevel - 0.27 * toe);

		// Sleeve recesses from the concrete forms. Two rows in each pour.
		float tie_x = (fract(p.x / 6.0) - 0.5) * 6.0;
		float tie_y = min(abs(p.y - 0.84), abs(p.y - 2.55));
		float tie = aline(length(vec2(tie_x, tie_y)), 0.11, length(aa) * 2.0);
		body *= 1.0 - 0.56 * tie;

		// The taller city walls carry bolted access hatches with louvres
		// and a small identification tab. The hardware is flush to the face.
		float hx = (fract(p.x / 48.0) - 0.5) * 48.0;
		vec2 at = vec2(hx, p.y - 4.55);
		vec2 hatch_edge = abs(at) - vec2(3.30, 0.77);
		float surround = panel_rect(hatch_edge - 0.10, aa);
		float door = panel_rect(hatch_edge + 0.035, aa);
		float grille = panel_rect(abs(at + vec2(0.9, 0.0)) - vec2(1.75, 0.38), aa);
		float louvre = aline(abs(fract(p.y / 0.22) - 0.5) * 0.22, 0.045, aa.y * 2.0);
		float label = panel_rect(abs(at - vec2(2.29, 0.28)) - vec2(0.50, 0.12), aa);
		body = mix(body, body * 0.36, surround);
		body = mix(body, vec3(0.076, 0.087, 0.089) * (0.87 + 0.25 * streak), door);
		body *= 1.0 - 0.65 * grille * louvre;
		body = mix(body, vec3(0.38, 0.36, 0.27), label);
		ALBEDO = body;
		ROUGHNESS = mix(0.90, 0.56, door);
		SPECULAR = mix(0.22, 0.38, door);
	} else {
		// Restrict the existing structural weathering to neutral vertical
		// faces so paint on the road stays crisp.
		float neutral=1.0-smoothstep(0.025,0.12,max(paint.r,max(paint.g,paint.b))-min(paint.r,min(paint.g,paint.b)));
		float side=1.0-smoothstep(0.55,0.92,abs(normal_local.y));
		vec2 coord=vec2(position_local.x+position_local.z,position_local.y);
		float weather=pnoise(coord/vec2(7.0,90.0),1048576.0);
		float grit=pnoise(coord*2.0,1048576.0);
		float detail=1.0-smoothstep(0.5,4.0,length(fwidth(coord)));
		float seam_distance=min(mod(position_local.y,18.0),18.0-mod(position_local.y,18.0));
		float seam=(1.0-smoothstep(0.10,0.30,seam_distance))*(1.0-smoothstep(0.5,4.0,fwidth(position_local.y)));
		float variation=0.78+0.16*weather+0.08*grit*detail-0.14*seam;
		ALBEDO=paint*mix(1.0,variation,side*neutral);
		ROUGHNESS=mix(0.72,0.94,neutral);
		SPECULAR=0.22;
	}
}
