extends PlayerState


@export_group("行为 Behavior")
## 落地硬直时长（秒）：期间不产生过渡，保证落地动作播完再走下一步。
@export var hold_time: float = 0.1

@export_group("状态过渡 Transitions")
## 硬直结束后切往的状态（一般是 idle）。
@export var target_next: StringName = PlayerStateNames.IDLE

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.LAND)
	_play_action(PlayerStateNames.IDLE)

func get_transition(_delta: float) -> StringName:
	return target_next if elapsed > hold_time else &""
