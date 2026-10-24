extends EnemyState
class_name EnemyGroundReturnState


## 抵达出生点的判定距离（像素）。
@export var arrive_distance: float = 8.0
## 返回速度倍率（相对 enemy.move_speed）。
@export var return_speed_multiplier: float = 2.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")

func update(delta: float) -> void:
	var speed := enemy.move_speed * return_speed_multiplier
	var dir := enemy.nav_velocity(enemy.spawn_position, speed, true)
	if (enemy as EnemyGround).ledge_ahead():
		# 前方是悬崖：掉头往安全的一侧退，退回路面后才能继续朝巢走。
		# 只把速度清零会让敌人永远停在边缘（悬崖判定一直为真），导致彻底回不了巢。
		var back := -float(enemy.move_direction)
		_face_x(enemy.global_position.x + back)
		enemy.velocity.x = back * speed
	elif dir.x != 0.0:
		_face_x(enemy.global_position.x + dir.x)
		enemy.velocity.x = dir.x
	else:
		enemy.velocity.x = 0.0
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	# 陆地怪只按水平（x）距离判定归位：出生点的 y 可能受重力/地形影响
	# 与实际高度不一致，若用全量 2D 距离会永远到不了，导致卡在 return 状态。
	if abs(enemy.global_position.x - enemy.spawn_position.x) <= arrive_distance:
		enemy._set_combat(false)
		return EnemyStateNames.PATROL
	# 返回途中仅受击可重开战（take_damage 会置 combat_active）；否则继续返回。
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	return &""
