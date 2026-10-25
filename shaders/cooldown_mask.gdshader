shader_type canvas_item;

// 技能冷却扇形遮罩：从 12 点方向顺时针覆盖，随 ratio 收缩；
// 同时用圆角矩形 SDF 裁剪，让遮罩的外轮廓与图标区域的尺寸、圆角完全一致。

uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform float corner_radius = 6.0;
uniform vec4 mask_color : source_color = vec4(0.0, 0.0, 0.0, 0.65);
uniform vec2 rect_size = vec2(68.0);

varying vec2 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	vec2 half_size = rect_size * 0.5;
	vec2 p = v_pos - half_size;

	// 圆角矩形 SDF（负值在内部），0 等值线即遮罩外轮廓
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	vec2 q = abs(p) - (half_size - vec2(radius));
	float sdf = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float rect_mask = 1.0 - smoothstep(-0.5, 0.5, sdf);

	// 从 12 点方向顺时针的角度归一化到 0..1
	float ang = atan(p.x, -p.y);
	float t = (ang < 0.0 ? ang + 6.28318530718 : ang) * 0.15915494309;
	// fwidth 在 12 点接缝处会跳变，限制上界避免接缝处半透明
	float aa = min(fwidth(t) * 0.5, 0.02);
	float pie = ratio >= 0.999 ? 1.0 : 1.0 - smoothstep(ratio - aa, ratio + aa, t);

	COLOR = vec4(mask_color.rgb, mask_color.a * pie * rect_mask);
}
