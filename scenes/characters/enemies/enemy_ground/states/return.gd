extends EnemyState
class_name EnemyGroundReturnState


## 抵达出生点的判定距离（像素）。
@export var arrive_distance: float = 8.0
## 返回速度倍率（相对 enemy.move_speed）。
@export var return_speed_multiplier: float = 2.0
## 朝家那一步会踏空时的退避：锁定一个方向至少走满这么多像素才允许重新规划。
## 没有这个"承诺"就会每帧改主意，敌人会在边缘原地翻面（chase 里同一个坑已修掉）。
@export var escape_distance: float = 64.0
## 连续退避超过这么久，说明"家在对岸、根本过不去"：放弃防踏空判定，直接朝家走（交由重力/地形处理）。
## 保留这条兜底是为了让 return 一定能结束 —— 否则敌人会永远卡在平台边缘回不了巢。
@export var escape_patience: float = 3.0

var _escape_dir: float = 0.0
var _escape_origin: float = 0.0
var _escape_time: float = 0.0
## 退避超时后置 true：本状态下不再检查悬崖，一路朝家走。
var _ignore_ledge: bool = false

func enter(_from: StringName) -> void:
	_play_action(&"idle")
	_escape_dir = 0.0
	_escape_origin = 0.0
	_escape_time = 0.0
	_ignore_ledge = false

func update(delta: float) -> void:
	var speed := enemy.move_speed * return_speed_multiplier
	var dir := enemy.nav_velocity(enemy.spawn_position, speed, true)
	_step_return(dir, speed, delta)
	super.update(delta)

## 回家：原则上跟着导航走；前方踏空就先锁定安全方向退开一段再重新规划，
## 退到无解（escape_patience）后放弃踏空保护，保证状态能收敛。
func _step_return(dir: Vector2, speed: float, delta: float) -> void:
	if dir.x == 0.0:
		enemy.velocity.x = 0.0
		return
	var step_x := signf(dir.x)

	# 处于退避中：至少走满承诺距离再复盘，中途不改主意，避免逐帧掉头。
	# _escape_time 是本状态的累计退避时长（enter() 才清零），不会走出一段就归零，
	# 否则"来回退避"永远凑不满 escape_patience，兜底就失效了。
	if _escape_dir != 0.0:
		_escape_time += delta
		if _escape_time >= escape_patience:
			# 退了这么久还没能重新上路：认为家在对岸，不再防踏空。
			_ignore_ledge = true
			_escape_dir = 0.0
			_escape_time = 0.0
		elif absf(enemy.global_position.x - _escape_origin) >= escape_distance:
			_escape_dir = 0.0  # 走满承诺距离，回到正常逻辑重新找路
		else:
			_face_dir(_escape_dir)
			enemy.velocity.x = _escape_dir * speed
			return

	if not _ignore_ledge:
		var safe := (enemy as EnemyGround).safe_step_x(step_x)
		if safe == 0.0:
			_ignore_ledge = true  # 两侧都没地，只能朝家硬走
		elif safe != step_x:
			# 朝家的下一步会踏空：往身后的实地退开一段，退出去再找路。
			_escape_dir = safe
			_escape_origin = enemy.global_position.x
			_face_dir(_escape_dir)
			enemy.velocity.x = _escape_dir * speed
			return

	_face_dir(step_x)
	enemy.velocity.x = dir.x

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
