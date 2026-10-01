shader_type canvas_item;

// Noir backdrop: ink base, a warm light pool from above, slow drifting smoke,
// vignette and a whisper of film grain. Used by menu / lobby backgrounds.

uniform vec4 base_color : source_color = vec4(0.055, 0.043, 0.063, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.30, 0.26, 0.33, 1.0);
uniform vec4 light_color : source_color = vec4(0.79, 0.64, 0.36, 1.0);
uniform vec2 light_pos = vec2(0.5, -0.15);
uniform float light_strength = 0.34;
uniform float smoke_strength = 0.22;
uniform float vignette = 1.15;
uniform float grain = 0.035;
uniform float speed = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(uv.x * aspect, uv.y);
	float t = TIME * speed;

	vec3 col = base_color.rgb;

	// Warm light pool (elliptical falloff from above).
	vec2 d = (uv - light_pos) * vec2(1.0, 1.6);
	float light = exp(-dot(d, d) * 2.2) * light_strength;
	col += light_color.rgb * light;

	// Two layers of drifting smoke, brighter where the light hits.
	float s1 = fbm(p * 2.2 + vec2(t * 1.3, -t * 0.6));
	float s2 = fbm(p * 4.1 - vec2(t * 0.8, t * 1.1) + s1);
	float smoke = smoothstep(0.35, 0.95, s1 * 0.6 + s2 * 0.5);
	col += smoke_color.rgb * smoke * smoke_strength * (0.55 + light * 2.5);

	// Vignette.
	vec2 v = uv - 0.5;
	col *= clamp(1.0 - dot(v, v) * vignette, 0.0, 1.0);

	// Grain.
	col += (hash(uv * 813.7 + fract(TIME) * 37.0) - 0.5) * grain;

	COLOR = vec4(col, 1.0);
}
