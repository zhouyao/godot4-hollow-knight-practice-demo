class_name SectionHeader
extends VBoxContainer

## 设置分页顶部：标题 + 花纹单次动画（与音频页原先的效果一致）。
## 各分页只需在 tscn 里填 title_text；切 tab 重新显示时花纹自动从头重播。

@export var title_text := ""

@onready var _title: Label = $Title
@onready var _fleur: AnimatedSprite2D = $FleurHolder/Fleur


func _ready() -> void:
	_title.text = title_text
	play_intro()


func play_intro() -> void:
	_fleur.stop()
	_fleur.frame = 0
	_fleur.play(&"default")


# 可见性由外层容器（设置页的 ContentPanel、暂停菜单的 AudioPanel）控制，
# 每次重新显示都重放一次，不依赖调用方记得手动触发。
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		play_intro()
