extends EnemyState
class_name EnemyChaseState


## 追击速度倍率：乘以 enemy.move_speed，大于 1 表示冲锋型敌人。
@export var speed_multiplier: float = 1.0

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)

func update(delta: float) -> void:
	if enemy.target == null:
		enemy.velocity.x = 0.0
		super.update(delta)
		return
	var step_pos := enemy.get_navigation_step(enemy.target.global_position)
	var to_step := step_pos - enemy.global_position
	if to_step.length() > 1.0:
		var desired := 1 if to_step.x > 0.0 else -1
		if desired != enemy.move_direction:
			enemy._flip_direction()
		enemy.velocity.x = float(enemy.move_direction) * enemy.move_speed * speed_multiplier
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	return &""
