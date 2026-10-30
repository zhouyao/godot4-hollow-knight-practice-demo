extends PlayerState


## 下劈动作的最短持续时间（秒）：期间不接受过渡，保证俯冲到落地这段不被打断。
@export var hold_time: float = 0.3

## 下劈落地后切往的状态（一般是 land）。
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	# 本次挥砍的命中登记表清零（同一次下劈内可连砍多个目标，但每个目标只吃一次）。
	player.begin_attack()
	player.velocity.y = maxf(player.velocity.y, player.slash_down_dive_speed)
	_play_audio(PlayerStateNames.SLASH_DOWN)
	_play_action(PlayerStateNames.SLASH_DOWN)

func exit(_to: StringName) -> void:
	player.end_attack()

func on_attack_pressed() -> void:
	if player.is_on_floor() or not Input.is_action_pressed(&"down"):
		return
	if machine != null:
		machine.set_state(PlayerStateNames.SLASH_DOWN, true)

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	return target_grounded if player.is_on_floor() else airborne_transition()
