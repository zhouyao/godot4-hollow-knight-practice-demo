extends Node2D
class_name WorldTemplate

const PAUSE_MENU_SCENE := preload("res://scenes/menus/pause_menu.tscn")
var pause_menu: CanvasLayer = null

func _ready():
	Globals.level_preparing = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

# Esc 切换暂停：未暂停时打开暂停菜单；已暂停时由 PauseMenu 自身处理恢复
func _unhandled_input(event: InputEvent) -> void:
	if !event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if pause_menu == null:
		open_pause()

# 暂停游戏并把暂停菜单挂到世界节点下；菜单自身 process_mode = ALWAYS，
# 因此即使 SceneTree 被暂停，按钮与输入仍可用。
func open_pause() -> void:
	get_tree().paused = true
	pause_menu = PAUSE_MENU_SCENE.instantiate()
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.tree_exiting.connect(_on_pause_menu_exited)
	add_child(pause_menu)

func _on_pause_menu_exited() -> void:
	pause_menu = null

func _on_kill_box_body_entered(body: Node2D) -> void:
	if "kill" in body:
		body.kill()


func _on_start_timer_timeout() -> void:
	Globals.level_preparing = false
