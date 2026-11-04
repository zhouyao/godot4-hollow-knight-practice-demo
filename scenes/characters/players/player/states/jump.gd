extends PlayerState


@export_group("状态过渡 Transitions")
## 落回地面时切往的状态（一般是 land）。改成 idle 可以直接跳过落地硬直。
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.JUMP)
	_play_action(PlayerStateNames.JUMP)

func get_transition(_delta: float) -> StringName:
	if player.is_on_floor():
		return target_grounded
	if player.velocity.y >= 0.0:
		return PlayerStateNames.FALL
	return &""
