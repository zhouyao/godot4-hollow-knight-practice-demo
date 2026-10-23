extends PlayerState


## 前刺动作的最短持续时间（秒）：期间不接受过渡，保证挥砍不被打断。
@export var hold_time: float = 0.3

## 动作结束且已落地时切往的状态（一般是 idle）；还在空中则交给 airborne_transition()。
@export var target_next: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.SLASH_FORWARD)
	_play_action(PlayerStateNames.SLASH_FORWARD)

func exit(_to: StringName) -> void:
	player.end_attack()

func on_attack_pressed() -> void:
	pass

func get_transition(_delta: float) -> StringName:
	if elapsed <= hold_time:
		return &""
	return airborne_transition() if not player.is_on_floor() else target_next
