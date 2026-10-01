shader_type spatial;

// Recolors the single-surface poker table model: a woven green felt on the
// playing surface (with a faint brass betting ring), a dark leather rail
// around it, and dark lacquered wood below. Zones are picked in MODEL space
// by octagonal distance from the center + surface normal.

uniform vec3 felt_color : source_color = vec3(0.06, 0.24, 0.17);
uniform vec3 felt_edge_color : source_color = vec3(0.03, 0.13, 0.09);
uniform vec3 rail_color : source_color = vec3(0.13, 0.06, 0.05);
uniform vec3 wood_color : source_color = vec3(0.09, 0.05, 0.035);
uniform vec3 ring_color : source_color = vec3(0.79, 0.64, 0.36);
uniform float half_width = 0.634;
uniform float felt_edge = 0.80;   // fraction of half_width where felt ends
uniform float ring_at = 0.56;     // betting-line ring position (fraction)
uniform float top_y = 0.62;       // model-space height above which "top" begins

varying vec3 local_pos;
varying vec3 local_nrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	local_pos = VERTEX;
	local_nrm = NORMAL;
}

void fragment() {
	vec2 p = local_pos.xz;
	float octo = max(max(abs(p.x), abs(p.y)), (abs(p.x) + abs(p.y)) * 0.70710678);
	float r = octo / half_width;
	bool up = local_nrm.y > 0.8;
	bool top = local_pos.y > top_y;

	vec3 col;
	float rough;
	if (top && up && r < felt_edge) {
		// Felt: fine weave + soft darkening toward the rail.
		float weave = vnoise(p * 900.0) * 0.5 + vnoise(p * 260.0) * 0.5;
		col = mix(felt_color, felt_edge_color, smoothstep(felt_edge * 0.55, felt_edge, r));
		col *= 0.92 + weave * 0.16;
		float ring = 1.0 - smoothstep(0.0, 0.004, abs(r - ring_at));
		col = mix(col, ring_color * 0.55, ring * 0.6);
		rough = 0.95;
	} else if (top) {
		// Padded leather rail with a subtle grain.
		col = rail_color * (0.85 + vnoise(p * 180.0) * 0.3);
		rough = 0.45;
	} else {
		// Lacquered wood base / legs.
		col = wood_color * (0.8 + vnoise(local_pos.xy * 60.0 + local_pos.zy * 60.0) * 0.4);
		rough = 0.35;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
