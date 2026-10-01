shader_type canvas_item;

// Radial vignette overlay: nearly clear in the middle so the 3D table shows
// through, deep at the edges. `pulse` (0..1) tints the rim (heartbeat / flash).

uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 pulse_color : source_color = vec4(0.55, 0.05, 0.08, 1.0);
uniform float center_alpha = 0.55;
uniform float edge_alpha = 0.96;
uniform float inner = 0.18;
uniform float outer = 0.8;
uniform float pulse = 0.0;

void fragment() {
	vec2 v = UV - 0.5;
	v.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length(v);
	float k = smoothstep(inner, outer, d);
	vec3 col = mix(tint.rgb, pulse_color.rgb, k * pulse);
	COLOR = vec4(col, mix(center_alpha, edge_alpha, k));
}
