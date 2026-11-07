extends CanvasLayer

## 区域标题：单行主标题 + 上下花纹，淡入 → 停留 → 淡出，结束后自毁。
## 文案由使用方传入（关卡一般传地图名）。

const FADE_IN := 1.7
const HOLD := 5.0
const FADE_OUT := 0.85

## 中文原文作翻译 key（见 translations.csv），_ready 时统一走 Tr.apply。
@export var title := "未知区域"

@onready var _title: Label = $Root/Title
@onready var _top: AnimatedSprite2D = $Root/Top
@onready var _bottom: AnimatedSprite2D = $Root/Bottom


func _ready() -> void:
	_title.text = title
	Tr.apply(self)
	_title.modulate.a = 0.0
	_top.frame = 0
	_bottom.frame = 0
	_play()


func _play() -> void:
	var top_last := _top.sprite_frames.get_frame_count(&"default") - 1
	var bottom_last := _bottom.sprite_frames.get_frame_count(&"default") - 1

	var tween := create_tween()
	tween.tween_method(_set_alpha, 0.0, 1.0, FADE_IN)
	tween.parallel().tween_method(_set_top_frame, 0.0, float(top_last), FADE_IN)
	tween.parallel().tween_method(_set_bottom_frame, 0.0, float(bottom_last), FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_method(_set_alpha, 1.0, 0.0, FADE_OUT)
	tween.parallel().tween_method(_set_top_frame, float(top_last), 0.0, FADE_OUT)
	tween.parallel().tween_method(_set_bottom_frame, float(bottom_last), 0.0, FADE_OUT)
	tween.tween_callback(queue_free)


func _set_alpha(a: float) -> void:
	_title.modulate.a = a


func _set_top_frame(v: float) -> void:
	_top.frame = int(v)


func _set_bottom_frame(v: float) -> void:
	_bottom.frame = int(v)
