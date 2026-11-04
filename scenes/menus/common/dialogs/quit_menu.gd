class_name QuitMenu
extends Control

# 通用确认弹窗（复刻 HollowKnight 的 quit_menu / quit_pause_menu）：
# 警告花纹 + 标题 +（可选）副标题 + 是 / 否，覆盖在当前界面上。
# 主菜单“离开游戏”与暂停菜单“退回主菜单”共用本场景，文案由调用方在 add_child 前写入；
# 点“是”只发 confirmed，具体做什么（退出游戏 / 回主菜单）交给调用方，弹窗不预设行为。
# 默认聚焦“否”（同 HK），避免回车 / 手柄确认误触。

signal confirmed
signal closed

@export var title_text := "退出游戏？"
@export var subtitle_text := ""

@onready var _title: Label = $VBoxContainer/Texts/TitleLabel
@onready var _subtitle: Label = $VBoxContainer/Texts/SubtitleLabel
@onready var _deny_button: FocusMenuButton = $VBoxContainer/DenyButton
@onready var _fleur: AnimatedSprite2D = $VBoxContainer/Fleur/Sprite


func _ready() -> void:
	_title.text = title_text
	_subtitle.text = subtitle_text
	_subtitle.visible = subtitle_text != ""
	Tr.apply(self)
	play_fleur()
	_deny_button.quiet_focus()


# 花纹是单次动画：每次出现都重放（同 HK）
func play_fleur() -> void:
	_fleur.stop()
	_fleur.frame = 0
	_fleur.play(&"default")


func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	dismiss()


## 关闭弹窗：与 HK 一致先隐藏再发信号（调用方据此恢复原界面），本帧末释放自身
func dismiss() -> void:
	hide()
	closed.emit()
	queue_free()


func _on_confirm_button_pressed() -> void:
	confirmed.emit()


func _on_deny_button_pressed() -> void:
	dismiss()
