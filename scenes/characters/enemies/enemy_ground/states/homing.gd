extends EnemyState
class_name EnemyGroundHomingState


## 是否自动回巢：开启后脱离领地超过 territory_leave_timeout 就切进 homing 状态。
@export var auto_return_to_nest: bool = true
## 脱离领地的容忍时长（秒）：连续待在活动范围外超过该时间就回巢（受击硬直期间不计时）。
@export var territory_leave_timeout: float = 6.0
## 回巢速度倍率：乘以 enemy.move_speed，大于 1 表示"逃回巢"比平时快。
@export var return_speed_multiplier: float = 1.0
## 回巢到位的判定半径（像素）：水平与垂直方向都进入该范围内才算到家，随即切回原状态。
@export var return_arrival_threshold: float = 4.0
## 回巢最长耗时（秒）：超时视为放弃，按原状态返回，防止寻路异常时永远卡在回巢状态。
@export var return_max_duration: float = 10.0

## 进入回巢状态时发出（enemy 有效的前提下），可用来播放"撤退"表现或清理追击现场。
signal return_to_nest_started
## 退出回巢状态时发出：到巢、超时都会触发。
signal return_to_nest_finished

var _return_from: StringName = &""
var _elapsed: float = 0.0
var _out_of_territory_time: float = 0.0


func poll_territory(delta: float) -> void:
	if machine == null or enemy == null or enemy.dead or not machine.active:
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


func enter(_from: StringName) -> void:
	_return_from = _from
	_elapsed = 0.0
	_play_action(EnemyStateNames.IDLE)
	if enemy != null:
		return_to_nest_started.emit()

func update(delta: float) -> void:
	enemy._apply_vertical_motion(delta)
	_elapsed += delta
	var to_spawn := enemy.spawn_position - enemy.global_position
	if _is_home(to_spawn):
		return
	var step := enemy.spawn_position
	if enemy.navigation_region != null and enemy.navigation_agent != null:
		enemy.navigation_agent.target_position = enemy.spawn_position
		if enemy.navigation_agent.is_target_reachable():
			var np := enemy.navigation_agent.get_next_path_position()
			if np.distance_to(enemy.global_position) >= 1.0:
				step = np
	var desired := 1 if step.x > enemy.global_position.x else -1
	if desired != enemy.move_direction:
		enemy._flip_direction()
	enemy.velocity.x = float(enemy.move_direction) * enemy.move_speed * return_speed_multiplier
	enemy._apply_movement()


func get_transition(_delta: float) -> StringName:
	var to_spawn := enemy.spawn_position - enemy.global_position
	if _is_home(to_spawn) or _elapsed >= return_max_duration:
		return _return_from if _return_from != &"" else EnemyStateNames.IDLE
	return &""

func exit(_to: StringName) -> void:
	if enemy != null:
		return_to_nest_finished.emit()


func _is_home(to_spawn: Vector2) -> bool:
	return absf(to_spawn.x) <= return_arrival_threshold and absf(to_spawn.y) <= return_arrival_threshold

func _is_outside_territory() -> bool:
	if enemy.navigation_region == null or enemy.activity_rect.size.x <= 0.0 \
			or enemy.activity_rect.size.y <= 0.0:
		return false
	return not enemy.activity_rect.has_point(enemy.global_position)

func _push_debug(is_returning: bool, countdown: float) -> void:
	if enemy != null and enemy.debug != null:
		enemy.debug.set_return_info(is_returning, countdown)
