extends Node
class_name StateMachine

## 状态变化时发出，供 UI / 音频 / 动画等外部系统订阅
signal state_changed(new_state: int, old_state: int)

## 当前状态 id，语义由子类的 enum 定义；-1 表示未初始化
var state: int = -1
var previous_state: int = -1

## 宿主节点，不绑定具体类型，敌人 / NPC / UI 都能复用
@onready var parent: Node = get_parent()

func _physics_process(delta: float) -> void:
	_state_logic(delta)
	set_state(_get_transition(delta))

func _unhandled_input(event: InputEvent) -> void:
	_handle_input(event)

func set_state(new_state: int) -> void:
	if new_state == -1 or new_state == state:
		return  # 无效状态 / 同态，不重复触发 enter/exit

	previous_state = state
	state = new_state

	if previous_state != -1:
		_exit_state(previous_state, new_state)
	if new_state != -1:
		_enter_state(new_state, previous_state)

	state_changed.emit(new_state, previous_state)

# --- 子类按需重写 ---
func _handle_input(_event: InputEvent) -> void: pass                # 事件式输入（跳跃 / 攻击）
func _state_logic(_delta: float) -> void: pass
func _get_transition(_delta: float) -> int: return -1
func _enter_state(_new_state: int, _old_state: int) -> void: pass
func _exit_state(_old_state: int, _new_state: int) -> void: pass
