shader_type canvas_item;

// 背景高斯模糊：对应源项目 Bg::Init(..., blur=true) 时调用的
// GaussianFilter(image, radius = -layer + 1)。
// 用两圈 8 方向采样近似二维高斯，避免逐像素 2D 卷积的高开销。

uniform float blur_radius : hint_range(0.0, 16.0) = 4.0;
uniform float sigma_scale : hint_range(0.1, 1.0) = 0.3333;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * blur_radius;
	vec4 color = texture(TEXTURE, UV);
	float total = 1.0;

	for (int ring = 1; ring <= 2; ring++) {
		float r = float(ring) * 0.5;
		float w = exp(-0.5 * (r * r) / (sigma_scale * sigma_scale));
		float d = r * 0.70710678;

		color += texture(TEXTURE, UV + vec2(r, 0.0) * texel) * w;
		color += texture(TEXTURE, UV - vec2(r, 0.0) * texel) * w;
		color += texture(TEXTURE, UV + vec2(0.0, r) * texel) * w;
		color += texture(TEXTURE, UV - vec2(0.0, r) * texel) * w;

		color += texture(TEXTURE, UV + vec2(d, d) * texel) * w;
		color += texture(TEXTURE, UV + vec2(d, -d) * texel) * w;
		color += texture(TEXTURE, UV + vec2(-d, d) * texel) * w;
		color += texture(TEXTURE, UV + vec2(-d, -d) * texel) * w;

		total += 8.0 * w;
	}

	COLOR = color / total;
}
