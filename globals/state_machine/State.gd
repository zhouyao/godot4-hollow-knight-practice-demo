extends Node
class_name State

## 状态基类：每个具体状态是 StateMachine 下的一个子节点，自治 enter/exit/update/input。
## 父节点即状态机，通过它访问宿主（player）与状态机本身。
##
## 推荐用法：不要直接继承本类，而是为每个宿主派生一层类型化基类
## （见 scenes/characters/players/player_initial/states/player_state.gd），
## 这样状态内部可以拿到强类型的宿主引用，不必每帧做 as 转换。

## 进入状态（from 为上一个状态名）。不要在这里直接 set_state 触发无限递归。
func enter(_from: StringName) -> void: pass
## 离开状态（to 为下一个状态名）。
func exit(_to: StringName) -> void: pass
## 每物理帧更新（仅当前状态被调用）。
func update(_delta: float) -> void: pass
## 事件式输入（跳跃 / 攻击等）。
func handle_input(_event: InputEvent) -> void: pass
## 返回要切换到的目标状态名（建议使用如 PlayerStateNames 的常量）；无过渡返回 &""。
func get_transition(_delta: float) -> StringName: return &""

## 本状态已持续的秒数，切换时由状态机自动清零；update 调用前已累加当帧 delta。
## 需要"进入后保持 N 秒"的状态直接用它，不必自己维护计时变量。
var elapsed: float = 0.0

var _machine: StateMachine

## 所属状态机（父节点），首次访问后缓存，避免每帧反复 get_parent + 转型。
var machine: StateMachine:
	get:
		if _machine == null or not is_instance_valid(_machine):
			_machine = get_parent() as StateMachine
		return _machine

## 状态机宿主；machine 无效时为 null。
var host: Node:
	get: return machine.host if machine != null else null

## 播放宿主 audio_nodes 中名为 key 的音效；节点不存在则安全跳过。
func _play_audio(key: StringName) -> void:
	if machine == null:
		return
	machine.play_sfx(key)

## 停止宿主 audio_nodes 中名为 key 的音效；节点不存在则安全跳过。
func _stop_audio(key: StringName) -> void:
	if machine == null:
		return
	machine.stop_sfx(key)
