extends CanvasLayer
class_name Toast

## 轻量提示条：淡入 → 停留 → 淡出 → 自毁。
## 不占用 HUD 的节点结构，任何系统都可以 instantiate 一个来提示一次。

const FADE_IN := 0.2
const HOLD := 1.4
const FADE_OUT := 0.3

@onready var _label: Label = $Label


## 显示一句提示。text 走 TranslationServer，源文案即 key。
func show_text(text: String, hold := HOLD) -> void:
	_label.text = TranslationServer.translate(text)
	_label.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(hold)
	tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	queue_free()
