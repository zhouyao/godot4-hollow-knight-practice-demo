extends EnemyState
class_name EnemyFlyingState


## 两次吐息之间的冷却（秒）：进入射程后还要等冷却走完才切到 spit 状态。
@export var spit_interval: float = 1.5
## 吐息射程（像素）：与目标的距离在该值以内才考虑吐息。
@export var spit_range: float = 500.0

## 与目标保持的水平距离（像素）：追到该距离内就停止水平靠近，避免贴脸。
@export var keep_distance: float = 120.0
## 飞行速度倍率：乘以 enemy.move_speed，飞行怪一般比地面怪慢一点。
@export_range(0.05, 2.0) var fly_speed_multiplier: float = 0.75

const LEASH_EDGE_MARGIN := 8.0

var _spit_timer := 0.0
var _last_known_target_pos: Vector2 = Vector2.ZERO

func enter(_from: StringName) -> void:
	_play_action(EnemyStateNames.IDLE)
	if _from == EnemyStateNames.SPIT:
		_spit_timer = 0.0
	else:
		_reset()

func update(delta: float) -> void:
	enemy.velocity.x = 0.0
	if enemy.target == null:
		_on_target_lost()
	else:
		_on_target_visible(delta)
	super.update(delta)

func get_transition(_delta: float) -> StringName:
	if enemy.target != null \
			and enemy.global_position.distance_to(enemy.target.global_position) <= spit_range \
			and _spit_timer >= spit_interval:
		return EnemyStateNames.SPIT
	return &""



func _on_target_lost() -> void:
	if not _is_flyer():
		return
	_pursue(enemy.clamp_to_activity(_last_known_target_pos), _last_known_target_pos)

func _on_target_visible(delta: float) -> void:
	var target_pos: Vector2 = enemy.target.global_position
	_last_known_target_pos = target_pos
	_face_target(target_pos.x)
	if _is_flyer():
		_fly_toward(target_pos)
	_spit_timer += delta



func _fly_toward(target_pos: Vector2) -> void:
	_pursue(enemy.clamp_to_activity(target_pos), target_pos)

func _pursue(goal: Vector2, target_pos: Vector2) -> void:
	var speed := _fly_speed()
	var stop_distance := LEASH_EDGE_MARGIN if absf(goal.x - target_pos.x) > 0.01 else keep_distance
	var step: Vector2 = enemy.get_navigation_step(goal)
	var to_step := step - enemy.global_position
	if absf(to_step.x) > stop_distance:
		enemy.velocity.x = signf(to_step.x) * speed
	else:
		enemy.velocity.x = 0.0
	enemy.velocity.y = signf(to_step.y) * speed if absf(to_step.y) > 1.0 else 0.0



func _reset() -> void:
	_spit_timer = 0.0

func _is_flyer() -> bool:
	return not enemy.gravity_enabled

func _fly_speed() -> float:
	return enemy.move_speed * fly_speed_multiplier

func _face_target(target_x: float) -> void:
	var desired := 0
	if target_x > enemy.global_position.x:
		desired = 1
	elif target_x < enemy.global_position.x:
		desired = -1
	if desired != 0 and desired != enemy.move_direction:
		enemy._flip_direction()
