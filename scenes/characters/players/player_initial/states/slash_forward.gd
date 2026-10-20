extends PlayerState


## 挥砍保持时长（秒）；与 ActionAnimationPlayer/slash_forward 的动画长度（0.3s）对齐
@export var hold_time: float = 0.3

## 挥砍结束后的去向；此时若已离地则交给 airborne_transition()
@export var target_next: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.SLASH_FORWARD)
	_play_action(PlayerStateNames.SLASH_FORWARD)

func on_attack_pressed() -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	return airborne_transition() if not player.is_on_floor() else target_next
