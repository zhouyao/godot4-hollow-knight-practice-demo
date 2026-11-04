shader_type canvas_item;

// 灵魂球"灌液"遮罩（空之骑士 HUD 效果）：
// 用一张液面遮罩图裁剪能量球贴图，液面从球底往上涨。
// mask_translation = 1 - 能量占比：
//   接近 0 → 遮罩与球体对齐，球几乎灌满；
//   接近 1 → 遮罩整体下沉到球外，球完全看不见。
// 遮罩图本身是多帧动画，液面会轻微起伏，和原作一样有"晃动"的手感。

uniform sampler2D mask;
uniform float mask_translation : hint_range(0.0, 1.0, 0.001) = 0.0;

// 采样整体上移一点：满能量时遮罩上边缘不会切掉球顶。
const float MASK_LIFT = 0.1;

void fragment() {
	vec4 orb = texture(TEXTURE, UV);
	vec4 liquid = texture(mask, UV - vec2(0.0, mask_translation - MASK_LIFT));
	if (liquid.a <= 0.0) {
		discard;
	}
	COLOR = orb * liquid.a;
}
