shader_type canvas_item;

// Full-screen player-state effects on top of the 3D view:
//  - wired: pumped colour, chromatic fringing, racing pulse, zoom throb
//  - crash: fades toward grey with a heavy vignette
//  - drunk: swaying, smeared, doubled vision with a warm tint
// When `use_own_texture` is set (the UI cover) the node's own texture is the
// source instead of the screen behind it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform bool use_own_texture = false;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float crash : hint_range(0.0, 1.0) = 0.0;
uniform float drunk : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;

vec3 src_at(sampler2D own_tex, sampler2D screen, bool own, vec2 uv) {
	if (own) {
		return texture(own_tex, uv).rgb;
	}
	return texture(screen, uv).rgb;
}

void fragment() {
	vec2 base = use_own_texture ? UV : SCREEN_UV;
	vec2 c = base - 0.5;
	float pulse = 0.5 + 0.5 * sin(t * 11.0);
	float pulse2 = 0.5 + 0.5 * sin(t * 4.3 + 1.7);
	vec2 uv = 0.5 + c * (1.0 - 0.035 * pulse * intensity + 0.02 * pulse2 * intensity);

	// Drunk: the picture drifts and wobbles.
	uv += vec2(sin(t * 0.9 + uv.y * 4.0), cos(t * 0.7 + uv.x * 3.0)) * 0.010 * drunk;
	uv += c * sin(t * 0.6) * 0.03 * drunk;

	float ab = (0.003 + 0.007 * pulse) * intensity + 0.002 * drunk;
	vec2 dir = normalize(c + vec2(0.00001));
	vec3 col;
	col.r = src_at(TEXTURE, screen_tex, use_own_texture, uv + dir * ab).r;
	col.g = src_at(TEXTURE, screen_tex, use_own_texture, uv).g;
	col.b = src_at(TEXTURE, screen_tex, use_own_texture, uv - dir * ab).b;

	if (drunk > 0.001) {
		// Ghost image + soft smear.
		vec2 off = vec2(0.016 * sin(t * 0.5 + 1.0), 0.006 * cos(t * 0.8)) * drunk;
		vec3 ghost = src_at(TEXTURE, screen_tex, use_own_texture, uv + off);
		float r = 0.004 * drunk;
		vec3 blur = (src_at(TEXTURE, screen_tex, use_own_texture, uv + vec2(r, 0.0)) + src_at(TEXTURE, screen_tex, use_own_texture, uv - vec2(r, 0.0)) + src_at(TEXTURE, screen_tex, use_own_texture, uv + vec2(0.0, r)) + src_at(TEXTURE, screen_tex, use_own_texture, uv - vec2(0.0, r))) * 0.25;
		col = mix(col, ghost, 0.4 * drunk);
		col = mix(col, blur, 0.6 * drunk);
		col *= mix(vec3(1.0), vec3(1.06, 0.98, 0.9), drunk);
	}

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, 1.0 + 0.85 * intensity - 0.95 * crash - 0.15 * drunk);
	col = (col - 0.5) * (1.0 + 0.25 * intensity - 0.12 * crash) + 0.5;
	col *= 1.0 + 0.16 * intensity * pulse - 0.28 * crash - 0.1 * drunk;

	float v = smoothstep(0.35, 0.95, length(c) * 1.4);
	col *= 1.0 - v * (0.22 * intensity + 0.6 * crash + 0.45 * drunk);
	col += vec3(0.9, 0.95, 1.0) * intensity * 0.05 * (1.0 - v);
	COLOR = vec4(col, 1.0);
}
