extends PlayerState

func enter(_from: StringName) -> void:
	_play_action(PlayerStateNames.LOOK_DOWN)
	AuCameraDirector.look_down()

func exit(_to: StringName) -> void:
	AuCameraDirector.clear_look()

func update(_delta: float) -> void:
	player._apply_gravity(_delta)
	player._apply_movement()

func get_transition(_delta: float) -> StringName:
	if not player.is_on_floor():
		return airborne_transition()
	if Input.is_action_pressed(&"left") or Input.is_action_pressed(&"right"):
		return PlayerStateNames.IDLE
	if Input.is_action_pressed(&"down"):
		return &""
	return PlayerStateNames.IDLE
