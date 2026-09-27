shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;
// Slow-moving overcast cloud layer high above the valley.
uniform sampler2D clouds : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.42, 0.45, 0.48, 1.0);
uniform float speed = 0.004;

void fragment() {
	vec2 uv = UV * 3.0 + vec2(TIME * speed, TIME * speed * 0.4);
	vec4 c = texture(clouds, uv);
	vec4 c2 = texture(clouds, UV * 1.3 - vec2(TIME * speed * 0.6, 0.0));
	float d = clamp(c.a * 0.7 + c2.a * 0.5, 0.0, 1.0);
	// Fade out towards the edges of the plane so there is no visible border
	float edge = 1.0 - smoothstep(0.3, 0.5, length(UV - 0.5));
	ALBEDO = tint.rgb * mix(0.8, 1.15, c.r);
	ALPHA = d * edge * 0.85;
}
