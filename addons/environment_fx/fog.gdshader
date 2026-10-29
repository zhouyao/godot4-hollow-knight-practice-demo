shader_type canvas_item;

uniform sampler2D noise_texture: repeat_enable, filter_nearest;
uniform float density: hint_range(0.0, 1.0) = 0.25;
uniform vec2 speed = vec2(0.02, 0.01);
uniform float thickness: hint_range(0.0, 1.0) = 1.0;
// 雾的颜色（可在 Fog 节点的 fog_color 中配置）
uniform vec3 fog_color = vec3(1.0);

// 区域限制：region_enabled = false 时行为与无区域一致
uniform bool region_enabled = false;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(0.0);
// 区域包络衰减半宽（像素）：只负责"区域外逐渐消失"，很宽很柔，不构成可见轮廓
uniform float region_fade = 400.0;
// true = 椭圆包络（没有直边和直角），false = 矩形包络
uniform bool elliptical = false;

// 云形：雾的可见边界完全由噪声等值线决定（云边），与几何形状无关
uniform sampler2D mask_noise_texture: repeat_enable, filter_linear;
uniform float cloud_noise_scale: hint_range(0.0002, 0.01) = 0.0016;
// 覆盖率：越低雾越浓越连贯，越高越稀、洞越多（边界破碎感主要来自这里）
uniform float coverage: hint_range(0.0, 1.0) = 0.18;
// 云边柔和度
uniform float softness: hint_range(0.01, 1.0) = 0.2;
// 用噪声扭曲"区域包络"的边界，让包络轮廓本身也不是直线/直角
uniform float edge_noise: hint_range(0.0, 1200.0) = 320.0;
// 各层不同采样偏移：各层云形不同，叠出层次
uniform float edge_seed = 0.0;
// 内部浓淡起伏：让雾不是一片死白
uniform float density_variation: hint_range(0.0, 1.0) = 0.3;
// 几何边缘渐隐（UV 比例 0~0.5）：把 ColorRect / Parallax 平铺接缝的硬边抹掉
uniform float edge_margin: hint_range(0.0, 0.5) = 0.04;
// 淡出曲线指数
uniform float edge_gamma: hint_range(0.5, 4.0) = 1.0;

varying vec2 world_pos;

float smoother_step(float e0, float e1, float x) {
	float t = clamp((x - e0) / max(e1 - e0, 0.0001), 0.0, 1.0);
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// 噪声原始值是钟形分布（集中在 0.5 附近），拉开对比度才能真正推动边界
float stretch(float v) {
	return clamp((v - 0.5) * 3.0 + 0.5, 0.0, 1.0);
}

void vertex() {
	// MODEL_MATRIX: 局部 -> 世界；已包含 Parallax2D 的滚动偏移与 repeat 平铺偏移
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float noise = texture(noise_texture, UV).r;
	float mask = 1.0;

	if (region_enabled) {
		// 1) 区域有符号距离场（像素，区域内为正）
		float sdf;
		if (elliptical) {
			vec2 center = (region_min + region_max) * 0.5;
			vec2 half_size = max((region_max - region_min) * 0.5, vec2(1.0));
			sdf = (1.0 - length((world_pos - center) / half_size)) * min(half_size.x, half_size.y);
		} else {
			vec2 dmin = world_pos - region_min;
			vec2 dmax = region_max - world_pos;
			sdf = min(min(dmin.x, dmax.x), min(dmin.y, dmax.y));
		}

		// 2) 三个八度噪声（拉伸对比度后）
		vec2 base = world_pos * cloud_noise_scale + vec2(edge_seed);
		float w1 = stretch(texture(mask_noise_texture, base).r);
		float w2 = stretch(texture(mask_noise_texture, base * 2.9 + vec2(0.37, 0.61) + vec2(edge_seed)).r);
		float w3 = stretch(texture(mask_noise_texture, base * 7.3 + vec2(0.11, 0.83) + vec2(edge_seed)).r);

		// 3) 用噪声扭曲包络的边界，让"区域边界"本身也是有机形状，不是直线/直角
		float warp = ((w1 - 0.5) + (w2 - 0.5) * 0.5 + (w3 - 0.5) * 0.25) * edge_noise;
		float envelope = smoother_step(-region_fade, region_fade, sdf + warp);

		// 4) 云场：边界由噪声等值线决定（云边），与几何无关 —— 这是可见边缘的来源
		float cloud = w1 * 0.6 + w2 * 0.3 + w3 * 0.1;
		float cloud_mask = smoothstep(coverage, coverage + softness, cloud);

		// 5) 组合：云形决定可见边缘，包络只做区域限制，二者相乘不会复活几何等值线
		mask = cloud_mask * envelope * mix(1.0 - density_variation, 1.0, cloud);
		mask = pow(clamp(mask, 0.0, 1.0), edge_gamma);
	}

	// 几何边缘渐隐：抹掉 ColorRect / Parallax 平铺接缝的硬边（这是"层边缘直线"的直接来源）
	float g = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	mask *= smoother_step(0.0, edge_margin, g);

	float fog = clamp(noise * 2.0 - (1.0 - thickness), 0.0, 1.0);
	COLOR.rgb *= fog_color;
	COLOR.a *= fog * density * mask;
}
