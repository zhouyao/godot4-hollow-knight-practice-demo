extends CombatState
class_name EnemyGroundChaseState


## 追击速度倍率：乘以 enemy.move_speed，大于 1 表示冲锋型敌人。
@export var speed_multiplier: float = 1.0

## 远程吐弹射程（像素）：配了 projectile_scene 时用这个距离判定进入 attack（否则用 enemy.attack_range）。
@export var shoot_range: float = 400.0
## 两次吐弹之间的冷却（秒）：仅远程模式生效，近战不受冷却限制。
@export var attack_interval: float = 1.5
## 远程追击时与目标保持的水平距离（像素）：追到该距离内就停下吐弹，不再贴脸。0 = 不保持距离。
## 逐只覆盖请改敌人根节点的 shoot_keep_distance（Enemy 基类导出，< 0 沿用本默认值）。
@export var shoot_keep_distance: float = 140.0

var _attack_timer := 0.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	_attack_timer = 0.0  # 每次进入追击重新计时（含吐弹后摇结束回追击）

func update(delta: float) -> void:
	var player := enemy.get_player()
	if player == null:
		enemy.velocity.x = 0.0
		super.update(delta)
		return
	enemy.target = player
	var dir := enemy.nav_velocity(player.global_position, enemy.move_speed * speed_multiplier, true)
	_step_chase(dir, player)
	enemy.tick_combat(delta)
	_attack_timer += delta
	super.update(delta)

func get_transition(delta: float) -> StringName:
	return _check_combat_transition(delta)

## 远程怪用吐弹射程，纯近战怪沿用基类的贴身距离。
func _attack_range() -> float:
	if enemy == null:
		return 0.0
	if enemy.has_projectile():
		return _tuning(&"shoot_range", shoot_range)
	return enemy.attack_range

func _can_attack(_delta: float) -> bool:
	if not enemy.has_projectile():
		return true
	return _attack_timer >= _tuning(&"attack_interval", attack_interval)

## 水平追击：远程怪追到保持距离内就停下（仍面朝目标），且全程不踏空。
func _step_chase(dir: Vector2, player: Node2D) -> void:
	var keep := _keep_distance()
	if keep > 0.0:
		var dx := player.global_position.x - enemy.global_position.x
		if absf(dx) <= keep:
			_face_x(player.global_position.x)  # 站定吐弹，朝向目标
			enemy.velocity.x = 0.0
			return

	if dir.x == 0.0:
		enemy.velocity.x = 0.0
		return
	if (enemy as EnemyGround).ledge_ahead():
		# 悬崖挡路：掉头往回走，绝不踏空（仍处战斗态，玩家回到可追击侧再追；
		# 对岸玩家一直不走则边缘来回掉头，直至 combat_lose_time 丢战）。
		_face_x(enemy.global_position.x - dir.x)  # 掉头面向安全方向
		enemy.velocity.x = -dir.x                # 往回走
	else:
		_face_x(enemy.global_position.x + dir.x)
		enemy.velocity.x = dir.x

func _keep_distance() -> float:
	if not enemy.has_projectile():
		return 0.0  # 近战怪照旧贴脸
	return _tuning(&"shoot_keep_distance", shoot_keep_distance)
