extends EnemyStateMachine


func _physics_process(delta: float) -> void:
	if active and current_state != null:
		var homing := states.get(EnemyStateNames.HOMING) as EnemyGroundHomingState
		if homing != null:
			homing.poll_territory(delta)
	super._physics_process(delta)
