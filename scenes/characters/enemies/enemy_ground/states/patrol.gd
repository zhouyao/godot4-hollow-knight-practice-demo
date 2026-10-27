extends EnemyState
class_name EnemyGroundPatrolState


## 巡逻半径（像素）：无领地时绕出生点来回移动的范围。
@export var patrol_radius: float = 80.0
## 巡逻速度倍率（相对 enemy.move_speed）。
@export var patrol_speed_multiplier: float = 0.5
## 到达端点后的停留时长（秒）。
@export var wait_time: float = 1.0

var _dir: int = 1
var _wait: float = 0.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	_dir = enemy.move_direction

func update(delta: float) -> void:
	_patrol_ground(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if enemy.combat_active:
		return EnemyStateNames.CHASE
	return &""

## 巡逻左右边界（世界 x）。绑领地时用领地左右端，否则回退出生点 ± radius。
func _get_patrol_bounds() -> Vector2:
	var zone = enemy.get_node_or_null(enemy.enemy_zone)
	if zone != null and zone is EnemyZone:
		var z := zone as EnemyZone
		var half := z.size.x * 0.5
		return Vector2(z.global_position.x - half, z.global_position.x + half)
	return Vector2(enemy.spawn_position.x - patrol_radius, enemy.spawn_position.x + patrol_radius)

func _patrol_ground(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		enemy.velocity.x = 0.0
		return

	# 非战斗巡逻：前方撞墙，或前方无地面（悬崖）都立即调头返回继续巡逻。
	# force_raycast_update()：RayCast2D 的碰撞结果是上一物理帧的缓存，
	# 查询前先按当前位置刷新一次，免得读到"翻面前那一侧"的旧结果。
	var wall: RayCast2D = enemy.get("wall_detector")
	if wall != null:
		wall.force_raycast_update()
	# 悬崖判定按"本帧准备走的方向"而不是当前朝向：掉头的那一帧两者并不一致。
	var wall_blocked := wall != null and wall.is_colliding()
	var ledge_blocked := not (enemy as EnemyGround).has_ground_ahead(float(_dir))
	if wall_blocked or ledge_blocked:
		_dir *= -1
		_face_dir(float(_dir))  # 立即转身，使探测器指向反方向
		_wait = wait_time * 0.5
		enemy.velocity.x = 0.0
		return

	var bounds := _get_patrol_bounds()
	var target_x := bounds.x if _dir < 0 else bounds.y
	var dir := enemy.nav_velocity(Vector2(target_x, enemy.global_position.y), enemy.move_speed * patrol_speed_multiplier, true)
	if dir.x != 0.0:
		_face_dir(signf(dir.x))
		enemy.velocity.x = dir.x
	else:
		# 抵达端点（nav_velocity 返回零向量），调头并停留，之后继续巡逻。
		_dir *= -1
		_wait = wait_time
		enemy.velocity.x = 0.0
