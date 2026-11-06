extends CanvasLayer
class_name WorldPrompt

## 世界内提示（椅子上的"坐下"等）：花纹 + 文案锚在世界坐标上，
## 镜头移动时跟着目标走，并做一点点上下浮动。
##
## 显示后会自己倒计时，到时间自动淡出；调用方也可以提前收掉（玩家坐下）。
## 与 Toast 的分工：
##   · Toast 是一次性反馈（"存档成功"），播完自毁；
##   · 本节点常驻复用，只切换透明度，不销毁节点。
##
## 版式与 Toast 一致（见 world_prompt.tscn）：文案嵌在花纹中间的空隙里，
## 花纹底部的箭头尖指向被提示的东西，所以锚点 = 箭头尖的落点。

## 淡入 / 淡出时长（秒）。
const FADE_TIME := 0.2
## 上下浮动的幅度（像素）与单程时长（秒）：越小越安静。
const FLOAT_HEIGHT := 7.0
const FLOAT_HALF_PERIOD := 1.1
## 花纹贴图里箭头尖所在的行（像素）：Content 按这一行对齐锚点。
const ARROW_TIP_Y := 146.0

## 显示后自动消失的时间（秒）；<= 0 表示不自动消失。
@export var auto_hide_time := 5.0

## 跟随目标：提示框每帧按它的全局坐标摆位，镜头移动时不会掉队。
var _anchor_node: Node2D = null
var _anchor_offset := Vector2.ZERO
var _float_time := 0.0
var _fade_tween: Tween = null
## 距离自动淡出还剩多少秒；0 表示当前没有在倒计时。
var _auto_hide_left := 0.0

@onready var _content: Control = $Content
@onready var _label: Label = $Content/Label


func _process(delta: float) -> void:
	_float_time += delta
	_tick_auto_hide(delta)
	_apply_position()


## 绑定跟随目标：箭头尖落在「anchor 全局坐标 + anchor_offset」。
## text 走 TranslationServer，源文案即 key。
func setup(anchor: Node2D, anchor_offset: Vector2, text: String) -> void:
	_anchor_node = anchor
	_anchor_offset = anchor_offset
	_label.text = TranslationServer.translate(text)
	_apply_position()


## 淡入，并重新开始 auto_hide_time 的倒计时。重复调用只会重置淡入与倒计时。
func show_prompt() -> void:
	if not is_instance_valid(_anchor_node):
		return
	_auto_hide_left = maxf(auto_hide_time, 0.0)
	_fade_to(1.0)


## 淡出：玩家坐下 / 离开时收起，节点留着，下次还能直接再淡入。
func hide_prompt() -> void:
	_auto_hide_left = 0.0
	_fade_to(0.0)


## 自动消失倒计时：到点走同一套淡出，和主动收起没有区别。
func _tick_auto_hide(delta: float) -> void:
	if _auto_hide_left <= 0.0:
		return
	_auto_hide_left -= delta
	if _auto_hide_left <= 0.0:
		hide_prompt()


func _fade_to(alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_content, "modulate:a", alpha, FADE_TIME)


## 摆位：世界锚点逐帧换算成屏幕坐标，再叠加一个正弦上下浮动。
func _apply_position() -> void:
	if _content == null or not is_instance_valid(_anchor_node):
		return
	var box := _content.size
	if box.x <= 0.0:
		return
	var point := get_viewport().get_canvas_transform() * (_anchor_node.global_position + _anchor_offset)
	var float_y := -sin(_float_time * PI / FLOAT_HALF_PERIOD) * FLOAT_HEIGHT
	_content.position = Vector2(point.x - box.x * 0.5, point.y - ARROW_TIP_Y + float_y)
