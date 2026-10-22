extends EnemyState
class_name EnemyChaseState

@export var speed_multiplier: float = 1.0

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)

func update(delta: float) -> void:
	if enemy.target == null:
		enemy.velocity.x = 0.0
		super.update(delta)
		return
	var dx := enemy.target.global_position.x - enemy.global_position.x
	var desired := 0
	if dx > 0.0:
		desired = 1
	elif dx < 0.0:
		desired = -1
	if desired != 0 and desired != enemy.move_direction:
		enemy._flip_direction()
	enemy.velocity.x = float(enemy.move_direction) * enemy.move_speed * speed_multiplier

	super.update(delta)

func get_transition(_delta: float) -> StringName:
	return &""
