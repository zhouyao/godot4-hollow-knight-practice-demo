extends CombatState
class_name EnemyFlyingChaseState


## 与目标保持的水平距离（像素）：追到该距离内就停止水平靠近，避免贴脸。
## 世界场景里无法改实例内部子节点，逐只覆盖请改敌人根节点的同名导出（见 enemy_flying.gd）。
@export var keep_distance: float = 120.0
## 飞行速度倍率：乘以 enemy.move_speed，飞行怪一般比地面怪慢一点。
@export_range(0.05, 2.0) var fly_speed_multiplier: float = 0.75

## 进入攻击的射程（像素）：与目标距离在该值内才考虑切到 attack 状态。
@export var attack_range: float = 500.0
## 两次攻击之间的冷却（秒）：切到 attack 后需等冷却走完才允许再次攻击。
@export var attack_interval: float = 1.5
## 以上四个参数均可在敌人根节点上逐只覆盖（attack_interval 的覆盖在 Enemy 基类），详见 _tuning()。

var _attack_timer := 0.0

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	if _from == EnemyStateNames.ATTACK:
		_attack_timer = 0.0
	else:
		_reset()

func update(delta: float) -> void:
	enemy.velocity = Vector2.ZERO
	if not _is_flyer():
		super.update(delta)
		return
	var player := enemy.get_player()
	if player == null:
		super.update(delta)
		return
	enemy.target = player
	_face_target(player.global_position.x)
	_fly_toward(player.global_position)
	_attack_timer += delta
	enemy.tick_combat(delta)
	super.update(delta)

func get_transition(delta: float) -> StringName:
	return _check_combat_transition(delta)

func _attack_range() -> float:
	return _tuning(&"fly_attack_range", attack_range)

## 注：_tuning() 已上提到 EnemyState，飞行与陆地状态共用。

func _keep_distance() -> float:
	return _tuning(&"keep_distance", keep_distance)

func _can_attack(_delta: float) -> bool:
	return _attack_timer >= _tuning(&"attack_interval", attack_interval)

func _fly_toward(target_pos: Vector2) -> void:
	var speed := _fly_speed()
	var dir := enemy.nav_velocity(target_pos, speed, false)
	# 与目标保持水平间距，避免贴脸冲撞。
	var to_step := target_pos - enemy.global_position
	if absf(to_step.x) <= _keep_distance():
		dir.x = 0.0
	enemy.velocity = dir

func _reset() -> void:
	_attack_timer = 0.0

func _is_flyer() -> bool:
	return not enemy.gravity_enabled

func _fly_speed() -> float:
	return enemy.move_speed * _tuning(&"fly_speed_multiplier", fly_speed_multiplier)

func _face_target(target_x: float) -> void:
	var desired := 0
	if target_x > enemy.global_position.x:
		desired = 1
	elif target_x < enemy.global_position.x:
		desired = -1
	if desired != 0 and desired != enemy.move_direction:
		enemy._flip_direction()
