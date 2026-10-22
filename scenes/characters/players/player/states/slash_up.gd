extends PlayerState


## 上劈保持时长（秒）。不要求与 slash_up 动画长度相等：
## 动画更长即为"后摇可取消"，更短则尾段停在最后一帧。打断残留由 exit() 兜底。
@export var hold_time: float = 0.3

## 上劈结束后的去向；此时若已离地则交给 airborne_transition()
@export var target_next: StringName = PlayerStateNames.IDLE

## 结束后（地面）仍按住 ↑ 时的去向：直接回到抬头姿态，不必先闪一下 idle
@export var target_hold_up: StringName = PlayerStateNames.LOOK_UP

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.SLASH_UP)
	# 动画按资源原速播放：动画长度与 hold_time 不强制相等，
	# 有意让动画长于 hold_time 时即为"后摇可取消"，短于时尾段停在最后一帧。
	# 被任何原因打断时的判定区 / 刀光残留由 exit() → player.end_attack() 兜底。
	_play_action(PlayerStateNames.SLASH_UP)

## 离开本状态时收尾：判定区与刀光可能停在动画中间帧的"开启 / 可见"状态。
## exit() 由状态机在任何切换前调用，所以被受击、死亡、落地等打断都能清理干净。
func exit(_to: StringName) -> void:
	player.end_attack()

## 挥砍过程中不响应新的攻击，避免自己打断自己
func on_attack_pressed() -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	if not player.is_on_floor():
		return airborne_transition()
	return target_hold_up if Input.is_action_pressed(&"up") else target_next
