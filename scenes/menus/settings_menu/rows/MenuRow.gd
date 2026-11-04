extends HBoxContainer
class_name MenuRow


## 行首显示的文本（会走 tr() 翻译，填的是 key 而不是最终文字）。运行时修改会同步到 NameLabel。
@export var display_name: String = "":
	set = set_display_name

@onready var name_label: Label = $NameLabel


func _ready() -> void:
	_apply_display_name()


func set_display_name(value: String) -> void:
	display_name = value
	if is_node_ready():
		_apply_display_name()


func _apply_display_name() -> void:
	name_label.text = tr(display_name)
