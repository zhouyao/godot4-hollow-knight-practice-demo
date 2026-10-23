extends EnemyState


var _landed := false

func enter(_from: StringName) -> void:
	machine.active = true
	_flash_white()
	_play_action(EnemyStateNames.DEATH)
	_play_audio(EnemyStateNames.DEATH)
	enemy.gravity_enabled = true
	if enemy.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING:
		enemy.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED

func update(delta: float) -> void:
	super.update(delta)
	if _landed or not enemy.is_on_floor():
		return
	_landed = true
	enemy.collision_shape.set_deferred("disabled", true)
	machine.active = false

func get_transition(_delta: float) -> StringName:
	return &""
