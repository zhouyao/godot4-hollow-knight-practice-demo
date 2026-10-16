extends HBoxContainer
class_name MenuRow

# 设置菜单里每一行的公共部分：名称列宽度 + 显示名称的翻译。
# 原先音量行与按键行各自维护了一份逐字相同的处理，这里收拢后两边共用。
# 重置按钮那一套不在这里，见 ResetButton。

# 名称列宽度，行本体和表头都从这里取值，避免两处手改后错位
const NAME_MIN_WIDTH := 200.0

@export var display_name: String = "":
	set = set_display_name

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	name_label.custom_minimum_size.x = NAME_MIN_WIDTH
	_apply_display_name()


func set_display_name(value: String) -> void:
	display_name = value
	if is_node_ready():
		_apply_display_name()


# @export 的自定义属性不参与 Godot 的内置自动翻译，这里显式转一道
func _apply_display_name() -> void:
	name_label.text = tr(display_name)
