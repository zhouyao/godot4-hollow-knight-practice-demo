extends EnemyState
class_name EnemyFlyingPatrolState


## 巡逻半径（像素）：绕出生点来回移动的范围。
@export var patrol_radius: float = 80.0
## 巡逻速度倍率（相对 enemy.move_speed）。
@export var patrol_speed_multiplier: float = 0.5

var _dir: int = 1

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	_dir = enemy.move_direction

func update(delta: float) -> void:
	_patrol_fly(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	return &""

## 2D 飘移：在出生点附近横向往返，并叠加轻微纵向浮动。
## 飞行怪不受重力、不分领地，保持原巡逻逻辑。
func _patrol_fly(_delta: float) -> void:
	var target := enemy.spawn_position + Vector2(_dir * patrol_radius, sin(elapsed * 2.0) * 20.0)
	var dir := enemy.nav_velocity(target, enemy.move_speed * patrol_speed_multiplier, false)
	enemy.velocity = dir
	if dir.x != 0.0:
		_face_dir(signf(dir.x))
	if enemy.global_position.distance_to(enemy.spawn_position) > patrol_radius * 1.5:
		_dir *= -1
