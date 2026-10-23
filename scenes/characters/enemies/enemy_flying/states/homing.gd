extends EnemyState
class_name EnemyFlyingHomingState


## 是否自动回巢：开启后脱离领地超时、或丢失目标过久都会自动切进 homing 状态。
@export var auto_return_to_nest: bool = true
## 脱离领地的容忍时长（秒）：连续待在活动范围外超过该时间就回巢（受击硬直期间不计时）。
@export var territory_leave_timeout: float = 6.0
## 丢失目标的等待时长（秒）：目标消失超过该时间就回巢。设为 0 或负数表示不做丢失判定。
@export var lost_target_delay: float = 3.0
## 回巢速度倍率：乘以 enemy.move_speed，大于 1 表示"逃回巢"比平时快。
@export var return_speed_multiplier: float = 1.0
## 回巢最长耗时（秒）：超时就原地停下不再移动，防止寻路异常时永远卡在回巢状态。
@export var return_max_duration: float = 10.0
const LEASH_EDGE_MARGIN := 8.0

## 进入回巢状态时发出（enemy 有效的前提下），可用来播放"撤退"表现或清理追击现场。
signal return_to_nest_started
## 退出回巢状态时发出：到巢、超时、或重新发现目标都会触发。
signal return_to_nest_finished

var _elapsed: float = 0.0
var _out_of_territory_time: float = 0.0
var _lost_target_time: float = 0.0


func poll_territory(delta: float) -> void:
	if not _pollable():
		return
	var current := machine.get_state_name()
	if current == EnemyStateNames.HOMING:
		_push_debug(true, 0.0)
		return
	var countdown := 0.0
	if auto_return_to_nest:
		if _is_outside_territory():
			_out_of_territory_time += delta
			if _out_of_territory_time >= territory_leave_timeout and current != EnemyStateNames.HURT:
				_out_of_territory_time = 0.0
				machine.set_state(EnemyStateNames.HOMING)
				_push_debug(true, 0.0)
				return
		else:
			_out_of_territory_time = 0.0
		countdown = maxf(0.0, territory_leave_timeout - _out_of_territory_time)
	_push_debug(false, countdown)


func poll_lost_target(delta: float) -> void:
	if not _pollable():
		return
	var current := machine.get_state_name()
	if current == EnemyStateNames.HOMING or current == EnemyStateNames.HURT:
		_lost_target_time = 0.0
		return
	if enemy.target != null or lost_target_delay <= 0.0:
		_lost_target_time = 0.0
		return
	_lost_target_time += delta
	if _lost_target_time >= lost_target_delay:
		_lost_target_time = 0.0
		machine.set_state(EnemyStateNames.HOMING)


func enter(_from: StringName) -> void:
	_elapsed = 0.0
	_play_action(EnemyStateNames.IDLE)
	if enemy != null:
		return_to_nest_started.emit()

func update(delta: float) -> void:
	enemy._apply_vertical_motion(delta)
	_elapsed += delta
	if _elapsed >= return_max_duration:
		enemy.velocity.x = 0.0
		enemy.velocity.y = 0.0
		enemy._apply_movement()
		return
	var home := enemy.spawn_position
	var step := enemy.get_navigation_step(home)
	var to_step := step - enemy.global_position
	var speed := enemy.move_speed * return_speed_multiplier
	if absf(home.x - enemy.global_position.x) > LEASH_EDGE_MARGIN:
		_face_x(step.x)
		enemy.velocity.x = signf(to_step.x) * speed
	else:
		enemy.velocity.x = 0.0
	enemy.velocity.y = signf(to_step.y) * speed if absf(home.y - enemy.global_position.y) > LEASH_EDGE_MARGIN else 0.0
	enemy._apply_movement()


func get_transition(_delta: float) -> StringName:
	if enemy.target != null:
		return EnemyStateNames.CHASE
	return &""

func exit(_to: StringName) -> void:
	if enemy != null:
		return_to_nest_finished.emit()


func _pollable() -> bool:
	return machine != null and enemy != null and not enemy.dead and machine.active

func _is_outside_territory() -> bool:
	if enemy.navigation_region == null or enemy.activity_rect.size.x <= 0.0 \
			or enemy.activity_rect.size.y <= 0.0:
		return false
	return not enemy.activity_rect.has_point(enemy.global_position)

func _push_debug(is_returning: bool, countdown: float) -> void:
	if enemy != null and enemy.debug != null:
		enemy.debug.set_return_info(is_returning, countdown)
