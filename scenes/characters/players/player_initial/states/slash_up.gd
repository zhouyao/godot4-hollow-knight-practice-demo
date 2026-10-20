extends PlayerState


## 上劈保持时长（秒）；与 ActionAnimationPlayer/slash_up 的动画长度（0.3s）对齐
@export var hold_time: float = 0.3

## 上劈结束后的去向；此时若已离地则交给 airborne_transition()
@export var target_next: StringName = PlayerStateNames.IDLE

## 结束后（地面）仍按住 ↑ 时的去向：直接回到抬头姿态，不必先闪一下 idle
@export var target_hold_up: StringName = PlayerStateNames.LOOK_UP

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.SLASH_UP)
	_play_action(PlayerStateNames.SLASH_UP)

## 挥砍过程中不响应新的攻击，避免自己打断自己
func on_attack_pressed() -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	if not player.is_on_floor():
		return airborne_transition()
	return target_hold_up if Input.is_action_pressed(&"up") else target_next
