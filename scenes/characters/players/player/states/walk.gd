extends PlayerState


const STOP_EPS := 1.0

## 横向速度衰减到阈值以下时切往的目标状态（一般是 idle）。
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
