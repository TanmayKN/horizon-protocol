shader_type spatial;
// Military vehicle paint: matte base colour, worn edges and grime from the paint texture,
// mud caked on the lower body (by local height), and a wet sheen from the rain.
uniform vec4 paint : source_color = vec4(0.33, 0.37, 0.27, 1.0);
uniform sampler2D grime : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grime_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 mud : source_color = vec4(0.23, 0.17, 0.11, 1.0);
uniform float mud_height = 1.0;
uniform float tex_scale = 0.6;
varying vec3 lpos;
varying vec3 lnorm;

void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
}

vec4 triplanar(sampler2D t, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

void fragment() {
	vec3 p = lpos * tex_scale;
	vec4 g = triplanar(grime, p, lnorm);
	// Grime texture is light paint with rusty chips: use its darkness as wear
	float wear = clamp(1.0 - g.r * 1.1, 0.0, 1.0);
	vec3 col = paint.rgb * mix(0.85, 1.05, g.g);
	col = mix(col, vec3(0.3, 0.22, 0.15), wear * 0.35);
	// Mud splashed up from the wheels
	float noise_m = triplanar(grime, lpos * 1.7, lnorm).b;
	float m = smoothstep(mud_height + 0.15, mud_height - 0.35, lpos.y + (noise_m - 0.5) * 0.6);
	col = mix(col, mud.rgb, m * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.9, m) - 0.15;
	METALLIC = 0.15 * (1.0 - m);
	NORMAL_MAP = triplanar(grime_n, p, lnorm).rgb;
	NORMAL_MAP_DEPTH = 0.6;
}
