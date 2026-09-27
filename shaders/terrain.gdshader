shader_type spatial;
// Terrain splat shader: forest floor everywhere, blended with mud (COLOR.r),
// gravel (COLOR.g), concrete (COLOR.b) and rock (COLOR.a, slopes/mountains).
// `wetness` darkens the ground and makes it shiny in the rain.

uniform sampler2D forest_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D conc_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_r : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float scale = 2.5;
uniform float wetness : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 uv = UV * scale;
	vec2 uv_far = UV * scale * 0.21;   // second, larger tiling breaks up repetition
	vec4 w = COLOR;

	vec3 a = mix(texture(forest_a, uv).rgb, texture(forest_a, uv_far).rgb, 0.35);
	vec3 n = texture(forest_n, uv).rgb;
	float r = texture(forest_r, uv).r;

	vec3 ma = mix(texture(mud_a, uv).rgb, texture(mud_a, uv_far).rgb, 0.3);
	a = mix(a, ma, w.r);
	n = mix(n, texture(mud_n, uv).rgb, w.r);
	r = mix(r, texture(mud_r, uv).r, w.r);

	a = mix(a, texture(gravel_a, uv * 1.5).rgb, w.g);
	n = mix(n, texture(gravel_n, uv * 1.5).rgb, w.g);
	r = mix(r, texture(gravel_r, uv * 1.5).r, w.g);

	a = mix(a, texture(conc_a, uv * 0.5).rgb, w.b);
	n = mix(n, texture(conc_n, uv * 0.5).rgb, w.b);
	r = mix(r, texture(conc_r, uv * 0.5).r, w.b);

	a = mix(a, texture(rock_a, uv * 0.4).rgb, w.a);
	n = mix(n, texture(rock_n, uv * 0.4).rgb, w.a);
	r = mix(r, texture(rock_r, uv * 0.4).r, w.a);

	// Large-scale brightness variation so the ground never looks tiled
	float macro = texture(forest_a, UV * 0.07).g;
	a *= mix(0.82, 1.12, macro * 1.6);

	float wet = wetness * (0.6 + 0.4 * w.r);
	ALBEDO = a * (1.0 - wet * 0.15);
	ROUGHNESS = clamp(r * (1.0 - wet * 0.45), 0.05, 1.0);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 1.2;
}
