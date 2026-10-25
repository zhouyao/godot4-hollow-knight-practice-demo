shader_type canvas_item;

// 技能图标不可用时的着色：amount = 0 原色，1 整体变黑（保留 alpha，只留轮廓）。
// 用于"能量不足按不出去"的提示，与冷却扇形遮罩互不干扰。

uniform float amount : hint_range(0.0, 1.0) = 0.0;
// 不可用态的目标色，默认纯黑；想改成其他颜色（比如暗红）只调这里。
uniform vec3 disabled_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex.rgb, disabled_color, amount), tex.a) * COLOR;
}
