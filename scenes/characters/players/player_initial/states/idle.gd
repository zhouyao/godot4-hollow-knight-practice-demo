extends PlayerState

## 站立态：水平速度接近 0 且在地面。一旦有水平速度就切 walk；离地走 jump / fall。

## 判定静止的阈值：避免 knockback 等残余速度导致永远回不到 idle
const MOVE_EPS := 1.0

## 一旦开始移动就切到这个状态（可在检查器改指向 dash 等）
@export var target_move: StringName = PlayerStateNames.WALK

func enter(_from: StringName) -> void:
	_play_action(PlayerStateNames.IDLE)

func get_transition(_delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if absf(player.velocity.x) > MOVE_EPS:
		return target_move
	return &""
