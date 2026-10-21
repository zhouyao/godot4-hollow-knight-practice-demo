extends EnemyState

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.DEATH)
	_play_audio(EnemyStateNames.DEATH)
	machine.active = false
	# 尸体不再阻挡玩家，也不再被玩家攻击区命中
	enemy.collision_shape.set_deferred("disabled", true)

func get_transition(_delta: float) -> StringName:
	return &""
