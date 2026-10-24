extends EnemyState
class_name EnemyFlyingReturnState


## 抵达出生点的判定距离（像素）。
@export var arrive_distance: float = 8.0
## 返回速度倍率（相对 enemy.move_speed）。
@export var return_speed_multiplier: float = 2.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")

func update(delta: float) -> void:
	enemy.velocity = enemy.nav_velocity(enemy.spawn_position, enemy.move_speed * return_speed_multiplier, false)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if enemy.global_position.distance_to(enemy.spawn_position) <= arrive_distance:
		enemy._set_combat(false)
		return EnemyStateNames.PATROL
	# 返回途中仅受击可重开战（take_damage 会置 combat_active）；否则继续返回。
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	return &""
