shader_type canvas_item;

// 通用去色：amount = 0 原色，1 完全灰度。用于技能图标"能量不足"的不可用提示。

uniform float amount : hint_range(0.0, 1.0) = 1.0;
// 灰度之外再叠加的压暗比例（0 = 不压暗），让不可用的图标比正常态更"退后"。
uniform float dim : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 gray = vec3(lum) * (1.0 - dim * amount);
	COLOR = vec4(mix(tex.rgb, gray, amount), tex.a) * COLOR;
}
