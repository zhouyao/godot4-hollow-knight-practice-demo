extends PlayerState


## 下劈保持时长（秒）；与 ActionAnimationPlayer/slash_down 的动画长度（0.3s）对齐
@export var hold_time: float = 0.3

## 落地后的去向
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	player.velocity.y = maxf(player.velocity.y, player.slash_down_dive_speed)
	_play_audio(PlayerStateNames.SLASH_DOWN)
	_play_action(PlayerStateNames.SLASH_DOWN)

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
