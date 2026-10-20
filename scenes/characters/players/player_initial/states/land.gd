extends PlayerState

## 落地保持时长（秒）；状态机自动维护 elapsed
@export var hold_time: float = 0.1

## 保持结束后的去向
@export var target_next: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.LAND)
	_play_action(PlayerStateNames.IDLE)

func get_transition(_delta: float) -> StringName:
	return target_next if elapsed > hold_time else &""
