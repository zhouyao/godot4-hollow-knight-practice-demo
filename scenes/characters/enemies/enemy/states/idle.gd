extends EnemyState


func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)

func update(delta: float) -> void:
	enemy.velocity.x = 0.0
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	return &""
