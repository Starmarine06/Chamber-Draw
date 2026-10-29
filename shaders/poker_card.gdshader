shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// One face of a poker card: lit paper with a glossy coat, an optional curl (peeking a corner up),
// and a gold glow / dim used to highlight the winning hand.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float bend = 0.0;       // how far the near edge curls toward the face normal (local units)
uniform float half_h = 0.1;     // half the card length (local Y)
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float dim : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	float k = clamp((half_h - VERTEX.y) / (2.0 * half_h), 0.0, 1.0);
	VERTEX.z += bend * k * k;
	if (abs(NORMAL.z) > 0.5) {
		float slope = bend * k / half_h;
		NORMAL = normalize(vec3(0.0, NORMAL.z * slope, NORMAL.z));
	}
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	vec3 base = mix(t.rgb, t.rgb * 0.32, dim);
	ALBEDO = base;
	ROUGHNESS = 0.45;
	SPECULAR = 0.5;
	CLEARCOAT = 0.45;
	CLEARCOAT_ROUGHNESS = 0.14;
	EMISSION = glow * vec3(1.0, 0.8, 0.35) * 0.55 + base * 0.05;
}
