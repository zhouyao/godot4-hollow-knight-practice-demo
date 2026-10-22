extends PlayerState

## 判定静止的阈值：避免 knockback 等残余速度导致永远回不到 idle
const STOP_EPS := 1.0

## 停下来后的去向（可在检查器改指向 dash 等）
@export var target_stop: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.WALK)
	_play_action(PlayerStateNames.WALK)

func exit(_to: StringName) -> void:
	_stop_audio(PlayerStateNames.WALK)

func get_transition(_delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if absf(player.velocity.x) < STOP_EPS:
		return target_stop
	return &""
