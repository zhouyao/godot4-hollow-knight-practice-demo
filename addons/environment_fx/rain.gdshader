shader_type canvas_item;

// —— 降雨表现：程序化生成的下落雨丝（无外部贴图，纯噪声/哈希） ——
// 与 fog.gdshader 保持一致的区域遮罩接口，可无缝替换。

// 雨的颜色（可在 Rain 节点的 rain_color 中配置）
uniform vec3 rain_color = vec3(0.72, 0.82, 1.0);
// 雨的整体强度（0~1）。所有层共用，统一控制。
uniform float density: hint_range(0.0, 1.0) = 0.25;
// 下落方向（单位向量，由 Rain.angle_deg 写入；默认竖直向下 (0,1)）。
// 仅表示方向，长度恒为 1，不影响下落速度。
uniform vec2 speed = vec2(0.0, 1.0);
// 下落速度倍率（由 Rain.rain_speed 写入；1.0 = 默认，>1 更快，<1 更慢，0 = 静止）。
// 只缩放时间推进速率，不改变雨势起伏与倾斜表现。
uniform float fall_speed: hint_range(0.0, 4.0) = 1.0;
// 雨丝的"实度 / 粗细"（0~1）：越大雨丝越粗越实
uniform float thickness: hint_range(0.0, 1.0) = 0.85;
// 覆盖率：落雨的列占比（0 = 无雨，1 = 全部列落雨）
uniform float coverage: hint_range(0.0, 1.0) = 0.18;
// 雨丝柔边：越大雨丝边缘越朦胧
uniform float softness: hint_range(0.01, 1.0) = 0.2;
// 紊乱度（0~1）：让每条雨丝各自有不同的斜度 / 粗细 / 轻微弯曲，
// 打破"整齐平行"的观感；0 = 整齐平行，越接近 1 越像真实风雨中的杂乱雨丝
uniform float chaos: hint_range(0.0, 1.0) = 0.0;
// 拖影长度倍率（运动模糊）：1.0 = 默认，>1 雨丝拖得更长更柔（慢快门感），<1 更短更利落
uniform float trail_scale: hint_range(0.2, 3.0) = 1.0;

// —— 水珠头：圆润发亮的水滴头，骑在雨丝前端，补足“雨滴”观感（不破坏平行/平铺） ——
// 整体淡入系数：0 = 纯雨丝（改造前行为），1 = 水珠头完全显现；>0 时雨丝依旧存在，只是前端多出亮珠。
uniform float droplet: hint_range(0.0, 1.0) = 0.6;
// 水珠头大小（列宽分数）：越大珠头越粗。
uniform float drop_size: hint_range(0.0, 1.0) = 0.5;
// 纵向拉伸：越小水珠头越接近正圆（抵消“列宽 vs 周期”在屏幕上的长宽比，约 0.22 为正圆）。
uniform float drop_stretch: hint_range(0.1, 1.0) = 0.25;
// 水珠头亮度：>1 时比雨丝更亮，读起来像迎光的水珠。
uniform float drop_brightness: hint_range(0.5, 3.0) = 1.6;

// 区域限制：region_enabled = false 时行为与无区域一致
uniform bool region_enabled = false;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(0.0);
// 区域包络衰减半宽（像素）：只负责"区域外逐渐消失"，很宽很柔，不构成可见轮廓
uniform float region_fade = 400.0;
// true = 椭圆包络（没有直边和直角），false = 矩形包络
uniform bool elliptical = false;

// 区域强度起伏：让雨不是均匀一片（对应 Fog 的 density_variation）
uniform sampler2D mask_noise_texture: repeat_enable, filter_linear;
uniform float cloud_noise_scale: hint_range(0.0002, 0.01) = 0.0016;
// 用噪声扭曲"区域包络"的边界，让包络轮廓本身也不是直线/直角
uniform float edge_noise: hint_range(0.0, 1200.0) = 320.0;
// 各层不同采样偏移：各层雨形不同，叠出层次
uniform float edge_seed = 0.0;
// 内部浓淡起伏：让雨不是一片死白
uniform float density_variation: hint_range(0.0, 1.0) = 0.3;
// 几何边缘渐隐（UV 比例 0~0.5）：把 ColorRect / Parallax 平铺接缝的硬边抹掉
uniform float edge_margin: hint_range(0.0, 0.5) = 0.04;
// 淡出曲线指数
uniform float edge_gamma: hint_range(0.5, 4.0) = 1.0;

varying vec2 world_pos;

// 均匀哈希：取代噪声贴图，生成每列雨丝的随机参数
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float smoother_step(float e0, float e1, float x) {
	float t = clamp((x - e0) / max(e1 - e0, 0.0001), 0.0, 1.0);
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// 噪声原始值是钟形分布（集中在 0.5 附近），拉开对比度才能真正推动边界
float stretch(float v) {
	return clamp((v - 0.5) * 3.0 + 0.5, 0.0, 1.0);
}

// 一层雨：在 UV 空间（每平铺块 0~1）生成向下滑落的雨丝。
// 列数 / 纵向周期取整数，且随机参数只依赖"列"而非"行"，
// 因此跨 Parallax2D 平铺块天然无缝（与雾的 UV 平铺策略一致）。
float rain_layer(vec2 uv, float columns, float period, float t, float seed) {
	float colf = uv.x * columns;
	float col = floor(colf);
	float fx = fract(colf);

	// 该列是否落雨：coverage 越大，落雨的列越多
	float rnd = hash21(vec2(col, seed));
	if (rnd > coverage) {
		return 0.0;
	}

	// 紊乱度：让每条雨丝各自有不同的斜度与粗细，打破"整齐平行"的观感
	float jx = hash21(vec2(col, seed + 31.7));
	float col_tilt = (jx - 0.5) * chaos * 0.7;          // 每条雨丝各自的微小斜度
	float thick_j = mix(1.0, 0.45 + 0.55 * jx, chaos);  // 粗细随机扰动

	// 雨丝在列内的水平位置（居中 ±0.35，不会跨到相邻列）
	float xoff = (hash21(vec2(col, seed + 11.3)) - 0.5) * 0.7;
	float phase = hash21(vec2(col, seed + 2.9));
	// 每列速度分布更宽（真实雨滴速度并不一致）
	float spd = 0.55 + 0.9 * hash21(vec2(col, seed + 7.3));   // ~0.55..1.45
	float fall = spd * (0.6 + rnd * 0.8);
	float fy = fract(uv.y * period - t * fall + phase);

	// 沿雨丝方向的横向扰动（随下落相位流动；整数周期保证平铺无缝）
	float wave = sin((uv.y * period - t * fall + phase) * 2.0 * PI) * chaos * 0.05;

	// 雨丝中心随纵向位置偏移 → 雨丝呈斜向 / 轻微弯曲，而非笔直
	float center_x = 0.5 + xoff + col_tilt * (fy - 0.5) + wave;
	float dx = abs(fx - center_x);
	// 雨丝半宽：thickness 越大越粗（0.008~0.05 列宽）
	float halfw = mix(0.008, 0.05, clamp(thickness * thick_j, 0.0, 1.0));
	float edge = max(softness * 0.06, 0.001);
	float line = 1.0 - smoothstep(halfw, halfw + edge, dx);

	// —— 运动模糊：雨丝头部最亮，向尾部指数衰减；头部前方几乎不可见 ——
	float len = mix(0.3, 0.95, hash21(vec2(col, seed + 5.7)));
	float trail = mix(0.12, 0.55, spd) * trail_scale; // 速度 → 拖尾长度（可被 trail_scale 整体缩放）
	float behind = len - fy;                       // >0 表示在头部之后的拖尾区
	float motion = exp(-max(behind, 0.0) / trail); // 指数拖尾
	motion *= smoothstep(-0.03, 0.0, behind);      // 头部前方快速归零

	// 内部浓淡起伏：让雨不是均匀一片
	float dv = mix(1.0 - density_variation, 1.0, hash21(vec2(col, seed + 9.1)));

	// 速度 → 整体亮度（快滴更亮，符合人眼对高速运动的感知）
	return line * motion * dv * mix(0.7, 1.3, clamp(spd - 0.55, 0.0, 0.9));
}

// 水珠头：在每条已落雨的列（与 rain_layer 共用同一列决策，绝不串列）的“前端”画一个
// 圆润发亮的水滴头 + 一截极短拖尾。只依赖“列”与整数周期，跨 Parallax 平铺天然无缝。
// 与 rain_layer 共用同一套 xoff/phase/spd/fall/len，因此水珠头严格骑在对应雨丝的亮头上，
// 不会随时间漂移（雨丝亮头在 fy≈len 处，水珠头中心也在 fy≈len）。
float rain_head(vec2 uv, float columns, float period, float t, float seed) {
	float colf = uv.x * columns;
	float col = floor(colf);
	float fx = fract(colf);

	// 与 rain_layer 完全一致的列决策，保证水珠头只出现在有雨丝的列上
	float rnd = hash21(vec2(col, seed));
	if (rnd > coverage) {
		return 0.0;
	}

	float xoff = (hash21(vec2(col, seed + 11.3)) - 0.5) * 0.7;
	float phase = hash21(vec2(col, seed + 2.9));
	// 与 rain_layer 完全一致的每列速度，保证水珠头与雨丝亮头严格同步（不漂移）
	float spd = 0.55 + 0.9 * hash21(vec2(col, seed + 7.3));
	float fall = spd * (0.6 + rnd * 0.8);
	float fy = fract(uv.y * period - t * fall + phase);
	float len = mix(0.3, 0.95, hash21(vec2(col, seed + 5.7)));

	// 复用 rain_layer 的紊乱度偏移，使水珠头在高 chaos 时仍贴合弯曲/倾斜的雨丝
	float jx = hash21(vec2(col, seed + 31.7));
	float col_tilt = (jx - 0.5) * chaos * 0.7;
	float wave = sin((uv.y * period - t * fall + phase) * 2.0 * PI) * chaos * 0.05;

	// 以雨丝前导端（fy≈len）为水珠头中心；dy<0 在头之上（拖尾方向）
	float center_x = 0.5 + xoff + col_tilt * (fy - 0.5) + wave;
	float dx = fx - center_x;
	float dy = fy - len;

	// 圆润水珠头：用归一化距离画一个近圆亮块（纵向按 drop_stretch 缩放成水滴形）
	float hr = mix(0.02, 0.06, clamp(drop_size, 0.0, 1.0));
	vec2 p = vec2(dx, dy) / (hr * vec2(1.0, drop_stretch));
	float r = length(p);                          // 0=中心, 1=边缘
	float body = 1.0 - smoothstep(0.7, 1.0, r);  // 珠体

	// 受光高光：朝光源方向偏移的小亮斑（默认左上）
	vec2 L = normalize(vec2(-0.5, -0.6));
	float spec = (1.0 - smoothstep(0.0, 0.35, length(p - L * 0.45))) * 1.8;

	// 菲涅尔暗边：边缘比中心暗，读起来像透明水珠而非白点
	float rim = body * (0.4 + 0.6 * smoothstep(0.6, 1.0, r));

	float head = (rim * 0.5 + spec) * drop_brightness;
	// 极短拖尾：朝雨丝方向（dy<0，头之上）渐隐，强化“滴”而不是孤立的“点”
	float tail = (1.0 - smoothstep(0.0, 0.25, -dy)) * (1.0 - smoothstep(hr, hr + 0.01, abs(dx))) * 0.4;

	return max(head, tail) * body;
}

void vertex() {
	// MODEL_MATRIX: 局部 -> 世界；已包含 Parallax2D 的滚动偏移与 repeat 平铺偏移
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// 倾斜由 Rain.angle_deg 通过 speed（单位方向向量）驱动；去掉 0.4 上限，让角度真正生效。
	// speed 归一化后长度恒为 1，下落速度（t）保持不变，保证多层 Parallax 平铺无缝。
	float tilt = clamp(speed.x / max(speed.y, 0.001), -4.0, 4.0);
	vec2 uv = vec2(UV.x + UV.y * tilt, UV.y);

	float t = TIME * (0.5 + length(speed)) * fall_speed;
	// 三层不同密度的雨丝叠出景深（近处更粗更亮、远处更细更淡）
	float threads = 0.0;
	threads += rain_layer(uv, 64.0, 10.0, t, edge_seed) * 0.55;
	threads += rain_layer(uv, 128.0, 16.0, t * 1.3, edge_seed + 17.0) * 1.0;
	threads += rain_layer(uv, 192.0, 22.0, t * 1.7, edge_seed + 41.0) * 0.5;

	// 同结构三层水珠头：与雨丝共用列决策，自然骑在每条雨丝前端
	float drops = 0.0;
	drops += rain_head(uv, 64.0, 10.0, t, edge_seed) * 0.55;
	drops += rain_head(uv, 128.0, 16.0, t * 1.3, edge_seed + 17.0) * 1.0;
	drops += rain_head(uv, 192.0, 22.0, t * 1.7, edge_seed + 41.0) * 0.5;

	// 雨丝始终存在；水珠头以 droplet 系数淡入，并用 max 压在雨丝之上（头部更亮）
	float rain = max(threads, drops * droplet);

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

		// 4) 区域内部的强弱起伏：雨势在区域内也不是均匀的
		float gust = w1 * 0.6 + w2 * 0.3 + w3 * 0.1;

		mask = envelope * mix(1.0 - density_variation, 1.0, gust);
		mask = pow(clamp(mask, 0.0, 1.0), edge_gamma);
	}

	// 几何边缘渐隐：抹掉 ColorRect / Parallax 平铺接缝的硬边
	float g = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	mask *= smoother_step(0.0, edge_margin, g);

	COLOR.rgb = rain_color;
	COLOR.a *= clamp(rain, 0.0, 1.0) * density * mask;
}
