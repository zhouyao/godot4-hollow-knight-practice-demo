shader_type canvas_item;

// —— 降雪表现：程序化生成的柔和六瓣雪花（无外部贴图，纯噪声/哈希） ——
// 与 fog.gdshader / rain.gdshader 保持一致的区域遮罩接口，可无缝替换。

// 雪的颜色（可在 Snow 节点的 snow_color 中配置）
uniform vec3 snow_color = vec3(0.95, 0.97, 1.0);
// 雪的整体强度（0~1）。所有层共用，统一控制（透明度）。
uniform float density: hint_range(0.0, 1.0) = 0.5;
// 下落方向（单位向量，由 Snow.angle_deg 写入；默认竖直向下 (0,1)）。
// 仅表示方向，长度恒为 1，不影响下落速度（风力/角度影响）。
uniform vec2 speed = vec2(0.0, 1.0);
// 下落速度倍率（由 Snow.snow_speed 写入；1.0 = 默认，>1 更快，<1 更慢，0 = 静止）。
// 只缩放时间推进速率，不改变雪势起伏与倾斜表现。
uniform float fall_speed: hint_range(0.0, 4.0) = 1.0;
// 雪片尺寸（0~1）：越大雪片越大越实（对应雨的 thickness）。
uniform float thickness: hint_range(0.0, 1.0) = 0.85;
// 覆盖率：落雪的格占比（0 = 无雪，1 = 全部格落雪）。≈ 粒子数量。
uniform float coverage: hint_range(0.0, 1.0) = 0.6;
// 边缘柔化：越大雪花边缘越朦胧。
uniform float softness: hint_range(0.01, 1.0) = 0.8;
// 漂移/紊乱度（0~1）：让每片雪花各自有不同飘摆幅度与朝向，
// 打破"整齐下落"的观感；0 = 笔直下落，越接近 1 越像真实风雪中的飘摆。
uniform float chaos: hint_range(0.0, 1.0) = 0.6;
// 雪片形态：0=柔六瓣(默认) 1=柔圆点 2=六角晶体 3=散景大圆 4=闪烁亮片
uniform int flake_shape: hint_enum("petal", "dot", "crystal", "bokeh", "sparkle") = 0;

// 区域限制：region_enabled = false 时行为与无区域一致
uniform bool region_enabled = false;
uniform vec2 region_min = vec2(0.0);
uniform vec2 region_max = vec2(0.0);
// 区域包络衰减半宽（像素）：只负责"区域外逐渐消失"，很宽很柔，不构成可见轮廓
uniform float region_fade = 400.0;
// true = 椭圆包络（没有直边和直角），false = 矩形包络
uniform bool elliptical = false;

// 区域强度起伏：让雪不是均匀一片（对应 Fog / Rain 的 density_variation）
uniform sampler2D mask_noise_texture: repeat_enable, filter_linear;
uniform float cloud_noise_scale: hint_range(0.0002, 0.01) = 0.0016;
// 用噪声扭曲"区域包络"的边界，让包络轮廓本身也不是直线/直角
uniform float edge_noise: hint_range(0.0, 1200.0) = 320.0;
// 各层不同采样偏移：各层雪形不同，叠出层次
uniform float edge_seed = 0.0;
// 内部浓淡起伏：让雪不是一片死白
uniform float density_variation: hint_range(0.0, 1.0) = 0.3;
// 几何边缘渐隐（UV 比例 0~0.5）：把 ColorRect / Parallax 平铺接缝的硬边抹掉
uniform float edge_margin: hint_range(0.0, 0.5) = 0.04;
// 淡出曲线指数
uniform float edge_gamma: hint_range(0.5, 4.0) = 1.0;

varying vec2 world_pos;

// 均匀哈希：取代噪声贴图，生成每格雪花的随机参数
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

// 柔和六瓣雪花 SDF（0 = 外, 1 = 中心）。借鉴开源雪花着色器：
// 六重对称折叠得到六条主瓣（spoke），叠加中央柔和核与整体光晕，
// 全程用 smoothstep 收边，保证边缘平滑过渡、无硬边。
float snowflake(vec2 p, float r) {
	float d = length(p);
	// 早退：只在雪片包围盒内才进入角度折叠，省算力（与雨同量级）
	if (d > r * 1.15) {
		return 0.0;
	}
	// 柔圆点 / 闪烁亮片：只取中央核 + 柔光晕，去掉六瓣（亮片更小更聚）
	if (flake_shape == 1 || flake_shape == 4) {
		float soft = mix(0.4, 1.0, clamp(softness, 0.0, 1.0));
		float core = (flake_shape == 4)
			? (1.0 - smoothstep(r * 0.05, r * 0.22, d))
			: (1.0 - smoothstep(r * 0.18, r * 0.52, d));
		float glow = (1.0 - smoothstep(r * 0.15, r * (flake_shape == 4 ? 0.5 : 0.85), d)) * 0.3 * soft;
		return clamp(core + glow, 0.0, 1.0);
	}
	// 六角晶体：锐利主瓣 + 细亮核 + 薄边环，光晕收小（更几何、像真实冰晶）
	if (flake_shape == 2) {
		float sector = 6.2831853 / 6.0;
		float fa = abs(mod(atan(p.y, p.x) + sector * 0.5, sector) - sector * 0.5);
		float arm = fa * d;
		float spine = (1.0 - smoothstep(0.0, r * 0.06, arm)) * (1.0 - smoothstep(r * 0.18, r, d));
		float core = 1.0 - smoothstep(r * 0.1, r * 0.32, d);
		float rim = (1.0 - smoothstep(r * 0.82, r * 0.98, d)) * 0.5;
		float glow = (1.0 - smoothstep(r * 0.45, r * 0.95, d)) * 0.18 * mix(0.4, 1.0, clamp(softness, 0.0, 1.0));
		return clamp(max(max(spine, core), rim) + glow, 0.0, 1.0);
	}
	// 散景大圆：柔和虚化的大光斑（电影景深感），单颗透明度偏低
	if (flake_shape == 3) {
		float soft = mix(0.4, 1.0, clamp(softness, 0.0, 1.0));
		float core = 1.0 - smoothstep(r * 0.1, r * 0.62, d);
		float glow = (1.0 - smoothstep(r * 0.5, r * 1.05, d)) * 0.6 * soft;
		return clamp(core * 0.7 + glow, 0.0, 1.0);
	}
	// 默认（0）：柔六瓣雪花
	float sector = 6.2831853 / 6.0;
	float fa = abs(mod(atan(p.y, p.x) + sector * 0.5, sector) - sector * 0.5);
	float arm = fa * d;
	float spine = (1.0 - smoothstep(0.0, r * 0.14, arm)) * (1.0 - smoothstep(r * 0.12, r, d));
	float core = 1.0 - smoothstep(r * 0.18, r * 0.52, d);
	float glow = (1.0 - smoothstep(r * 0.3, r * 0.85, d)) * 0.35;
	float shape = max(spine, core) + glow * mix(0.4, 1.0, clamp(softness, 0.0, 1.0));
	return clamp(shape, 0.0, 1.0);
}

// 一层雪：在 UV 空间（每平铺块 0~1）生成向下飘落的雪花。
// 用 fract 回卷，跨 Parallax2D 平铺块天然无缝。
float snow_layer(vec2 uv, float cols, float rows, float t, float seed) {
	vec2 gv = uv * vec2(cols, rows);
	vec2 id = floor(gv);
	vec2 f = fract(gv) - 0.5;          // 各 cell 内局部坐标 -0.5..0.5（平铺块为正方形，故各向同性）

	// 该 cell 是否落雪：coverage 越大，落雪的格越多（≈ 粒子数量）
	float rnd = hash21(id + seed);
	if (rnd > coverage) {
		return 0.0;
	}

	// 每片雪花的随机属性
	float spd  = 0.35 + 0.75 * hash21(id + seed + 7.3);    // 下落速度差异
	float sz   = mix(0.55, 1.0, hash21(id + seed + 11.3)); // 尺寸差异
	float yph  = hash21(id + seed + 2.9);                  // 纵向相位（生命周期起点）
	float xoff = (hash21(id + seed + 13.1) - 0.5) * 0.4;   // 列内水平基准偏移
	float sway = (hash21(id + seed + 5.7) - 0.5);          // 飘摆方向/幅度种子
	float rot  = hash21(id + seed + 17.9) * 6.2831853;     // 六瓣朝向（旋转，避免整齐感）

	// 下落：按各自速度推进并用 fract 回卷（对应"生命周期"循环，跨平铺无缝）
	float ly = fract(f.y - t * spd + yph);
	float py = ly - 0.5;

	// 横向漂移：基准偏移 + 随风/紊乱的正弦飘摆（chaos 越大越飘）
	float drift = xoff + sin((t * spd + yph) * 6.2831853 + sway * 6.2831853) * (0.04 + chaos * 0.16);

	// 旋转后的局部坐标（让六瓣朝向各异）
	float c = cos(rot), s = sin(rot);
	vec2 p = vec2((f.x - drift) * c - py * s, (f.x - drift) * s + py * c);

	// 雪片半径：由 thickness（尺寸）与每片 sz 共同决定。
	// 上限 0.3（须 < 0.5，否则边缘渐隐窗安全距 clip=0.5-radius 变负而失效）。
	float radius = mix(0.06, 0.3, clamp(thickness, 0.0, 1.0)) * sz;
	float flake = snowflake(p, radius);

	// 闪烁亮片：基于每片固定相位做时间闪烁（仅 flake_shape == 4 时生效）
	if (flake_shape == 4) {
		float ph = hash21(id + seed + 3.7) * 6.2831853;
		float tw = 0.5 + 0.5 * sin(TIME * 5.0 + ph);
		flake *= 0.3 + 0.7 * pow(tw, 3.0);
	}

	// 单元边缘渐隐窗：让雪花主体在触及 cell 边界前就淡出，彻底消除平铺接缝处的硬切/闪烁，
	// 同时让雪花自然"飘入飘出"，跨 Parallax 平铺无缝（与雨的整列连续性等价）。
	float clip = 0.5 - radius;   // 主体圆盘不越界的安全中心距
	float win = (1.0 - smoothstep(clip * 0.5, clip, abs(drift)))
	          * (1.0 - smoothstep(clip * 0.5, clip, abs(py)));
	flake *= win;

	// 近大近亮、远小远淡；速度略影响亮度
	float bright = mix(0.6, 1.1, sz) * mix(0.85, 1.15, spd);
	return flake * bright;
}

void vertex() {
	// MODEL_MATRIX: 局部 -> 世界；已包含 Parallax2D 的滚动偏移与 repeat 平铺偏移
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// 风力/角度：与雨一致，用 speed 方向做整体剪切，保持下落速度不变。
	float tilt = clamp(speed.x / max(speed.y, 0.001), -4.0, 4.0);
	vec2 uv = vec2(UV.x + UV.y * tilt, UV.y);

	// 雪比雨慢：基础时间推进系数更小
	float t = TIME * (0.25 + length(speed) * 0.5) * fall_speed;

	// 三层景深：近处更大更亮、远处更小更淡（与雨同结构）。
	// 注意：雪片是实心圆/六瓣（占面积），单元数必须与雨同量级，否则会糊成白幕。
	float snow = 0.0;
	snow += snow_layer(uv, 40.0, 40.0, t, edge_seed) * 0.5;
	snow += snow_layer(uv, 68.0, 68.0, t * 1.25, edge_seed + 17.0) * 1.0;
	snow += snow_layer(uv, 96.0, 96.0, t * 1.6, edge_seed + 41.0) * 0.5;

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

		// 4) 区域内部的强弱起伏：雪势在区域内也不是均匀的
		float gust = w1 * 0.6 + w2 * 0.3 + w3 * 0.1;

		mask = envelope * mix(1.0 - density_variation, 1.0, gust);
		mask = pow(clamp(mask, 0.0, 1.0), edge_gamma);
	}

	// 几何边缘渐隐：抹掉 ColorRect / Parallax 平铺接缝的硬边（同时盖住风力剪切在平铺边界产生的接缝）
	float g = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	mask *= smoother_step(0.0, edge_margin, g);

	COLOR.rgb = snow_color;
	COLOR.a *= clamp(snow, 0.0, 1.0) * density * mask;
}
