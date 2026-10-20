extends PlayerState
## 上升态：离地且 velocity.y < 0。可变跳跃高度在松手时截断。

## 落地后的去向（可在检查器改指向 land / dash 等）
@export var target_grounded: StringName = PlayerStateNames.LAND

func enter(_from: StringName) -> void:
	_play_audio(PlayerStateNames.JUMP)
	_play_action(PlayerStateNames.JUMP)

func handle_input(event: InputEvent) -> void:
	super.handle_input(event)
	if event.is_action_released(&"jump") and player.velocity.y < player.min_jump_velocity:
		player.velocity.y = player.min_jump_velocity

func get_transition(_delta: float) -> StringName:
	if player.is_on_floor():
		return target_grounded
	if player.velocity.y >= 0.0:
		return PlayerStateNames.FALL
	return &""
