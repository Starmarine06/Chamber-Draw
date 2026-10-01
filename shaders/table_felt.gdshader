shader_type spatial;

// Woven casino felt for the procedural table: fine weave, a soft pool of light toward the
// middle, darker toward the rail, double brass betting rings, six brass "chamber" studs
// and a small revolver-drum emblem in the centre. Works in local XZ (the table's centre is
// the origin), measured against the felt radius.

uniform float felt_radius = 0.9;
uniform vec3 felt_color : source_color = vec3(0.055, 0.24, 0.165);
uniform vec3 felt_dark : source_color = vec3(0.02, 0.1, 0.07);
uniform vec3 brass : source_color = vec3(0.79, 0.64, 0.36);

varying vec2 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float ring(float r, float at, float w) {
	return 1.0 - smoothstep(w * 0.6, w, abs(r - at));
}

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp) / felt_radius;
	float ang = atan(lp.x, lp.y);

	// Weave + very slow mottling so big flat areas never look like plastic.
	float weave = vnoise(lp * 1100.0) * 0.5 + vnoise(lp * 330.0) * 0.5;
	float mottle = vnoise(lp * 7.0);
	vec3 col = mix(felt_color, felt_dark, smoothstep(0.25, 1.0, r));
	col *= 0.9 + weave * 0.16 + (mottle - 0.5) * 0.08;

	float metal = 0.0;
	// Double betting ring.
	metal = max(metal, ring(r, 0.66, 0.0055));
	metal = max(metal, ring(r, 0.635, 0.0035) * 0.8);
	// Six brass studs on the ring: one per chamber.
	float seg = TAU / 6.0;
	float a = mod(ang + seg * 0.5, seg) - seg * 0.5;
	vec2 q = vec2(cos(a), sin(a)) * r;           // studs sit at (r = 0.66) along each sector axis
	float stud = 1.0 - smoothstep(0.016, 0.022, length(q - vec2(0.66, 0.0)));
	metal = max(metal, stud);
	// Centre emblem: small ring with a ring of dots, like a revolver drum seen end-on.
	metal = max(metal, ring(r, 0.115, 0.004));
	vec2 q2 = vec2(cos(a), sin(a)) * r;
	float dots = 1.0 - smoothstep(0.011, 0.016, length(q2 - vec2(0.075, 0.0)));
	metal = max(metal, dots * (1.0 - step(0.115, r)));
	metal = max(metal, 1.0 - smoothstep(0.012, 0.018, r));

	col = mix(col, brass * 0.85, metal);
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.35, metal);
	METALLIC = metal * 0.7;
	SPECULAR = mix(0.2, 0.6, metal);
}
