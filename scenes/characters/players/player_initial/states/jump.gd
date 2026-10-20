extends PlayerState

## 落地后的去向（可在检查器改指向 land / dash 等）
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
