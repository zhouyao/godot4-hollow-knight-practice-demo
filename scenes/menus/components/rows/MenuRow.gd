extends HBoxContainer
class_name MenuRow

@export var display_name: String = "":
	set = set_display_name

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	_apply_display_name()


func set_display_name(value: String) -> void:
	display_name = value
	if is_node_ready():
		_apply_display_name()


# @export 的自定义属性不参与 Godot 的内置自动翻译，这里显式转一道
func _apply_display_name() -> void:
	name_label.text = tr(display_name)
