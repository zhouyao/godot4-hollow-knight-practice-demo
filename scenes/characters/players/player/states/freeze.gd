extends PlayerState
class_name PlayerFreezeState

## 被 boss 吼叫等演出锁定的"冻结/硬直"状态：
## 水平速度清零、忽略一切玩家输入（移动/跳跃/攻击/冲刺/技能），但仍受重力（空中则下坠落地），
## 演出结束后自动回到 idle / 空中状态。冻结期间照常可被击中（受击会打断进入 hurt）。

## 冻结时长（秒），与 boss 吼叫演出对齐。
@export var freeze_duration: float = 3.0

func enter(_from: StringName) -> void:
	player.velocity.x = 0.0

func update(delta: float) -> void:
	# 忽略移动 / 操作输入：水平速度清零，只走重力 + 移动（空中则下坠，落地则站定）。
	player.velocity.x = 0.0
	player._apply_gravity(delta)
	player._apply_movement()

func handle_input(_event: InputEvent) -> void:
	pass

func exit(_to: StringName) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed < freeze_duration:
		return &""
	return PlayerStateNames.FALL if not player.is_on_floor() else PlayerStateNames.IDLE
