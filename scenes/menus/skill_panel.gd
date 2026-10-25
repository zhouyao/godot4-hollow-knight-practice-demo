extends CanvasLayer
class_name SkillPanel

## 技能面板：按 skill 键由 WorldTemplate 实例化。
## 仅作预览/查阅，不做任何战斗状态修改；关闭即恢复游戏。

const SKILL_ROW_SCENE := preload("res://scenes/menus/components/skill_row.tscn")

@onready var list_container: VBoxContainer = $Margin/Layout/Body/HCenter/Content/List
@onready var empty_label: Label = $Margin/Layout/Body/HCenter/Content/EmptyLabel


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	Tr.apply(self)
	_build()


func _build() -> void:
	if Skills.list.is_empty():
		empty_label.visible = true
		return
	empty_label.visible = false
	for def in Skills.list:
		var row := SKILL_ROW_SCENE.instantiate()
		list_container.add_child(row)   # 先入树，确保 @onready 节点就绪
		row.setup(def)

## 关闭面板并恢复游戏（与暂停菜单对称，负责解除暂停）。
func close() -> void:
	if get_tree().paused:
		get_tree().paused = false
	# 打开面板时鼠标被切成了可见，关闭要切回游戏内隐藏，否则拖完图标鼠标会常驻在屏幕上
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"skill"):
		get_viewport().set_input_as_handled()
		close()
