extends CanvasLayer
class_name Toast

## 轻量提示条：花纹 + 文案整体淡入 → 停留 → 淡出 → 自毁。
##
## 版式（见 toast.tscn）：文案嵌在花纹贴图中间的空隙里，花纹底部的箭头指向被提示的东西。
## 因此 show_text_at() 传的锚点 = 箭头尖的落点：长椅 / 椅子会给出"椅背上方"的位置，
## 每帧把世界坐标换算成屏幕坐标，镜头移动时提示框跟着目标走。
##
## 两种用法：
##   · show_text(text)                      屏幕下方居中（拿不到世界锚点时的回落）
##   · show_text_at(text, world_position)   箭头尖指着世界里的某个点

const FADE_IN := 0.2
const HOLD := 1.4
const FADE_OUT := 0.3

## 花纹出场时的起始缩放：略微缩一下再弹回 1.0，给静态花纹一点"冒出"的手感。
const PROMPT_POP_SCALE := Vector2(0.9, 0.9)
## 花纹贴图里箭头尖所在的行（像素）：Content 按这一行对齐锚点。
const ARROW_TIP_Y := 146.0
## 没有世界锚点时整块提示的落点（相对屏幕中心，y 向下为正）。
const SCREEN_FALLBACK_OFFSET := Vector2(0, 330)

var _anchor_world := Vector2.INF

@onready var _content: Control = $Content
@onready var _label: Label = $Content/Label
@onready var _prompt: AnimatedSprite2D = $Content/Prompt


func _process(_delta: float) -> void:
	_apply_position()


## 显示一句提示（屏幕下方居中）。text 走 TranslationServer，源文案即 key。
func show_text(text: String, hold := HOLD) -> void:
	_anchor_world = Vector2.INF
	_play(text, hold)


## 显示一句提示，箭头尖落在世界坐标 world_position（椅子上方 / 可交互物上方）。
func show_text_at(text: String, world_position: Vector2, hold := HOLD) -> void:
	_anchor_world = world_position
	_play(text, hold)


# ---------------------------------------------------------------- 内部

func _play(text: String, hold: float) -> void:
	_label.text = TranslationServer.translate(text)
	_content.modulate.a = 0.0
	_prompt.scale = PROMPT_POP_SCALE
	_apply_position()

	var tween := create_tween()
	# 文案与花纹同在 Content 下：淡入 / 淡出只动 Content 的 alpha，天然同步。
	tween.set_parallel(true)
	tween.tween_property(_content, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(_prompt, "scale", Vector2.ONE, FADE_IN) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_interval(hold)
	tween.tween_property(_content, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	queue_free()


## 摆位：世界锚点逐帧换算（跟随镜头）；没有锚点时回落屏幕下方。
func _apply_position() -> void:
	if _content == null:
		return
	var box := _content.size
	if box.x <= 0.0:
		return
	var point: Vector2
	if _anchor_world == Vector2.INF:
		point = get_viewport().get_visible_rect().size * 0.5 + SCREEN_FALLBACK_OFFSET
	else:
		point = get_viewport().get_canvas_transform() * _anchor_world
	_content.position = Vector2(point.x - box.x * 0.5, point.y - ARROW_TIP_Y)
