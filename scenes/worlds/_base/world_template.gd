extends Node2D
class_name WorldTemplate


const PAUSE_MENU_SCENE := preload("res://scenes/menus/pause_menu.tscn")
var pause_menu: CanvasLayer = null

const SKILL_PANEL_SCENE := preload("res://scenes/menus/skill_panel.tscn")
var skill_panel: CanvasLayer = null

## 常驻技能条（技能面板打开时保持可见以便拖放，暂停菜单打开时隐藏）。
@onready var skill_bar: SkillBar = $SkillBar
@onready var player: PlayerInitial = $Player

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
	# 技能条靠这个引用读技能冷却：子节点先 ready，这里注入后每帧才会读到值。
	if skill_bar != null:
		skill_bar.player = player
	# 兜底：进游戏时用存档值对齐一次窗口（覆盖启动延迟 apply 偶发的时序失败）。
	Settings.display.apply_now()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"skill"):
		get_viewport().set_input_as_handled()
		if skill_panel == null:
			open_skill_panel()
		return
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if pause_menu == null:
		open_pause()

func open_pause() -> void:
	get_tree().paused = true
	_set_skill_bar_visible(false)
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.tree_exiting.connect(_on_pause_menu_exited)
	add_child(pause_menu)

func _on_pause_menu_exited() -> void:
	pause_menu = null
	_set_skill_bar_visible(true)


func _set_skill_bar_visible(should_show: bool) -> void:
	if skill_bar != null:
		skill_bar.visible = should_show


func open_skill_panel() -> void:
	get_tree().paused = true
	skill_panel = SKILL_PANEL_SCENE.instantiate()
	skill_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	skill_panel.tree_exiting.connect(_on_skill_panel_exited)
	add_child(skill_panel)
	if skill_bar != null:
		skill_bar.set_panel_open(true)


func _on_skill_panel_exited() -> void:
	skill_panel = null
	if skill_bar != null:
		skill_bar.set_panel_open(false)

func _on_kill_box_body_entered(body: Node2D) -> void:
	if "kill" in body:
		body.kill()
