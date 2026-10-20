extends State
class_name PlayerState

## 玩家专用状态基类：提供强类型的 player 引用与通用行为，
## 具体状态只需实现差异部分（动画、音效、过渡条件）。
##
## 新增一个玩家状态的最小步骤：
##   1. 在本目录新建脚本 extends PlayerState
##   2. 在场景中挂到 StateMachine 下，节点名 == 目标状态名（同时在 PlayerStateNames 加常量）
##   3. 需要时把 target 写成 @export var target_xxx（见下方常量区示范）

var _player: PlayerInitial

var player: PlayerInitial:
	get:
		if _player == null or not is_instance_valid(_player):
			_player = machine.host as PlayerInitial if machine != null else null
		return _player

# ---------------------------------------------------------------- 通用行为

## 默认的物理表现：读输入 -> 重力 -> move_and_slide。
## 空中、地面、落地等状态完全一致，只有特殊状态（死亡、冲刺）才覆写。
func update(delta: float) -> void:
	player._handle_move_input()
	player._apply_gravity(delta)
	player._apply_movement()

## 默认输入：地面按下 jump 给最大起跳速度。
## 需要额外处理（如松手截断跳跃高度）时先 super.handle_input(event) 再写自己的逻辑。
func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"jump") and player.is_on_floor():
		player.velocity.y = player.max_jump_velocity

## 播放 ActionAnimationPlayer 中名为 name 的动画。
func _play_action(name: StringName) -> void:
	player.action_animation_player.play(name)

# ---------------------------------------------------------------- 公共判定

## 不在地面时的去向：上升 -> jump，下落 -> fall
func airborne_transition() -> StringName:
	return PlayerStateNames.JUMP if player.velocity.y < 0.0 else PlayerStateNames.FALL
