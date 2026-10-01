shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Back-room wall: dark wood wainscot with raised panels, a brass rail, then
// damask-striped wallpaper that falls off into shadow toward the ceiling.

uniform vec3 wood_color : source_color = vec3(0.34, 0.18, 0.09);
uniform vec3 paper_a : source_color = vec3(0.42, 0.08, 0.11);
uniform vec3 paper_b : source_color = vec3(0.26, 0.05, 0.07);
uniform vec3 brass : source_color = vec3(0.62, 0.45, 0.2);
uniform float tiles = 5.0;
uniform float rail = 0.32;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float x = UV.x;
	float y = 1.0 - UV.y; // 0 = floor, 1 = ceiling
	vec3 col;
	float rough = 0.85;
	float metal = 0.0;

	if (y < rail) {
		// Raised wood panels with grain.
		vec2 p = vec2(x * tiles, y / rail * 1.6);
		vec2 f = fract(p);
		float inner = step(0.09, f.x) * step(f.x, 0.91) * step(0.1, f.y) * step(f.y, 0.9);
		float edge = smoothstep(0.0, 0.05, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
		float grain = vnoise(vec2(x * tiles * 2.0, y * 90.0)) * 0.6 + vnoise(vec2(x * tiles * 9.0, y * 14.0)) * 0.4;
		col = wood_color * (0.55 + 0.75 * grain) * mix(0.55, 1.0, inner) * mix(0.75, 1.0, edge);
		rough = 0.55;
	} else if (y < rail + 0.018) {
		col = brass;
		rough = 0.3;
		metal = 0.8;
	} else {
		// Wallpaper: soft vertical stripes + a repeating damask blob.
		float s = 0.5 + 0.5 * sin(x * tiles * 6.2831 * 3.0);
		float n = vnoise(vec2(x * tiles * 14.0, y * 26.0));
		col = mix(paper_a, paper_b, s * 0.55 + n * 0.35);
		vec2 q = fract(vec2(x * tiles * 1.5, (y - rail) * 7.0)) - 0.5;
		float d = length(q * vec2(1.0, 0.8));
		col += vec3(0.055, 0.012, 0.012) * smoothstep(0.26, 0.14, d);
		// Crown shadow toward the ceiling.
		col *= mix(1.0, 0.55, smoothstep(0.7, 1.0, y));
	}

	// Corner darkening so the room reads as a volume, not a flat backdrop.
	col *= 0.82 + 0.18 * smoothstep(0.0, 0.18, min(x, 1.0 - x) * 2.0);

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
