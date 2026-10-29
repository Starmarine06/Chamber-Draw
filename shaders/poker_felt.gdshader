shader_type spatial;

// Plain casino felt for the Hold'em table: fine weave, a soft pool of light in the middle,
// darker toward the rail. No rings, studs or emblems, so the cards and chips are the only
// things on the cloth.

uniform vec2 felt_half = vec2(1.3, 0.84);
uniform sampler2D logo_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 felt_color : source_color = vec3(0.05, 0.25, 0.17);
uniform vec3 felt_dark : source_color = vec3(0.03, 0.15, 0.105);

varying vec2 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	lp = VERTEX.xz;
}

void fragment() {
	float r = length(lp / felt_half);
	float weave = vnoise(lp * 900.0) * 0.5 + vnoise(lp * 280.0) * 0.5;
	float mottle = vnoise(lp * 6.0);
	vec3 col = mix(felt_color, felt_dark, smoothstep(0.45, 1.05, r));
	col *= 0.92 + weave * 0.14 + (mottle - 0.5) * 0.06;
	vec2 uv = lp / (2.0 * felt_half) + 0.5;
	vec4 lg = texture(logo_tex, uv);
	col = mix(col, lg.rgb * (0.9 + weave * 0.2), lg.a);
	ALBEDO = col;
	METALLIC = lg.a * 0.55;
	ROUGHNESS = mix(0.96, 0.5, lg.a);
	SPECULAR = mix(0.08, 0.5, lg.a);
}
