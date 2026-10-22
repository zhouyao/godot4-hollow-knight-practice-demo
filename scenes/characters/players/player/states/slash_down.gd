extends PlayerState


## 下劈保持时长（秒）。不要求与 slash_down 动画长度相等：
## 动画更长即为"后摇可取消"，更短则尾段停在最后一帧。打断残留由 exit() 兜底。
@export var hold_time: float = 0.3

## 落地后的去向
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	player.velocity.y = maxf(player.velocity.y, player.slash_down_dive_speed)
	_play_audio(PlayerStateNames.SLASH_DOWN)
	# 动画按资源原速播放：动画长度与 hold_time 不强制相等，
	# 有意让动画长于 hold_time 时即为"后摇可取消"，短于时尾段停在最后一帧。
	# 被任何原因打断时的判定区 / 刀光残留由 exit() → player.end_attack() 兜底。
	_play_action(PlayerStateNames.SLASH_DOWN)

## 离开本状态时收尾：判定区与刀光可能停在动画中间帧的"开启 / 可见"状态。
## exit() 由状态机在任何切换前调用，所以被受击、死亡、落地等打断都能清理干净。
## 空中按住 ↓ 连踩时是 exit → enter 重入，刀光闪一下随即被动画第 0 帧重置，无副作用。
func exit(_to: StringName) -> void:
	player.end_attack()

## 空中按住 ↓ 再攻击：直接重新进入本状态，实现连续踩踏
func on_attack_pressed() -> void:
	if player.is_on_floor() or not Input.is_action_pressed(&"down"):
		return
	if machine != null:
		machine.set_state(PlayerStateNames.SLASH_DOWN, true)

## 命中敌人时由 player 反弹（见 PlayerInitial._on_down_attack_area_body_entered），
## 这里只负责收尾：反弹后仍在空中，hold_time 结束后交回 jump / fall
func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	return target_grounded if player.is_on_floor() else airborne_transition()
