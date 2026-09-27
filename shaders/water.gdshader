shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;
// Flowing creek water: two scrolling normal maps, dark and glossy, slightly see-through.
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 deep : source_color = vec4(0.07, 0.1, 0.09, 0.82);
uniform vec2 flow = vec2(0.35, 0.05);

void fragment() {
	vec2 uv = UV;
	vec3 n1 = texture(normal_a, uv * 0.6 + flow * TIME * 0.4).rgb;
	vec3 n2 = texture(normal_a, uv * 1.1 - flow.yx * TIME * 0.3 + vec2(0.3)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	ALBEDO = deep.rgb;
	ALPHA = deep.a;
	ROUGHNESS = 0.04;
	METALLIC = 0.1;
	SPECULAR = 0.7;
}
