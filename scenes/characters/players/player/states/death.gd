extends PlayerState


func enter(_from: StringName) -> void:
	_play_action(PlayerStateNames.DEATH)
	_play_audio(PlayerStateNames.DEATH)
	machine.active = false

func update(_delta: float) -> void:
	pass

func get_transition(_delta: float) -> StringName:
	return &""
